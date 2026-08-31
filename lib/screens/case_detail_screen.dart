import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/case.dart';
import '../models/work_report.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import 'report_detail_screen.dart';

/// 「案件」詳細画面。
///
/// 【位置づけ】1つの案件(伝票No/受付No一致、または内容類似度による
/// 自動グルーピングの結果)に紐づく複数の日報をまとめて表示する。
/// 管理者は、誤って自動グルーピングされた日報をここから手動で
/// 案件から切り離すことができる(A案の安全弁)。
class CaseDetailScreen extends StatefulWidget {
  final String caseId;
  const CaseDetailScreen({super.key, required this.caseId});

  @override
  State<CaseDetailScreen> createState() => _CaseDetailScreenState();
}

class _CaseDetailScreenState extends State<CaseDetailScreen> {
  WorkCase? _case;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final appState = context.read<AppState>();
      final c = await appState.getCaseById(widget.caseId);
      setState(() {
        _case = c;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '案件情報の取得に失敗しました: $e';
        _loading = false;
      });
    }
  }

  Future<void> _confirmUnlink(WorkReport report) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('案件から切り離しますか?'),
        content: Text(
          '${report.authorName}さんの日報(${DateFormat('yyyy/M/d').format(report.visitDate)})を'
          'この案件から手動で切り離します。\n\n'
          '誤って自動グルーピングされたと判断した場合のみ実行してください。'
          'この操作は取り消せません(再度保存されれば自動再判定されます)。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('切り離す'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    try {
      final appState = context.read<AppState>();
      await appState.unlinkReportFromCase(report.id, widget.caseId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('日報を案件から切り離しました')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('切り離しに失敗しました: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isAdmin = appState.isAdmin;
    final dateFmt = DateFormat('yyyy/M/d (E)', 'ja_JP');

    return Scaffold(
      appBar: AppBar(title: const Text('案件詳細')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(onPressed: _load, child: const Text('再試行')),
                  ],
                ),
              ),
            )
          : _case == null
          ? const Center(child: Text('該当する案件が見つかりません'))
          : Builder(
              builder: (context) {
                final c = _case!;
                final reports = appState.getReportsForCase(c);
                return RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildSummaryCard(c),
                      const SizedBox(height: 16),
                      Text(
                        '紐づく日報 (${reports.length}件)',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (!c.isConfirmed)
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.help_outline,
                                size: 18,
                                color: AppColors.warning,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'この案件は伝票No/受付Noが無いため、店舗・訪問日・作業内容の'
                                  '類似度から推測でまとめられています。誤りがあれば、管理者は'
                                  '該当の日報を個別に「切り離す」ことができます。',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ...reports.map(
                        (r) => Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: const Icon(Icons.person_outline),
                            title: Text(
                              r.authorName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '${dateFmt.format(r.visitDate)} ・ ${r.workContent}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isAdmin)
                                  IconButton(
                                    tooltip: 'この日報を案件から切り離す',
                                    icon: const Icon(
                                      Icons.link_off,
                                      size: 20,
                                      color: AppColors.danger,
                                    ),
                                    onPressed: () => _confirmUnlink(r),
                                  ),
                                const Icon(Icons.chevron_right, size: 18),
                              ],
                            ),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ReportDetailScreen(reportId: r.id),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildSummaryCard(WorkCase c) {
    final dateFmt = DateFormat('yyyy/M/d');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _statusBadge(c),
                if (c.hasRefrigerantFilling) ...[
                  const SizedBox(width: 6),
                  _refrigerantBadge(),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    c.storeName.isNotEmpty ? c.storeName : '(店舗不明)',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (c.primaryKeyValue.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.confirmation_number_outlined,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '伝票No/受付No: ${c.primaryKeyValue}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: _statTile(
                    icon: Icons.groups,
                    label: '対応者',
                    value: c.participants.map((p) => p.authorName).join('・'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _statTile(
                    icon: Icons.access_time,
                    label: '合計作業時間',
                    value: '${c.totalWorkHours.toStringAsFixed(1)} h',
                  ),
                ),
                Expanded(
                  child: _statTile(
                    icon: Icons.event,
                    label: '訪問期間',
                    value: c.firstVisitDate != null
                        ? (c.firstVisitDate == c.lastVisitDate
                              ? dateFmt.format(c.firstVisitDate!)
                              : '${dateFmt.format(c.firstVisitDate!)}〜${dateFmt.format(c.lastVisitDate ?? c.firstVisitDate!)}')
                        : '-',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              Text(
                value.isEmpty ? '-' : value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _refrigerantBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.ac_unit, size: 12, color: Colors.blue.shade700),
          const SizedBox(width: 3),
          Text(
            '冷媒充填',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.blue.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(WorkCase c) {
    final isConfirmed = c.isConfirmed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (isConfirmed ? AppColors.success : AppColors.warning).withValues(
          alpha: 0.12,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isConfirmed ? '確実' : '推測',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: isConfirmed ? AppColors.success : AppColors.warning,
        ),
      ),
    );
  }
}
