/// Web版限定のExcel(.xlsx)ファイル選択機能。
///
/// web_pdf_picker.dartと全く同じ理由(file_pickerパッケージのWeb実装が
/// ビルド環境のキャッシュ状態次第で登録されず「MissingPluginException」が
/// 発生する不具合を根本回避するため)で、package:web直接操作の
/// 自前実装に切り替える。
library;

export 'web_excel_picker_web.dart'
    if (dart.library.io) 'web_excel_picker_stub.dart';
