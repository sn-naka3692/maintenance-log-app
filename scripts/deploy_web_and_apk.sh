#!/bin/bash
# Web版(マニュアル・アプリ本体)を Firebase Hosting へデプロイし、
# 続けて配布用APKをビルドして GitHub Releases に公開するスクリプト。
#
# 【重要・v1.2.6で変更】APK配布は v1.2.5 で一時的に Firebase Hosting
# 経由に変更したが、Firebase Hosting(Fastly CDN)は大容量バイナリの
# 配信時に Content-Length を返さず、Range リクエスト(途中からの
# 再開)にも対応していないという構造的な制限があり、ダウンロードが
# 完了しない不具合を引き起こした。GitHub Releases(Azure Blob Storage
# 配信)はこの両方に対応していることを検証済みのため、v1.2.6で
# APK配布はGitHub Releasesに戻した。
# Web版(マニュアル・PWA)は元々問題がないため、Firebase Hostingの
# ままとしている。
#
# 使い方: cd /home/user/flutter_app && bash scripts/deploy_web_and_apk.sh
#
# 【注意】GitHub Releaseの作成には gh コマンドの認証が必要。
# 事前に setup_github_environment 相当の認証設定を済ませておくこと。
# また、既に同名タグのリリースがある場合は手動で削除するか、
# バージョンを更新してから実行すること。
#
# 【重要・2026-08-26】Flutter Webは標準でService Worker(オフライン
# キャッシュ)を組み込むため、既にアプリを開いたことがあるブラウザは
# サーバー側を更新しても古い画面をキャッシュから表示し続けてしまう
# 不具合が過去に実際発生した(v1.2.15で「Web版がv1.2.13のまま更新
# されない」という問い合わせが発生)。
# 対策として --pwa-strategy=none でService Workerの新規登録を止めて
# いる(下記)。さらに firebase.json のCache-Controlも合わせて確認
# すること。main.dart.js 等はファイル名にハッシュが付かないため、
# 誤って長期キャッシュ(max-age=31536000等)を設定するとCDN・ブラウザ
# 双方で更新が反映されなくなる。js/css/html/md/pdf/jsonは必ず
# no-cache, no-store, must-revalidate にすること
# (ハッシュ付きの canvaskit/ や assets/ のみ長期キャッシュ可)。
# --pwa-strategy=none を付け忘れても、外しても、このフラグ単体では
# 既存ユーザーの不具合は解決しないため、絶対に外さないこと。
#
# 【重要・2026-08-26 障害発生とその教訓】上記の対策でも「すでに古い
# Service Workerがブラウザで有効化済みのユーザー」には効果がないため、
# 一時的に「古いService Workerを検出したら自動的に強制有効化・登録
# 解除・強制リロードする」キルスイッチ的な仕組みを導入したが、これが
# 実際の障害(ログイン画面が高速リトライを繰り返し、読み込みが完了
# しない)を引き起こしてしまった。
# 原因: 古いバージョンのFlutter Webは「Service Workerの管理者が
# 切り替わったら(controllerchangeイベント)自動的にページを再読み込み
# する」処理を内部的に持っている。新しいService Workerがactivate時に
# 自分自身をunregister()すると、この「管理者切り替わり」を誘発し、
# 古いJSの自動リロードが発火→リロード後も古いJSがSWを再登録→再度
# unregister→再度管理者切り替わり検知→…という終わらない無限ループ
# になることを再現実験で確認した。
# このため、scripts/kill_switch_service_worker.js は「何もしない、
# 完全に無害な空のService Worker」に変更し、以下を徹底している:
#   - skipWaiting() を呼ばない(通常のブラウザの待機ルールに従う)
#   - unregister() を呼ばない(controllerchangeを誘発しない)
#   - clients.claim() を呼ばない(開いているタブに影響を与えない)
# 【絶対に守ること】この教訓を踏まえ、Service Worker関連の「自動で
# 強制的に何かする」仕組みを再導入する場合は、必ずローカルで
# 「古いService Worker登録済み状態からの切り替え」を再現実験し、
# 無限ループが発生しないことを確認してからデプロイすること。
#
# 【重要】このスクリプトの実行後は、必ず
#   python3 scripts/release_version_config.py <version> <build_number>
# を実行し、Firestore app_config/settings の latest_version /
# latest_build_number / download_url を更新すること(アプリ内の
# 「新しいバージョンがあります」通知バナーが機能しなくなるため)。
#
# 【重大障害・2026-09-01発生・教訓】v1.2.41で firestore.rules に
# refrigerant_types コレクションのルールを追加したが、当時の本スクリプト
# は `firebase deploy --only hosting` のみで firestore:rules のデプロイ
# ステップが欠落していた。結果、本番Firestoreのルールが更新されず、
# ログイン後に AppState.init() が refrigerant_types を読み取る際に
# ルール未定義(デフォルト拒否)で PERMISSION_DENIED となり、WEB版・
# APK版ともに「ログイン画面は表示されるがログイン後の全データ読み込みが
# 失敗する」という重大障害を引き起こした。
# 【絶対に守ること】firestore.rules を変更した回のリリースでは、
# 必ず firestore:rules のデプロイ(下記Step 5)も実行し、本番の
# ルールが実際に更新されたことを(Firebase Rules APIやコンソール等で)
# 確認すること。
#
# 【構造修正・2026-09-15】従来 `firebase deploy --only firestore:rules`
# を使っていたが、本サンドボックスのサービスアカウントには
# serviceusage.googleapis.com への照会権限がなく、CLIの事前チェック
# (「firestore.googleapis.com APIが有効か」の確認)が常に403で失敗する
# ことが判明した(実際のルール変更権限自体は正しく持っている)。
# この403によりスクリプトが `set -e` で停止し、その後段にあった
# Step 6(GitHub Release公開)・Step 7(Firestore app_config/settings
# 更新=更新通知バナーの生命線)が実行されないまま終わってしまう事故が
# 2026-09-11・2026-09-15に連続発生した。
# 【再発防止】
#   (1) firestore:rules のデプロイは、CLIを経由せずFirebase Rules API
#       を直接叩く scripts/deploy_firestore_rules.py に置き換えた
#       (前記の403問題を完全に回避できる)。
#   (2) それでもルールデプロイ自体が何らかの理由で失敗した場合に備え、
#       このステップだけは `|| true` で失敗を許容し、後続のStep 6/7
#       (GitHub Release公開・Firestore設定更新)は【何があっても必ず
#       実行される】ようスクリプト全体の構成を変更した(下記参照)。
#       firestore.rulesの反映有無は、失敗時に表示される警告メッセージで
#       必ず目視確認すること。

