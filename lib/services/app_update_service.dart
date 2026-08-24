/// Web版アプリの「最新版へ更新」機能。
///
/// dart:ioが使えるかどうか(=ネイティブ/Androidかどうか)で
/// Android用スタブ/Web実装を自動的に切り替える(conditional import)。
/// dart.library.io はAndroid・iOS・デスクトップ(Dart VM)でのみtrueになり、
/// Web(dart2js/dartdevc)では常にfalseになるため、Web判定として利用する。
/// - dart.library.ioがtrue(Android等) -> app_update_service_stub.dart
///   (何もしないダミー実装)
/// - それ以外(Web) -> app_update_service_web.dart
///   (Service Worker/キャッシュを削除してから強制リロード)
library;

export 'app_update_service_web.dart'
    if (dart.library.io) 'app_update_service_stub.dart';
