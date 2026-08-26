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

  final _searchCtrl = TextEditingController();
  bool _searchExpanded = false;
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

  void _toggleSearch() {
    setState(() {
      _searchExpanded = !_searchExpanded;
      if (!_searchExpanded) {
        _searchCtrl.clear();
        _searchQuery = '';
      }
    });
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
      // 1件しか日報が紐づいていない案件は「グルーピングの意味がない」ため
      // 一覧のノイズを減らす目的で除外する。
      final filtered = cases.where((c) => c.linkedReportIds.length > 1).toList();
      setState(() {
        _cases = filtered;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '案件一覧の取得に失敗しました: $e';
        _loading = false;
      });
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('案件一覧'),
        actions: [
          IconButton(
            icon: Icon(_searchExpanded ? Icons.search_off : Icons.search),
            tooltip: '案件を検索',
            onPressed: _toggleSearch,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          if (_searchExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
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
                    '複数の日報が紐づいた案件のみを表示しています。伝票No・受付Noが一致した場合は確実な紐付け、番号がない場合は内容の類似度から自動的に推測しています。',
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
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: displayed.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final c = displayed[index];
                      return Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CaseDetailScreen(caseId: c.id),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(14),
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
                                        c.storeName.isNotEmpty
                                            ? c.storeName
                                            : '(店舗不明)',
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
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                    ),
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
                                      c.participants
                                          .map((p) => p.authorName)
                                          .join('・'),
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
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
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
        color: (isConfirmed ? AppColors.success : AppColors.warning)
            .withValues(alpha: 0.12),
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
