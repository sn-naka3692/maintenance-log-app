import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';

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
                        label: Text(user?.isAdmin == true ? '管理者' : '一般作業員'),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: user?.isAdmin == true
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
          if (appState.isAdmin)
            OutlinedButton.icon(
              onPressed: () => _showAddUserDialog(context),
              icon: const Icon(Icons.person_add),
              label: const Text('社員を追加する'),
            ),
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
              '札幌中野冷機 業務日報アプリ\nバージョン 1.0.0',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ),
        ],
      ),
    );
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
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
                    style: const TextStyle(color: AppColors.danger, fontSize: 12),
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
  // ------------------------------------------------------------------
  void _showAddUserDialog(BuildContext context) {
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
                  items: const [
                    DropdownMenuItem(
                      value: UserRole.staff,
                      child: Text('一般作業員'),
                    ),
                    DropdownMenuItem(value: UserRole.admin, child: Text('管理者')),
                  ],
                  onChanged: (v) => setState(() => role = v!),
                ),
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
                    style: const TextStyle(color: AppColors.danger, fontSize: 12),
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
                          await ctx
                              .read<AppState>()
                              .sendPasswordResetEmail(email);
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
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
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
