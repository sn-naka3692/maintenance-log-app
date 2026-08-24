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

set -e
cd "$(dirname "$0")/.."

VERSION=$(grep -m1 '^version:' pubspec.yaml | sed 's/version: *//' | cut -d'+' -f1)
TAG="v${VERSION}"

echo "▶ 1/4 配布用APK(arm64-v8a専用)をビルドします..."
bash scripts/build_release_apk.sh
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"

echo "▶ 2/4 Web版をビルドします..."
flutter build web --release

echo "▶ 3/4 Web版をFirebase Hostingへデプロイします..."
GOOGLE_APPLICATION_CREDENTIALS=/opt/flutter/firebase-admin-sdk.json \
  firebase deploy --only hosting --project sn-report

echo "▶ 4/4 APKをGitHub Releasesへ公開します(tag: ${TAG})..."
gh release create "${TAG}" "${APK_PATH}" \
  --title "${TAG}" \
  --notes "自動生成リリース。詳細はアプリ内の更新履歴画面を参照してください。" \
  || gh release upload "${TAG}" "${APK_PATH}" --clobber

echo ""
echo "✅ デプロイ完了"
echo "   Web版:  https://sn-report.web.app/"
echo "   APK版:  https://github.com/sn-naka3692/maintenance-log-app/releases/latest/download/app-release.apk"
