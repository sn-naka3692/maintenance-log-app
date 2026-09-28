/// 「処置内容」ブロック(部位/詳細部位/事象/事象補足/原因/処置内容)の
/// 見出し文字混入補正。
///
/// 紙面レイアウト上、見出し文字と値が区切り線なくベタ書きされているため、
/// OCR(Azure Document Intelligence)が値の開始境界を誤り、見出し文字の
/// 一部が値の先頭に混入することがある。実データ検証(28件独立ホールドアウト)
/// で、この後処理により sdrs-repair-report-v3 の Cause 正解率が
/// 67.9%(19/28)->100%(28/28)まで改善することを確認済み。
///
/// 対象フィールドは実データで混入が確認された Cause / PartCategory / Symptom
/// の3項目のみ。SymptomDetail は「補足」で始まる正当な値
/// (例:「補足E02/AL-2(排水警報)」)が多数存在するため対象外とする。
///
/// (Python版 /home/user/azure_scan_proxy/function_app.py および
///  /home/user/azure_training/field_heading_normalizer.py と同一ロジック。
///  サーバー側でも正規化済みだが、念のためクライアント側でも冪等に
///  正規化しておく=maker_name_normalizerと同じ「二重防御」方針)
library;

RegExp _headingPattern(List<String> fragments) {
  final alt = fragments
      .map((frag) => frag.split('').map(RegExp.escape).join(r'\s*'))
      .join('|');
  return RegExp('^(?:$alt)\\s*');
}

final Map<String, RegExp> _fieldHeadingPatterns = {
  'Cause': _headingPattern(['原因', '因']),
  'PartCategory': _headingPattern(['部位', '位']),
  'Symptom': _headingPattern(['事象', '象']),
  // 【2026-09-10追加】「kg充填量」欄の見出し文字が値の先頭に混入するケース
  // (実データ検証: 202605a_p006, 202605b_p048 で確認済み)
  'ChargeAmountKg': _headingPattern(['kg充填量', '充填量']),
};

// 見出し文字列そのもので始まる正当な値の保護リスト(誤って除去しない)
final Map<String, Set<String>> _protectedExactValues = {
  'Cause': {'原因不明'},
};

String _stripWhitespace(String text) {
  return text.replaceAll(RegExp(r'[\s\u3000]'), '');
}

/// 指定フィールドの値から、先頭に混入した見出し文字を除去する。
///
/// 対象外のフィールド、または値が空の場合はそのまま返す。
/// 除去した結果が空文字になる場合や、見出し文字列そのもので始まる
/// 正当な値(例:「原因不明」)の場合は、情報を失わないよう元の値を返す。
String normalizeFieldHeading(String fieldKey, String? rawValue) {
  if (rawValue == null || rawValue.isEmpty) {
    return rawValue ?? '';
  }

  final pattern = _fieldHeadingPatterns[fieldKey];
  if (pattern == null) {
    return rawValue;
  }

  final protectedValues = _protectedExactValues[fieldKey];
  if (protectedValues != null &&
      protectedValues.contains(_stripWhitespace(rawValue))) {
    return rawValue;
  }

  var stripped = rawValue.replaceFirst(pattern, '');
  stripped = stripped.replaceFirst(RegExp(r'^[ \u3000]+'), '');

  if (stripped.isEmpty) {
    return rawValue;
  }
  return stripped;
}

/// values辞書({fieldKey: 抽出値, ...})に対して、対象フィールド
/// (Cause / PartCategory / Symptom / ChargeAmountKg)のみ
/// 見出し除去正規化を適用する。
Map<String, String> normalizeFieldHeadingsInValues(
  Map<String, String> values,
) {
  final result = Map<String, String>.from(values);
  for (final fieldKey in _fieldHeadingPatterns.keys) {
    if (result.containsKey(fieldKey)) {
      result[fieldKey] = normalizeFieldHeading(fieldKey, result[fieldKey]);
    }
  }
  return result;
}

// ------------------------------------------------------------
// 日付フィールドの末尾欠落補正。
//
// 紙面の日付欄(YYYY/M/D形式)の右隣に別の日付・時刻欄が隣接しているため、
// OCRが値の終端境界を誤り、隣接する別の日付・時刻が連結して抽出される
// ことがある(実データ検証: ProWan側 work_start_date で確認済み)。
// 抽出テキストから「YYYY/M/D」または「YYYY M/D」形式の日付パターンを
// 抜き出し、複数該当する場合は最後(=本来の日付欄に最も近い側)を採用する。
// ------------------------------------------------------------
final RegExp _datePattern = RegExp(r'\d{4}[\s/]\d{1,2}/\d{1,2}');

const Set<String> dateLikeFields = {
  'VisitDate',
  'WorkStartDate',
  'ReceiptDate',
  'DeliveryDate',
};

String normalizeDateLike(String? rawValue) {
  if (rawValue == null || rawValue.isEmpty) {
    return rawValue ?? '';
  }
  final matches = _datePattern.allMatches(rawValue).toList();
  if (matches.isEmpty) {
    return rawValue;
  }
  final candidate = matches.last.group(0)!.replaceAll(' ', '/');
  return candidate;
}

// ------------------------------------------------------------
// バーコード(Barcode)欄の誤検出補正。
//
// 正しいバーコード値は英字2文字+数字10桁の固定形式(例: AA0001835399、
// 計12文字)。紙面上、バーコード欄が空欄の場合に隣接する「kg充填量」欄
// の単位文字(「kg」)や冷媒量の数値を誤って抜き出すことが実データ検証で
// 確認された。固定形式に一致しない値は「読み取れなかった(空欄)」として
// 扱う方が実運用上安全なため、形式チェックを行う。
// ------------------------------------------------------------
final RegExp _barcodePattern = RegExp(r'^[A-Za-z]{2}\d{10}$');

String normalizeBarcode(String? rawValue) {
  if (rawValue == null || rawValue.isEmpty) {
    return rawValue ?? '';
  }
  final stripped = _stripWhitespace(rawValue);
  if (_barcodePattern.hasMatch(stripped)) {
    return stripped;
  }
  // 固定形式に一致しない場合は誤検出とみなし空欄を返す
  return '';
}
