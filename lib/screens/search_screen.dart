import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
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
  DateTime? _from;
  DateTime? _to;

  List<WorkReport> _results = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runSearch());
  }

  void _runSearch() {
    final appState = context.read<AppState>();
    setState(() {
      _results = appState.search(
        keyword: _keywordCtrl.text,
        responseType: _filterType,
        from: _from,
        to: _to,
        onlySuccess: _onlySuccess,
        onlyIssues: _onlyIssues,
      );
    });
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
      appBar: AppBar(title: const Text('日報検索・ナレッジ検索')),
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
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final r = _results[index];
                      return ReportCard(
                        report: r,
                        showAuthor: true,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ReportDetailScreen(reportId: r.id),
                            ),
                          );
                        },
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
