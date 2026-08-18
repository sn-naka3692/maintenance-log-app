import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/report_card.dart';
import 'report_detail_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  String? _selectedAuthorId;

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

    return Scaffold(
      appBar: AppBar(title: const Text('管理者ダッシュボード')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
