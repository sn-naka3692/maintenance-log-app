import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../models/work_report.dart';
import '../providers/app_state.dart';
import '../services/app_config_service.dart';
import '../services/monthly_export_status_service.dart';
import '../theme/app_theme.dart';
import '../widgets/report_card.dart';
import '../utils/csv_exporter.dart';
import 'report_detail_screen.dart';
import 'submission_check_screen.dart';
import 'parts_reconciliation_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  String? _selectedAuthorId;
  bool _isExporting = false;
  bool _isSaving = false;

  // ------------------------------------------------------------
  // 冷媒種類マスタ(管理者昇格ルート・2026-09導入)関連
  // ------------------------------------------------------------
  final TextEditingController _newRefrigerantCtrl = TextEditingController();
  bool _addingRefrigerantType = false;

  // ------------------------------------------------------------
  // 月次CSVエクスポート(SE店舗分・プロワン案件分・社内業務分)関連
  // ------------------------------------------------------------
  final MonthlyExportStatusService _monthlyExportService =
      MonthlyExportStatusService.instance;
  MonthlyExportStatus? _monthlyStatus;
  bool _monthlyStatusLoading = true;
  bool _monthlyExportRunning = false;
  // リマインドの対象は「前月」(まだ月末まで作業日が確定していない今月分は対象外)。
  late final DateTime _targetMonth = _computePreviousMonth(DateTime.now());

  // ------------------------------------------------------------
  // 【月末チェック(日報記入率)機能】ON/OFFトグル関連
  // ------------------------------------------------------------
  bool _submissionCheckEnabled = false;
  bool _submissionCheckLoading = true;
  bool _submissionCheckToggling = false;

  static DateTime _computePreviousMonth(DateTime now) {
    return now.month == 1
        ? DateTime(now.year - 1, 12)
        : DateTime(now.year, now.month - 1);
  }

  String get _targetMonthKey => DateFormat('yyyy-MM').format(_targetMonth);
  String get _targetMonthLabel => DateFormat('yyyy年M月').format(_targetMonth);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMonthlyStatus());
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _loadSubmissionCheckEnabled(),
    );
  }

  @override
  void dispose() {
    _newRefrigerantCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSubmissionCheckEnabled() async {
    setState(() => _submissionCheckLoading = true);
    try {
      final enabled = await AppConfigService.instance
          .fetchSubmissionCheckEnabled();
      if (mounted) setState(() => _submissionCheckEnabled = enabled);
    } finally {
      if (mounted) setState(() => _submissionCheckLoading = false);
    }
  }

  Future<void> _toggleSubmissionCheckEnabled(bool value) async {
    setState(() => _submissionCheckToggling = true);
    try {
      await AppConfigService.instance.updateSubmissionCheckEnabled(value);
      if (mounted) setState(() => _submissionCheckEnabled = value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('設定の更新に失敗しました: $e')));
      }
    } finally {
      if (mounted) setState(() => _submissionCheckToggling = false);
    }
  }

  Future<void> _loadMonthlyStatus() async {
    setState(() => _monthlyStatusLoading = true);
    try {
      final status = await _monthlyExportService.fetchStatus(_targetMonthKey);
      if (mounted) setState(() => _monthlyStatus = status);
    } finally {
      if (mounted) setState(() => _monthlyStatusLoading = false);
    }
  }

  /// 対象月(前月)の日報を3分類(SE/プロワン/社内業務)に振り分けたうえで、
  /// それぞれCSVを生成・共有(または保存)し、実施結果をFirestoreに記録する。
  Future<void> _runMonthlyExport(
    List<WorkReport> allReports, {
    required bool saveToDevice,
  }) async {
    final appState = context.read<AppState>();
    final monthly = CsvExporter.filterByMonth(
      allReports,
      _targetMonth.year,
      _targetMonth.month,
    );
    final byCategory = CsvExporter.splitByCategory(monthly, appState.stores);
    final authorName = appState.currentUser?.name ?? '';

    setState(() => _monthlyExportRunning = true);

    final resultCounts = <MonthlyExportCategory, int>{};
    final errors = <String>[];

    for (final category in MonthlyExportCategory.values) {
      final reports = byCategory[category] ?? [];
      resultCounts[category] = reports.length;
      if (reports.isEmpty) {
        // 対象0件のカテゴリも「出力済み」として記録し、翌月以降
        // 意味のないリマインドが出続けないようにする。
        try {
          await _monthlyExportService.markExported(
            monthKey: _targetMonthKey,
            category: category.key,
            count: 0,
            exportedByName: authorName,
          );
        } catch (e) {
          errors.add('${category.label}: 記録に失敗しました($e)');
        }
        continue;
      }
      try {
        final prefix = '日報データ_${_targetMonthKey}_${category.label}';
        if (saveToDevice) {
          await CsvExporter.exportAndSaveToDevice(
            reports,
            fileNamePrefix: prefix,
          );
        } else {
          await CsvExporter.exportAndShare(reports, fileNamePrefix: prefix);
        }
        await _monthlyExportService.markExported(
          monthKey: _targetMonthKey,
          category: category.key,
          count: reports.length,
          exportedByName: authorName,
        );
      } catch (e) {
        errors.add('${category.label}: 出力に失敗しました($e)');
      }
    }

    if (mounted) setState(() => _monthlyExportRunning = false);
    await _loadMonthlyStatus();

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              errors.isEmpty ? Icons.check_circle : Icons.warning_amber,
              color: errors.isEmpty ? AppColors.success : AppColors.warning,
            ),
            const SizedBox(width: 8),
            const Expanded(child: Text('月次CSVエクスポート結果')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '対象月: $_targetMonthLabel(訪問日基準)',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              for (final category in MonthlyExportCategory.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.description_outlined, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '${category.label}: ${resultCounts[category] ?? 0}件',
                      ),
                    ],
                  ),
                ),
              if (errors.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'エラー:',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.danger,
                  ),
                ),
                for (final e in errors)
                  Text('・$e', style: TextStyle(color: AppColors.danger)),
              ],
              const SizedBox(height: 10),
              Text(
                saveToDevice
                    ? 'このデバイスに保存しました。データが蓄積してきたら、保存されたCSVファイルを会社のNASへ移動してください。'
                    : '共有シートから、保存・送信先を選んでください。データが蓄積してきたら会社のNASへ移動してください。',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCsv(List filtered, {required bool isAll}) async {
    if (filtered.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('エクスポート対象の日報がありません')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('CSV出力に失敗しました: $e')));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// 共有シートを経由せず、端末(このデバイス)のダウンロードフォルダに
  /// 直接CSVを保存する。
  Future<void> _saveCsvToDevice(List filtered, {required bool isAll}) async {
    if (filtered.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存対象の日報がありません')));
      return;
    }
    setState(() => _isSaving = true);
    try {
      final savedName = await CsvExporter.exportAndSaveToDevice(
        filtered.cast(),
        fileNamePrefix: isAll ? '日報データ_全社員' : '日報データ_絞り込み',
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('このデバイスに保存しました: $savedName')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('CSV保存に失敗しました: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// 月次CSVエクスポート(SE店舗分・プロワン案件分・社内業務分)の
  /// リマインド表示+実行ボタンのカード。
  Widget _buildMonthlyExportCard() {
    final status = _monthlyStatus;
    final allExported = status?.allExported ?? false;
    final appState = context.watch<AppState>();
    final monthlyReportCount = CsvExporter.filterByMonth(
      appState.reports,
      _targetMonth.year,
      _targetMonth.month,
    ).length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: allExported
            ? AppColors.success.withValues(alpha: 0.06)
            : AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: allExported
              ? AppColors.success.withValues(alpha: 0.25)
              : AppColors.warning.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                allExported ? Icons.check_circle_outline : Icons.event_note,
                color: allExported ? AppColors.success : AppColors.warning,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '月次CSVエクスポート($_targetMonthLabel分)',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_monthlyStatusLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            )
          else if (allExported)
            Text(
              '$_targetMonthLabel分($monthlyReportCount件)は、SE店舗分・プロワン案件分・社内業務分すべて出力済みです。',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_targetMonthLabel分($monthlyReportCount件)のCSVがまだ出力されていません。'
                  '「対応区分」に応じてSE店舗分・プロワン案件分・社内業務分の3ファイルに'
                  '自動で振り分けて出力します。データが蓄積したら会社のNASへ移してください。',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800),
                ),
                if (status != null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _exportStatusChip('SE店舗分', status.seExported),
                      _exportStatusChip('プロワン案件分', status.prowanExported),
                      _exportStatusChip('社内業務分', status.backofficeExported),
                    ],
                  ),
                ],
              ],
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _monthlyExportRunning
                      ? null
                      : () => _runMonthlyExport(
                          appState.reports,
                          saveToDevice: false,
                        ),
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text('共有で出力'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _monthlyExportRunning
                      ? null
                      : () => _runMonthlyExport(
                          appState.reports,
                          saveToDevice: true,
                        ),
                  icon: const Icon(Icons.save_alt, size: 18),
                  label: const Text('保存で出力'),
                ),
              ),
            ],
          ),
          if (_monthlyExportRunning)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  /// 【月末チェック(日報記入率)機能】導線カード。
  ///
  /// 紙の作業報告書をコピー機でまとめてスキャンしたPDFをOCR解析し、
  /// 弊社受付Noを主キーとしてアプリ側の日報データと突合することで
  /// 「未提出の日報」を検知する機能。段階導入のためON/OFFトグルを
  /// 設け、既定はOFF(最高管理者のみ変更可能)。
  Widget _buildSubmissionCheckCard() {
    final appState = context.watch<AppState>();
    final canToggle = appState.isSuperAdmin;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.fact_check_outlined,
                color: AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '月末チェック(日報記入率)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
              if (_submissionCheckLoading || _submissionCheckToggling)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Switch(
                  value: _submissionCheckEnabled,
                  onChanged: canToggle ? _toggleSubmissionCheckEnabled : null,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '紙の作業報告書をまとめてスキャンしたPDFをアップロードし、AI-OCRで'
            '弊社受付Noを読み取ってアプリ側の日報データと自動突合します。'
            '未提出(記入漏れ)の日報を検知するための機能です。',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800),
          ),
          if (!canToggle) ...[
            const SizedBox(height: 6),
            Text(
              'ON/OFFの切り替えは最高管理者のみ行えます。',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
            ),
          ],
          const SizedBox(height: 10),
          if (_submissionCheckEnabled)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SubmissionCheckScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('月末チェックを開始(PDFアップロード)'),
              ),
            )
          else
            Text(
              '現在この機能はOFFになっています。',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }

  /// 【部品情報突合機能】導線カード。
  ///
  /// SDRSから毎月末頃に届く「SE請求明細書」Excelをアップロードし、
  /// 弊社受付Noを主キーとしてアプリ側の日報の使用部品記録と自動突合する
  /// ことで、現場入力の漏れ・記録ミスを検知する機能。
  Widget _buildPartsReconciliationCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                color: AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '部品情報突合(月次請求明細)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'SDRSから毎月末頃に届く「SE請求明細書」(Excel)をアップロードし、'
            '弊社受付Noをキーにアプリ側の日報の使用部品記録と自動突合します。'
            '入力漏れ・記録ミスの疑いがある案件を検知するための機能です。',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PartsReconciliationScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('部品突合を開始(Excelアップロード)'),
            ),
          ),
        ],
      ),
    );
  }

  /// 新しい冷媒種類をマスタへ正式追加する(管理者昇格ルート)。
  Future<void> _addRefrigerantType() async {
    final name = _newRefrigerantCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _addingRefrigerantType = true);
    try {
      await context.read<AppState>().addRefrigerantType(name);
      _newRefrigerantCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('「$name」を冷媒種類マスタへ追加しました')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('追加に失敗しました: $e')));
      }
    } finally {
      if (mounted) setState(() => _addingRefrigerantType = false);
    }
  }

  Future<void> _confirmDeleteRefrigerantType(
    BuildContext context,
    String id,
    String name,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('冷媒種類マスタから削除'),
        content: Text('「$name」をマスタから削除しますか?\n(既存の日報データには影響しません)'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('削除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<AppState>().deleteRefrigerantType(id);
    }
  }

  /// 【設計方針・2026-09追加】冷媒種類は「その他」入力の逃げ道を用意して
  /// いるが、現場で頻出する新しい冷媒はここから管理者が正式にマスタへ
  /// 昇格登録できる(ユーザー承認: 「管理者側でのマスタ昇格ルートでOK」。
  /// 種類が急激に増える想定ではないため、シンプルな一覧+追加フォームのみ。
  Widget _buildRefrigerantMasterCard() {
    final appState = context.watch<AppState>();
    final types = appState.refrigerantTypes;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.ac_unit, color: AppColors.primary, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '冷媒種類マスタ管理',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '日報の冷媒種類入力欄で「その他」選択時に自由入力された冷媒のうち、'
            '今後も使われそうなものをここでマスタへ正式追加すると、'
            '全社員のプルダウン選択肢に反映されます。',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newRefrigerantCtrl,
                  decoration: const InputDecoration(
                    labelText: '新しい冷媒種類(例: R290)',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _addingRefrigerantType ? null : _addRefrigerantType,
                child: _addingRefrigerantType
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('追加'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (types.isEmpty)
            Text(
              'まだマスタへ追加された冷媒種類はありません。',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: types
                  .map(
                    (t) => Chip(
                      label: Text(t.name),
                      onDeleted: () =>
                          _confirmDeleteRefrigerantType(context, t.id, t.name),
                      deleteIconColor: Colors.grey.shade600,
                      backgroundColor: AppColors.primary.withValues(
                        alpha: 0.08,
                      ),
                      side: BorderSide.none,
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _exportStatusChip(String label, bool exported) {
    return Chip(
      avatar: Icon(
        exported ? Icons.check : Icons.close,
        size: 14,
        color: exported ? AppColors.success : Colors.grey.shade600,
      ),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: exported
          ? AppColors.success.withValues(alpha: 0.1)
          : Colors.grey.shade200,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      side: BorderSide.none,
    );
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
    // 【締切管理ルール・2026-09導入】作業報告書作成後(作業日基準)1週間を
    // 過ぎてもナレッジ未入力の日報件数(要対応の目安として管理者へ表示)。
    final overdueCount = allReports.where((r) => r.isKnowledgeOverdue).length;

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
          const SizedBox(height: 10),
          // 【締切管理ルール・2026-09導入】作業報告書作成後(作業日基準)
          // 1週間を過ぎてもナレッジ未入力の件数。0件でなければ管理者が
          // 一目で気づけるよう警告色で表示する。
          _MiniStat(
            label: 'ナレッジ未入力(1週間超過)',
            value: '$overdueCount件',
            color: overdueCount > 0 ? AppColors.warning : Colors.grey,
            icon: Icons.schedule,
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
          _buildMonthlyExportCard(),
          const SizedBox(height: 20),
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
          const SizedBox(height: 20),
          _buildSubmissionCheckCard(),
          const SizedBox(height: 12),
          _buildPartsReconciliationCard(),
          const SizedBox(height: 12),
          _buildRefrigerantMasterCard(),
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
