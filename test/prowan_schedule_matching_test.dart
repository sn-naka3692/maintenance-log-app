// エンドツーエンド検証: Azureカスタムモデル(prowan-report-v1)が実際に
// 返すWorkStartDate値("2026 08/26"形式)を使って、複数日程(関連案件)の
// うち正しい1件をFirestoreキャッシュから選び出せることを確認するテスト。
//
// 実際にAzureへ本番PDFを投げて得られた出力値(2026-08-27実施の検証結果)を
// そのまま入力値として使用している:
//   - 幌向店(A2026081194, 2日程): WorkStartDate="2026 08/26"
//   - 奥沢店(A2026081148, 3日程): WorkStartDate="2026 08/26"
//   - 栗山店(R2026080980, 2日程): WorkStartDate="2026 08/26"
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/models/prowan_job_cache.dart';

void main() {
  group('ProwanJobCache.findScheduleByScannedWorkStartDate (E2E)', () {
    test('幌向店: Azure実出力"2026 08/26"で最新日程(08/26)が選ばれる', () {
      final cache = ProwanJobCache.fromMap('A2026081194', {
        'store_name': 'ラッキーマート幌向店',
        'schedules': [
          {'schedule_start': '2026/08/25 13:45', 'work_content': '一次対応'},
          {'schedule_start': '2026/08/26 09:00', 'work_content': '本修理'},
        ],
      });

      final matched = cache.findScheduleByScannedWorkStartDate('2026 08/26');
      expect(matched, isNotNull);
      expect(matched!.scheduleStart, '2026/08/26 09:00');
      expect(matched.workContent, '本修理');
    });

    test('奥沢店: Azure実出力"2026 08/26"で3日程中の正しい1件(08/26)が選ばれる', () {
      final cache = ProwanJobCache.fromMap('A2026081148', {
        'store_name': 'スーパーアークス奥沢店',
        'schedules': [
          {'schedule_start': '2026/08/20 16:15', 'work_content': '発見・点検'},
          {'schedule_start': '2026/08/25 07:00', 'work_content': '部品調達待ち再訪'},
          {'schedule_start': '2026/08/26 13:00', 'work_content': '本修理完了'},
        ],
      });

      final matched = cache.findScheduleByScannedWorkStartDate('2026 08/26');
      expect(matched, isNotNull);
      expect(matched!.scheduleStart, '2026/08/26 13:00');
      expect(matched.workContent, '本修理完了');
    });

    test('奥沢店: スキャン値が中間日程(08/25)に近い場合はその日程が選ばれる', () {
      final cache = ProwanJobCache.fromMap('A2026081148', {
        'store_name': 'スーパーアークス奥沢店',
        'schedules': [
          {'schedule_start': '2026/08/20 16:15', 'work_content': '発見・点検'},
          {'schedule_start': '2026/08/25 07:00', 'work_content': '部品調達待ち再訪'},
          {'schedule_start': '2026/08/26 13:00', 'work_content': '本修理完了'},
        ],
      });

      final matched = cache.findScheduleByScannedWorkStartDate('2026 08/25');
      expect(matched, isNotNull);
      expect(matched!.scheduleStart, '2026/08/25 07:00');
      expect(matched.workContent, '部品調達待ち再訪');
    });

    test('栗山店: Azure実出力"2026 08/26"で最新日程(08/26)が選ばれる', () {
      final cache = ProwanJobCache.fromMap('R2026080980', {
        'store_name': 'ラッキー栗山店',
        'schedules': [
          {'schedule_start': '2026/08/17 16:00', 'work_content': '一次対応'},
          {'schedule_start': '2026/08/26 13:00', 'work_content': '本修理'},
        ],
      });

      final matched = cache.findScheduleByScannedWorkStartDate('2026 08/26');
      expect(matched, isNotNull);
      expect(matched!.scheduleStart, '2026/08/26 13:00');
    });

    test('単一日程(schedules.length < 2)の場合は常にnull(選択の余地なし)', () {
      final cache = ProwanJobCache.fromMap('R2026080987', {
        'store_name': 'ラッキー倶知安店',
        'schedules': [
          {'schedule_start': '2026/08/19 09:30', 'work_content': '定期点検'},
        ],
      });

      final matched = cache.findScheduleByScannedWorkStartDate('2026 08/19');
      expect(matched, isNull);
    });

    test('WorkStartDateが空欄(OCR未検出)の場合はnull(呼び出し元がフォールバック)', () {
      final cache = ProwanJobCache.fromMap('A2026081194', {
        'store_name': 'ラッキーマート幌向店',
        'schedules': [
          {'schedule_start': '2026/08/25 13:45', 'work_content': '一次対応'},
          {'schedule_start': '2026/08/26 09:00', 'work_content': '本修理'},
        ],
      });

      final matched = cache.findScheduleByScannedWorkStartDate('');
      expect(matched, isNull);
    });

    test('スラッシュ表記"2026/08/26"でも従来通り解析できる(後方互換)', () {
      final cache = ProwanJobCache.fromMap('A2026081194', {
        'store_name': 'ラッキーマート幌向店',
        'schedules': [
          {'schedule_start': '2026/08/25 13:45', 'work_content': '一次対応'},
          {'schedule_start': '2026/08/26 09:00', 'work_content': '本修理'},
        ],
      });

      final matched = cache.findScheduleByScannedWorkStartDate('2026/08/26');
      expect(matched, isNotNull);
      expect(matched!.scheduleStart, '2026/08/26 09:00');
    });

    test('和暦風表記"2026年08月26日"でも解析できる', () {
      final cache = ProwanJobCache.fromMap('A2026081194', {
        'store_name': 'ラッキーマート幌向店',
        'schedules': [
          {'schedule_start': '2026/08/25 13:45', 'work_content': '一次対応'},
          {'schedule_start': '2026/08/26 09:00', 'work_content': '本修理'},
        ],
      });

      final matched = cache.findScheduleByScannedWorkStartDate('2026年08月26日');
      expect(matched, isNotNull);
      expect(matched!.scheduleStart, '2026/08/26 09:00');
    });
  });
}
