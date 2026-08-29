import 'package:excel/excel.dart' as xls;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/services/billing_part_import_service.dart';

/// BillingPartImportService(SDRS月次請求明細Excelのパース処理)のテスト。
///
/// 実際のSDRS「SE請求明細書」フォーマット(シート名「SEJ請求 」、8行目が
/// ヘッダー、9行目以降が明細)を模した最小限のExcelをコード上で組み立てて
/// 検証する(本物のファイルをテスト資産として同梱する代わりに、列検出
/// ロジックがヘッダー名ベースで動くことを確認する)。
void main() {
  /// テスト用のシンプルな請求明細Excel(bytes)を組み立てるヘルパー。
  /// [headerRow] はゼロ始まりの行インデックス(実物は7=8行目相当)。
  List<int> buildSampleXlsx({int headerRowIndex = 7}) {
    final excel = xls.Excel.createExcel();
    final sheet = excel['SEJ請求 '];
    // デフォルトで自動生成される'Sheet1'を削除しておく。
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    // ヘッダー行より前は適当な空行/タイトル行で埋める。
    for (int r = 0; r < headerRowIndex; r++) {
      sheet.appendRow([xls.TextCellValue('タイトル行$r')]);
    }

    // ヘッダー行(列インデックス: 弊社受付NO=0, 店舗名称=1, 店番=2,
    // 修理年月日=3, 設備名称=4, 使用部品名1=5, 使用個数=6,
    // 使用部品名2=7, 使用個数=8, 使用部品名3=9, 使用個数=10)
    sheet.appendRow([
      xls.TextCellValue('弊社受付NO'),
      xls.TextCellValue('店舗名称'),
      xls.TextCellValue('店番'),
      xls.TextCellValue('修理年月日'),
      xls.TextCellValue('設備名称'),
      xls.TextCellValue('使用部品名1'),
      xls.TextCellValue('使用個数'),
      xls.TextCellValue('使用部品名2'),
      xls.TextCellValue('使用個数'),
      xls.TextCellValue('使用部品名3'),
      xls.TextCellValue('使用個数'),
    ]);

    // 明細行1: 部品2件
    sheet.appendRow([
      xls.TextCellValue('2606sa0000356185'),
      xls.TextCellValue('札幌中野店'),
      xls.TextCellValue('00123'),
      xls.TextCellValue('2026/08/10'),
      xls.TextCellValue('冷凍ショーケース'),
      xls.TextCellValue('コンプレッサー'),
      xls.IntCellValue(1),
      xls.TextCellValue('ファンモーター'),
      xls.IntCellValue(2),
      xls.TextCellValue(''),
      xls.TextCellValue(''),
    ]);

    // 明細行2: 部品なし(受付Noのみ)
    sheet.appendRow([
      xls.TextCellValue('2606sa0000399999'),
      xls.TextCellValue('別の店舗'),
      xls.TextCellValue('00456'),
      xls.TextCellValue('2026/08/15'),
      xls.TextCellValue('空調機'),
      xls.TextCellValue(''),
      xls.TextCellValue(''),
      xls.TextCellValue(''),
      xls.TextCellValue(''),
      xls.TextCellValue(''),
      xls.TextCellValue(''),
    ]);

    // 空行(受付Noが空 -> スキップされるはず)
    sheet.appendRow([xls.TextCellValue('')]);

    return excel.encode()!;
  }

  test('ヘッダー行・列をヘッダー名から検出し、明細をパースできる', () {
    final bytes = buildSampleXlsx();
    final records = BillingPartImportService.parse(bytes);

    expect(records.length, 2);

    final r1 = records[0];
    expect(r1.receiptNumber, '2606sa0000356185');
    expect(r1.normalizedReceiptNumber, '2606SA0000356185');
    expect(r1.storeName, '札幌中野店');
    expect(r1.storeNumber, '00123');
    expect(r1.equipmentName, '冷凍ショーケース');
    expect(r1.hasParts, isTrue);
    expect(r1.parts.length, 2);
    expect(r1.parts[0].name, 'コンプレッサー');
    expect(r1.parts[0].quantity, 1);
    expect(r1.parts[1].name, 'ファンモーター');
    expect(r1.parts[1].quantity, 2);

    final r2 = records[1];
    expect(r2.receiptNumber, '2606sa0000399999');
    expect(r2.hasParts, isFalse);
    expect(r2.parts, isEmpty);
  });

  test('受付No列が見つからない場合は例外を投げる', () {
    final excel = xls.Excel.createExcel();
    final sheet = excel['請求データ'];
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }
    sheet.appendRow([xls.TextCellValue('店舗名称'), xls.TextCellValue('店番')]);
    sheet.appendRow([xls.TextCellValue('テスト店'), xls.TextCellValue('001')]);
    final bytes = excel.encode()!;

    expect(
      () => BillingPartImportService.parse(bytes),
      throwsA(isA<FormatException>()),
    );
  });

  test('ヘッダー行の位置が多少ずれても検出できる(先頭に余分な行があっても可)', () {
    final bytes = buildSampleXlsx(headerRowIndex: 3);
    final records = BillingPartImportService.parse(bytes);
    expect(records.length, 2);
    expect(records[0].parts.length, 2);
  });
}
