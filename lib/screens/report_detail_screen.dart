import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/work_report.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import 'report_edit_screen.dart';

class ReportDetailScreen extends StatelessWidget {
  final String reportId;
  const ReportDetailScreen({super.key, required this.reportId});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    WorkReport? report;
    try {
      report = appState.reports.firstWhere((r) => r.id == reportId);
    } catch (_) {
      report = null;
    }

    if (report == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('日報詳細')),
        body: const Center(child: Text('日報が見つかりません')),
      );
    }

    final dateFmt = DateFormat('yyyy年M月d日 (E)', 'ja_JP');
    final timeFmt = DateFormat('HH:mm');
    final canEdit = report.authorId == appState.currentUser?.id;
    final typeColor = responseTypeColor(report.responseType.label);

    return Scaffold(
      appBar: AppBar(
        title: const Text('日報詳細'),
        actions: [
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReportEditScreen(existing: report),
                  ),
                );
              },
            ),
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('日報を削除しますか?'),
                    content: const Text('この操作は取り消せません。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('キャンセル'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.danger,
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('削除'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await appState.deleteReport(reportId);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  report.responseType.label,
                  style: TextStyle(
                    color: typeColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              Text(dateFmt.format(report.visitDate)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            report.clientName,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(
                Icons.person,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                report.authorName,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(width: 16),
              const Icon(
                Icons.access_time,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                '${timeFmt.format(report.startTime)} - ${timeFmt.format(report.endTime)}',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
          const Divider(height: 32),

          if (report.equipmentModel.isNotEmpty)
            _InfoRow(
              icon: Icons.qr_code,
              label: '機器型番',
              value: report.equipmentModel,
            ),
          if (report.proWanRefNumber.isNotEmpty)
            _InfoRow(
              icon: Icons.numbers,
              label: 'プロワン管理番号',
              value: report.proWanRefNumber,
            ),

          _SectionCard(
            title: '作業内容',
            icon: Icons.build,
            child: Text(
              report.workContent.isEmpty ? '(未記入)' : report.workContent,
            ),
          ),

          if (report.partsUsed.isNotEmpty)
            _SectionCard(
              title: '使用部品',
              icon: Icons.inventory_2,
              child: Column(
                children: report.partsUsed
                    .map(
                      (p) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            const Icon(Icons.circle, size: 6),
                            const SizedBox(width: 8),
                            Text('${p.name} × ${p.quantity}'),
                            if (p.note != null && p.note!.isNotEmpty)
                              Text(
                                ' (${p.note})',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),

          if (report.successPoints.isNotEmpty)
            _SectionCard(
              title: 'うまくいったこと・工夫した点',
              icon: Icons.thumb_up_alt_outlined,
              iconColor: AppColors.success,
              child: Text(report.successPoints),
            ),

          if (report.issuesPoints.isNotEmpty)
            _SectionCard(
              title: '課題・失敗・改善点',
              icon: Icons.report_problem_outlined,
              iconColor: AppColors.warning,
              child: Text(report.issuesPoints),
            ),

          if (report.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: report.tags.map((t) => Chip(label: Text(t))).toList(),
              ),
            ),

          if (report.storeSystemReportCopy.isNotEmpty)
            _SectionCard(
              title: 'コンビニ側システム入力控え',
              icon: Icons.receipt_long,
              child: Text(report.storeSystemReportCopy),
            ),

          if (report.notes.isNotEmpty)
            _SectionCard(
              title: '備考',
              icon: Icons.notes,
              child: Text(report.notes),
            ),

          const SizedBox(height: 16),
          Text(
            '作成: ${DateFormat('yyyy/MM/dd HH:mm').format(report.createdAt)}\n更新: ${DateFormat('yyyy/MM/dd HH:mm').format(report.updatedAt)}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Color? iconColor;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: iconColor ?? AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
