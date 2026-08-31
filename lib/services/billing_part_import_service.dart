import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xls;
import 'package:xml/xml.dart';

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
  static const List<String> _partNameHeaders = ['使用部品名1', '使用部品名2', '使用部品名3'];
  static const String _quantityHeaderSuffix = '使用個数';

  /// 突合キーとなる受付No列の候補ヘッダー名(表記ゆれに対応)。
  static const List<String> _receiptNumberHeaders = [
    '弊社受付NO',
    '弊社受付No',
    '受付NO',
  ];

  static const List<String> _storeNameHeaders = ['店舗名称'];
  static const List<String> _storeNumberHeaders = ['店番'];
  static const List<String> _equipmentNameHeaders = ['設備名称'];
  static const List<String> _repairDateHeaders = ['修理年月日'];

  /// SDRS請求明細Excel(xlsx)のバイト列を解析し、部品情報を含む
  /// 明細一覧を返す。対象シートが見つからない場合は例外を投げる。
  ///
  /// 【不具合対応・2026-08-28】実際にSDRSから届くExcelには、Excel本来の
  /// 仕様(カスタム数値書式のnumFmtIdは164以上)から外れて164未満の値が
  /// 使われているケースがあり(他ソフトでの編集・再保存等が原因と推測)、
  /// excelパッケージ(4.0.6)がこれを不正な形式として例外を投げてしまう。
  /// アプリ側では数値書式の情報自体は使わないため、事前にstyles.xml内の
  /// 該当箇所を無害化(該当numFmtエントリを除去)してから読み込むことで
  /// 回避する。
  static List<BillingPartRecord> parse(List<int> bytes) {
    final sanitized = _sanitizeSharedStrings(_sanitizeXlsxBytes(bytes));
    final excel = xls.Excel.decodeBytes(sanitized);

    // シート名は年月や版で完全一致しないことがあるため、
    // 「請求」を含むシート名を優先的に探す。見つからなければ先頭シート。
    xls.Sheet? sheet;
    for (final name in excel.tables.keys) {
      if (name.contains('請求')) {
        sheet = excel.tables[name];
        break;
      }
    }
    sheet ??= excel.tables.values.isNotEmpty ? excel.tables.values.first : null;
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
      return _stripZeroWidthMarkers(value.value.text?.trim() ?? '');
    }
    return _stripZeroWidthMarkers(value.toString().trim());
  }

  /// [_sanitizeSharedStrings]で重複解消のために埋め込んだ不可視マーカー
  /// (ゼロ幅文字)を、実際に読み取ったテキストから取り除く。
  static String _stripZeroWidthMarkers(String text) {
    return text.replaceAll(RegExp('[\u200B\u200C\u200D\uFEFF]'), '');
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

  /// xlsx(zip)内の `xl/styles.xml` にある `<numFmt numFmtId="...">` のうち、
  /// 164未満(Excel仕様上は組み込み書式用の番号帯)のエントリを取り除く。
  ///
  /// 用紙側の数値表示形式が変わるだけで、セルの実際の値
  /// (TextCellValue/IntCellValue等)には影響しないため、部品名・数量の
  /// 読み取りには支障がない。styles.xmlが見つからない、あるいは
  /// 解析中に何らかの理由で失敗した場合は、元のバイト列をそのまま返す
  /// (通常フォーマットのExcelであれば元々このワークアラウンドは不要な
  /// ため、安全側に倒して既存の動作を壊さない)。
  static List<int> _sanitizeXlsxBytes(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final stylesFile = archive.findFile('xl/styles.xml');
      if (stylesFile == null) return bytes;

      final content = utf8.decode(stylesFile.content as List<int>);
      final sanitized = _stripInvalidNumFmts(content);
      if (sanitized == content) return bytes; // 変更不要ならそのまま返す

      final newArchive = Archive();
      for (final f in archive.files) {
        if (f.name == 'xl/styles.xml') {
          final data = utf8.encode(sanitized);
          newArchive.addFile(ArchiveFile(f.name, data.length, data));
        } else {
          newArchive.addFile(f);
        }
      }
      final encoded = ZipEncoder().encode(newArchive);
      return encoded ?? bytes;
    } catch (_) {
      // サニタイズに失敗した場合は元のバイト列で通常通り読み込みを試みる。
      return bytes;
    }
  }

  /// styles.xml内の `<numFmt numFmtId="N" .../>` のうち N<164 のものを
  /// 文字列置換ベースで除去する(XMLパーサーを介さない軽量な実装)。
  static String _stripInvalidNumFmts(String xmlContent) {
    final numFmtPattern = RegExp(r'<numFmt\s+[^>]*?/>');
    return xmlContent.replaceAllMapped(numFmtPattern, (match) {
      final tag = match.group(0)!;
      final idMatch = RegExp(r'numFmtId="(\d+)"').firstMatch(tag);
      if (idMatch == null) return tag;
      final id = int.tryParse(idMatch.group(1)!) ?? 0;
      return id < 164 ? '' : tag;
    });
  }

  /// 【不具合対応・2026-09】excelパッケージ(4.0.6)は`xl/sharedStrings.xml`
  /// を読み込む際、内容(文字列値)が完全一致する`<si>`要素を「同一の共有
  /// 文字列」として重複排除し、内部リスト(`_list`)に1つだけ保持する。
  ///
  /// しかし各ワークシートのセル(`<c t="s"><v>N</v></c>`)は、
  /// sharedStrings.xml内での**元の出現順インデックス**(0始まり)を直接
  /// 参照する。実際にSDRSから届くExcelには、内容が完全一致する`<si>`
  /// (例:同じ部品名や同じ受付No文字列)が複数箇所に存在するため、
  /// 重複排除後の`_list`の長さが元の`<si>`要素数より短くなり、
  /// 後方の`<si>`を指すインデックスが範囲外となって
  /// `Null check operator used on a null value` 例外を引き起こす。
  ///
  /// 【対応方針】読み込み前に`sharedStrings.xml`内の`<si>`要素をすべて
  /// 「内容として重複しない」ように加工する。具体的には、2回目以降に
  /// 出現する同一内容の`<si>`の末尾に、出現順で一意なゼロ幅文字列
  /// (`\u200B`を出現回数分)を追加し、excelパッケージ側の重複排除
  /// ロジックが別々の文字列として扱うようにする。これにより
  /// `_list`の長さが常に元の`<si>`要素数と一致し、インデックス参照が
  /// 破綻しなくなる。読み取り後は[_stripZeroWidthMarkers]で除去する
  /// ため、アプリ側で扱う実際のテキスト内容には影響しない。
  static List<int> _sanitizeSharedStrings(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final sharedStringsFile = archive.findFile('xl/sharedStrings.xml');
      if (sharedStringsFile == null) return bytes;

      final content = utf8.decode(sharedStringsFile.content as List<int>);
      final sanitized = _dedupeSharedStringsXml(content);
      if (sanitized == null) return bytes; // 変更不要 or 加工失敗

      final newArchive = Archive();
      for (final f in archive.files) {
        if (f.name == 'xl/sharedStrings.xml') {
          final data = utf8.encode(sanitized);
          newArchive.addFile(ArchiveFile(f.name, data.length, data));
        } else {
          newArchive.addFile(f);
        }
      }
      final encoded = ZipEncoder().encode(newArchive);
      return encoded ?? bytes;
    } catch (_) {
      // 加工に失敗した場合は元のバイト列で通常通り読み込みを試みる
      // (重複がなければそもそも問題は発生しないため安全側に倒す)。
      return bytes;
    }
  }

  /// sharedStrings.xml内の`<si>`要素のテキスト内容(rPh等の読み仮名は
  /// 除く`<t>`テキストの結合値)を比較し、2回目以降に同一内容が出現した
  /// 場合、その`<si>`内の最初の`<t>`要素にゼロ幅文字を追記して一意化する。
  /// 重複が1件もなければ`null`を返す(加工不要)。
  static String? _dedupeSharedStringsXml(String xmlContent) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(xmlContent);
    } catch (_) {
      return null;
    }

    final siElements = document.findAllElements('si').toList();
    final Map<String, int> occurrenceCount = {};
    bool changed = false;

    for (final si in siElements) {
      final value = _sharedStringPlainText(si);
      final count = occurrenceCount.update(
        value,
        (v) => v + 1,
        ifAbsent: () => 1,
      );
      if (count > 1) {
        // 2回目以降の出現: 一意化のためゼロ幅文字マーカーを追記する。
        final marker = '\u200B' * count;
        final tElement = si.findElements('t').isNotEmpty
            ? si.findElements('t').first
            : null;
        if (tElement != null) {
          tElement.children.add(XmlText(marker));
          changed = true;
        } else {
          // <t>直下がなくランタン(<r>)構成のみの場合は、siの先頭に
          // 新しい<t>要素を追加してマーカーを持たせる。
          si.children.insert(
            0,
            XmlElement(XmlName('t'), [], [XmlText(marker)]),
          );
          changed = true;
        }
      }
    }

    if (!changed) return null;
    return document.toXmlString();
  }

  /// [SharedString.stringValue]相当のロジック(読み仮名`rPh`を除いた
  /// `<t>`テキストの結合)を、excelパッケージに依存せず算出する。
  static String _sharedStringPlainText(XmlElement si) {
    final buffer = StringBuffer();
    for (final t in si.findAllElements('t')) {
      final parent = t.parentElement;
      if (parent != null && parent.name.local == 'rPh') continue;
      buffer.write(t.innerText);
    }
    return buffer.toString();
  }
}