set -e
cd "$(dirname "$0")/.."

VERSION=$(grep -m1 '^version:' pubspec.yaml | sed 's/version: *//' | cut -d'+' -f1)
BUILD_NUMBER=$(grep -m1 '^version:' pubspec.yaml | sed 's/.*+//')
TAG="v${VERSION}"

# 【重大障害・2026-09-02発生・教訓】v1.2.42リリース時、pubspec.yamlの
# バージョンは更新したが lib/build_info.dart の kCompiledBuildNumber /
# kCompiledVersionName の更新を失念した。Web版の更新チェックは
# package_info_plus ではなくこのコンパイル時定数を見て「自分自身が
# 古いビルドか」を判定する仕組みのため、これが古いままだと
# Firestoreのlatest_build_numberを更新しても「新しいバージョンが
# あります」バナーが永久に消えない(=何度リロードしても効果がない)
# 事故になる。ビルド前に必ず整合性を検証し、不一致なら即停止する。
COMPILED_BUILD=$(grep -m1 'kCompiledBuildNumber' lib/build_info.dart | grep -o '[0-9]\+')
COMPILED_VERSION=$(grep -m1 'kCompiledVersionName' lib/build_info.dart | sed -E "s/.*'([^']+)'.*/\1/")
if [[ "$COMPILED_BUILD" != "$BUILD_NUMBER" || "$COMPILED_VERSION" != "$VERSION" ]]; then
  echo "❌ 停止: lib/build_info.dart が pubspec.yaml と不一致です。"
  echo "   pubspec.yaml:    version=${VERSION} build=${BUILD_NUMBER}"
  echo "   build_info.dart: version=${COMPILED_VERSION} build=${COMPILED_BUILD}"
  echo "   lib/build_info.dart の kCompiledBuildNumber/kCompiledVersionName を"
  echo "   更新してから再実行してください(Web版の更新お知らせバナーが"
  echo "   消えなくなる重大な不具合の原因になります)。"
  exit 1
