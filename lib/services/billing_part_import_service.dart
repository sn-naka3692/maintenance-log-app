import 'package:excel/excel.dart' as xls;

import '../models/billing_part_record.dart';

/// SDRSから毎月末頃に届く「SEJ請求 」シート形式のExcelを解析し、
/// 部品情報(BillingPartRecord)のリストへ変換するサービス。
///
/// 【対象フォーマット】「SE請求明細書」Excel(SEJ請求 シート)
/// - 8行目: ヘッダー行(列名が入っている)
/// - 9行目以降: 1行=1案件の明細
/// - 「弊社受付NO」列(突合キー)
/// - 「使用部品名1」「使用個数」/「使用部品名2」「使用個数」/
///   「使用部品名3」「使用個数」の3ペア(列位置はヘッダー名で自動検出)
///
/// 【設計方針】
/// 列の並び順がファイルごとに多少変わっても壊れないよう、列インデックス
/// は固定せずヘッダー行のテキストから都度検出する。ヘッダーが見つから
/// ない列は無視する(致命的な欠落は呼び出し側でエラー表示する)。
class BillingPartImportService {
  BillingPartImportService._();

  /// 部品ペア(名称列, 個数列)を探すためのヘッダーラベルの組。
  static const List<String> _partNameHeaders = [
    '使用部品名1',
    '使用部品名2',
    '使用部品名3',
  ];
  static const String _quantityHeaderSuffix = '使用個数';

  /// 突合キーとなる受付No列の候補ヘッダー名(表記ゆれに対応)。
  static const List<String> _receiptNumberHeaders = ['弊社受付NO', '弊社受付No', '受付NO'];

  static const List<String> _storeNameHeaders = ['店舗名称'];
  static const List<String> _storeNumberHeaders = ['店番'];
  static const List<String> _equipmentNameHeaders = ['設備名称'];
  static const List<String> _repairDateHeaders = ['修理年月日'];

  /// SDRS請求明細Excel(xlsx)のバイト列を解析し、部品情報を含む
  /// 明細一覧を返す。対象シートが見つからない場合は例外を投げる。
  static List<BillingPartRecord> parse(List<int> bytes) {
    final excel = xls.Excel.decodeBytes(bytes);

    // シート名は年月や版で完全一致しないことがあるため、
    // 「請求」を含むシート名を優先的に探す。見つからなければ先頭シート。
    xls.Sheet? sheet;
    for (final name in excel.tables.keys) {
      if (name.contains('請求')) {
        sheet = excel.tables[name];
        break;
      }
    }
    sheet ??= excel.tables.values.isNotEmpty
        ? excel.tables.values.first
        : null;
    if (sheet == null) {
      throw const FormatException('Excel内にシートが見つかりませんでした。');
    }

    final rows = sheet.rows;

    // ヘッダー行を探す(先頭から数行の中で、受付No列が見つかる行)。
    int headerRowIndex = -1;
    Map<int, String> headerByCol = {};
    for (int r = 0; r < rows.length && r < 15; r++) {
      final rowMap = <int, String>{};
      for (int c = 0; c < rows[r].length; c++) {
        final v = _cellText(rows[r][c]);
        if (v.isNotEmpty) rowMap[c] = v;
      }
      if (rowMap.values.any((v) => _receiptNumberHeaders.contains(v))) {
        headerRowIndex = r;
        headerByCol = rowMap;
        break;
      }
    }
    if (headerRowIndex == -1) {
      throw const FormatException(
        'ヘッダー行(弊社受付NO列)が見つかりませんでした。想定と異なるフォーマットの'
        'Excelの可能性があります。',
      );
    }

    int? findCol(List<String> candidates) {
      for (final entry in headerByCol.entries) {
        if (candidates.contains(entry.value)) return entry.key;
      }
      return null;
    }

    final receiptCol = findCol(_receiptNumberHeaders);
    if (receiptCol == null) {
      throw const FormatException('受付No列が見つかりませんでした。');
    }
    final storeNameCol = findCol(_storeNameHeaders);
    final storeNumberCol = findCol(_storeNumberHeaders);
    final equipmentCol = findCol(_equipmentNameHeaders);
    final repairDateCol = findCol(_repairDateHeaders);

    // 部品名列ごとに対応する「使用個数」列(直後の列であることが多いが、
    // 念のためヘッダー名で個別に検出する。3ペア分)。
    final partNameCols = <int>[];
    for (final h in _partNameHeaders) {
      final col = findCol([h]);
      if (col != null) partNameCols.add(col);
    }
    // 使用個数列は複数存在するため、部品名列の直後にある「使用個数」列を
    // それぞれ個別に対応付ける。
    final quantityColsForPartCol = <int, int>{};
    for (final nameCol in partNameCols) {
      // 部品名列の右隣から数列以内で最初に見つかった「使用個数」列を採用。
      for (int c = nameCol + 1; c <= nameCol + 3 && c < 200; c++) {
        if (headerByCol[c] == _quantityHeaderSuffix) {
          quantityColsForPartCol[nameCol] = c;
          break;
        }
      }
    }

    final records = <BillingPartRecord>[];
    for (int r = headerRowIndex + 1; r < rows.length; r++) {
      final row = rows[r];
      String cellAt(int? col) {
        if (col == null || col >= row.length) return '';
        return _cellText(row[col]);
      }

      final receiptNumber = cellAt(receiptCol);
      if (receiptNumber.isEmpty) continue; // 空行はスキップ

      final parts = <BillingPartRecordItem>[];
      for (final nameCol in partNameCols) {
        final name = cellAt(nameCol);
        if (name.isEmpty) continue;
        final qtyCol = quantityColsForPartCol[nameCol];
        final qtyText = cellAt(qtyCol);
        final qty = int.tryParse(qtyText) ?? (qtyText.isEmpty ? 1 : 1);
        parts.add(BillingPartRecordItem(name: name, quantity: qty));
      }

      records.add(
        BillingPartRecord(
          receiptNumber: receiptNumber,
          storeName: cellAt(storeNameCol),
          storeNumber: cellAt(storeNumberCol),
          repairDate: _tryParseDateCell(
            repairDateCol != null && repairDateCol < row.length
                ? row[repairDateCol]
                : null,
          ),
          equipmentName: cellAt(equipmentCol),
          parts: parts,
        ),
      );
    }

    return records;
  }

  static String _cellText(xls.Data? cell) {
    final value = cell?.value;
    if (value == null) return '';
    if (value is xls.DateCellValue) {
      return value.asDateTimeLocal().toIso8601String();
    }
    if (value is xls.TextCellValue) {
      return value.value.text?.trim() ?? '';
    }
    return value.toString().trim();
  }

  static DateTime? _tryParseDateCell(xls.Data? cell) {
    final value = cell?.value;
    if (value == null) return null;
    if (value is xls.DateCellValue) return value.asDateTimeLocal();
    if (value is xls.DateTimeCellValue) {
      return DateTime(
        value.year,
        value.month,
        value.day,
        value.hour,
        value.minute,
        value.second,
      );
    }
    return null;
  }
}
