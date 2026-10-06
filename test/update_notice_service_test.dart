// 【回帰テスト・2026-10-06追加】
//
// UpdateNoticeService(アプリ内changelogの「未読」バッジ判定)のロジック。
// これはAppConfigService(サーバー比較方式の更新お知らせ)とは別の
// 独立した通知経路であり、「今動いているコードに、既に入っている
// 最新のchangelogEntryを、この端末でまだ見ていない」ことを検知する。
//
// shared_preferencesはテスト用のインメモリモック
// (SharedPreferences.setMockInitialValues)が公式に提供されているため、
// 実機・ブラウザなしでロジックを検証できる。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_app/services/update_notice_service.dart';

void main() {
  setUp(() {
    // 各テスト実行前に「保存された値が何もない状態」にリセットする。
    SharedPreferences.setMockInitialValues({});
  });

  group('UpdateNoticeService.hasUnseenUpdate', () {
    test('一度もmarkLatestAsSeenを呼んでいない場合は未読ありと判定する', () async {
      final result = await UpdateNoticeService.hasUnseenUpdate();
      // changelogEntriesが1件以上存在する前提(実データ依存だが、
      // 本アプリのchangelog_data.dartは常に1件以上登録されている)。
      expect(result, true);
    });

    test('markLatestAsSeenを呼んだ直後は未読なしと判定する', () async {
      await UpdateNoticeService.markLatestAsSeen();
      final result = await UpdateNoticeService.hasUnseenUpdate();
      expect(result, false);
    });

    test(
      '保存されているバージョンが最新と異なる(古いバージョンを見たまま)場合は'
      '未読ありと判定する',
      () async {
        SharedPreferences.setMockInitialValues({
          'last_seen_changelog_version': '0.0.1-ありえない古いバージョン',
        });
        final result = await UpdateNoticeService.hasUnseenUpdate();
        expect(result, true);
      },
    );
  });
}
