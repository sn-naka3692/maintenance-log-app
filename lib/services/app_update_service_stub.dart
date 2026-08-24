/// [app_update_service.dart]の非Web環境(Android等)向けスタブ実装。
///
/// Android(APKビルド)ではService Workerの概念自体が存在しないため、
/// 何もしないダミー実装を提供する。実際の処理はconditional importにより
/// Web版では[app_update_service_web.dart]に差し替わる。
bool get isWebPlatform => false;

Future<void> reloadForLatestVersion() async {
  // Android版では何もしない(呼び出されない想定)。
}
