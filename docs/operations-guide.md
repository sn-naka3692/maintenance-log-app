# 日報アプリ 運用ガイド(トラブル防止チェックリスト)

2026-10-10 のスキャン401・インストール失敗・バナー不整合の全障害を踏まえた防止策。

## 絶対ルール
1. **署名キーを再生成しない** — GitHubシークレット `APK_KEYSTORE_B64` 等は正規キー(v1.2.55以降、CN=Nakano Reiki)。再生成すると全端末で再インストールが必要になる
2. **scan と scan_batch は別々の関数キーを持つ** — アプリはCIシークレット(`SCAN_PROXY_FUNCTION_KEY` / `SCAN_PROXY_FUNCTION_KEY_BATCH`)で両方を埋め込む。片方だけ更新しない
3. **Azure Portal は `naka-p@sapporonakano.onmicrosoft.com` でサインイン**(naka@にはサブスクリプション権限がない)
4. **build_info.dart の値を手で書き換えない** — CIが自動同期する

## Azure リソース一覧
| リソース | 名前 |
|---|---|
| サブスクリプション | Azure subscription 1 |
| リソースグループ | nakano-reikiken-rg |
| 関数アプリ | nakano-scan-proxy(関数: health / scan / scan_batch。scan_batchのURLルートは scanBatch) |
| Document Intelligence | nakano-doc-intelligence(S0) |

## リリース手順(毎回この5点)
1. pubspec.yaml のバージョンを +1(例: 1.2.56+65)
2. lib/data/changelog_data.dart の先頭に更新履歴を追加(**閉じ括弧 `),` を忘れない** — 過去2回これでCI失敗)
3. commit → push → タグを打って push
4. CI成功を確認(署名ガード・スモークテストは自動で失敗を止める)
5. リリース後: version.json とバナー設定が更新されたことを確認

## トラブル時の切り分け
- スキャン401 → scripts/health_check.sh で実測 → 401なら Azure側キーとGitHubシークレットを照合
- インストールできない → (1)ファイルサイズ31.9MB確認 (2)Playプロテクトで「インストールする」(3)それでもダメならアンインストール→再インストール
- バナーが出ない/消えない → version.json と Firestore app_config/settings を確認
