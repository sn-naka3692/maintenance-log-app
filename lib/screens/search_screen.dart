import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/store.dart';
import '../models/work_report.dart';
import '../providers/app_state.dart';
import '../widgets/report_card.dart';
import 'report_detail_screen.dart';

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
  DateTime? _from;
  DateTime? _to;
  String? _filterStoreId;

  List<WorkReport> _results = [];

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
    );
    _computeNewestYearMonth(results);
    setState(() {
      _results = results;
    });
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
      appBar: AppBar(title: const Text('日報・ナレッジ')),
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
                  '${_results.length}件の結果',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            child: _results.isEmpty
                ? Center(
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
                  )
                : _buildGroupedResults(),
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
