import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/parts_reconciliation_result.dart';
import '../providers/app_state.dart';
import '../services/billing_part_import_service.dart';
import '../services/parts_reconciliation_service.dart';
import '../services/parts_reconciliation_storage_service.dart';
import '../theme/app_theme.dart';
import '../utils/web_excel_picker.dart';

/// 【部品情報突合機能】
///
/// SDRS(サンデン・リテールシステム)から毎月末頃に届く「SE請求明細書」
/// Excelをアップロードすると、弊社受付Noをキーにアプリ側の日報データ
/// (WorkReport.partsUsed)と自動突合し、以下のズレを検知する:
///   - 現場記録なし(入力漏れ疑い): 請求明細には部品代計上があるのに
///     現場側の日報に使用部品の記録がない
///   - 内容不一致: 双方に記録はあるが部品名が食い違う
///   - 該当日報が見つからない: 受付Noに対応するWorkReportがアプリ側にない
///
/// 結果は対象月ごとにFirestore(parts_reconciliations)へ保存され、
/// 月末チェック(日報記入率)機能と同様に、同月内の再実行では
/// 前回結果が上書きされる。
class PartsReconciliationScreen extends StatefulWidget {
  const PartsReconciliationScreen({super.key});

  @override
  State<PartsReconciliationScreen> createState() =>
      _PartsReconciliationScreenState();
}

