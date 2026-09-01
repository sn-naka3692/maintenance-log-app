import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/store.dart';
import '../models/work_report.dart';
import '../providers/app_state.dart';
import '../utils/excel_exporter.dart';
import '../utils/pdf_exporter.dart';
import '../widgets/report_card.dart';
import 'report_detail_screen.dart';

/// 出力形式(Excel/PDF)の選択肢
enum _ExportFormat { excel, pdf }

/// 出力方法(共有/端末保存)の選択肢
enum _ExportMethod { share, save }

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _keywordCtrl = TextEditingController();
  ResponseType? _filterType;
  bool _onlySuccess = false;
  bool _onlyIssues = false;
  bool _onlyRefrigerantFilling = false;
  bool _onlyKnowledgeOverdue = false;
  DateTime? _from;
  DateTime? _to;
  String? _filterStoreId;

  List<WorkReport> _results = [];
  bool _refreshing = false;
  bool _exporting = false;

  // 【出力対象選択機能・2026-08追加】
  // 「選択して出力」を押すと選択モードに入り、チェックを付けた日報のみを
  // Excel/PDF出力の対象にできる。選択モードでないときは検索結果全件が
  // 対象になる(従来通りの挙動)。
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  // 【検索結果のフォルダー化・2026-08追加】案件一覧と同様の方靈で、
  // 検索結果(日報)も訪問日の年→月のフォルダー(ExpansionTile)に
  // 分類して表示する。一番新しい年・年月のフォルダーだけを初期展開する。
  int? _newestYear;
  String? _newestYearMonthKey; // "yyyy-M" 形式

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runSearch());
  }

  /// 「更新」操作(手動リフレッシュ)。
  ///
  /// 【背景・2026-08追加】他の従業員が新しく投稿した日報がすぐに一覧へ
  /// 反映されない(アプリを開いたタイミングのキャッシュのまま)という声を
  /// 踏まえ、「案件」タブと同様に、この画面にも手動更新ボタンを設ける。
  /// Firestoreから最新の日報一覧を取得し直してから、現在の検索条件で
  /// 再検索する。
  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await context.read<AppState>().refreshReports();
      if (mounted) _runSearch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('更新に失敗しました: $e')));
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _runSearch() {
    final appState = context.read<AppState>();
    final results = appState.search(
      keyword: _keywordCtrl.text,
      storeId: _filterStoreId,
      responseType: _filterType,
      from: _from,
      to: _to,
      onlySuccess: _onlySuccess,
      onlyIssues: _onlyIssues,
      onlyRefrigerantFilling: _onlyRefrigerantFilling,
      onlyKnowledgeOverdue: _onlyKnowledgeOverdue,
    );
    _computeNewestYearMonth(results);
    setState(() {
      _results = results;
      // 検索条件が変わった際、選択済みIDの中に結果から消えたものが
      // あれば取り除く(絞り込み変更後に見えない日報が選択されたまま
      // 出力対象に残ってしまうのを防ぐ)。
      final resultIds = results.map((r) => r.id).toSet();
      _selectedIds.removeWhere((id) => !resultIds.contains(id));
    });
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) _selectedIds.clear();
    });
  }

  void _toggleSelected(String reportId) {
    setState(() {
      if (_selectedIds.contains(reportId)) {
        _selectedIds.remove(reportId);
      } else {
        _selectedIds.add(reportId);
      }
    });
  }

  void _selectAllVisible() {
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(_results.map((r) => r.id));
    });
  }

  void _clearSelection() {
    setState(() => _selectedIds.clear());
  }

  /// 一番新しい年・年月を算出し、フォルダーの初期展開状態の基準にする。
  void _computeNewestYearMonth(List<WorkReport> reports) {
    if (reports.isEmpty) {
      _newestYear = null;
      _newestYearMonthKey = null;
      return;
    }
    final sorted = List<WorkReport>.from(reports)
      ..sort((a, b) => b.visitDate.compareTo(a.visitDate));
    final newest = sorted.first.visitDate;
    _newestYear = newest.year;
    _newestYearMonthKey = '${newest.year}-${newest.month}';
  }

  /// 検索結果(日報)を訪問日の年→月の階層マップに分類する。
  /// 戻り値: {年: {月: [日報一覧(訪問日新しい順)]}}
  Map<int, Map<int, List<WorkReport>>> _groupByYearMonth(
    List<WorkReport> reports,
  ) {
    final map = <int, Map<int, List<WorkReport>>>{};
    for (final r in reports) {
      final date = r.visitDate;
      final monthMap = map.putIfAbsent(date.year, () => {});
      monthMap.putIfAbsent(date.month, () => []).add(r);
    }
    for (final monthMap in map.values) {
      for (final list in monthMap.values) {
        list.sort((a, b) => b.visitDate.compareTo(a.visitDate));
      }
    }
    return map;
  }

  /// 【日報・ナレッジ出力機能・2026-08追加】
  /// 現在の検索結果(_results)をExcel(.xlsx)またはPDFとして出力する。
  /// 出力形式(Excel/PDF)と出力方法(共有/端末保存)を選択させ、
  /// [ExcelExporter]/[PdfExporter]を呼び出す。
  Future<void> _exportResults() async {
    // 選択モード中はチェックした日報のみ、それ以外は検索結果全件を対象にする。
    final targets = _selectionMode
        ? _results.where((r) => _selectedIds.contains(r.id)).toList()
        : _results;

    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_selectionMode ? '出力する日報を選択してください' : '出力対象の日報がありません'),
        ),
      );
      return;
    }

    final format = await showModalBottomSheet<_ExportFormat>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  '出力形式を選択',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.grid_on, color: Colors.green),
                title: const Text('Excel(.xlsx)で出力'),
                subtitle: Text('A4横向き表形式・${targets.length}件'),
                onTap: () => Navigator.pop(context, _ExportFormat.excel),
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: const Text('PDFで出力'),
                subtitle: Text('A4帳票形式・${targets.length}件'),
                onTap: () => Navigator.pop(context, _ExportFormat.pdf),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (format == null || !mounted) return;

    final method = await showModalBottomSheet<_ExportMethod>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  '出力方法を選択',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('共有で出力'),
                subtitle: const Text('メール添付・LINE送信など'),
                onTap: () => Navigator.pop(context, _ExportMethod.share),
              ),
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('端末に保存'),
                subtitle: const Text('ダウンロードフォルダへ直接保存'),
                onTap: () => Navigator.pop(context, _ExportMethod.save),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (method == null || !mounted) return;

    setState(() => _exporting = true);
    try {
      String? savedFileName;
      if (format == _ExportFormat.excel) {
        if (method == _ExportMethod.share) {
          await ExcelExporter.exportAndShare(targets);
        } else {
          savedFileName = await ExcelExporter.exportAndSaveToDevice(targets);
        }
      } else {
        if (method == _ExportMethod.share) {
          await PdfExporter.exportAndShare(targets);
        } else {
          savedFileName = await PdfExporter.exportAndSaveToDevice(targets);
        }
      }
      if (mounted && savedFileName != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存しました: $savedFileName')));
      }
      // 出力完了後は選択モードを解除して通常表示に戻す。
      if (mounted && _selectionMode) {
        setState(() {
          _selectionMode = false;
          _selectedIds.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('出力に失敗しました: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _from != null && _to != null
          ? DateTimeRange(start: _from!, end: _to!)
          : null,
      locale: const Locale('ja', 'JP'),
    );
    if (range != null) {
      setState(() {
        _from = range.start;
        _to = range.end;
      });
      _runSearch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('M/d');
    return Scaffold(
      appBar: AppBar(
        title: const Text('日報・ナレッジ'),
        actions: [
          IconButton(
            icon: _refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: '最新の日報に更新',
            onPressed: _refreshing ? null : _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _keywordCtrl,
                  decoration: InputDecoration(
                    hintText: '顧客名・作業内容・機種・キーワードで検索',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _keywordCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _keywordCtrl.clear();
                              _runSearch();
                            },
                          )
                        : null,
                  ),
                  onChanged: (_) => _runSearch(),
                ),
                const SizedBox(height: 10),
                Consumer<AppState>(
                  builder: (context, appState, _) {
                    final stores = List<Store>.from(appState.stores)
                      ..sort((a, b) => a.name.compareTo(b.name));
                    return DropdownButtonFormField<String?>(
                      initialValue: _filterStoreId,
                      decoration: const InputDecoration(
                        labelText: '店舗名で絞り込み',
                        prefixIcon: Icon(Icons.storefront_outlined),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('すべての店舗'),
                        ),
                        ...stores.map(
                          (s) => DropdownMenuItem<String?>(
                            value: s.id,
                            child: Text(
                              s.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        setState(() => _filterStoreId = v);
                        _runSearch();
                      },
                    );
                  },
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('うまくいった事例'),
                        avatar: const Icon(Icons.thumb_up, size: 16),
                        selected: _onlySuccess,
                        onSelected: (v) {
                          setState(() => _onlySuccess = v);
                          _runSearch();
                        },
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('失敗・課題事例'),
                        avatar: const Icon(Icons.report_problem, size: 16),
                        selected: _onlyIssues,
                        onSelected: (v) {
                          setState(() => _onlyIssues = v);
                          _runSearch();
                        },
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('冷媒充填案件'),
                        avatar: const Icon(Icons.propane_tank, size: 16),
                        selected: _onlyRefrigerantFilling,
                        onSelected: (v) {
                          setState(() => _onlyRefrigerantFilling = v);
                          _runSearch();
                        },
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('ナレッジ未入力(1週間超過)'),
                        avatar: Icon(
                          Icons.schedule,
                          size: 16,
                          color: _onlyKnowledgeOverdue
                              ? Colors.white
                              : Colors.orange.shade800,
                        ),
                        selected: _onlyKnowledgeOverdue,
                        selectedColor: Colors.orange.shade700,
                        labelStyle: TextStyle(
                          color: _onlyKnowledgeOverdue
                              ? Colors.white
                              : Colors.orange.shade800,
                        ),
                        onSelected: (v) {
                          setState(() => _onlyKnowledgeOverdue = v);
                          _runSearch();
                        },
                      ),
                      const SizedBox(width: 8),
                      ActionChip(
                        avatar: const Icon(Icons.date_range, size: 16),
                        label: Text(
                          _from != null && _to != null
                              ? '${dateFmt.format(_from!)} - ${dateFmt.format(_to!)}'
                              : '期間指定',
                        ),
                        onPressed: _pickRange,
                      ),
                      if (_from != null)
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () {
                            setState(() {
                              _from = null;
                              _to = null;
                            });
                            _runSearch();
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _typeChip(null, '全対応区分'),
                      ...ResponseType.values.map((t) => _typeChip(t, t.label)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  _selectionMode
                      ? '${_selectedIds.length}件選択中(全${_results.length}件)'
                      : '${_results.length}件の結果',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const Spacer(),
                if (_selectionMode) ...[
                  TextButton(
                    onPressed: _selectAllVisible,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 32),
                    ),
                    child: const Text('全選択', style: TextStyle(fontSize: 12)),
                  ),
                  TextButton(
                    onPressed: _clearSelection,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 32),
                    ),
                    child: const Text('解除', style: TextStyle(fontSize: 12)),
                  ),
                  TextButton.icon(
                    onPressed: _exporting ? null : _exportResults,
                    icon: const Icon(Icons.file_download_outlined, size: 16),
                    label: const Text('出力', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: '選択をやめる',
                    onPressed: _toggleSelectionMode,
                    visualDensity: VisualDensity.compact,
                  ),
                ] else if (_results.isNotEmpty) ...[
                  TextButton.icon(
                    onPressed: _toggleSelectionMode,
                    icon: const Icon(Icons.checklist, size: 16),
                    label: const Text('選択して出力', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _exporting ? null : _exportResults,
                    icon: const Icon(Icons.file_download_outlined, size: 16),
                    label: const Text('全件出力', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: _results.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.5,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.search_off,
                                  size: 48,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '該当する日報が見つかりません',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : _buildGroupedResults(),
            ),
          ),
        ],
      ),
    );
  }

  /// 【検索結果のフォルダー化】検索結果(日報)を訪問日の年→月フォルダーに
  /// 分類して表示する。案件一覧画面と同じ設計思想(最新の年・年月だけ
  /// 初期展開)。
  Widget _buildGroupedResults() {
    final grouped = _groupByYearMonth(_results);
    final years = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        for (final year in years) _buildYearFolder(year, grouped[year]!),
      ],
    );
  }

  /// 「年」フォルダー(ExpansionTile)。その下に「月」フォルダーを内包する。
  Widget _buildYearFolder(int year, Map<int, List<WorkReport>> monthMap) {
    final months = monthMap.keys.toList()..sort((a, b) => b.compareTo(a));
    final totalCount = monthMap.values.fold<int>(0, (sum, l) => sum + l.length);
    final initiallyExpanded = year == _newestYear;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey('report_year_$year'),
          initiallyExpanded: initiallyExpanded,
          leading: const Icon(Icons.folder_outlined, color: Colors.indigo),
          title: Text(
            '$year年',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$totalCount件',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more),
            ],
          ),
          children: [
            for (final month in months)
              _buildMonthFolder(year, month, monthMap[month]!),
          ],
        ),
      ),
    );
  }

  /// 「月」フォルダー(ExpansionTile)。日報カード一覧を内包する。
  Widget _buildMonthFolder(int year, int month, List<WorkReport> reports) {
    final monthKey = '$year-$month';
    final initiallyExpanded = monthKey == _newestYearMonthKey;

    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8),
      child: ExpansionTile(
        key: PageStorageKey('report_month_$monthKey'),
        initiallyExpanded: initiallyExpanded,
        leading: const Icon(Icons.folder_open_outlined, size: 20),
        title: Text(
          '$month月',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${reports.length}件',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 20),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
        children: [
          for (final r in reports)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ReportCard(
                report: r,
                showAuthor: true,
                selectionMode: _selectionMode,
                selected: _selectedIds.contains(r.id),
                onSelectToggle: () => _toggleSelected(r.id),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReportDetailScreen(reportId: r.id),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _typeChip(ResponseType? type, String label) {
    final selected = _filterType == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _filterType = type);
          _runSearch();
        },
      ),
    );
  }
}
