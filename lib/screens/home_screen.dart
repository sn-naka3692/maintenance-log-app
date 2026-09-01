import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../data/changelog_data.dart';
import '../providers/app_state.dart';
import '../services/app_config_service.dart';
import '../services/app_update_service.dart' as app_update;
import '../services/update_notice_service.dart';
import '../utils/apk_update_flow.dart';
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
            // 【不具合対応・2026-08-31】電波不良等でまだサーバーに送信できて
            // いない日報がある場合、本人が気づけるように最優先で表示する。
            // (保存自体は成功しているように見えても、管理者側にはまだ
            // 反映されていない状態のため、他のお知らせより優先度を高くする)
            if (appState.totalPendingCount > 0)
              SliverToBoxAdapter(
                child: _PendingSyncBanner(count: appState.totalPendingCount),
              )
            else if (_hasServerUpdate)
              SliverToBoxAdapter(
                child: _NewVersionBanner(
                  latestVersion: _serverLatestVersion,
                  // 【不具合修正・2026-09-01】以前はWeb版タップ時に単純な
                  // location.reload()のみを行っていたため、Service Worker
                  // のcache-firstキャッシュにより古いJSが読み込まれ続け、
                  // 「更新のお知らせが消えない」症状(v1.2.40で発生)の
                  // 原因になっていた。v1.2.7からプロフィール画面で実績の
                  // あるreloadForLatestVersion()(キャッシュ全削除→
                  // Service Worker全解除→リロード。skipWaiting/clients.claim
                  // は呼ばないため、過去のcontrollerchange無限ループ障害の
                  // 引き金にはならない設計)に統一し、確実に最新版へ更新
                  // されるようにした。
                  onTap: () => kIsWeb
                      ? app_update.reloadForLatestVersion()
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
            // 【使用後クローズ案内・2026-08-31追加】
            // 送信待ちの日報が無いときのみ表示。送信待ちバナーは逆に
            // 「開いたままお待ちください」と案内しているため、矛盾しない
            // ようにここで排他制御している。
            if (appState.totalPendingCount == 0)
              const SliverToBoxAdapter(child: _CloseAppTipBanner()),
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

/// 【不具合対応・2026-08-31】
/// 電波不良等で、自分が保存した日報がまだサーバーに送信されていない
/// (端末内に留まっている)ことを本人に知らせるバナー。
///
/// Firestoreはオフライン永続化がデフォルト有効なため、保存操作自体は
/// 電波が無い場所でも「成功」して見えるが、実際のサーバーへの反映は
/// 電波が回復するまで保留される。この状態を放置してアプリを閉じる・
/// 端末を再起動する等をすると、送信されないまま止まってしまう
/// ことがあるため、目立つ位置に常時表示して気づきを促す。
class _PendingSyncBanner extends StatefulWidget {
  final int count;
  const _PendingSyncBanner({required this.count});

  @override
  State<_PendingSyncBanner> createState() => _PendingSyncBannerState();
}

class _PendingSyncBannerState extends State<_PendingSyncBanner> {
  // 【自動再送信機能・2026-08-31追加】ボタン押下中の多重タップ防止用フラグ。
  bool _isRetrying = false;

  void _showDetail(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('送信待ちの日報があります'),
        content: Text(
          'まだサーバーに送信できていない日報が${widget.count}件あります。\n\n'
          '現場の電波状況が悪い場所で保存すると、この画面には表示され'
          'ますが、会社のサーバー・管理者からはまだ見えていない状態です。\n\n'
          '【対応方法】\n'
          '・このアプリを開いたまま、電波の良い場所(Wi-Fiなど)で\n'
          '  数十秒ほどお待ちください。自動的に送信されます。\n'
          '・下の「今すぐ送信を試す」ボタンでも再送信を試みます。\n'
          '・送信が完了すると、このお知らせは自動的に消えます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  /// 【自動再送信機能・2026-08-31追加】
  /// ボタン押下で「今すぐ」Firestoreへの再接続を促し、送信完了(または
  /// タイムアウト)まで待って結果をSnackBarで知らせる。
  /// 電波が実際に無い場所ではタイムアウトして失敗表示になるのが正しい挙動。
  Future<void> _retryNow() async {
    if (_isRetrying) return;
    setState(() => _isRetrying = true);
    final appState = context.read<AppState>();
    bool success = false;
    try {
      success = await appState.retryPendingSyncNow();
    } finally {
      if (mounted) {
        setState(() => _isRetrying = false);
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? '送信できました(画面表示の更新まで数秒かかる場合があります)'
              : 'まだ送信できていません。電波の良い場所でもう一度お試しください。',
        ),
        backgroundColor: success ? Colors.green.shade700 : Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _showDetail(context),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.cloud_off,
                    size: 18,
                    color: Colors.red.shade700,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '送信待ちの日報が${widget.count}件あります',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: Colors.red.shade900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '電波の良い場所でアプリを開いたままお待ちください(タップで詳細)',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.red.shade400),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _isRetrying ? null : _retryNow,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade800,
                side: BorderSide(color: Colors.red.shade400),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
              ),
              icon: _isRetrying
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.red.shade800,
                      ),
                    )
                  : const Icon(Icons.sync, size: 16),
              label: Text(
                _isRetrying ? '送信中...' : '今すぐ送信を試す',
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 【使用後クローズ案内・2026-08-31追加】
///
/// 作業終了後にアプリを閉じることを促す控えめな案内バナー。
/// 送信待ちの日報が無い(=送信完了済み)ときのみ表示され、一覧の一番下に
/// ひっそりと表示する。タップすると理由を説明するダイアログを開く。
///
/// 【表示する理由】
/// ・Web版はブラウザの仕様上、タブを開いたままだと新しいバージョンに
///   永久に切り替わらないことがある(タブを閉じるまで古い版が残る)。
/// ・APK版でも、アプリを開いたままにしておくとバッテリー・通信量を
///   余計に消費する。
class _CloseAppTipBanner extends StatelessWidget {
  const _CloseAppTipBanner();

  void _showDetail(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('作業が終わったらアプリを閉じましょう'),
        content: const Text(
          '本日の日報登録・作業が終わったら、アプリを閉じることをおすすめ'
          'します。\n\n'
          '【理由】\n'
          '・Web版をお使いの方:ブラウザのタブを開いたままにしていると、'
          '新しいバージョンに切り替わらないことがあります(タブを閉じる'
          'まで古い版が残り続ける仕組みのためです)。\n'
          '・APK版をお使いの方:アプリを開いたままにしておくと、バッテリー'
          'や通信量を余計に消費してしまいます。\n\n'
          '※送信待ちの日報がある間は、先に送信が完了する(この画面の'
          '警告が消える)のを確認してから閉じてください。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('わかりました'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showDetail(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 14, color: Colors.grey.shade500),
            const SizedBox(width: 6),
            Text(
              '作業が終わったらアプリを閉じてください(理由を見る)',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
            ),
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
