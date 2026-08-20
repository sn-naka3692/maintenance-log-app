import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';

/// 社員の権限・登録を管理する画面(最高管理者のみアクセス可能)。
///
/// 事故防止のための3つのガード:
/// 1. 自分自身の役割変更・削除は不可(誤操作による自己ロックアウト防止)
/// 2. 一般管理者は他人に管理者権限を付与できない(社員追加ダイアログ側で制御)
/// 3. 最後の1人の最高管理者は降格・削除できない(管理者が誰もいなくなる事故防止)
///
/// これらのガードはUI側でも極力事前に防ぐが、最終防衛線として
/// ReportService/Firestoreセキュリティルール側でも同じチェックを行っている。
class UserManagementScreen extends StatelessWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final currentUser = appState.currentUser;

    // 直接ルーティングされた場合等の保険(最高管理者以外はアクセス不可)
    if (!appState.isSuperAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('社員の権限・登録を管理する')),
        body: const Center(child: Text('この画面は最高管理者のみ利用できます。')),
      );
    }

    final users = List<AppUser>.from(appState.users)
      ..sort((a, b) {
        // 最高管理者 → 一般管理者 → 一般作業員の順、同じ役割内では氏名順
        int rank(UserRole r) => switch (r) {
          UserRole.superAdmin => 0,
          UserRole.admin => 1,
          UserRole.staff => 2,
        };
        final rc = rank(a.role).compareTo(rank(b.role));
        if (rc != 0) return rc;
        return a.name.compareTo(b.name);
      });

    final superAdminCount = users.where((u) => u.isSuperAdmin).length;

    return Scaffold(
      appBar: AppBar(title: const Text('社員の権限・登録を管理する')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined, color: AppColors.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '管理者権限には「最高管理者」「一般管理者」の2階層があります。\n'
                    '・最高管理者:役割変更・社員削除など全ての管理操作が可能\n'
                    '・一般管理者:管理ダッシュボードの閲覧、一般作業員の追加のみ可能\n'
                    '自分自身の役割変更・削除、および最後の最高管理者の降格・削除はできません。',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '社員一覧(${users.length}名)',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          ...users.map((u) {
            final isSelf = currentUser != null && u.id == currentUser.id;
            final isLastSuperAdmin = u.isSuperAdmin && superAdminCount <= 1;
            final locked = isSelf || isLastSuperAdmin;

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _roleColor(u.role).withValues(alpha: 0.15),
                  child: Text(
                    u.name.isNotEmpty ? u.name.substring(0, 1) : '?',
                    style: TextStyle(color: _roleColor(u.role)),
                  ),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        u.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isSelf) ...[
                      const SizedBox(width: 6),
                      Text(
                        '(自分)',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Text(
                        '${u.department.isEmpty ? '部門未設定' : u.department} ・ ${u.employeeCode}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Chip(
                        label: Text(
                          AppUser.roleLabel(u.role),
                          style: const TextStyle(fontSize: 11),
                        ),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: _roleColor(
                          u.role,
                        ).withValues(alpha: 0.12),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.more_vert),
                  tooltip: locked ? '操作不可(事故防止のためロック中)' : '役割変更・削除',
                  onPressed: () => _openUserActionSheet(
                    context,
                    user: u,
                    isSelf: isSelf,
                    isLastSuperAdmin: isLastSuperAdmin,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Color _roleColor(UserRole r) {
    switch (r) {
      case UserRole.superAdmin:
        return AppColors.danger;
      case UserRole.admin:
        return AppColors.primary;
      case UserRole.staff:
        return Colors.grey.shade700;
    }
  }

  void _openUserActionSheet(
    BuildContext context, {
    required AppUser user,
    required bool isSelf,
    required bool isLastSuperAdmin,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '現在の役割: ${AppUser.roleLabel(user.role)}',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                if (isSelf)
                  _lockedNotice(context, '自分自身の役割変更・削除はできません(誤操作防止のため)。')
                else if (isLastSuperAdmin)
                  _lockedNotice(
                    context,
                    '最後の最高管理者のため、降格・削除はできません。\n先に別の社員を最高管理者に設定してから操作してください。',
                  )
                else ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline),
                    title: const Text('一般作業員にする'),
                    enabled: user.role != UserRole.staff,
                    onTap: () => _confirmAndChangeRole(
                      context,
                      sheetCtx,
                      user,
                      UserRole.staff,
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.admin_panel_settings_outlined),
                    title: const Text('一般管理者にする'),
                    enabled: user.role != UserRole.admin,
                    onTap: () => _confirmAndChangeRole(
                      context,
                      sheetCtx,
                      user,
                      UserRole.admin,
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.security),
                    title: const Text('最高管理者にする'),
                    enabled: user.role != UserRole.superAdmin,
                    onTap: () => _confirmAndChangeRole(
                      context,
                      sheetCtx,
                      user,
                      UserRole.superAdmin,
                    ),
                  ),
                  const Divider(height: 20),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.delete_outline,
                      color: AppColors.danger,
                    ),
                    title: const Text(
                      '社員を削除する',
                      style: TextStyle(color: AppColors.danger),
                    ),
                    onTap: () => _confirmAndDelete(context, sheetCtx, user),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _lockedNotice(BuildContext context, String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndChangeRole(
    BuildContext context,
    BuildContext sheetCtx,
    AppUser user,
    UserRole newRole,
  ) async {
    Navigator.pop(sheetCtx);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('役割を変更しますか?'),
        content: Text(
          '${user.name} さんの役割を「${AppUser.roleLabel(newRole)}」に変更します。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('変更する'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    try {
      await context.read<AppState>().updateUserRole(
        targetUserId: user.id,
        newRole: newRole,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${user.name} さんの役割を「${AppUser.roleLabel(newRole)}」に変更しました。',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('変更に失敗しました: ${_friendlyError(e)}')),
        );
      }
    }
  }

  Future<void> _confirmAndDelete(
    BuildContext context,
    BuildContext sheetCtx,
    AppUser user,
  ) async {
    Navigator.pop(sheetCtx);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('社員を削除しますか?'),
        content: Text(
          '${user.name} さんのアカウント情報を削除します。この操作は取り消せません。\n'
          '(※ログイン用のFirebaseアカウント自体は別途無効化が必要です)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    try {
      await context.read<AppState>().deleteUser(user.id);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${user.name} さんを削除しました。')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('削除に失敗しました: ${_friendlyError(e)}')),
        );
      }
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    return s.replaceFirst('StateError: ', '').replaceFirst('Exception: ', '');
  }
}
