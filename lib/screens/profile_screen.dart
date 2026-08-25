import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/changelog_data.dart';
import '../services/apk_installer_service.dart' as apk_installer;
import '../models/user.dart';
import '../providers/app_state.dart';
import '../services/app_update_service.dart' as app_update;
import '../services/update_notice_service.dart';
import '../theme/app_theme.dart';
import 'changelog_screen.dart';
import 'manual_screen.dart';
import 'system_architecture_screen.dart';
import 'user_management_screen.dart';

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

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final user = appState.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('プロフィール・設定')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                    child: Text(
                      user != null && user.name.isNotEmpty
                          ? user.name.substring(0, 1)
                          : '?',
                      style: const TextStyle(
                        fontSize: 24,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.name ?? '未設定',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${user?.department ?? ''} ・ ${user?.employeeCode ?? ''}',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 4),
                      Chip(
                        label: Text(AppUser.roleLabel(user?.role)),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: user?.isSuperAdmin == true
                            ? AppColors.danger.withValues(alpha: 0.12)
                            : user?.isAdmin == true
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : Colors.grey.shade200,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (user != null && user.email.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.mail_outline),
                title: const Text('メールアドレス'),
                subtitle: Text(user.email),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.password),
              title: const Text('パスワードを変更する'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showChangePasswordDialog(context),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'アプリ情報',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                // 【不具合修正・2026-08】Web版とAndroid(APK)版で表示するボタンを
                // 出し分ける。以前はWeb版でも「APKをダウンロード」ボタンが表示
                // されており、Web版利用者がタップするとAndroid用のAPKファイルが
                // ダウンロードされてしまい「これを開けるアプリが分からない」
                // という混乱を招いていた。
                // - Web版: 「最新の状態に更新する」(Service Worker/キャッシュを
                //   削除して強制リロードする、本来必要だったボタン)
                // - Android版: 従来通り「最新版のアプリ(APK)をダウンロード」
                if (kIsWeb)
                  ListTile(
                    leading: const Icon(
                      Icons.refresh,
                      color: AppColors.primary,
                    ),
                    title: const Text('最新の状態に更新する'),
                    subtitle: Text(
                      'ブラウザに保存された古いデータを消去し、'
                      '最新バージョン(v${changelogEntries.first.version})に'
                      '更新します',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _reloadWebApp(context),
                  )
                else
                  ListTile(
                    leading: const Icon(
                      Icons.download_outlined,
                      color: AppColors.primary,
                    ),
                    title: const Text('最新版のアプリ(APK)をダウンロード'),
                    subtitle: Text(
                      '最新バージョン(v${changelogEntries.first.version})を'
                      'ダウンロードします',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _downloadLatestApk(context),
                  ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.system_update,
                    color: AppColors.primary,
                  ),
                  title: const Text('更新履歴'),
                  subtitle: const Text('アプリの変更内容をここで確認できます'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ChangelogScreen(),
                      ),
                    );
                    // ホーム画面の「更新されました」バナーを既読にする
                    await UpdateNoticeService.markLatestAsSeen();
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.menu_book_outlined,
                    color: AppColors.primary,
                  ),
                  title: const Text('入力マニュアル'),
                  subtitle: const Text('日報の入力ルールを確認できます'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ManualScreen()),
                  ),
                ),
                if (appState.isSuperAdmin) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(
                      Icons.security,
                      color: AppColors.danger,
                    ),
                    title: const Text('システム構成・アカウント整理'),
                    subtitle: const Text('外部サービス・APIキーの管理状況(最高管理者のみ)'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SystemArchitectureScreen(),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (appState.isAdmin)
            OutlinedButton.icon(
              onPressed: () => _showAddUserDialog(context),
              icon: const Icon(Icons.person_add),
              label: const Text('社員を追加する'),
            ),
          if (appState.isSuperAdmin) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const UserManagementScreen()),
              ),
              icon: const Icon(Icons.admin_panel_settings_outlined),
              label: const Text('社員の権限・登録を管理する'),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('ログアウトしますか?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('キャンセル'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('ログアウト'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await context.read<AppState>().signOut();
              }
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
            ),
            icon: const Icon(Icons.logout),
            label: const Text('ログアウト'),
          ),
          const SizedBox(height: 30),
          Center(
            child: Text(
              '札幌中野冷機 業務日報アプリ\nバージョン ${changelogEntries.first.version}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // 最新版APKのダウンロード
  // ------------------------------------------------------------------
  /// GitHub Releasesの「latest」固定URLを外部ブラウザで開き、
  /// 最新版のAPKをダウンロードさせる。
  ///
  /// 【運用上の背景】現場から「ダウンロードリンクの入手方法・更新方法が
  /// 分かりにくい」との相談があったため、アプリ内(プロフィール画面)から
  /// 直接ボタン一つでダウンロードできるようにした。URL自体はタグ名を
  /// 含まない固定リンクのため、GitHub上で新しいリリースを作成する限り、
  /// 常に最新版のAPKがダウンロードされる。
  /// 【不具合修正・2026-08】従来はブラウザ委任のダウンロードのみで、
  /// 「ダウンロード→通知から手動でファイルを開いてインストール」という
  /// 2段階の手間があった。アプリ内で直接バイナリをダウンロードし、
  /// 完了後にインストーラーを自動起動することでシームレスな更新体験に
  /// 改善する(apk_installer_service.dart)。万一失敗した場合は、
  /// 従来通りブラウザでのダウンロードにフォールバックする。
  Future<void> _downloadLatestApk(BuildContext context) async {
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

  // ------------------------------------------------------------------
  // Web版の更新(最新の状態に更新する)
  // ------------------------------------------------------------------
  /// 【不具合修正・2026-08】Web版はブラウザがService Worker経由で
  /// ファイルをキャッシュするため、Firebase Hostingへ新バージョンを
  /// デプロイしても、開きっぱなしのタブでは古いバージョンが表示され
  /// 続けてしまう。「Web版で更新の案内が出ない・何をすればいいか
  /// 分からない」という問い合わせへの対応として、確実に最新版へ
  /// 更新するボタンを用意した。
  ///
  /// 処理は app_update_service.dart(conditional import)経由で
  /// Web実装(Service Worker解除・キャッシュ削除・強制リロード)を呼ぶ。
  Future<void> _reloadWebApp(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('最新の状態に更新しますか?'),
        content: const Text(
          'ブラウザに保存されている古いデータを消去し、ページを再読み込みして'
          '最新バージョンに更新します。入力中の内容があれば失われますので、'
          '保存してから実行してください。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('更新する'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await app_update.reloadForLatestVersion();
  }

  // ------------------------------------------------------------------
  // パスワード変更
  // ------------------------------------------------------------------
  void _showChangePasswordDialog(BuildContext context) {
    final newPwCtrl = TextEditingController();
    final confirmPwCtrl = TextEditingController();
    bool obscure = true;
    bool loading = false;
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('パスワードを変更'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '新しいパスワード(6文字以上)を入力してください。',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newPwCtrl,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: '新しいパスワード',
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setState(() => obscure = !obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: confirmPwCtrl,
                  obscureText: obscure,
                  decoration: const InputDecoration(labelText: '新しいパスワード(確認)'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    error!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: loading
                  ? null
                  : () async {
                      final pw = newPwCtrl.text;
                      if (pw.length < 6) {
                        setState(() => error = 'パスワードは6文字以上で入力してください。');
                        return;
                      }
                      if (pw != confirmPwCtrl.text) {
                        setState(() => error = '確認用パスワードが一致しません。');
                        return;
                      }
                      setState(() {
                        loading = true;
                        error = null;
                      });
                      try {
                        await ctx.read<AppState>().changePassword(pw);
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('パスワードを変更しました。')),
                          );
                        }
                      } on FirebaseAuthException catch (e) {
                        setState(() {
                          loading = false;
                          if (e.code == 'requires-recent-login') {
                            error = 'セキュリティのため、再度ログインしてからお試しください。';
                          } else {
                            error = 'パスワードの変更に失敗しました。';
                          }
                        });
                      } catch (_) {
                        setState(() {
                          loading = false;
                          error = 'パスワードの変更に失敗しました。';
                        });
                      }
                    },
              child: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('変更する'),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // 社員追加(Firebase Authアカウントも同時作成)
  //
  // 事故防止: 一般管理者は「一般ユーザー」としてのみ新規社員を追加できる。
  // 管理者権限(一般管理者/最高管理者)を持つ社員の新規作成は最高管理者のみ可能
  // (一般管理者が他人に管理者権限を付与してしまう事故を防止するため)。
  // ------------------------------------------------------------------
  void _showAddUserDialog(BuildContext context) {
    final isSuperAdmin = context.read<AppState>().isSuperAdmin;
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final deptCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    UserRole role = UserRole.staff;
    // 'paper' = 画面表示して紙等で伝達、'email' = 本人にパスワード設定メールを送信
    String deliveryMethod = 'paper';
    bool loading = false;
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('社員を追加'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: '氏名 *'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(labelText: '社員番号 *'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: deptCtrl,
                  decoration: const InputDecoration(labelText: '所属部門'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'メールアドレス(ログイン用) *',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: '電話番号 *(初期パスワード生成に使用)',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<UserRole>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: '役割'),
                  items: [
                    const DropdownMenuItem(
                      value: UserRole.staff,
                      child: Text('一般ユーザー'),
                    ),
                    if (isSuperAdmin) ...const [
                      DropdownMenuItem(
                        value: UserRole.admin,
                        child: Text('一般管理者'),
                      ),
                      DropdownMenuItem(
                        value: UserRole.superAdmin,
                        child: Text('最高管理者'),
                      ),
                    ],
                  ],
                  onChanged: (v) => setState(() => role = v!),
                ),
                if (!isSuperAdmin) ...[
                  const SizedBox(height: 6),
                  Text(
                    '※ 管理者権限を持つ社員の追加は最高管理者のみ行えます。',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  '初期パスワードの伝え方',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 6),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: 'paper',
                  groupValue: deliveryMethod,
                  title: const Text('画面に表示する(紙などで手渡し)'),
                  subtitle: const Text(
                    '社員番号と電話番号下4桁からパスワードを自動生成し、この場で表示します。',
                    style: TextStyle(fontSize: 11),
                  ),
                  onChanged: (v) => setState(() => deliveryMethod = v!),
                ),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: 'email',
                  groupValue: deliveryMethod,
                  title: const Text('本人にメールで送信する'),
                  subtitle: const Text(
                    'ランダムなパスワードを設定し、パスワード設定用のリンクを本人のメールに送信します。',
                    style: TextStyle(fontSize: 11),
                  ),
                  onChanged: (v) => setState(() => deliveryMethod = v!),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    error!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: loading
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      final code = codeCtrl.text.trim();
                      final email = emailCtrl.text.trim();
                      final phone = phoneCtrl.text.trim();
                      if (name.isEmpty ||
                          code.isEmpty ||
                          email.isEmpty ||
                          phone.isEmpty) {
                        setState(() {
                          error = '氏名・社員番号・メールアドレス・電話番号は必須です。';
                        });
                        return;
                      }
                      final phoneDigitsCheck = phone.replaceAll(
                        RegExp(r'\D'),
                        '',
                      );
                      if (phoneDigitsCheck.length < 4) {
                        setState(() {
                          error = '電話番号は数字4桁以上で入力してください。';
                        });
                        return;
                      }

                      setState(() {
                        loading = true;
                        error = null;
                      });

                      final digits = phoneDigitsCheck;
                      final last4 = digits.substring(digits.length - 4);
                      final generatedPassword = deliveryMethod == 'paper'
                          ? '$code$last4'
                          : _randomPassword();

                      try {
                        await ctx.read<AppState>().addUser(
                          name: name,
                          employeeCode: code,
                          role: role,
                          department: deptCtrl.text.trim(),
                          email: email,
                          initialPassword: generatedPassword,
                          phone: phone,
                        );

                        if (deliveryMethod == 'email') {
                          await ctx.read<AppState>().sendPasswordResetEmail(
                            email,
                          );
                        }

                        if (ctx.mounted) Navigator.pop(ctx);

                        if (context.mounted) {
                          if (deliveryMethod == 'paper') {
                            _showGeneratedPasswordDialog(
                              context,
                              name: name,
                              email: email,
                              password: generatedPassword,
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '$name さんを追加しました。パスワード設定メールを $email に送信しました。',
                                ),
                              ),
                            );
                          }
                        }
                      } on FirebaseAuthException catch (e) {
                        setState(() {
                          loading = false;
                          if (e.code == 'email-already-in-use') {
                            error = 'このメールアドレスは既に使用されています。';
                          } else if (e.code == 'weak-password') {
                            error = 'パスワードが弱すぎます(内部エラー)。もう一度お試しください。';
                          } else {
                            error = '社員の追加に失敗しました: ${e.message ?? e.code}';
                          }
                        });
                      } catch (e) {
                        setState(() {
                          loading = false;
                          error = '社員の追加に失敗しました: $e';
                        });
                      }
                    },
              child: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('追加'),
            ),
          ],
        ),
      ),
    );
  }

  void _showGeneratedPasswordDialog(
    BuildContext context, {
    required String name,
    required String email,
    required String password,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('社員を追加しました'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$name さんのログイン情報です。紙などで安全にお渡しください。'),
            const SizedBox(height: 16),
            _CopyableRow(label: 'メールアドレス', value: email),
            const SizedBox(height: 8),
            _CopyableRow(label: '初期パスワード', value: password),
            const SizedBox(height: 12),
            const Text(
              '※初回ログイン後、本人にパスワード変更を推奨してください。',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  static String _randomPassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    final rnd = Random.secure();
    return List.generate(12, (_) => chars[rnd.nextInt(chars.length)]).join();
  }
}

class _CopyableRow extends StatelessWidget {
  final String label;
  final String value;
  const _CopyableRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
