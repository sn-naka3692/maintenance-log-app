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
#
# 【回帰テストゲート・2026-10-06追加】
# このスクリプトは deploy_web_and_apk.sh から呼ばれる場合と、単体で
# 直接実行される場合の両方がある。単体実行時にテストなしでAPKが
# ビルドされてしまう抜け道を防ぐため、このスクリプト自身にも
# 回帰テストゲートを持たせている(deploy_web_and_apk.sh経由では
# 二重実行になるが、既存機能の動作保証を最優先し許容する)。

set -e
cd "$(dirname "$0")/.."

echo "▶ 回帰テストを実行します(既存機能を壊していないか自動確認)..."
if ! flutter test; then
  echo ""
  echo "❌ 停止: 回帰テストが失敗しました。APKビルドを中止します。"
  echo "   既存の正常動作している機能が壊れている可能性があります。"
  echo "   上記の失敗したテストを確認し、修正してから再実行してください。"
  echo "   (テスト自体を無効化・削除して通すことは絶対に行わないこと)"
  exit 1
fi
echo "✅ 回帰テスト全件通過(既存機能の動作保証OK)"
echo ""

SECRETS_FILE="scripts/secrets.env"
if [[ -f "$SECRETS_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$SECRETS_FILE"
fi

if [[ -z "${SCAN_PROXY_FUNCTION_KEY:-}" ]]; then
  # secrets.env が無い/キーが空の場合、Azure CLIから直接取得を試みる
  # (v1.2.48 で「キー空のまま配布」となった再発を防ぐ。2026-10-08 対応)
  if command -v az >/dev/null 2>&1 && az account show >/dev/null 2>&1; then
    echo "▶ SCAN_PROXY_FUNCTION_KEY が未設定のため Azure CLI から取得します..."
    SCAN_PROXY_FUNCTION_KEY="$(az functionapp function keys list --name nakano-scan-proxy --resource-group nakano-reikiken-rg --function-name scan --query 'default' -o tsv 2>/dev/null || true)"
  fi
fi

if [[ -z "${SCAN_PROXY_FUNCTION_KEY:-}" ]]; then
  echo ""
  echo "❌ 停止: SCAN_PROXY_FUNCTION_KEY が取得できません。APKビルドを中止します。"
  echo "   このまま続行すると、スキャン機能が必ず401エラーになるAPKが配布されます"
  echo "   (v1.2.48 で実際に発生した不具合)。"
  echo ""
  echo "   対処: scripts/secrets.env に以下の1行を書いてから再実行してください:"
  echo '     SCAN_PROXY_FUNCTION_KEY="<Azure関数scanのキー>"'
  echo "   または Azure CLI でログイン済みなら、このスクリプトが自動取得します:"
  echo "     az login"
  exit 1
fi
echo "✅ スキャン機能用Function Keyの埋め込みを確認(キー未埋め込みの配布をブロック)"

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
