import 'dart:typed_data';

/// [web_pdf_picker_web.dart] のスタブ(非Web platform向け)。
///
/// APK版(Android)では file_picker のネイティブ実装(Storage Access
/// Framework経由)をそのまま使うため、この関数自体は呼び出されない想定。
/// 万一呼ばれても分かりやすい例外を出す。
Future<WebPickedPdf?> pickPdfFileWeb() async {
  throw UnsupportedError('pickPdfFileWebはWeb版専用です');
}

/// [web_pdf_picker_web.dart]のWebPickedPdfのスタブ版(型を合わせるため)。
class WebPickedPdf {
  final Uint8List bytes;
  final String name;

  const WebPickedPdf({required this.bytes, required this.name});
}
