import 'package:flutter/material.dart';
import '../data/system_architecture_data.dart';
import '../services/app_config_service.dart';
import '../theme/app_theme.dart';

/// アプリのシステム構成・外部サービス・アカウント関係の整理画面。
///
/// 【アクセス制限】最高管理者(superAdmin)のみがこの画面に到達できる。
/// 呼び出し元(profile_screen.dart)で appState.isSuperAdmin をチェックした上で
/// 遷移させているが、念のためこの画面自体でも防御的に同じチェックを行う。
class SystemArchitectureScreen extends StatelessWidget {
  const SystemArchitectureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('システム構成・アカウント整理'),
        backgroundColor: AppColors.danger,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _WarningBanner(),
          const SizedBox(height: 20),

          _SectionHeader(
            icon: Icons.shield_outlined,
            title: '強制アップデートゲート・更新お知らせ',
            subtitle: '古いアプリの利用ブロック(強制)/新バージョンのお知らせ(任意)',
          ),
          const SizedBox(height: 10),
          const _ForceUpdateGateSection(),
          const SizedBox(height: 12),
          const _VersionBuildTable(),

          const SizedBox(height: 24),
          _SectionHeader(
            icon: Icons.cloud_outlined,
            title: '現在使用中の外部サービス',
            subtitle: 'このアプリの裏側で稼働している仕組み一覧',
          ),
          const SizedBox(height: 10),
          ...externalServices.map((s) => _ServiceCard(service: s)),

          const SizedBox(height: 24),
          _SectionHeader(
            icon: Icons.history_toggle_off,
            title: '検討したが不採用/廃止したもの',
            subtitle: '開発過程で検討・変更した経緯の記録',
          ),
          const SizedBox(height: 10),
          if (consideredButNotAdopted.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '該当なし',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            )
          else
            ...consideredButNotAdopted.map((s) => _ServiceCard(service: s)),

          const SizedBox(height: 24),
          _SectionHeader(
            icon: Icons.groups_outlined,
            title: 'アカウント・権限に関する整理',
            subtitle: '運用上、社長として押さえておくべきポイント',
          ),
          const SizedBox(height: 10),
          ...accountStructureNotes.map((n) => _NoteCard(note: n)),

          const SizedBox(height: 24),
          _SectionHeader(
            icon: Icons.flag_outlined,
            title: '今後の課題',
            subtitle: '現時点では見送っているが、将来的に検討が必要な事項',
          ),
          const SizedBox(height: 10),
          ...futureConsiderations.map((f) => _FutureConsiderationCard(item: f)),

          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Colors.grey.shade600, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'この一覧はアプリの改修が入るたびに更新される想定です。'
                    '実際のパスワード・APIキーの値はここには表示されません(保管場所の案内のみ)。',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.security, color: AppColors.danger, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '最高管理者専用ページです。社外の方や一般社員には共有しないでください。',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final ExternalService service;
  const _ServiceCard({required this.service});

