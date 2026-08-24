#!/bin/bash
# 配布用APKのリリースビルドスクリプト。
#
# 【重要】現場端末(Galaxy A53以降)はすべてarm64-v8a(64bit ARM)のため、
# --target-platform android-arm64 を必ず指定すること。
# このフラグを忘れると、x86_64(エミュレータ用)・armeabi-v7a(旧32bit機種用)
# も同梱された約58MBの巨大APKが生成され、ダウンロードタイムアウトの
# 原因になる(v1.2.4で実際に発生した不具合)。
#
# 使い方: cd /home/user/flutter_app && bash scripts/build_release_apk.sh

set -e
cd "$(dirname "$0")/.."

echo "▶ arm64-v8a専用の配布用APKをビルドします..."
flutter build apk --release --target-platform android-arm64

APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
SIZE=$(du -h "$APK_PATH" | cut -f1)
echo "✅ ビルド完了: $APK_PATH ($SIZE)"

if [[ "$(du -m "$APK_PATH" | cut -f1)" -gt 30 ]]; then
  echo "⚠️  警告: APKサイズが30MBを超えています。"
  echo "   --target-platform android-arm64 が正しく反映されているか確認してください。"
fi
