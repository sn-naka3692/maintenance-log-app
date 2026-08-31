import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/app_state.dart';
import '../services/app_config_service.dart';
import '../theme/app_theme.dart';
import '../utils/web_reload_stub.dart'
    if (dart.library.js_interop) '../utils/web_reload_web.dart';

/// 強制アップデートゲート: 実行中のコードが古すぎる場合に表示される
/// 全画面ブロック画面。日報の閲覧・入力を含め、アプリを一切操作できない。
///
/// 【運用上の背景】現場で古いバージョンのアプリ(またはWeb版の古いタブ)が
/// 使われ続けると、新しい入力ルール(例: 作業者氏名の選択方式変更など)が
/// 反映されず、情報の回収に支障が出るおそれがある。単なる「お知らせバナー」では
/// 現場が更新を後回しにするリスクが残るため、より強い強制力を持たせている。
///
/// 【不具合修正・2026-09・Bug②対応】従来はAPK版のみを想定していたが、
/// Web版でも実行中のコード(main.dart.js)が古いまま検知されずに動作し続ける
/// 事故が実際に発生したため、Web版もこの画面の対象に含めた。
/// APK版は「最新のAPKを入手する」ボタン、Web版は「ページを再読み込みする」
/// ボタンを表示する(自動リロードは無限ループ事故の再発防止のため行わない。
/// あくまでユーザーの明示的なタップ操作のみで再読み込みする)。
class UpdateRequiredScreen extends StatelessWidget {
  final AppMinVersionConfig config;
  const UpdateRequiredScreen({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final message = config.message.isNotEmpty
        ? config.message
        : (kIsWeb
              ? '表示中のページが古いバージョンのままになっています。\n'
                    'このままでは正しく動作しません。ページを再読み込みしてください。'
              : '現在お使いのアプリのバージョンが古いため、このままでは正しく動作しません。\n'
                    '新しいアプリ(APK)を入手して再インストールしてください。');

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.system_update_alt,
                    size: 56,
                    color: AppColors.danger,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'アプリの更新が必要です',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 28),
                if (kIsWeb)
                  // 【不具合修正・2026-09・Bug②対応】Web版はページの
                  // 再読み込みボタンを表示する。自動リロードは過去に
                  // 無限ループ事故を起こした経緯があるため、あくまで
                  // ユーザーの明示的なタップ操作のみで実行する。
                  FilledButton.icon(
                    onPressed: () => reloadWebPage(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('ページを再読み込みする'),
                  )
                else if (config.downloadUrl.isNotEmpty)
                  FilledButton.icon(
                    onPressed: () async {
                      final uri = Uri.tryParse(config.downloadUrl);
                      if (uri != null) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('最新のアプリを入手する'),
                  )
                else
                  Text(
                    '最新のアプリの入手方法については、管理者にお問い合わせください。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () => appState.signOut(),
                  icon: const Icon(Icons.logout),
                  label: const Text('ログアウト'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
