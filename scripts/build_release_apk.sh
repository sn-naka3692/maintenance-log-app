#!/bin/bash
# 配布用APKのリリースビルドスクリプト。
#
# 【重要】現場端末(Galaxy A53以降)はすべてarm64-v8a(64bit ARM)のため、
# --target-platform android-arm64 を必ず指定すること。
# このフラグを忘れると、x86_64(エミュレータ用)・armeabi-v7a(旧32bit機種用)
# も同梱された約58MBの巨大APKが生成され、ダウンロードタイムアウトの
# 原因になる(v1.2.4で実際に発生した不具合)。
#
# 【重要】作業報告書スキャン機能(document_scan_service.dart)は、
# Azure Functions中継エンドポイント(nakano-scan-proxy)を呼び出すための
# Function Key(SCAN_PROXY_FUNCTION_KEY)を --dart-define でビルド時に
# 埋め込む必要がある。これを忘れると、コード内のプレースホルダー文字列が
# そのまま使われてしまい、Azure側から401(認証エラー)が返り、
# アプリ上では「サーバーからの応答を解釈できませんでした(HTTP 401)」
# というエラーになる(2026-08 実際に発生した不具合)。
# キーは scripts/secrets.env に保存されている(git管理外の秘密情報)。
# 万一 secrets.env が無い場合、キー未設定でビルド自体は進むが、
# スキャン機能は必ず401エラーになる旨を警告表示する。
#
# 使い方: cd /home/user/flutter_app && bash scripts/build_release_apk.sh

set -e
cd "$(dirname "$0")/.."

SECRETS_FILE="scripts/secrets.env"
if [[ -f "$SECRETS_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$SECRETS_FILE"
else
  echo "⚠️  警告: $SECRETS_FILE が見つかりません。"
  echo "   作業報告書のスキャン機能はビルドされたAPKで401エラーになります。"
fi

if [[ -z "${SCAN_PROXY_FUNCTION_KEY:-}" ]]; then
  echo "⚠️  警告: SCAN_PROXY_FUNCTION_KEY が未設定です。スキャン機能は動作しません。"
fi

echo "▶ arm64-v8a専用の配布用APKをビルドします..."
flutter build apk --release --target-platform android-arm64 \
  --dart-define=SCAN_PROXY_FUNCTION_KEY="${SCAN_PROXY_FUNCTION_KEY:-}"

APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
SIZE=$(du -h "$APK_PATH" | cut -f1)
echo "✅ ビルド完了: $APK_PATH ($SIZE)"

if [[ "$(du -m "$APK_PATH" | cut -f1)" -gt 30 ]]; then
  echo "⚠️  警告: APKサイズが30MBを超えています。"
  echo "   --target-platform android-arm64 が正しく反映されているか確認してください。"
fi