class _PartsReconciliationScreenState
    extends State<PartsReconciliationScreen> {
  Uint8List? _excelBytes;
  String? _excelFileName;

  bool _processing = false;
  String? _errorMessage;

  bool _saving = false;
  bool _saved = false;

  final List<PartsReconciliationResult> _results = [];

  /// この画面で扱う対象月(実行時点の年月、"yyyy-MM")。
  late final String _checkMonth = DateFormat('yyyy-MM').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSavedResults());
  }

  Future<void> _loadSavedResults() async {
    final saved = await PartsReconciliationStorageService.instance
        .fetchResultsForMonth(_checkMonth);
    if (!mounted || saved.isEmpty) return;
    setState(() {
      _results
        ..clear()
        ..addAll(saved);
      _saved = true;
    });
  }

  Future<void> _pickExcel() async {
    setState(() => _errorMessage = null);
    try {
      Uint8List? bytes;
      String? fileName;
      if (kIsWeb) {
        // file_pickerのWeb実装がビルド環境次第で登録されない不具合を
        // 回避するため、PDF版と同様に自前の<input type="file">実装を使う。
        final picked = await pickExcelFileWeb();
        if (picked == null) return; // キャンセル
        bytes = picked.bytes;
        fileName = picked.name;
      } else {
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
          withData: true,
        );
        if (result == null || result.files.isEmpty) return;
        final file = result.files.single;
        bytes = file.bytes;
        fileName = file.name;
      }
      if (bytes == null) {
        setState(() => _errorMessage = 'ファイルの読み込みに失敗しました');
        return;
      }
      setState(() {
        _excelBytes = bytes;
        _excelFileName = fileName;
        _results.clear();
        _saved = false;
      });
    } catch (e) {
      setState(() => _errorMessage = 'ファイル選択に失敗しました: $e');
    }
  }

  Future<void> _startProcessing() async {
    final bytes = _excelBytes;
    if (bytes == null) return;

    final appState = context.read<AppState>();
    final allReports = appState.reports;

    setState(() {
      _processing = true;
      _errorMessage = null;
      _saved = false;
      _results.clear();
    });

    try {
      final billingRecords = BillingPartImportService.parse(bytes);
      if (billingRecords.isEmpty) {
        setState(() => _errorMessage = '明細データが見つかりませんでした。ファイル形式をご確認ください。');
        return;
      }
      final results = PartsReconciliationService.reconcile(
        billingRecords: billingRecords,
        allReports: allReports,
      );
      setState(() => _results.addAll(results));

      if (mounted && _results.isNotEmpty) {
        await _saveResultsToFirestore();
      }
    } catch (e) {
      setState(() => _errorMessage = '解析に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _saveResultsToFirestore() async {
    setState(() => _saving = true);
    try {
      await PartsReconciliationStorageService.instance.saveResults(
        checkMonth: _checkMonth,
        results: _results,
      );
      if (mounted) {
        setState(() => _saved = true);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('突合結果を保存しました')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('突合結果の保存に失敗しました: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<PartsReconciliationResult> get _attentionResults =>
      _results.where((r) => r.status.needsAttention).toList();

  @override
  Widget build(BuildContext context) {
    final matchedCount = _results
        .where((r) => r.status == PartsMatchStatus.matched)
        .length;
    final attentionCount = _attentionResults.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('部品情報突合(月次請求明細)'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else if (_saved)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: Icon(Icons.cloud_done_outlined, color: Colors.white),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SDRSから毎月末頃に届く「SE請求明細書」(Excel)をアップロード'
                'してください。弊社受付Noをキーに、アプリ側の日報に記録された'
                '使用部品情報と自動で突き合わせます。結果は対象月'
                '($_checkMonth)ごとにFirestoreへ自動保存され、同月内に'
                '再実行すると前回結果が上書きされます。',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
              ),
              if (_saved && !_processing) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.cloud_done_outlined,
                      size: 16,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$_checkMonth 分の結果は保存済みです',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.table_chart_outlined,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _excelFileName ?? 'Excelファイル(.xlsx)が選択されていません',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _processing ? null : _pickExcel,
                              icon: const Icon(Icons.folder_open, size: 18),
                              label: const Text('Excelを選択'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: (_excelBytes == null || _processing)
                                  ? null
                                  : _startProcessing,
                              icon: const Icon(Icons.play_arrow, size: 18),
                              label: const Text('突合を開始'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: AppColors.danger, fontSize: 12.5),
                  ),
                ),
              ],
              if (_processing) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ],
              if (_results.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    _resultChip(
                      '一致',
                      matchedCount,
                      AppColors.success,
                      Icons.check_circle_outline,
                    ),
                    const SizedBox(width: 10),
                    _resultChip(
                      '要確認',
                      attentionCount,
                      AppColors.warning,
                      Icons.warning_amber,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (attentionCount > 0) ...[
                  Text(
                    '要確認の案件(入力漏れ・不一致の疑い)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.warning,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._attentionResults.map(_buildResultTile),
                  const SizedBox(height: 16),
                ],
                Text(
                  '全結果(全${_results.length}件)',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                ..._results.map(_buildResultTile),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultChip(String label, int count, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(
              '$label $count件',
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultTile(PartsReconciliationResult r) {
    late final IconData icon;
    late final Color color;

    switch (r.status) {
      case PartsMatchStatus.matched:
        icon = Icons.check_circle_outline;
        color = AppColors.success;
        break;
      case PartsMatchStatus.missingOnSite:
        icon = Icons.report_gmailerrorred;
        color = AppColors.danger;
        break;
      case PartsMatchStatus.missingOnBilling:
        icon = Icons.help_outline;
        color = AppColors.warning;
        break;
      case PartsMatchStatus.mismatch:
        icon = Icons.warning_amber;
        color = AppColors.warning;
        break;
      case PartsMatchStatus.reportNotFound:
        icon = Icons.search_off;
        color = AppColors.warning;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(
          '受付No: ${r.receiptNumber}${r.storeName.isNotEmpty ? '(${r.storeName})' : ''}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                r.status.label,
                style: TextStyle(
                  fontSize: 12.5,
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '請求明細: ${r.billingParts.isEmpty ? 'なし' : r.billingParts.join(', ')}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              Text(
                '現場記録: ${r.sitePartsRecorded.isEmpty ? 'なし' : r.sitePartsRecorded.join(', ')}'
                '${r.matchedAuthorName != null ? '(${r.matchedAuthorName})' : ''}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
        isThreeLine: true,
      ),
    );
  }
}
