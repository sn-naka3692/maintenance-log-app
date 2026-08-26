#!/usr/bin/env python3
"""
リリースのたびに実行する、Firestore app_config/settings の
latest_version / latest_build_number を更新するスクリプト。

【背景・重要】
このアプリの「新しいバージョンがあります」お知らせ(ホーム画面バナー)は、
Firestoreの app_config/settings ドキュメントにある latest_version /
latest_build_number の値と、実機のビルド番号を比較して判定している
(lib/services/app_config_service.dart 参照)。

このスクリプトを実行し忘れると、実際に新しいAPKをGitHub Releasesへ
アップロードしても、社員のホーム画面には「新しいバージョンがあります」
という通知が一切表示されない(値が古いまま)ため、必ず新バージョンの
APKビルド・GitHub Release作成とセットで実行すること。

なお download_url は GitHub Releases の "latest" 固定URLを使うため、
一度設定すれば変更不要(値は変わらない)。
    https://github.com/sn-naka3692/maintenance-log-app/releases/latest/download/app-release.apk

使い方:
    python3 scripts/release_version_config.py 1.2.15 24
    (第1引数: pubspec.yaml の version 名, 第2引数: pubspec.yaml の build number)
"""
import sys

import firebase_admin
from firebase_admin import credentials, firestore

DOWNLOAD_URL = (
    "https://github.com/sn-naka3692/maintenance-log-app/"
    "releases/latest/download/app-release.apk"
)


def main():
    if len(sys.argv) != 3:
        print("使い方: python3 release_version_config.py <version> <build_number>")
        print("例:     python3 release_version_config.py 1.2.15 24")
        sys.exit(1)

    version = sys.argv[1]
    try:
        build_number = int(sys.argv[2])
    except ValueError:
        print(f"エラー: build_numberは整数で指定してください: {sys.argv[2]}")
        sys.exit(1)

    if not firebase_admin._apps:
        cred = credentials.Certificate("/opt/flutter/firebase-admin-sdk.json")
        firebase_admin.initialize_app(cred)

    db = firestore.client()
    doc_ref = db.collection("app_config").document("settings")

    doc_ref.set(
        {
            "latest_version": version,
            "latest_build_number": build_number,
            "download_url": DOWNLOAD_URL,
            "updated_at": firestore.SERVER_TIMESTAMP,
        },
        merge=True,
    )

    doc = doc_ref.get()
    print(f"✅ app_config/settings を更新しました: {doc.to_dict()}")


if __name__ == "__main__":
    main()
