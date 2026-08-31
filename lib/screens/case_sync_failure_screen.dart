import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/case_sync_failure_service.dart';
import '../theme/app_theme.dart';
import 'report_detail_screen.dart';

/// 【管理者用】「日報→案件」自動反映の失敗一覧画面。
///
/// 【背景・2026-08-31追加】
/// 日報保存時の案件自動グルーピング処理はベストエフォートであり、
/// 従来は失敗してもデバッグログのみで本番環境からは見えなかった。
/// このため「日報にはある情報が案件に反映されていない」という
/// 不整合に管理者が気づく手段が無かった。この画面は、記録された
/// 同期失敗を一覧表示し、その場で再試行または解決済みマークを
/// できるようにする。
class CaseSyncFailureScreen extends StatefulWidget {
  const CaseSyncFailureScreen({super.key});

  @override
  State<CaseSyncFailureScreen> createState() => _CaseSyncFailureScreenState();
}

class _CaseSyncFailureScreenState extends State<CaseSyncFailureScreen> {
  List<CaseSyncFailure> _failures = [];
  bool _loading = true;
  String? _error;
  final Set<String> _processingIds = {};

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
      final failures = await appState.getCaseSyncFailures();
      if (!mounted) return;
      setState(() {
        _failures = failures;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '一覧の取得に失敗しました: $e';
        _loading = false;
      });
    }
  }

  Future<void> _retry(CaseSyncFailure failure) async {
    setState(() => _processingIds.add(failure.id));
    try {
      final appState = context.read<AppState>();
      final ok = await appState.retryCaseSync(failure.reportId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? '再同期に成功しました' : '対象の日報が見つかりませんでした(記録を削除しました)'),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('再同期に失敗しました: $e')));
      await _load();
    } finally {
      if (mounted) setState(() => _processingIds.remove(failure.id));
    }
  }

  Future<void> _dismiss(CaseSyncFailure failure) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解決済みにしますか?'),
        content: const Text(
          'この記録を一覧から削除します。日報自体・案件への紐付けは変更されません'
          '(意図的に未グルーピングのままで問題ない場合などに使用してください)。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('解決済みにする'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    setState(() => _processingIds.add(failure.id));
    try {
      final appState = context.read<AppState>();
      await appState.dismissCaseSyncFailure(failure.reportId);
      await _load();
    } finally {
      if (mounted) setState(() => _processingIds.remove(failure.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('案件反映エラー一覧'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
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
          : _failures.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 48,
                      color: AppColors.success,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '現在、未解決の反映エラーはありません',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber,
                        size: 18,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_failures.length}件の日報で、案件への自動反映に失敗しています。'
                          '「再試行」で解決しない場合は、日報の内容(伝票No等)を確認してください。',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
                ..._failures.map((f) => _buildFailureCard(f)),
              ],
            ),
    );
  }

  Widget _buildFailureCard(CaseSyncFailure f) {
    final processing = _processingIds.contains(f.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, size: 18, color: AppColors.danger),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    f.reportSummary,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '発生日時: ${DateFormat('yyyy/MM/dd HH:mm').format(f.occurredAt)}',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 4),
            Text(
              'エラー内容: ${f.errorMessage}',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton.icon(
                  onPressed: processing
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ReportDetailScreen(reportId: f.reportId),
                            ),
                          );
                        },
                  icon: const Icon(Icons.description_outlined, size: 16),
                  label: const Text('日報を見る'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: processing ? null : () => _dismiss(f),
                  child: const Text('解決済みにする'),
                ),
                const SizedBox(width: 4),
                ElevatedButton.icon(
                  onPressed: processing ? null : () => _retry(f),
                  icon: processing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync, size: 16),
                  label: const Text('再試行'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