  ({Color color, String label, IconData icon}) _statusVisual() {
    switch (service.status) {
      case ServiceStatus.active:
        return (
          color: AppColors.primary,
          label: '稼働中',
          icon: Icons.check_circle_outline,
        );
      case ServiceStatus.newlyAdded:
        return (
          color: AppColors.success,
          label: '今回新規導入',
          icon: Icons.fiber_new_outlined,
        );
      case ServiceStatus.deprecated:
        return (
          color: AppColors.warning,
          label: '廃止予定',
          icon: Icons.warning_amber_outlined,
        );
      case ServiceStatus.removed:
        return (
          color: Colors.grey,
          label: '不採用・削除済み',
          icon: Icons.block_outlined,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visual = _statusVisual();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    service.name,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: visual.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(visual.icon, size: 12, color: visual.color),
                      const SizedBox(width: 3),
                      Text(
                        visual.label,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: visual.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              service.category,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const Divider(height: 18),
            _InfoRow(label: '提供元', value: service.provider),
            _InfoRow(label: '用途', value: service.purpose),
            _InfoRow(label: '契約・アカウント', value: service.accountOwner),
            _InfoRow(label: '費用面の注意', value: service.costNote),
            _InfoRow(label: '認証情報の保管場所', value: service.credentialLocation),
            if (service.notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...service.notes.map(
                (n) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('・', style: TextStyle(fontSize: 12)),
                      Expanded(
                        child: Text(
                          n,
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
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _FutureConsiderationCard extends StatelessWidget {
  final FutureConsideration item;
  const _FutureConsiderationCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.pending_actions_outlined,
                  size: 16,
                  color: Colors.amber.shade800,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.description,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 最高管理者が「強制アップデートゲート」の最低利用可能バージョンを
/// 設定・変更するためのセクション。
///
/// 【事故防止策】
/// - 現在の設定値を必ず表示してから変更させる(意図しない値の入力を防止)。
/// - 保存前に確認ダイアログを表示し、「この操作で古いアプリが使えなくなる
///   社員が出る可能性がある」ことを明示する。
/// - 万が一の設定ミスでも、最高管理者自身はブロック対象外(auth_gate.dart側の
///   安全策)のため、この画面から必ず設定を直せる。
class _ForceUpdateGateSection extends StatefulWidget {
  const _ForceUpdateGateSection();

  @override
  State<_ForceUpdateGateSection> createState() =>
      _ForceUpdateGateSectionState();
}

class _ForceUpdateGateSectionState extends State<_ForceUpdateGateSection> {
  bool _loading = true;
  String? _error;
  AppMinVersionConfig _config = const AppMinVersionConfig(minSupportedBuild: 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fetched = await AppConfigService.instance.fetchConfig();
      setState(() {
        _config = fetched ?? const AppMinVersionConfig(minSupportedBuild: 0);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '設定の読み込みに失敗しました: $e';
        _loading = false;
      });
    }
  }

  Future<void> _openEditDialog() async {
    final buildCtrl = TextEditingController(
      text: _config.minSupportedBuild.toString(),
    );
    final messageCtrl = TextEditingController(text: _config.message);
    final urlCtrl = TextEditingController(text: _config.downloadUrl);
    final latestVersionCtrl = TextEditingController(text: _config.latestVersion);
    final latestBuildCtrl = TextEditingController(
      text: _config.latestBuildNumber > 0
          ? _config.latestBuildNumber.toString()
          : '',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('強制アップデートゲート・更新お知らせの設定'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ここで設定したビルド番号より古いアプリを使っている社員は、'
                'ログイン後にブロック画面が表示され、日報の閲覧・入力ができなくなります。',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: buildCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '最低利用可能ビルド番号 *',
                  helperText: '新しいAPKビルド時のビルド番号(pubspec.yamlの +N の部分)を入力',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: messageCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'ブロック画面のお知らせ文(任意)',
                  helperText: '空欄の場合はデフォルトの文言が表示されます',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(
                  labelText: '新しいAPKのダウンロードURL(任意)',
                ),
              ),
              const Divider(height: 28),
              const Text(
                '下記は【更新お知らせ】(強制ではない)の設定です。'
                '実機のビルド番号がここで入力したもの未満の場合、'
                'ホーム画面上部に「新しいバージョンがあります」バナーが表示されます。'
                'ブロックはされません。',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: latestVersionCtrl,
                decoration: const InputDecoration(
                  labelText: '現在配布中の最新バージョン名(任意、例: 1.2.13)',
                  helperText: 'ホーム画面のバナーに表示される文字(表示用)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: latestBuildCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '現在配布中の最新ビルド番号(任意)',
                  helperText: '空欄の場合は更新お知らせ機能を使用しない',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(buildCtrl.text.trim());
              if (parsed == null || parsed < 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('最低利用可能ビルド番号は0以上の整数で入力してください。')),
                );
                return;
              }
              final latestBuildText = latestBuildCtrl.text.trim();
              if (latestBuildText.isNotEmpty) {
                final parsedLatest = int.tryParse(latestBuildText);
                if (parsedLatest == null || parsedLatest < 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('最新ビルド番号は0以上の整数で入力してください。'),
                    ),
                  );
                  return;
                }
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('次へ(確認)'),
          ),
        ],
      ),
    );

    if (result != true) return;

    final newConfig = AppMinVersionConfig(
      minSupportedBuild: int.parse(buildCtrl.text.trim()),
      message: messageCtrl.text.trim(),
      downloadUrl: urlCtrl.text.trim(),
      latestVersion: latestVersionCtrl.text.trim(),
      latestBuildNumber: int.tryParse(latestBuildCtrl.text.trim()) ?? 0,
    );

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('本当に変更しますか?'),
        content: Text(
          '最低利用可能ビルド番号を「${newConfig.minSupportedBuild}」に設定します。\n\n'
          'これより古いアプリを使っている社員は、次回ログイン時からアプリを'
          '使用できなくなります(最高管理者は対象外)。\n\n'
          '【更新お知らせ】最新ビルド番号: '
          '${newConfig.latestBuildNumber > 0 ? newConfig.latestBuildNumber : "未設定"}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('設定を反映する'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await AppConfigService.instance.updateConfig(newConfig);
      if (!mounted) return;
      setState(() => _config = newConfig);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('強制アップデートゲートの設定を更新しました。')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('設定の更新に失敗しました: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _load, child: const Text('再読み込み')),
            ],
          ),
        ),
      );
    }

    final isActive = _config.minSupportedBuild > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isActive ? Icons.gpp_good_outlined : Icons.gpp_maybe_outlined,
                  size: 18,
                  color: isActive ? AppColors.success : Colors.grey,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isActive ? '有効(現場での強制力あり)' : '未設定(誰もブロックされません)',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: isActive
                          ? AppColors.success
                          : Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 18),
            _InfoRow(
              label: '最低ビルド番号',
              value: isActive ? '${_config.minSupportedBuild}' : '未設定',
            ),
            if (_config.message.isNotEmpty)
              _InfoRow(label: 'お知らせ文', value: _config.message),
            if (_config.downloadUrl.isNotEmpty)
              _InfoRow(label: 'ダウンロードURL', value: _config.downloadUrl),
            const Divider(height: 18),
            Row(
              children: [
                Icon(
                  _config.latestBuildNumber > 0
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                  size: 18,
                  color: _config.latestBuildNumber > 0
                      ? Colors.orange.shade700
                      : Colors.grey,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _config.latestBuildNumber > 0
                        ? '更新お知らせ: 有効(ホーム画面にバナー表示)'
                        : '更新お知らせ: 未設定(バナーは表示されません)',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: _config.latestBuildNumber > 0
                          ? Colors.orange.shade700
                          : Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_config.latestVersion.isNotEmpty)
              _InfoRow(label: '最新バージョン名', value: _config.latestVersion),
            if (_config.latestBuildNumber > 0)
              _InfoRow(
                label: '最新ビルド番号',
                value: '${_config.latestBuildNumber}',
              ),
            const SizedBox(height: 8),
            Text(
              '※ 新しいAPKをビルドするたびに、ここで「最低ビルド番号」と'
              '「最新ビルド番号(更新お知らせ用)」の両方を更新してください。'
              '更新しない場合、古いアプリでもそのまま使えてしまう/'
              '新バージョンのお知らせが表示されないままになります。',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _openEditDialog,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('設定を変更する'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// バージョン名(1.1.9など)とビルド番号(強制アップデートゲートに入力
/// する数字)の対応表。新しいAPKをビルドするたびに、上の「最低利用可能
/// ビルド番号」を更新する際、ここを見れば「今回はどの数字を入れればいいか」
/// を迷わずに判断できるようにするための一覧。
class _VersionBuildTable extends StatelessWidget {
  const _VersionBuildTable();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.table_rows_outlined,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'バージョン名 ⇔ ビルド番号 対応表',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '上の「最低利用可能ビルド番号」に入力するのは、'
              '「バージョン名」ではなく下表の「ビルド番号」の数字です。',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
            const Divider(height: 18),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(1.3),
                1: FlexColumnWidth(1.1),
                2: FlexColumnWidth(1.4),
                3: FlexColumnWidth(3.2),
              },
              border: TableBorder(
                horizontalInside: BorderSide(color: Colors.grey.shade200),
              ),
              children: [
                TableRow(
                  decoration: BoxDecoration(color: Colors.grey.shade100),
                  children: const [
                    _TableHeaderCell('バージョン名'),
                    _TableHeaderCell('ビルド番号'),
                    _TableHeaderCell('リリース日'),
                    _TableHeaderCell('主な変更点'),
                  ],
                ),
                for (final r in versionBuildHistory)
                  TableRow(
                    children: [
                      _TableDataCell(r.versionName, bold: true),
                      _TableDataCell(
                        '${r.buildNumber}',
                        bold: true,
                        color: AppColors.primary,
                      ),
                      _TableDataCell(r.releaseDate),
                      _TableDataCell(r.summary),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Colors.orange.shade800,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '新しいAPKをビルドしたら、この表の先頭に1行追加してください'
                      '(system_architecture_data.dart の versionBuildHistory)。'
                      'このリストが古いままだと、ゲートに入力すべき数字を'
                      '間違えるおそれがあります。',
                      style: TextStyle(fontSize: 11, color: Colors.orange.shade900),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TableHeaderCell extends StatelessWidget {
  final String text;
  const _TableHeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: Colors.grey.shade700,
        ),
      ),
    );
  }
}

class _TableDataCell extends StatelessWidget {
  final String text;
  final bool bold;
  final Color? color;
  const _TableDataCell(this.text, {this.bold = false, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
          color: color ?? Colors.grey.shade800,
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final AccountNote note;
  const _NoteCard({required this.note});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.push_pin_outlined,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    note.title,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              note.description,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
