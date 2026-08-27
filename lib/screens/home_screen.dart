import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../data/changelog_data.dart';
import '../providers/app_state.dart';
import '../services/app_config_service.dart';
import '../services/update_notice_service.dart';
import '../utils/apk_update_flow.dart';
import '../utils/web_reload_stub.dart'
    if (dart.library.js_interop) '../utils/web_reload_web.dart';
import '../widgets/report_card.dart';
import 'changelog_screen.dart';
import 'report_detail_screen.dart';
import 'report_edit_screen.dart';
import 'store_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _hasUnseenUpdate = false;

  // 【更新お知らせ・v1.2.13で追加】サーバー側(Firestore)に登録されている
  // 「現在配布中の最新バージョン」と、実機のビルド番号を比較し、
  // 本当に未ダウンロードの新バージョンがある場合のみ true にする。
  // 上の `_hasUnseenUpdate`(既にアプリ内に入っている更新履歴の未読フラグ)とは
  // 目的が違い、こちらは「まだ一度も更新していない古い端末」にも
  // 気づかせることができる。
  bool _hasServerUpdate = false;
  String _serverLatestVersion = '';

  // 【権限拡張・2026-08】一般ユーザーも他ユーザーの日報・業務内容を
  // 閲覧できるようにするための表示切替(true=全員の日報、false=自分の日報)。
  // アクセス制御自体はFirestore側で既に全ユーザーに開放されているため、
  // ここはあくまでホーム画面上の「見る対象」を切り替えるUIスイッチ。
  bool _showAllReports = false;

  @override
  void initState() {
    super.initState();
    _checkUnseenUpdate();
    _checkServerUpdate();
  }

  Future<void> _checkUnseenUpdate() async {
    final has = await UpdateNoticeService.hasUnseenUpdate();
    if (mounted) setState(() => _hasUnseenUpdate = has);
  }

  Future<void> _checkServerUpdate() async {
    // 【v1.2.23で修正】以前はWeb版を対象外にしていたが、Firebase Hosting
    // へのデプロイ漏れやブラウザキャッシュにより、Web版でも古いビルドが
    // 表示され続けるケースがあるため、Web版でもチェックを行う。
    final result = await AppConfigService.instance.checkUpdateAvailability();
    if (mounted) {
      setState(() {
        _hasServerUpdate = result.hasNewerVersion;
        _serverLatestVersion = result.latestVersion;
      });
    }
  }

  Future<void> _openChangelog() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ChangelogScreen()));
    // 更新履歴画面を開いた=確認したものとして、バナーを消す
    await UpdateNoticeService.markLatestAsSeen();
    if (mounted) setState(() => _hasUnseenUpdate = false);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final myReports = appState.myReports;
    // 「全員の日報」表示時は appState.reports(全社員分)、それ以外は自分の日報のみ。
    final displayedReports = _showAllReports ? appState.reports : myReports;
    final today = DateTime.now();
    final todayReports = myReports
        .where(
          (r) =>
              r.visitDate.year == today.year &&
              r.visitDate.month == today.month &&
              r.visitDate.day == today.day,
        )
        .toList();

    final thisMonthReports = myReports
        .where(
          (r) =>
              r.visitDate.year == today.year &&
              r.visitDate.month == today.month,
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('札幌中野冷機 日報'),
        actions: [
          IconButton(
            icon: const Icon(Icons.storefront_outlined),
            tooltip: '店舗マスタ',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StoreListScreen()),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => appState.refreshReports(),
        child: CustomScrollView(
          slivers: [
            // 【更新お知らせ・v1.2.13】サーバー側で本当に新しいバージョンが
            // 配布されている場合はこちらを優先表示(未ダウンロードの端末にも
            // 気づかせる)。それ以外は従来の「更新履歴・未読」バナーを表示する。
            if (_hasServerUpdate)
              SliverToBoxAdapter(
                child: _NewVersionBanner(
                  latestVersion: _serverLatestVersion,
                  onTap: () => kIsWeb
                      ? reloadWebPage()
                      : downloadAndInstallLatestApkWithDialog(context),
                ),
              )
            else if (_hasUnseenUpdate)
              SliverToBoxAdapter(child: _UpdateBanner(onTap: _openChangelog)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'こんにちは、${appState.currentUser?.name ?? ''}さん',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('yyyy年M月d日 (E)', 'ja_JP').format(today),
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: '本日の日報',
                            value: '${todayReports.length}',
                            icon: Icons.today,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            label: '今月の実績',
                            value: '${thisMonthReports.length}',
                            icon: Icons.calendar_month,
                            color: Colors.teal,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _showAllReports ? '全社員の日報' : '最近の日報',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '全${displayedReports.length}件',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 【権限拡張・2026-08】一般ユーザーも他ユーザーの日報・業務内容を
                    // 閲覧できるように、日報一覧の表示対象を切り替えるトグル。
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('自分の日報'),
                          icon: Icon(Icons.person_outline, size: 16),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('全員の日報'),
                          icon: Icon(Icons.groups_outlined, size: 16),
                        ),
                      ],
                      selected: {_showAllReports},
                      onSelectionChanged: (s) =>
                          setState(() => _showAllReports = s.first),
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (displayedReports.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: Column(
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: 56,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'まだ日報がありません',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      if (!_showAllReports) ...[
                        const SizedBox(height: 4),
                        Text(
                          '右下の+ボタンから作成してください',
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final report = displayedReports[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ReportCard(
                        report: report,
                        showAuthor: _showAllReports,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ReportDetailScreen(reportId: report.id),
                            ),
                          );
                        },
                      ),
                    );
                  }, childCount: displayedReports.length),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const ReportEditScreen()));
        },
        icon: const Icon(Icons.add),
        label: const Text('日報作成'),
      ),
    );
  }
}

/// 【更新お知らせ・v1.2.13で追加】サーバー側で本当に新しいバージョンが
/// 配布されている場合に表示するバナー。
///
/// `_UpdateBanner`(既にアプリ内に入っている更新履歴の未読フラグ)とは異なり、
/// こちらはFirestoreに登録された「現在配布中の最新バージョン」と実機の
/// ビルド番号を直接比較しているため、まだ一度も更新していない古い端末にも
/// 正しく表示される。タップすると最新版APKのダウンロードが始まる。
class _NewVersionBanner extends StatelessWidget {
  final String latestVersion;
  final VoidCallback onTap;
  const _NewVersionBanner({required this.latestVersion, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.system_update_alt,
                size: 18,
                color: Colors.orange.shade800,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    latestVersion.isNotEmpty
                        ? '新しいバージョン(v$latestVersion)があります'
                        : '新しいバージョンがあります',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: Colors.orange.shade900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    kIsWeb ? 'タップしてページを再読み込み' : 'タップして最新版をダウンロード',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange.shade700,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.orange.shade400),
          ],
        ),
      ),
    );
  }
}

/// 「アプリが更新されたことに気づけない」問題への対応バナー。
///
/// 端末で最後に確認した更新履歴バージョンと最新バージョンが異なる場合、
/// ホーム画面の一番上に自動で表示する。タップすると更新履歴画面に遷移し、
/// 確認済みとして記録されるとバナーは消える。
class _UpdateBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _UpdateBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final latest = changelogEntries.first;
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.indigo.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.indigo.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.indigo.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.new_releases,
                size: 18,
                color: Colors.indigo.shade700,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'アプリが更新されました(v${latest.version})',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: Colors.indigo.shade900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    latest.title,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.indigo.shade800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'タップして更新内容を確認',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.indigo.shade400,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.indigo.shade400),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
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
