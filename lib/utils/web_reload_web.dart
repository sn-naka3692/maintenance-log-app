import 'package:web/web.dart' as web;

/// Web版限定: 現在のページを強制的に再読み込みする。
///
/// 【v1.2.23で追加】Web版の「新しいバージョンがあります」バナーを
/// タップした際に呼び出す。APK版のようにAPKをダウンロードする概念が
/// ないため、代わりにブラウザのページを再読み込みし、Firebase Hosting
/// から配信されている最新のビルドを取得し直す。
void reloadWebPage() {
  web.window.location.reload();
}
