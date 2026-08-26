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
# 【重要・2026-08-27追記、2026-08-27再追記】Flutter Webは標準で
# Service Worker(オフラインキャッシュ)を組み込むため、既にアプリを
# 開いたことがあるブラウザはサーバー側を更新しても古い画面をキャッシュ
# から表示し続けてしまう不具合が過去に実際発生した(v1.2.15で「Web版が
# v1.2.13のまま更新されない」という問い合わせが発生)。
# この問題は2段構えで対策済み:
#   1) --pwa-strategy=none でService Workerの新規登録を止める(下記)
#   2) web/index.html 内のスクリプトで、既に登録済みの古いService
#      Workerを検出したら自動的に登録解除+キャッシュ削除+再読込を行う
#      (これが無いと、対策1だけでは「既存ユーザー」には効果がない)
# さらに、firebase.json のCache-Controlも合わせて確認すること。
# main.dart.js 等はファイル名にハッシュが付かないため、誤って長期
# キャッシュ(max-age=31536000等)を設定するとCDN・ブラウザ双方で
# 更新が反映されなくなる。js/css/html/md/pdf/jsonは必ず
# no-cache, no-store, must-revalidate にすること
# (ハッシュ付きの canvaskit/ や assets/ のみ長期キャッシュ可)。
# --pwa-strategy=none を付け忘れても、外しても、このフラグ単体では
# 既存ユーザーの不具合は解決しないため、絶対に外さないこと。
#
# 【重要】このスクリプトの実行後は、必ず
#   python3 scripts/release_version_config.py <version> <build_number>
# を実行し、Firestore app_config/settings の latest_version /
# latest_build_number / download_url を更新すること(アプリ内の
# 「新しいバージョンがあります」通知バナーが機能しなくなるため)。

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

echo "▶ 1/5 配布用APK(arm64-v8a専用)をビルドします..."
bash scripts/build_release_apk.sh
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"

echo "▶ 2/5 Web版をビルドします(Service Workerキャッシュ無効化 --pwa-strategy=none)..."
flutter build web --release \
  --pwa-strategy=none \
  --dart-define=SCAN_PROXY_FUNCTION_KEY="${SCAN_PROXY_FUNCTION_KEY:-}"

echo "▶ 3/5 Web版をFirebase Hostingへデプロイします..."
GOOGLE_APPLICATION_CREDENTIALS=/opt/flutter/firebase-admin-sdk.json \
  firebase deploy --only hosting --project sn-report

echo "▶ 4/5 APKをGitHub Releasesへ公開します(tag: ${TAG})..."
gh release create "${TAG}" "${APK_PATH}" \
  --title "${TAG}" \
  --notes "自動生成リリース。詳細はアプリ内の更新履歴画面を参照してください。" \
  || gh release upload "${TAG}" "${APK_PATH}" --clobber

echo "▶ 5/5 app_config/settings の最新バージョン情報を更新します(更新通知バナー用)..."
BUILD_NUMBER=$(grep -m1 '^version:' pubspec.yaml | sed 's/.*+//')
python3 scripts/release_version_config.py "${VERSION}" "${BUILD_NUMBER}" \
  || echo "⚠️  警告: app_config/settings の更新に失敗しました。手動で release_version_config.py を実行してください。"

echo ""
echo "✅ デプロイ完了"
echo "   Web版:  https://sn-report.web.app/"
echo "   APK版:  https://github.com/sn-naka3692/maintenance-log-app/releases/latest/download/app-release.apk"
