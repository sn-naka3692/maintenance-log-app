/// メーカー名 正規化マッピング。
///
/// サンデン・リテールシステム株式会社は社名変更し、現在は「SDRS株式会社」となっている。
/// AI-OCR(Azure Document Intelligence)で読み取った作業報告書には
/// 旧社名で印字されているものが混在するため、抽出後処理として
/// 常に新社名「SDRS株式会社」に統一する。
///
/// (Python版 /home/user/azure_training/maker_name_normalizer.py からの移植)
///
/// 中黒(・)の表記ゆれ(全角中黒「・」/ OCR誤認識の「·」(キリル中点)/ 中黒なし)や、
/// 「(株)」「株式会社」などの法人格表記ゆれにも対応する。
library;

/// 新社名(正規化後の統一表記)
const String kNewMakerName = 'SDRS株式会社';

// 中黒文字のゆれ: "・"(U+30FB) / "·"(U+00B7, OCR誤認識で出やすい) / "-" / なし
const String _dotChars = r'[・·\-]?';
// 法人格のゆれ: "株式会社" / "(株)" / "㈱"
const String _corpSuffix = r'(?:株式会社|\(株\)|㈱)';

final RegExp _oldNamePattern = RegExp(
  'サンデン$_dotChars'
  'リテール$_dotChars'
  'システム$_corpSuffix?',
);

// 法人格がない「サンデンリテールシステム」単体表記も対象に含める
final RegExp _oldNameBarePattern = RegExp(
  'サンデン$_dotChars'
  'リテール$_dotChars'
  'システム',
);

/// OCRテキストに含まれる旧社名表記を新社名に置換した文字列を返す。
///
/// フィールド全体が旧社名そのものである場合はもちろん、
/// 住所や備考欄など他の文字列と混在している場合でも、該当箇所だけを置換する。
String normalizeMakerNameText(String rawText) {
  if (rawText.isEmpty) return rawText;

  var text = rawText;
  if (_oldNamePattern.hasMatch(text) || _oldNameBarePattern.hasMatch(text)) {
    text = text.replaceAll(_oldNamePattern, kNewMakerName);
    text = text.replaceAll(_oldNameBarePattern, kNewMakerName);
  }
  return text;
}

/// メーカー名フィールド専用の正規化。
///
/// フィールド値が「サンデン・リテールシステム(株)」等の旧社名表記の場合は
/// 新社名に置き換える。それ以外(パナソニック等の他メーカー)はそのまま返す。
String normalizeMakerName(String? makerNameField) {
  if (makerNameField == null || makerNameField.isEmpty) {
    return makerNameField ?? '';
  }
  return normalizeMakerNameText(makerNameField);
}
