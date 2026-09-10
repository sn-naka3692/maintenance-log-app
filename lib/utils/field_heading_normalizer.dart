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
/// (Cause / PartCategory / Symptom)のみ見出し除去正規化を適用する。
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
