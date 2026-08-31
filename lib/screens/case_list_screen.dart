import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/case.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import 'case_detail_screen.dart';

/// 「案件」一覧画面。
///
/// 【位置づけ】日報検索とは別の切り口として、複数の日報が自動的に
/// 1つの案件としてまとめられたもの(伝票No/受付No一致、または内容の
/// 類似度に基づく自動グルーピング)を横断的に閲覧できるようにする。
/// 従業員の日報入力の手間は増やさず、あくまで閲覧・分析用の機能。
class CaseListScreen extends StatefulWidget {
  const CaseListScreen({super.key});

  @override
  State<CaseListScreen> createState() => _CaseListScreenState();
}

class _CaseListScreenState extends State<CaseListScreen> {
  List<WorkCase> _cases = [];
  bool _loading = true;
  String? _error;
  bool _onlyMultiPerson = false;
  bool _onlySuggested = false;
  bool _onlyRefrigerantFilling = false;
  bool _resyncing = false;
  bool _recalculating = false;
  bool _mergeMode = false;
  final Set<String> _selectedForMerge = {};

  // 【案件フォルダー化・2026-08追加】案件が増えてきた際の一覧性対策として、
  // 確定案件(status != 'suggested')を年→月のフォルダー(ExpansionTile)に
  // 分類して表示する。「要確認(推測)」の案件は判定が曖昧で見落とし厳禁の
  // ため、年月を問わず常に画面上部に平置き表示する(フォルダーの中に
  // 埋もれさせない)。
  int? _newestYear;
  String? _newestYearMonthKey; // "yyyy-M" 形式(初期展開の基準)

  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// 店舗名・伝票No/受付No・参加者名のいずれかに部分一致するかを判定する。
  bool _matchesQuery(WorkCase c, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    if (c.storeName.toLowerCase().contains(q)) return true;
    if (c.primaryKeyValue.toLowerCase().contains(q)) return true;
    for (final p in c.participants) {
      if (p.authorName.toLowerCase().contains(q)) return true;
    }
    return false;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final appState = context.read<AppState>();
      final cases = await appState.getAllCases();
      // 【2026-08変更】案件管理の観点から、単独対応の案件も含めて
      // 全件表示する(以前は複数日報が紐づく案件のみ表示していたが、
      // 経営側から「案件数の実態を把握したい」という要望のため撤廃)。
      _computeNewestYearMonth(cases);
      setState(() {
        _cases = cases;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '案件一覧の取得に失敗しました: $e';
        _loading = false;
      });
    }
  }

  /// 案件の「日付」を1つに定める共通ロジック(グルーピング・並び替え用)。
  /// 訪問日が無い(=まだ日報が紐づいていない)ケースは更新日時で代替する。
  DateTime _caseSortDate(WorkCase c) =>
      c.lastVisitDate ?? c.firstVisitDate ?? c.updatedAt;

  /// 一番新しい年・年月を算出し、フォルダーの初期展開状態の基準にする。
  /// 確定案件(status != 'suggested')を優先的に基準にする(「要確認」は
  /// フォルダー化の対象外のため)。確定案件が1件も無い場合のみ全件から算出。
  void _computeNewestYearMonth(List<WorkCase> cases) {
    final confirmed = cases.where((c) => c.status != 'suggested').toList();
    final source = confirmed.isNotEmpty ? confirmed : cases;
    if (source.isEmpty) {
      _newestYear = null;
      _newestYearMonthKey = null;
      return;
    }
    source.sort((a, b) => _caseSortDate(b).compareTo(_caseSortDate(a)));
    final newest = _caseSortDate(source.first);
    _newestYear = newest.year;
    _newestYearMonthKey = '${newest.year}-${newest.month}';
  }

  /// 確定案件(要確認以外)を年→月の階層マップに分類する。
  /// 戻り値: {年: {月: [案件一覧(日付新しい順)]}}
  Map<int, Map<int, List<WorkCase>>> _groupByYearMonth(List<WorkCase> cases) {
    final map = <int, Map<int, List<WorkCase>>>{};
    for (final c in cases) {
      final date = _caseSortDate(c);
      final monthMap = map.putIfAbsent(date.year, () => {});
      monthMap.putIfAbsent(date.month, () => []).add(c);
    }
    for (final monthMap in map.values) {
      for (final list in monthMap.values) {
        list.sort((a, b) => _caseSortDate(b).compareTo(_caseSortDate(a)));
      }
    }
    return map;
  }

  /// 未グルーピングの日報を一括で再判定する(管理者用)。
  ///
  /// 【背景】日報保存時、ブラウザが古いキャッシュ版アプリを使っていた等の
  /// 理由で、自動グルーピングが実行されないまま日報が保存されてしまう
  /// ケースがあることが判明した(2026-08-26)。このボタンは、既に案件へ
  /// 紐付いている日報には一切影響を与えず、未グルーピングの日報だけを
  /// 現在のロジックで再判定するための復旧手段。
  Future<void> _resyncUngrouped() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('未グルーピング日報の再判定'),
        content: const Text(
          'まだ案件に紐付いていない日報を対象に、現在の判定ロジックで'
          '再チェックします。\n\n'
          '・既に案件へ紐付いている日報には一切影響しません\n'
          '・伝票No/受付Noが一致するものは自動的に紐付けます\n'
          '・一致するものが見つからない日報はそのまま(未グルーピング)です\n\n'
          '実行してよろしいですか?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('実行する'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _resyncing = true);
    try {
      final appState = context.read<AppState>();
      final result = await appState.resyncUngroupedCases();
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('再判定が完了しました'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('対象の日報数: ${result.totalTargets}件'),
              Text('新たに案件へ紐付いた: ${result.linkedCount}件'),
              Text('一致なし(未グルーピングのまま): ${result.noMatchCount}件'),
              if (result.hasErrors)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'エラー: ${result.errorCount}件\n'
                    '${result.errors.take(3).join('\n')}',
                    style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('再判定処理に失敗しました: $e')));
    } finally {
      if (mounted) setState(() => _resyncing = false);
    }
  }

  /// 既存の全案件を、紐づく日報から正確に再計算する(管理者用)。
  ///
  /// 【背景】過去の不具合(日報の伝票No/受付Noを後から入力・変更した際に
  /// 旧案件からの切り離しが行われず、参加者・合計作業時間・冷媒充填有無
  /// 等の集計値が古いまま残ってしまう)により、既に案件へ紐付いている
  /// はずのデータが実際の日報内容と食い違ってしまうケースがあることが
  /// 判明した。このボタンは、既存の全案件を紐づく日報から丸ごと
  /// 作り直すことで、そうした不整合を一括で解消する。
  Future<void> _recalculateAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('全案件の再計算'),
        content: const Text(
          '既存のすべての案件を、現在紐づいている日報の内容から'
          '正確に作り直します。\n\n'
          '・日報の紐付け自体は変更しません\n'
          '・参加者・合計作業時間・冷媒充填有無・店舗名などの'
          '集計値を、日報の最新内容に基づいて再計算します\n'
          '・正常な案件の値は変化しません(安全な操作です)\n\n'
          '実行してよろしいですか?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('実行する'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _recalculating = true);
    try {
      final appState = context.read<AppState>();
      final result = await appState.recalculateAllCases();
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('再計算が完了しました'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('対象の案件数: ${result.totalTargets}件'),
              Text('再計算できた: ${result.successCount}件'),
              if (result.deletedCount > 0)
                Text('紐づく日報が消滅していたため削除: ${result.deletedCount}件'),
              if (result.hasErrors)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'エラー: ${result.errorCount}件\n'
                    '${result.errors.take(3).join('\n')}',
                    style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('再計算処理に失敗しました: $e')));
    } finally {
      if (mounted) setState(() => _recalculating = false);
    }
  }

  void _toggleMergeMode() {
    setState(() {
      _mergeMode = !_mergeMode;
      _selectedForMerge.clear();
    });
  }

  void _toggleSelectForMerge(String caseId) {
    setState(() {
      if (_selectedForMerge.contains(caseId)) {
        _selectedForMerge.remove(caseId);
      } else {
        _selectedForMerge.add(caseId);
      }
    });
  }

  /// 選択した複数案件を1つにまとめる(管理者用)。
  ///
  /// 【背景】案件一覧を全件表示にしたことで、本来同じ案件なのに
  /// 伝票No/受付Noの入力漏れ等により別々に分かれて表示されるケースが
  /// 見えるようになった。これを管理者が手動で統合できるようにする。
  Future<void> _mergeSelected() async {
    if (_selectedForMerge.length < 2) return;
    final selectedCases = _cases
        .where((c) => _selectedForMerge.contains(c.id))
        .toList();

    // まとめ先を選ぶ(デフォルトは確実判定・日報数最多のものを推奨)
    selectedCases.sort((a, b) {
      if (a.isConfirmed != b.isConfirmed) {
        return a.isConfirmed ? -1 : 1;
      }
      return b.linkedReportIds.length.compareTo(a.linkedReportIds.length);
    });
    String targetId = selectedCases.first.id;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String selected = targetId;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text('${selectedCases.length}件の案件をまとめる'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'どの案件を「まとめ先」にしますか?\n'
                    '他の案件はここに統合され、削除されます。',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  ...selectedCases.map(
                    (c) => RadioListTile<String>(
                      value: c.id,
                      groupValue: selected,
                      dense: true,
                      title: Text(
                        c.storeName.isNotEmpty ? c.storeName : '(店舗不明)',
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: Text(
                        '${c.isConfirmed ? "確実" : "推測"} ・ '
                        '日報${c.linkedReportIds.length}件'
                        '${c.primaryKeyValue.isNotEmpty ? " ・ ${c.primaryKeyValue}" : ""}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      onChanged: (v) {
                        if (v != null) setDialogState(() => selected = v);
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('キャンセル'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(selected),
                child: const Text('この案件にまとめる'),
              ),
            ],
          ),
        );
      },
    );
    if (result == null) return;
    targetId = result;

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('まとめてよろしいですか?'),
        content: const Text(
          '選択した案件を1つにまとめます。まとめ元の案件は削除され、'
          '紐づく日報はすべてまとめ先に付け替えられます。\n\n'
          'この操作は取り消せません(まとめ元に戻すには、日報を個別に'
          '案件から切り離す必要があります)。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('まとめる'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    try {
      final appState = context.read<AppState>();
      await appState.mergeCases(
        targetCaseId: targetId,
        sourceCaseIds: _selectedForMerge.toList(),
      );
      if (!mounted) return;
      setState(() {
        _mergeMode = false;
        _selectedForMerge.clear();
      });
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('案件をまとめました')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('まとめる処理に失敗しました: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('yyyy/M/d');
    var displayed = _cases;
    if (_onlyMultiPerson) {
      displayed = displayed.where((c) => c.isMultiPerson).toList();
    }
    if (_onlySuggested) {
      displayed = displayed.where((c) => c.status == 'suggested').toList();
    }
    if (_onlyRefrigerantFilling) {
      displayed = displayed.where((c) => c.hasRefrigerantFilling).toList();
    }
    if (_searchQuery.trim().isNotEmpty) {
      displayed = displayed
          .where((c) => _matchesQuery(c, _searchQuery.trim()))
          .toList();
    }

    final isAdmin = context.watch<AppState>().isAdmin;

    return Scaffold(
      appBar: AppBar(
        title: Text(_mergeMode ? '${_selectedForMerge.length}件選択中' : '案件一覧'),
        leading: _mergeMode
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'まとめモードを終了',
                onPressed: _toggleMergeMode,
              )
            : null,
        actions: [
          if (isAdmin && !_mergeMode)
            IconButton(
              icon: const Icon(Icons.merge_type),
              tooltip: '案件をまとめる',
              onPressed: _toggleMergeMode,
            ),
          if (isAdmin && !_mergeMode)
            IconButton(
              icon: _resyncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_problem_outlined),
              tooltip: '未グルーピング日報を再判定',
              onPressed: _resyncing ? null : _resyncUngrouped,
            ),
          if (isAdmin && !_mergeMode)
            IconButton(
              icon: _recalculating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.calculate_outlined),
              tooltip: '全案件を再計算(集計値の不整合を修復)',
              onPressed: _recalculating ? null : _recalculateAll,
            ),
          if (!_mergeMode)
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: '店舗名・伝票No/受付No・担当者名で検索',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _mergeMode
                        ? 'まとめたい案件を2件以上選択してください。伝票No・受付Noが一致した場合は確実な紐付け、番号がない場合は内容の類似度から自動的に推測しています。'
                        : '全ての案件を表示しています。伝票No・受付Noが一致した場合は確実な紐付け、番号がない場合は内容の類似度から自動的に推測しています。',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('複数人対応のみ'),
                    avatar: const Icon(Icons.groups, size: 16),
                    selected: _onlyMultiPerson,
                    onSelected: (v) => setState(() => _onlyMultiPerson = v),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('要確認(推測)のみ'),
                    avatar: const Icon(Icons.help_outline, size: 16),
                    selected: _onlySuggested,
                    onSelected: (v) => setState(() => _onlySuggested = v),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('冷媒充填のみ'),
                    avatar: const Icon(Icons.ac_unit, size: 16),
                    selected: _onlyRefrigerantFilling,
                    onSelected: (v) =>
                        setState(() => _onlyRefrigerantFilling = v),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
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
                          ElevatedButton(
                            onPressed: _load,
                            child: const Text('再試行'),
                          ),
                        ],
                      ),
                    ),
                  )
                : displayed.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _searchQuery.trim().isNotEmpty
                              ? Icons.search_off
                              : Icons.inbox_outlined,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _searchQuery.trim().isNotEmpty
                              ? '「$_searchQuery」に一致する案件がありません'
                              : '該当する案件がありません',
                          style: TextStyle(color: Colors.grey.shade600),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : _buildGroupedList(displayed, dateFmt),
          ),
          if (_mergeMode)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.merge_type),
                    label: Text(
                      _selectedForMerge.length >= 2
                          ? '${_selectedForMerge.length}件をまとめる'
                          : '2件以上選択してください',
                    ),
                    onPressed: _selectedForMerge.length >= 2
                        ? _mergeSelected
                        : null,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 【案件フォルダー化】絞り込み後の案件一覧を、
  /// 「要確認(推測)を上部に常時表示」+「確定案件を年→月フォルダーに分類」
  /// の形で組み立てる。
  Widget _buildGroupedList(List<WorkCase> displayed, DateFormat dateFmt) {
    // 「要確認(推測)」は判定が曖昧で見落とし厳禁のため、年月を問わず
    // 常に画面上部に平置き表示する(フォルダーの中に埋もれさせない)。
    final suggested = displayed.where((c) => c.status == 'suggested').toList()
      ..sort((a, b) => _caseSortDate(b).compareTo(_caseSortDate(a)));
    final confirmed = displayed.where((c) => c.status != 'suggested').toList();

    final grouped = _groupByYearMonth(confirmed);
    final years = grouped.keys.toList()
      ..sort((a, b) => b.compareTo(a)); // 新しい年順

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        if (suggested.isNotEmpty) ...[
          Row(
            children: [
              const Icon(
                Icons.help_outline,
                size: 16,
                color: AppColors.warning,
              ),
              const SizedBox(width: 6),
              Text(
                '要確認(推測) ${suggested.length}件',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...suggested.map(
            (c) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildCaseCard(c, dateFmt),
            ),
          ),
          if (years.isNotEmpty) ...[
            const SizedBox(height: 4),
            const Divider(height: 24),
          ],
        ],
        for (final year in years)
          _buildYearFolder(year, grouped[year]!, dateFmt),
      ],
    );
  }

  /// 「年」フォルダー(ExpansionTile)。その下に「月」フォルダーを内包する。
  Widget _buildYearFolder(
    int year,
    Map<int, List<WorkCase>> monthMap,
    DateFormat dateFmt,
  ) {
    final months = monthMap.keys.toList()..sort((a, b) => b.compareTo(a));
    final totalCount = monthMap.values.fold<int>(0, (sum, l) => sum + l.length);
    final initiallyExpanded = year == _newestYear;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // ExpansionTileの開閉インジケーター下線を非表示にして
        // カード枠と馴染ませる。
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey('case_year_$year'),
          initiallyExpanded: initiallyExpanded,
          leading: const Icon(Icons.folder_outlined, color: AppColors.primary),
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
              _buildMonthFolder(year, month, monthMap[month]!, dateFmt),
          ],
        ),
      ),
    );
  }

  /// 「月」フォルダー(ExpansionTile)。案件カード一覧を内包する。
  Widget _buildMonthFolder(
    int year,
    int month,
    List<WorkCase> cases,
    DateFormat dateFmt,
  ) {
    final monthKey = '$year-$month';
    final initiallyExpanded = monthKey == _newestYearMonthKey;

    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8),
      child: ExpansionTile(
        key: PageStorageKey('case_month_$monthKey'),
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
              '${cases.length}件',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 20),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
        children: [
          for (final c in cases)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildCaseCard(c, dateFmt),
            ),
        ],
      ),
    );
  }

  /// 案件1件分のカード表示(既存の一覧表示から切り出し、フォルダー表示・
  /// 「要確認」平置き表示の両方から再利用する)。
  Widget _buildCaseCard(WorkCase c, DateFormat dateFmt) {
    final selected = _selectedForMerge.contains(c.id);
    return Card(
      color: selected ? AppColors.primary.withValues(alpha: 0.08) : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          if (_mergeMode) {
            _toggleSelectForMerge(c.id);
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => CaseDetailScreen(caseId: c.id)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (_mergeMode) ...[
                    Checkbox(
                      value: selected,
                      onChanged: (_) => _toggleSelectForMerge(c.id),
                    ),
                    const SizedBox(width: 4),
                  ],
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
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (c.primaryKeyValue.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '伝票/受付No: ${c.primaryKeyValue}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.groups,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    c.participants.map((p) => p.authorName).join('・'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.access_time,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '合計${c.totalWorkHours.toStringAsFixed(1)}h',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                c.firstVisitDate != null
                    ? (c.firstVisitDate == c.lastVisitDate
                          ? dateFmt.format(c.firstVisitDate!)
                          : '${dateFmt.format(c.firstVisitDate!)} 〜 ${dateFmt.format(c.lastVisitDate ?? c.firstVisitDate!)}')
                    : '',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
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
