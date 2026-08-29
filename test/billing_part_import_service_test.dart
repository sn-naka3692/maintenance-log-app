import 'dart:convert';

import 'package:archive/archive.dart';
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

  test(
    '内容が完全一致する部品名(共有文字列)が複数行に登場しても'
    'excelパッケージの重複排除バグでクラッシュせず正しく読み取れる',
    () {
      // 実際にSDRSから届くExcelでは、同じ部品名(例:「アンカークリップ」)
      // が複数の明細行にまたがって登場する。excelパッケージ(4.0.6)は
      // sharedStrings.xml内の内容が完全一致する<si>要素を内部で重複排除
      // するが、各シートのセルは重複排除前の「元の出現順インデックス」
      // を参照しているため、後方の同一文字列を参照するセルで
      // 「Null check operator used on a null value」例外が発生する
      // 既知の不具合がある(BillingPartImportServiceの
      // _sanitizeSharedStrings で回避)。
      final bytes = buildSampleXlsx();
      final duplicated = _duplicateSharedString(bytes, '2606sa0000356185');

      // 事前条件の再現確認: 素の状態(サニタイズ前)でexcelパッケージへ
      // 直接読み込ませるとクラッシュすることを確認する。
      expect(
        () => xls.Excel.decodeBytes(duplicated),
        throwsA(isA<TypeError>()),
      );

      // BillingPartImportService.parse は内部でサニタイズしてから
      // 読み込むため、例外を起こさず正しく明細を取得できるはず。
      final records = BillingPartImportService.parse(duplicated);
      expect(records.length, 2);
      expect(records[0].receiptNumber, '2606sa0000356185');
      expect(records[0].parts.length, 2);
      expect(records[0].parts[0].name, 'コンプレッサー');
      expect(records[1].receiptNumber, '2606sa0000399999');
    },
  );
}

/// 与えられたxlsxバイト列の`xl/sharedStrings.xml`内で、[targetText]と
/// 完全一致する`<si>`要素をもう1つ複製して末尾に追加し、さらに
/// ワークシート側(1行目)に、その複製要素を実際に参照するセルを
/// 追加することで、実際にSDRSファイルで観測された不具合状況
/// (「内容が重複する共有文字列が複数存在し、後方の重複文字列を
/// 参照するセルが範囲外インデックスとなる」)を再現する。
///
/// excelパッケージ(4.0.6)は`<si>`の内容が完全一致するものを内部で
/// 重複排除して`_list`(実体を保持する配列)に積むため、重複排除後の
/// `_list`の長さは元の`<si>`総数より短くなる。一方、ワークシートの
/// セルは重複排除前の「元の出現順インデックス」をそのまま参照する
/// ため、複製した(=末尾に追加した)`<si>`を参照するセルを作ると、
/// そのインデックスが`_list`の範囲外となり例外が発生する。
List<int> _duplicateSharedString(List<int> bytes, String targetText) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final sharedStringsFile = archive.findFile('xl/sharedStrings.xml');
  final sheetFile = archive.findFile('xl/worksheets/sheet1.xml');
  if (sharedStringsFile == null || sheetFile == null) {
    throw StateError('必要なXMLファイルが見つかりません(テスト前提が崩れています)');
  }

  final ssContent = utf8.decode(sharedStringsFile.content as List<int>);
  final siPattern = RegExp(
    '<si><t[^>]*>${RegExp.escape(targetText)}</t></si>',
  );
  final match = siPattern.firstMatch(ssContent);
  if (match == null) {
    throw StateError('複製対象の共有文字列 "$targetText" が見つかりません');
  }
  final targetTag = match.group(0)!;

  // 複製前の<si>総数 = 複製後に追加される要素の(0始まり)インデックス。
  final originalSiCount = RegExp('<si>').allMatches(ssContent).length;
  final newIndex = originalSiCount;

  // 対象の<si>をもう1つ複製して</sst>の直前に挿入する。
  final duplicatedSsContent = ssContent.replaceFirst(
    '</sst>',
    '$targetTag</sst>',
  );
  final updatedSsContent = duplicatedSsContent.replaceFirstMapped(
    RegExp(r'count="(\d+)"'),
    (m) => 'count="${int.parse(m.group(1)!) + 1}"',
  );

  // ワークシート1行目に、複製した<si>(newIndex)を参照する新しいセルを
  // 追加する(未使用の列 "ZZ1" を使い、既存の列検出ロジックには影響
  // させない)。
  final sheetContent = utf8.decode(sheetFile.content as List<int>);
  final rowOnePattern = RegExp(r'<row r="1">.*?</row>');
  final rowOneMatch = rowOnePattern.firstMatch(sheetContent);
  if (rowOneMatch == null) {
    throw StateError('1行目の<row>要素が見つかりません(テスト前提が崩れています)');
  }
  final rowOneTag = rowOneMatch.group(0)!;
  final newCell = '<c r="ZZ1" t="s"><v>$newIndex</v></c>';
  final updatedRowOneTag = rowOneTag.replaceFirst(
    '</row>',
    '$newCell</row>',
  );
  final updatedSheetContent = sheetContent.replaceFirst(
    rowOneTag,
    updatedRowOneTag,
  );

  final newArchive = Archive();
  for (final f in archive.files) {
    if (f.name == 'xl/sharedStrings.xml') {
      final data = utf8.encode(updatedSsContent);
      newArchive.addFile(ArchiveFile(f.name, data.length, data));
    } else if (f.name == 'xl/worksheets/sheet1.xml') {
      final data = utf8.encode(updatedSheetContent);
      newArchive.addFile(ArchiveFile(f.name, data.length, data));
    } else {
      newArchive.addFile(f);
    }
  }
  final encoded = ZipEncoder().encode(newArchive);
  return encoded!;
}
