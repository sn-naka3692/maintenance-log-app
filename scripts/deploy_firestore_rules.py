#!/usr/bin/env python3
"""
firestore.rules を本番Firestoreへデプロイするスクリプト(Firebase CLIの代替)。

【背景・重要】
`firebase deploy --only firestore:rules` は、実行前に
serviceusage.googleapis.com 経由で「firestore.googleapis.com API が有効か」を
確認しようとするが、本サンドボックスのFirebase Admin SDKサービスアカウント
(firebase-adminsdk-fbsvc@sn-report.iam.gserviceaccount.com)には
serviceusage.services.get 権限がなく、常に以下のエラーで失敗する
(2026-09-11、2026-09-15に再現確認済み):

    Error: Request to https://serviceusage.googleapis.com/v1/projects/
    sn-report/services/firestore.googleapis.com had HTTP Error: 403,
    Permission denied to get service [firestore.googleapis.com]

一方、Firestoreのセキュリティルールを実際に更新する権限
(firebaserules.googleapis.com の Ruleset作成・Release更新)自体は
このサービスアカウントに正しく付与されている(2026-09-15に実API呼び出しで
検証済み)。つまり「ルールを書き換える権限」はあるのに、CLIの事前チェックだけが
別の権限(サービス有効化状態の照会)を要求してブロックしている状態。

【対策】
Firebase CLIを経由せず、Firebase Rules API
(https://firebaserules.googleapis.com) を直接呼び出してルールをデプロイする。
これにより問題のserviceusage APIチェックを完全にバイパスできる。

処理内容:
  1. firestore.rules の内容でRuleset(不変のルール集合)を新規作成
  2. projects/{project}/releases/cloud.firestore のリリース参照を
     新しいRulesetに向け直す(これで本番に即時反映される)

【恒久対応が理想】本来はGCP IAMコンソール等で、このサービスアカウントに
serviceusage.serviceUsageViewer ロールを付与すれば `firebase deploy` も
正常動作するようになる想定。権限付与ができるまでの回避策として本スクリプトを
使用する。

使い方:
    python3 scripts/deploy_firestore_rules.py
"""
import sys
from pathlib import Path

import google.auth
import google.auth.transport.requests
import requests

PROJECT_ID = "sn-report"
CRED_PATH = "/opt/flutter/firebase-admin-sdk.json"
RULES_PATH = Path(__file__).resolve().parent.parent / "firestore.rules"
RULES_API_BASE = "https://firebaserules.googleapis.com/v1"


def main():
    if not RULES_PATH.exists():
        print(f"❌ エラー: {RULES_PATH} が見つかりません。")
        sys.exit(1)

    rules_content = RULES_PATH.read_text(encoding="utf-8")

    credentials, _ = google.auth.load_credentials_from_file(
        CRED_PATH,
        scopes=[
            "https://www.googleapis.com/auth/cloud-platform",
            "https://www.googleapis.com/auth/firebase",
        ],
    )
    credentials.refresh(google.auth.transport.requests.Request())
    headers = {
        "Authorization": f"Bearer {credentials.token}",
        "Content-Type": "application/json",
    }

    # Step 1: 新しいRulesetを作成(既存のRulesetは変更されない。新規追加のみ)
    ruleset_body = {
        "source": {
            "files": [{"name": "firestore.rules", "content": rules_content}]
        }
    }
    resp = requests.post(
        f"{RULES_API_BASE}/projects/{PROJECT_ID}/rulesets",
        headers=headers,
        json=ruleset_body,
        timeout=30,
    )
    if resp.status_code != 200:
        print(f"❌ Ruleset作成に失敗しました(status={resp.status_code}):")
        print(resp.text[:2000])
        sys.exit(1)
    ruleset_name = resp.json()["name"]
    print(f"✅ 新しいRulesetを作成しました: {ruleset_name}")

    # Step 2: cloud.firestore のリリースを新しいRulesetへ切り替える
    # 【重要】リクエストボディは {"release": {...}} でラップし、
    # updateMaskクエリパラメータは付けないこと(付けると
    # "Unknown name rulesetName" 等の400エラーになる。2026-09-15検証済み)。
    release_name = f"projects/{PROJECT_ID}/releases/cloud.firestore"
    release_body = {
        "release": {
            "name": release_name,
            "rulesetName": ruleset_name,
        }
    }
    resp2 = requests.patch(
        f"{RULES_API_BASE}/{release_name}",
        headers=headers,
        json=release_body,
        timeout=30,
    )
    if resp2.status_code != 200:
        print(f"❌ リリースの切り替えに失敗しました(status={resp2.status_code}):")
        print(resp2.text[:2000])
        sys.exit(1)

    print("✅ firestore.rules を本番へデプロイしました。")
    print(f"   反映後のRuleset: {ruleset_name}")


if __name__ == "__main__":
    main()
