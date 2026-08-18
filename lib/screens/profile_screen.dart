import 'package:flutter/material.dart';
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
          const SizedBox(height: 20),
          const Text(
            'ユーザー切り替え(デモ用)',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '※実運用ではログイン認証に置き換え予定です',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 10),
          ...appState.users.map((u) {
            final selected = u.id == user?.id;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.08)
                  : null,
              child: ListTile(
                leading: Icon(
                  u.isAdmin ? Icons.admin_panel_settings : Icons.person,
                  color: selected ? AppColors.primary : Colors.grey.shade600,
                ),
                title: Text(u.name),
                subtitle: Text('${u.department} ・ ${u.employeeCode}'),
                trailing: selected
                    ? const Icon(Icons.check_circle, color: AppColors.primary)
                    : null,
                onTap: () => appState.switchUser(u.id),
              ),
            );
          }),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => _showAddUserDialog(context),
            icon: const Icon(Icons.person_add),
            label: const Text('社員を追加する'),
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

  void _showAddUserDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final deptCtrl = TextEditingController();
    UserRole role = UserRole.staff;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('社員を追加'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: '氏名'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(labelText: '社員番号'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: deptCtrl,
                  decoration: const InputDecoration(labelText: '所属部門'),
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) return;
                ctx.read<AppState>().addUser(
                  name: nameCtrl.text.trim(),
                  employeeCode: codeCtrl.text.trim(),
                  role: role,
                  department: deptCtrl.text.trim(),
                );
                Navigator.pop(ctx);
              },
              child: const Text('追加'),
            ),
          ],
        ),
      ),
    );
  }
}
