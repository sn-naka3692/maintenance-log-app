/// Web版限定のPDFファイル選択機能。
///
/// dart:ioが使えるかどうか(=ネイティブ/Androidかどうか)で
/// Android用スタブ/Web実装を自動的に切り替える(conditional import)。
/// - dart.library.ioがtrue(Android等) -> web_pdf_picker_stub.dart
///   (呼ばれない想定のダミー実装。APK版はfile_pickerのネイティブ実装を
///   そのまま使う)
/// - それ以外(Web) -> web_pdf_picker_web.dart
///   (package:web の <input type="file"> を直接操作する実装)
library;

export 'web_pdf_picker_web.dart'
    if (dart.library.io) 'web_pdf_picker_stub.dart';
