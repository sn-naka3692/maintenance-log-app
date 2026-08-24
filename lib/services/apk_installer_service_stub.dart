/// [apk_installer_service.dart]のWeb向けスタブ実装。
/// Web版では「アプリ内更新」ボタン自体を表示しない設計のため、
/// 呼び出されても何もしない(安全側のダミー実装)。
bool get isNativeUpdateSupported => false;

Future<void> downloadAndInstallLatestApk({
  required String url,
  required void Function(double progress) onProgress,
}) async {
  throw UnsupportedError('この機能はAndroid版でのみ利用できます');
}
