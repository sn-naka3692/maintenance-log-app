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
# 必ず `firebase deploy --only firestore:rules` も実行し、本番の
# ルールが実際に更新されたことを(Firebase Rules APIやコンソール等で)
# 確認すること。本スクリプトの Step 5/7 として組み込み済みなので、
# 手動デプロイに切り替える場合も本ステップを省略しないこと。

set -e
cd "$(dirname "$0")/.."

VERSION=$(grep -m1 '^version:' pubspec.yaml | sed 's/version: *//' | cut -d'+' -f1)
TAG="v${VERSION}"

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
GOOGLE_APPLICATION_CREDENTIALS=/opt/flutter/firebase-admin-sdk.json \
  firebase deploy --only firestore:rules --project sn-report

echo "▶ 6/7 APKをGitHub Releasesへ公開します(tag: ${TAG})..."
gh release create "${TAG}" "${APK_PATH}" \
  --title "${TAG}" \
  --notes "自動生成リリース。詳細はアプリ内の更新履歴画面を参照してください。" \
  || gh release upload "${TAG}" "${APK_PATH}" --clobber

echo "▶ 7/7 app_config/settings の最新バージョン情報を更新します(更新通知バナー用)..."
BUILD_NUMBER=$(grep -m1 '^version:' pubspec.yaml | sed 's/.*+//')
python3 scripts/release_version_config.py "${VERSION}" "${BUILD_NUMBER}" \
  || echo "⚠️  警告: app_config/settings の更新に失敗しました。手動で release_version_config.py を実行してください。"

echo ""
echo "✅ デプロイ完了"
echo "   Web版:  https://sn-report.web.app/"
echo "   APK版:  https://github.com/sn-naka3692/maintenance-log-app/releases/latest/download/app-release.apk"
