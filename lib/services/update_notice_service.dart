import 'package:shared_preferences/shared_preferences.dart';

import '../data/changelog_data.dart';

/// 「アプリの更新に気づけない」問題への対応。
///
/// 更新履歴(changelog_data.dart)の最新バージョンと、このスマホ端末で
/// 最後に確認したバージョンをshared_preferencesで比較し、未確認の更新が
/// あればホーム画面に通知バナーを表示するために使う。
///
/// 【注意】これはアプリ内のお知らせ機能であり、Webビルド/APKビルドを
/// 差し替えて再インストールしない限り、そもそも新しいコードは端末に
/// 届かない(=バナーの元になる新changelogEntry自体が存在しない)。
/// 実機へ反映するには、必ず新しいAPKをビルドして再インストールすること。
class UpdateNoticeService {
  static const _lastSeenVersionKey = 'last_seen_changelog_version';

  /// 未確認の更新があるかどうか。
  static Future<bool> hasUnseenUpdate() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSeen = prefs.getString(_lastSeenVersionKey);
    final latest = changelogEntries.isEmpty
        ? null
        : changelogEntries.first.version;
    if (latest == null) return false;
    return lastSeen != latest;
  }

  /// 現在の最新バージョンを「確認済み」として記録する。
  /// 更新履歴画面を開いたタイミングで呼び出す。
  static Future<void> markLatestAsSeen() async {
    if (changelogEntries.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSeenVersionKey, changelogEntries.first.version);
  }
}
