import 'dart:typed_data';

/// [web_excel_picker_web.dart] のスタブ(非Web platform向け)。
///
/// APK版(Android)では file_picker のネイティブ実装(Storage Access
/// Framework経由)をそのまま使うため、この関数自体は呼び出されない想定。
/// 万一呼ばれても分かりやすい例外を出す。
Future<WebPickedExcel?> pickExcelFileWeb() async {
  throw UnsupportedError('pickExcelFileWebはWeb版専用です');
}

/// [web_excel_picker_web.dart]のWebPickedExcelのスタブ版(型を合わせるため)。
class WebPickedExcel {
  final Uint8List bytes;
  final String name;

  const WebPickedExcel({required this.bytes, required this.name});
}