fi
echo "✅ build_info.dart整合性チェックOK(version=${VERSION} build=${BUILD_NUMBER})"

# 【重要】スキャン機能用Function Key(SCAN_PROXY_FUNCTION_KEY)は
# Web版・APK版どちらも --dart-define で埋め込む必要がある。
# 詳細は scripts/build_release_apk.sh の冒頭コメントを参照。
SECRETS_FILE="scripts/secrets.env"
if [[ -f "$SECRETS_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$SECRETS_FILE"
else
  echo "⚠️  警告: $SECRETS_FILE が見つかりません。スキャン機能は401エラーになります。"
fi

echo "▶ 1/7 配布用APK(arm64-v8a専用)をビルドします..."
bash scripts/build_release_apk.sh
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"

echo "▶ 2/7 Web版をビルドします(Service Workerキャッシュ無効化 --pwa-strategy=none)..."
flutter build web --release \
  --pwa-strategy=none \
  --dart-define=SCAN_PROXY_FUNCTION_KEY="${SCAN_PROXY_FUNCTION_KEY:-}"

echo "▶ 3/7 Service Workerを無害な空ファイルに置き換えます(古いSW対策)..."
# 【重要】scripts/kill_switch_service_worker.js は現在「何もしない、
# 完全に無害な空のService Worker」。過去に「自動で強制的に古いSWを
# 一掃する」実装を試みたが無限リロードループの障害を起こしたため撤回
# した(詳細は本ファイル冒頭のコメント、および
# scripts/kill_switch_service_worker.js 内のコメントを参照)。
cp scripts/kill_switch_service_worker.js build/web/flutter_service_worker.js

echo "▶ 4/7 Web版をFirebase Hostingへデプロイします..."
GOOGLE_APPLICATION_CREDENTIALS=/opt/flutter/firebase-admin-sdk.json \
  firebase deploy --only hosting --project sn-report

echo "▶ 5/7 Firestoreセキュリティルールをデプロイします..."
# 【重要・2026-09-01追加】v1.2.41で firestore.rules を更新したにも関わらず
# 本ステップが欠落していたため、ルール未反映(refrigerant_types 未定義→
# デフォルト拒否)によりログイン後の全データ読み込みが失敗する重大障害が
# 発生した。firestore.rules の変更を確実に本番へ反映するため、hosting と
# 同時に必ずデプロイすること。
#
# 【構造修正・2026-09-15】firebase CLIの `deploy --only firestore:rules`
# はサービスアカウント権限の都合で常に403になるため使わず、Firebase
# Rules APIを直接叩くPythonスクリプトを使う(冒頭コメント参照)。
# このステップが万一失敗しても($RULES_DEPLOY_FAILEDに記録した上で)
# 後続のStep 6/7は必ず実行する。firestore.rules自体に変更がないリリース
# であればこのステップの失敗は実害がないが、変更がある回は下記の警告を
# 必ず確認し、成功するまで手動で再実行すること。
RULES_DEPLOY_FAILED=0
python3 scripts/deploy_firestore_rules.py || RULES_DEPLOY_FAILED=1
if [[ "$RULES_DEPLOY_FAILED" -eq 1 ]]; then
  echo "⚠️  警告: firestore.rulesのデプロイに失敗しました。"
  echo "   firestore.rulesに実際の変更がある回のリリースの場合、本番の"
  echo "   ルールが古いままになっている可能性があります。"
  echo "   手動で python3 scripts/deploy_firestore_rules.py を再実行してください。"
fi

# 【構造修正・2026-09-15・最重要】Step 6(GitHub Release公開)・
# Step 7(Firestore app_config/settings更新=更新通知バナーの生命線)は、
# 上記Step 5がどうなろうと(set -eで停止しようと)必ず実行されなければ
# ならない。2026-09-11・2026-09-15と2回連続で「Step 5の403エラーで
# スクリプトが停止し、Step 6/7が実行されないまま終わる」事故が発生し、
# 手動補完が必要になったため、以降は明示的に `|| true` で個々の失敗を
# 許容しつつ、最後に全ステップの成否をまとめて報告する構成に変更した。
echo "▶ 6/7 APKをGitHub Releasesへ公開します(tag: ${TAG})..."
RELEASE_FAILED=0
gh release create "${TAG}" "${APK_PATH}" \
  --title "${TAG}" \
  --notes "自動生成リリース。詳細はアプリ内の更新履歴画面を参照してください。" \
  || gh release upload "${TAG}" "${APK_PATH}" --clobber \
  || RELEASE_FAILED=1
if [[ "$RELEASE_FAILED" -eq 1 ]]; then
  echo "❌ 警告: GitHub Releaseの公開に失敗しました。手動で確認してください。"
fi

echo "▶ 7/7 app_config/settings の最新バージョン情報を更新します(更新通知バナー用)..."
CONFIG_UPDATE_FAILED=0
python3 scripts/release_version_config.py "${VERSION}" "${BUILD_NUMBER}" \
  || CONFIG_UPDATE_FAILED=1
if [[ "$CONFIG_UPDATE_FAILED" -eq 1 ]]; then
  echo "❌ 警告: app_config/settings の更新に失敗しました。手動で release_version_config.py を実行してください。"
fi

echo ""
echo "========================================"
echo "デプロイ結果サマリー(${TAG})"
echo "========================================"
echo "  1-4/7 APK/Web版ビルド・Hostingデプロイ: ✅ 成功(ここまで到達済み)"
if [[ "$RULES_DEPLOY_FAILED" -eq 1 ]]; then
  echo "  5/7   Firestoreルールデプロイ         : ❌ 失敗(要手動対応)"
else
  echo "  5/7   Firestoreルールデプロイ         : ✅ 成功"
fi
if [[ "$RELEASE_FAILED" -eq 1 ]]; then
  echo "  6/7   GitHub Release公開             : ❌ 失敗(要手動対応)"
else
  echo "  6/7   GitHub Release公開             : ✅ 成功"
fi
if [[ "$CONFIG_UPDATE_FAILED" -eq 1 ]]; then
  echo "  7/7   Firestore設定更新(更新通知)    : ❌ 失敗(要手動対応・最重要)"
else
  echo "  7/7   Firestore設定更新(更新通知)    : ✅ 成功"
fi
echo "----------------------------------------"
echo "   Web版:  https://sn-report.web.app/"
echo "   APK版:  https://github.com/sn-naka3692/maintenance-log-app/releases/latest/download/app-release.apk"

if [[ "$RULES_DEPLOY_FAILED" -eq 1 || "$RELEASE_FAILED" -eq 1 || "$CONFIG_UPDATE_FAILED" -eq 1 ]]; then
  echo ""
  echo "⚠️  一部のステップが失敗しています。上記の「要手動対応」項目を確認してください。"
  exit 1
fi
