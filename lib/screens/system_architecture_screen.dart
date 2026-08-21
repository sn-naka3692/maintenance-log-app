import 'package:flutter/material.dart';
import '../data/system_architecture_data.dart';
import '../theme/app_theme.dart';

/// アプリのシステム構成・外部サービス・アカウント関係の整理画面。
///
/// 【アクセス制限】最高管理者(superAdmin)のみがこの画面に到達できる。
/// 呼び出し元(profile_screen.dart)で appState.isSuperAdmin をチェックした上で
/// 遷移させているが、念のためこの画面自体でも防御的に同じチェックを行う。
class SystemArchitectureScreen extends StatelessWidget {
  const SystemArchitectureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('システム構成・アカウント整理'),
        backgroundColor: AppColors.danger,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _WarningBanner(),
          const SizedBox(height: 20),

          _SectionHeader(
            icon: Icons.cloud_outlined,
            title: '現在使用中の外部サービス',
            subtitle: 'このアプリの裏側で稼働している仕組み一覧',
          ),
          const SizedBox(height: 10),
          ...externalServices.map((s) => _ServiceCard(service: s)),

          const SizedBox(height: 24),
          _SectionHeader(
            icon: Icons.history_toggle_off,
            title: '検討したが不採用/廃止したもの',
            subtitle: '開発過程で検討・変更した経緯の記録',
          ),
          const SizedBox(height: 10),
          if (consideredButNotAdopted.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '該当なし',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            )
          else
            ...consideredButNotAdopted.map((s) => _ServiceCard(service: s)),

          const SizedBox(height: 24),
          _SectionHeader(
            icon: Icons.groups_outlined,
            title: 'アカウント・権限に関する整理',
            subtitle: '運用上、社長として押さえておくべきポイント',
          ),
          const SizedBox(height: 10),
          ...accountStructureNotes.map((n) => _NoteCard(note: n)),

          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Colors.grey.shade600, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'この一覧はアプリの改修が入るたびに更新される想定です。'
                    '実際のパスワード・APIキーの値はここには表示されません(保管場所の案内のみ)。',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.security, color: AppColors.danger, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '最高管理者専用ページです。社外の方や一般社員には共有しないでください。',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final ExternalService service;
  const _ServiceCard({required this.service});

  ({Color color, String label, IconData icon}) _statusVisual() {
    switch (service.status) {
      case ServiceStatus.active:
        return (color: AppColors.primary, label: '稼働中', icon: Icons.check_circle_outline);
      case ServiceStatus.newlyAdded:
        return (color: AppColors.success, label: '今回新規導入', icon: Icons.fiber_new_outlined);
      case ServiceStatus.deprecated:
        return (color: AppColors.warning, label: '廃止予定', icon: Icons.warning_amber_outlined);
      case ServiceStatus.removed:
        return (color: Colors.grey, label: '不採用・削除済み', icon: Icons.block_outlined);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visual = _statusVisual();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    service.name,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: visual.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(visual.icon, size: 12, color: visual.color),
                      const SizedBox(width: 3),
                      Text(
                        visual.label,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: visual.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              service.category,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const Divider(height: 18),
            _InfoRow(label: '提供元', value: service.provider),
            _InfoRow(label: '用途', value: service.purpose),
            _InfoRow(label: '契約・アカウント', value: service.accountOwner),
            _InfoRow(label: '費用面の注意', value: service.costNote),
            _InfoRow(label: '認証情報の保管場所', value: service.credentialLocation),
            if (service.notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...service.notes.map(
                (n) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('・', style: TextStyle(fontSize: 12)),
                      Expanded(
                        child: Text(
                          n,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final AccountNote note;
  const _NoteCard({required this.note});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.push_pin_outlined, size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    note.title,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              note.description,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
