import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/utils/scan_date_parser.dart';

void main() {
  group('tryParseScanDate', () {
    test('プロワンOCR特有の "2026 08/26" 形式(年月日区切りが空白+スラッシュ)を解析できる', () {
      final result = tryParseScanDate('2026 08/26');
      expect(result, isNotNull);
      expect(result, DateTime(2026, 8, 26));
    });

    test('スラッシュ区切り "2026/08/17" を解析できる', () {
      final result = tryParseScanDate('2026/08/17');
      expect(result, DateTime(2026, 8, 17));
    });

    test('ハイフン区切り混在 "2026 08-17" を解析できる', () {
      final result = tryParseScanDate('2026 08-17');
      expect(result, DateTime(2026, 8, 17));
    });

    test('全角の年月日表記 "2026年8月17日" を解析できる', () {
      final result = tryParseScanDate('2026年8月17日');
      expect(result, DateTime(2026, 8, 17));
    });

    test('前後に空白やゴミ文字が付いていても解析できる', () {
      final result = tryParseScanDate('  2026 08/17  ');
      expect(result, DateTime(2026, 8, 17));
    });

    test('日付として解釈できない文字列はnullを返す', () {
      expect(tryParseScanDate(''), isNull);
      expect(tryParseScanDate('未完了'), isNull);
      expect(tryParseScanDate('R22'), isNull);
    });

    test('実在しない日付(例:2月30日)はnullを返す', () {
      expect(tryParseScanDate('2026/02/30'), isNull);
    });

    // 【不具合対応・2026-09-10】WorkStartDate実運用データの再学習検証で
    // 判明した「日付以外の文字列混入」パターン(scan_date_parser.dartの
    // クラスコメント参照)。時刻混入・複数日付混入いずれも、最後に
    // 出現する日付候補を採用することで正しい日付を取得できる。
    test('日付の後に作業開始時刻が続く場合、時刻を無視して日付のみ解析できる', () {
      final result = tryParseScanDate('2026 08/26 08:30');
      expect(result, DateTime(2026, 8, 26));
    });

    test('複数の日付候補が含まれる場合、最後(一番後ろ)の日付を採用する', () {
      // 訪問日欄が複数行ある報告書で、前回訪問日+今回訪問日+時刻の
      // 3つが連結して抽出されるケース(regression_report実測パターン)。
      final result = tryParseScanDate('2026 08/18 2026 08/27 21:00');
      expect(result, DateTime(2026, 8, 27));
    });

    test('複数の日付候補+時刻がなくても最後の日付を採用する', () {
      final result = tryParseScanDate('2026 08/18 2026 08/27');
      expect(result, DateTime(2026, 8, 27));
    });
  });

  group('isSameCalendarDay', () {
    test('年月日が一致する場合はtrue(時刻が異なっても)', () {
      final a = DateTime(2026, 8, 17, 9, 0);
      final b = DateTime(2026, 8, 17, 23, 59);
      expect(isSameCalendarDay(a, b), isTrue);
    });

    test('日が異なる場合はfalse', () {
      final a = DateTime(2026, 8, 17);
      final b = DateTime(2026, 8, 18);
      expect(isSameCalendarDay(a, b), isFalse);
    });

    test('年が異なる場合はfalse(同じ月日でも)', () {
      final a = DateTime(2025, 8, 17);
      final b = DateTime(2026, 8, 17);
      expect(isSameCalendarDay(a, b), isFalse);
    });
  });
}
