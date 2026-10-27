# 日報アプリ 運用ガイド(トラブル防止チェックリスト)

2026-10-10 のスキャン401・インストール失敗・バナー不整合、および 2026-10-20 の起動時権限エラーを踏まえた防止策。
**最終更新: 2026-10-28 / 最新リリース: v1.2.58(build 67)**

## 絶対ルール
1. **署名キーを再生成しない** — GitHubシークレット `APK_KEYSTORE_B64` 等は正規キー(v1.2.55以降、CN=Nakano Reiki)。再生成すると全端末で再インストールが必要になる
2. **scan と scan_batch は別々の関数キーを持つ** — アプリはCIシークレット(`SCAN_PROXY_FUNCTION_KEY` / `SCAN_PROXY_FUNCTION_KEY_BATCH`)で両方を埋め込む。片方だけ更新しない
3. **Azure Portal は `naka-p@sapporonakano.onmicrosoft.com` でサインイン**(naka@にはサブスクリプション権限がない)
4. **build_info.dart の値を手で書き換えない** — CIが自動同期する
5. **退職者は「社員を削除」で対応する** — 案件・日報は消えず、ダッシュボードの氏名別集計からは自動で非表示(v1.2.57)。Firestoreで直接データを消さない

## 現在の状態(2026-10-28時点)
| 項目 | 状態 |
|---|---|
| 最新版 | v1.2.58(build 67) |
| 署名 | CN=Nakano Reiki の正規キー(v1.2.55〜58 の4リリース連続で同一指紋を確認済み) |
| 起動時の社員マスタ自動投入 | usersコレクションが空の時のみ(v1.2.58で制限。非管理者の起動で権限エラーは出ない) |
| 起動時エラー表示 | 日本語化済み(v1.2.58) |
| 未実施 | `/api/disableUser` のサーバー配信(退職者のFirebaseアカウント無効化。アプリ側ログイン拒否で当面は安全) |

## Azure リソース一覧
| リソース | 名前 |
|---|---|
| サブスクリプション | Azure subscription 1 |
| リソースグループ | nakano-reikiken-rg |
| 関数アプリ | nakano-scan-proxy(関数: health / scan / scan_batch。scan_batchのURLルートは scanBatch) |
| Document Intelligence | nakano-doc-intelligence(S0) |

## リリース手順(毎回この5点)
1. pubspec.yaml のバージョンを +1(例: 1.2.59+68)
2. lib/data/changelog_data.dart の先頭に更新履歴を追加(**閉じ括弧 `),` を忘れない** — 過去2回これでCI失敗)
3. commit → push → タグを打って push
4. CI成功を確認(署名ガード・スモークテストは自動で失敗を止める)
5. リリース後: version.json とバナー設定が更新されたことを確認

## トラブル時の切り分け
- スキャン401 → scripts/health_check.sh で実測 → 401なら Azure側キーとGitHubシークレットを照合
- インストールできない → (1)ファイルサイズ約32MB確認 (2)Playプロテクトで「インストールする」(3)それでもダメならアンインストール→再インストール
- バナーが出ない/消えない → version.json と Firestore app_config/settings を確認
- 起動直後に「権限エラー(permission-denied)」 → 〜v1.2.57 の新規インストールで発生した既知事象。v1.2.58 で解消済み → 最新版への更新で解消
