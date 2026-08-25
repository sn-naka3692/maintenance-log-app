import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/apk_installer_service.dart' as apk_installer;

/// APKダウンロード用の固定URL(GitHub Releases経由)。
///
/// 【重要・v1.2.6で訂正】v1.2.5で一時的にFirebase Hosting経由の配布に
/// 変更したが、これは誤った対応だった。実際に調査したところ、
/// Firebase Hosting(裏側はFastly CDN)は大容量バイナリの配信時に
/// Content-Lengthヘッダーを返さず、Rangeリクエスト(途中からの再開)にも
/// 対応していないという構造的な制限があることが判明した。これにより
/// 「ダウンロードの進行状況が表示されない」「通信が少しでも乱れると
/// 最初からやり直しになりタイムアウトする」という不具合が起きていた
/// (自宅Wi-Fi・5Gモバイル回線を問わず発生していたのはこのため)。
///
/// 一方、GitHub Releases(実体はAzure Blob Storage配信)は
/// Content-Length・Range双方とも正常に機能することを検証済みのため、
/// v1.2.6で元のGitHub Releases配布方式に戻した。
/// 「latest」固定URLのため、新バージョンをリリースするたびに
/// 常に最新版を指すようになる(URL自体は不変)。
/// 社内マニュアル(web/manual.html・web/日報アプリ操作マニュアル.md)に
/// 記載しているURLと同一のものを使用している。
const String kLatestApkDownloadUrl =
    'https://github.com/sn-naka3692/maintenance-log-app/releases/latest/download/app-release.apk';

/// 「最新版のAPKをダウンロード→自動インストール起動」までを一気通貫で
/// 行う共通処理。
///
/// 【設計・v1.2.13】以前はプロフィール画面(profile_screen.dart)内に
/// この処理が直接書かれていたが、ホーム画面の「新しいバージョンが
/// あります」バナー(home_screen.dart)からも同じ操作を呼び出せるように
/// するため、共通関数として切り出した。呼び出し元がどの画面でも
/// 同じダウンロード進捗ダイアログ・失敗時のブラウザフォールバックが
/// 得られる。
Future<void> downloadAndInstallLatestApkWithDialog(BuildContext context) async {
  final progress = ValueNotifier<double>(0);
  bool dialogShown = false;
  try {
    dialogShown = true;
    if (context.mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, value, __) => AlertDialog(
            title: const Text('更新をダウンロード中'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: value > 0 ? value : null),
                const SizedBox(height: 12),
                Text(
                  value > 0 ? '${(value * 100).toStringAsFixed(0)}%' : '準備中…',
                ),
              ],
            ),
          ),
        ),
      );
    }

    await apk_installer.downloadAndInstallLatestApk(
      url: kLatestApkDownloadUrl,
      onProgress: (v) => progress.value = v,
    );

    if (context.mounted && dialogShown) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ダウンロードが完了しました。表示された画面の指示に従ってインストールしてください。'),
          duration: Duration(seconds: 6),
        ),
      );
    }
  } catch (_) {
    if (context.mounted && dialogShown) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    // フォールバック: 従来通りブラウザでダウンロードさせる。
    final uri = Uri.parse(kLatestApkDownloadUrl);
    bool launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          launched
              ? 'アプリ内更新に失敗したため、ブラウザでダウンロードを開始しました。完了したら通知からファイルを開いてインストールしてください。'
              : 'ダウンロードを開始できませんでした。時間をおいて再度お試しください。',
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }
}
