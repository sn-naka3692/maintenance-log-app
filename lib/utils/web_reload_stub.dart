/// [web_reload_web.dart] のスタブ(非Web platform向け)。
///
/// APK版(Android)では `dart.library.js_interop` が存在しないため
/// こちらが使われる。Web版でのみ実際にページを再読み込みする必要があり、
/// APK版からは呼び出されない想定だが、念のため何もしない実装にしておく。
void reloadWebPage() {
  // APK版では使用しない(kIsWebの分岐でガードされているため到達しない)。
}
