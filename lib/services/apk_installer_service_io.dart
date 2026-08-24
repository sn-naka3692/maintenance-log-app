// [apk_installer_service.dart]のAndroid(ネイティブ)向け実装。
//
// GitHub Releasesの固定URLからAPKバイナリを直接ダウンロードし、
// アプリのキャッシュディレクトリへ保存後、open_filexパッケージで
// android.intent.action.VIEWを発行してインストーラーを自動起動する。
// Android 8.0以降は「提供元不明のアプリ」許可ダイアログが自動的に
// 表示されるため、ユーザーは許可→インストールの2タップで更新できる
// (従来の「ダウンロード→通知を探して開く」よりも大幅に手間が減る)。
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

bool get isNativeUpdateSupported => true;

/// [url]からAPKファイルをダウンロードし、完了後にインストーラーを起動する。
/// ダウンロードの進捗(0.0〜1.0)を[onProgress]で通知する。
/// Content-Lengthが取得できない場合は進捗が不定(-1として通知しないため
/// 呼び出し側でインジケータを不確定表示に切り替える)。
Future<void> downloadAndInstallLatestApk({
  required String url,
  required void Function(double progress) onProgress,
}) async {
  final request = http.Request('GET', Uri.parse(url));
  final response = await http.Client().send(request);

  if (response.statusCode != 200) {
    throw Exception('ダウンロードに失敗しました(HTTP ${response.statusCode})');
  }

  final total = response.contentLength ?? 0;
  var received = 0;

  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/app-release-update.apk');
  final sink = file.openWrite();

  await for (final chunk in response.stream) {
    sink.add(chunk);
    received += chunk.length;
    if (total > 0) {
      onProgress(received / total);
    }
  }
  await sink.flush();
  await sink.close();

  // ダウンロード完了 -> インストーラーを自動起動(FileProvider経由)。
  final result = await OpenFilex.open(
    file.path,
    type: 'application/vnd.android.package-archive',
  );
  if (result.type.name != 'done') {
    throw Exception('インストーラーを起動できませんでした: ${result.message}');
  }
}
