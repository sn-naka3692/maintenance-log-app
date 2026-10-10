#!/usr/bin/env bash
# スキャン機能の健全性チェック(手動実行用)
# 使い方: scripts/health_check.sh <scanキー> <scan_batchキー>
# キーは Azure Portal(naka-p@sapporonakano.onmicrosoft.com でサインイン)の
# 各関数の「関数キー > default」から取得する。
S=${1:?"scan関数のキーを指定してください"}
B=${2:?"scan_batch関数のキーを指定してください"}
BASE="https://nakano-scan-proxy.azurewebsites.net/api"
s=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE/scan?code=$S&startPage=1&endPage=1" -H "Content-Type: application/pdf" --data-binary "" --max-time 60)
b=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE/scanBatch?code=$B&startPage=1&endPage=1" -H "Content-Type: application/pdf" --data-binary "" --max-time 60)
h=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/health" --max-time 30)
echo "health=$h scan=$s scanBatch=$b"
if [ "$s" = "401" ] || [ "$b" = "401" ]; then
  echo "❌ キー不一致(401)。Azure側の関数キーと GitHubシークレット(SCAN_PROXY_FUNCTION_KEY / SCAN_PROXY_FUNCTION_KEY_BATCH)を照合してください。"
  exit 1
fi
echo "✅ 認証は全エンドポイントで正常(401以外)"
