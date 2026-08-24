#!/bin/bash
# Web版マニュアル・アプリ本体、およびAPK版を Firebase Hosting へ
# まとめてデプロイするスクリプト。
#
# 【背景】v1.2.4まではAPKをGitHub Releasesで配布していたが、社内Wi-Fi等の
# 環境によってはGitHubのリリースファイル配信専用ドメインが遅延・ブロック
# され、ダウンロードがタイムアウトする不具合があった(進行状況の表示も
# 出ないまま止まる)。v1.2.5からはAPKもWeb版と同じ単一ドメイン
# (sn-report.web.app)経由で配布する方式に変更した。
#
# 【ファイル名について】Firebase Hosting無料プラン(Sparkプラン)は
# 「実行可能ファイル」のアップロードを禁止しているため、APKの拡張子を
# .apk から .data に変更してアップロードしている。ダウンロード時は
# Content-Disposition ヘッダーにより app-release.apk という名前で
# 保存されるため、利用者側には影響しない(firebase.json 参照)。
#
# 使い方: cd /home/user/flutter_app && bash scripts/deploy_web_and_apk.sh

set -e
cd "$(dirname "$0")/.."

echo "▶ 1/4 配布用APK(arm64-v8a専用)をビルドします..."
bash scripts/build_release_apk.sh

echo "▶ 2/4 APKをWeb配布用フォルダに配置します..."
mkdir -p web/downloads
cp build/app/outputs/flutter-apk/app-release.apk web/downloads/app-release.data

echo "▶ 3/4 Web版をビルドします..."
flutter build web --release

echo "▶ 4/4 Firebase Hostingへデプロイします..."
GOOGLE_APPLICATION_CREDENTIALS=/opt/flutter/firebase-admin-sdk.json \
  firebase deploy --only hosting --project sn-report

echo ""
echo "✅ デプロイ完了"
echo "   Web版:  https://sn-report.web.app/"
echo "   APK版:  https://sn-report.web.app/downloads/app-release.data"
