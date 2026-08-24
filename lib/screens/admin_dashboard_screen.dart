import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/report_card.dart';
import '../utils/csv_exporter.dart';
import 'report_detail_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  String? _selectedAuthorId;
  bool _isExporting = false;
  bool _isSaving = false;

  Future<void> _exportCsv(List filtered, {required bool isAll}) async {
    if (filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('エクスポート対象の日報がありません')),
      );
      return;
    }
    setState(() => _isExporting = true);
    try {
      await CsvExporter.exportAndShare(
        filtered.cast(),
        fileNamePrefix: isAll ? '日報データ_全社員' : '日報データ_絞り込み',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CSV出力に失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// 共有シートを経由せず、端末(このデバイス)のダウンロードフォルダに
  /// 直接CSVを保存する。
  Future<void> _saveCsvToDevice(List filtered, {required bool isAll}) async {
    if (filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存対象の日報がありません')),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      final savedName = await CsvExporter.exportAndSaveToDevice(
        filtered.cast(),
        fileNamePrefix: isAll ? '日報データ_全社員' : '日報データ_絞り込み',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('このデバイスに保存しました: $savedName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CSV保存に失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final allReports = appState.reports;

    final filtered = _selectedAuthorId == null
        ? allReports
        : allReports.where((r) => r.authorId == _selectedAuthorId).toList();

    final byType = appState.countByResponseType(allReports);
    final byAuthor = appState.countByAuthor(allReports);

    final successCount = allReports.where((r) => r.hasSuccess).length;
    final issuesCount = allReports.where((r) => r.hasIssues).length;

    final currentUser = appState.currentUser;
    final isSuperAdmin = appState.isSuperAdmin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('管理者ダッシュボード'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Chip(
                avatar: Icon(
                  isSuperAdmin ? Icons.security : Icons.admin_panel_settings,
                  size: 16,
                  color: isSuperAdmin ? AppColors.danger : AppColors.primary,
                ),
                label: Text(
                  AppUser.roleLabel(currentUser?.role),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isSuperAdmin ? AppColors.danger : AppColors.primary,
                  ),
                ),
                backgroundColor: isSuperAdmin
                    ? AppColors.danger.withValues(alpha: 0.1)
                    : AppColors.primary.withValues(alpha: 0.1),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                side: BorderSide.none,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!isSuperAdmin)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '一般管理者としてログイン中です。社員の役割変更・削除は最高管理者のみ行えます。',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: '全日報数',
                  value: '${allReports.length}',
                  color: AppColors.primary,
                  icon: Icons.description,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  label: '登録社員数',
                  value: '${appState.users.length}',
                  color: Colors.teal,
                  icon: Icons.groups,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: '成功事例',
                  value: '$successCount',
                  color: AppColors.success,
                  icon: Icons.thumb_up,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  label: '課題・失敗事例',
                  value: '$issuesCount',
                  color: AppColors.warning,
                  icon: Icons.report_problem,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          const Text(
            '対応区分別の件数',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          if (byType.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'データがありません',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            )
          else
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final keys = byType.keys.toList();
                          final i = value.toInt();
                          if (i < 0 || i >= keys.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              keys[i],
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: byType.entries.toList().asMap().entries.map((e) {
                    final index = e.key;
                    final entry = e.value;
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: entry.value.toDouble(),
                          color: responseTypeColor(entry.key),
                          width: 24,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),

          const SizedBox(height: 24),
          const Text(
            '社員別 日報提出数',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'タップすると個人の日報一覧に絞り込めます(人事評価の参考データ)',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          ...appState.users.map((u) {
            final count = byAuthor[u.name] ?? 0;
            final selected = _selectedAuthorId == u.id;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.08)
                  : null,
              child: ListTile(
                onTap: () {
                  setState(() {
                    _selectedAuthorId = selected ? null : u.id;
                  });
                },
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                  child: Text(
                    u.name.isNotEmpty ? u.name.substring(0, 1) : '?',
                    style: const TextStyle(color: AppColors.primary),
                  ),
                ),
                title: Text(u.name),
                subtitle: Text('${u.department} ・ ${u.employeeCode}'),
                trailing: Text(
                  '$count件',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            );
          }),

          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                _selectedAuthorId == null ? '全社員の日報一覧' : '絞り込み結果',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (_selectedAuthorId != null)
                TextButton(
                  onPressed: () => setState(() => _selectedAuthorId = null),
                  child: const Text('絞り込み解除'),
                ),
            ],
          ),
          const SizedBox(height: 10),
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
              children: [
                Icon(
                  Icons.table_chart_outlined,
                  color: AppColors.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '蓄積された日報データをCSVファイルで出力できます',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '共有(メール・LINE等に送る)',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isExporting
                      ? null
                      : () => _exportCsv(allReports, isAll: true),
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: Text('全件(${allReports.length}件)を共有'),
                ),
              ),
              if (_selectedAuthorId != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isExporting
                        ? null
                        : () => _exportCsv(filtered, isAll: false),
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: Text('絞り込み(${filtered.length}件)を共有'),
                  ),
                ),
              ],
            ],
          ),
          if (_isExporting)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
          const SizedBox(height: 14),
          Text(
            'このデバイスに保存(ダウンロードフォルダへ直接保存)',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isSaving
                      ? null
                      : () => _saveCsvToDevice(allReports, isAll: true),
                  icon: const Icon(Icons.save_alt, size: 18),
                  label: Text('全件(${allReports.length}件)を保存'),
                ),
              ),
              if (_selectedAuthorId != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isSaving
                        ? null
                        : () => _saveCsvToDevice(filtered, isAll: false),
                    icon: const Icon(Icons.save_alt, size: 18),
                    label: Text('絞り込み(${filtered.length}件)を保存'),
                  ),
                ),
              ],
            ],
          ),
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                '日報がありません',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            )
          else
            ...filtered
                .take(30)
                .map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ReportCard(
                      report: r,
                      showAuthor: true,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ReportDetailScreen(reportId: r.id),
                          ),
                        );
                      },
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
