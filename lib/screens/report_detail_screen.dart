import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/prowan_report_detail.dart';
import '../models/store_system_report.dart';
import '../models/work_report.dart';
import '../providers/app_state.dart';
import '../services/photo_upload_service.dart';
import '../theme/app_theme.dart';
import 'report_edit_screen.dart';

class ReportDetailScreen extends StatelessWidget {
  final String reportId;
  const ReportDetailScreen({super.key, required this.reportId});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    WorkReport? report;
    try {
      report = appState.reports.firstWhere((r) => r.id == reportId);
    } catch (_) {
      report = null;
    }

    if (report == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('日報詳細')),
        body: const Center(child: Text('日報が見つかりません')),
      );
    }

    final dateFmt = DateFormat('yyyy年M月d日 (E)', 'ja_JP');
    final timeFmt = DateFormat('HH:mm');
    final isOwnReport = report.authorId == appState.currentUser?.id;
    // 【権限追加・2026-08】現場での入力もれ・訂正対応のため、一般管理者以上
    // (admin/superAdmin)には本人以外の日報も編集できる権限を付与する
    // (誰が代筆したかは保存時に自動記録され、下部に表示される)。
    final canEdit = isOwnReport || appState.isAdmin;
    final canDelete = isOwnReport || appState.isAdmin;
    final typeColor = responseTypeColor(report.responseType.label);

    return Scaffold(
      appBar: AppBar(
        title: const Text('日報詳細'),
        actions: [
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReportEditScreen(existing: report),
                  ),
                );
              },
            ),
          if (canDelete)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('日報を削除しますか?'),
                    content: Text(
                      isOwnReport
                          ? 'この操作は取り消せません。'
                          : '管理者権限でこの日報を削除します。この操作は取り消せません。',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('キャンセル'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.danger,
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('削除'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  // 日報削除時、Storageに残った写真ファイルもまとめて
                  // 削除する(ゴミファイルとしてStorage容量を消費しないようにする)。
                  for (final url in report!.photoPaths) {
                    await PhotoUploadService.instance.deletePhoto(url);
                  }
                  await appState.deleteReport(reportId);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  report.responseType.label,
                  style: TextStyle(
                    color: typeColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              Text(dateFmt.format(report.visitDate)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            report.clientName.isNotEmpty
                ? report.clientName
                : report.responseType.label,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(
                Icons.person,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                report.authorName,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(width: 16),
              const Icon(
                Icons.access_time,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                '${timeFmt.format(report.startTime)} - ${timeFmt.format(report.endTime)}',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
          if (report.caseRolePreset.isNotEmpty ||
              report.caseRoleNote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.badge_outlined,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '案件においての役割: ${[
                      report.caseRolePreset,
                      report.caseRoleNote,
                    ].where((s) => s.isNotEmpty).join(' / ')}',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
          if (report.coWorkerIds.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.groups_outlined,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '共同作業者: ${report.coWorkerIds.map((id) {
                      final u = appState.users.where((u) => u.id == id).firstOrNull;
                      return u?.name ?? '(不明)';
                    }).join('、')}',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
          // 【代筆編集の記録・2026-08導入】一般管理者以上が本人の代わりに
          // 内容を追記・修正した場合、その記録を明示する(入力もれ対応の
          // 権限拡大に伴う監査証跡。誰でも後から気づける状態にする)。
          if (report.lastEditedByAdminId != null &&
              (report.lastEditedByAdminName ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 16,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      report.lastEditedByAdminAt != null
                          ? '${report.lastEditedByAdminName}さん(管理者)が'
                                '${dateFmt.format(report.lastEditedByAdminAt!)} '
                                '${timeFmt.format(report.lastEditedByAdminAt!)}に'
                                '代わりに編集しました'
                          : '${report.lastEditedByAdminName}さん(管理者)が'
                                '代わりに編集しました',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Divider(height: 32),

          if (report.equipmentModel.isNotEmpty)
            _InfoRow(
              icon: Icons.qr_code,
              label: '機器型番',
              value: report.equipmentModel,
            ),
          if (report.proWanRefNumber.isNotEmpty)
            _InfoRow(
              icon: Icons.numbers,
              label: 'プロワン管理番号',
              value: report.proWanRefNumber,
            ),
          // プロワン管轄案件(SE店舗以外)専用の冷媒種類・充填量。
          // SE店舗分は下部の「コンビニ側システム入力控え」内(冷媒種類/充填量)に表示される。
          // 【表記統一・2026-08】「なし」「無し」等の未充填表記はここで統一して
          // 「未充填」とわかりやすく表示する(編集画面の注意書きと表記を揃える)。
          if (report.nonSeRefrigerantType.isNotEmpty ||
              report.nonSeRefrigerantAmountKg.isNotEmpty) ...[
            _InfoRow(
              icon: Icons.propane_tank,
              label: '冷媒種類',
              value: report.nonSeRefrigerantType.isEmpty
                  ? '(未記入)'
                  : (WorkReport.isNotFilledType(report.nonSeRefrigerantType)
                        ? '未充填'
                        : report.nonSeRefrigerantType),
            ),
            _InfoRow(
              icon: Icons.propane_tank,
              label: '冷媒充填量',
              value: report.nonSeRefrigerantAmountKg.isEmpty
                  ? '(未記入)'
                  : (WorkReport.isNotFilledAmount(
                          report.nonSeRefrigerantAmountKg,
                        )
                        ? '未充填(0kg)'
                        : '${report.nonSeRefrigerantAmountKg} kg'),
            ),
          ],

          _SectionCard(
            title: '作業内容',
            icon: Icons.build,
            child: Text(
              report.workContent.isEmpty ? '(未記入)' : report.workContent,
            ),
          ),

          if (report.partsUsed.isNotEmpty)
            _SectionCard(
              title: '使用部品',
              icon: Icons.inventory_2,
              child: Column(
                children: report.partsUsed
                    .map(
                      (p) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            const Icon(Icons.circle, size: 6),
                            const SizedBox(width: 8),
                            Text('${p.name} × ${p.quantity}'),
                            if (p.note != null && p.note!.isNotEmpty)
                              Text(
                                ' (${p.note})',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),

          if (report.successPoints.isNotEmpty)
            _SectionCard(
              title: 'うまくいったこと・工夫した点',
              icon: Icons.thumb_up_alt_outlined,
              iconColor: AppColors.success,
              child: Text(report.successPoints),
            ),

          if (report.issuesPoints.isNotEmpty)
            _SectionCard(
              title: '課題・失敗・改善点',
              icon: Icons.report_problem_outlined,
              iconColor: AppColors.warning,
              child: Text(report.issuesPoints),
            ),

          if (report.photoPaths.isNotEmpty)
            _SectionCard(
              title: '写真',
              icon: Icons.photo_library,
              child: _PhotoGalleryView(report.photoPaths),
            ),

          if (report.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: report.tags.map((t) => Chip(label: Text(t))).toList(),
              ),
            ),

          if (!report.storeSystemReportCopy.isEmpty)
            _SectionCard(
              title: 'コンビニ側システム入力控え',
              icon: Icons.receipt_long,
              child: _StoreSystemReportView(report.storeSystemReportCopy),
            ),

          // 【不具合修正・2026-08】プロワン管轄案件の案件詳細
          // (店舗住所・部門・系統番号・障害内容等)の表示セクション。
          if (!report.proWanReportDetail.isEmpty)
            _SectionCard(
              title: 'プロワン案件詳細',
              icon: Icons.assignment,
              child: _ProWanReportDetailView(report.proWanReportDetail),
            ),

          if (report.notes.isNotEmpty)
            _SectionCard(
              title: '備考',
              icon: Icons.notes,
              child: Text(report.notes),
            ),

          // 【案件グルーピング機能・2026-08導入】
          // 同じ案件(伝票No/受付No一致、または内容が近い)と判定された
          // 他の日報がある場合、この日報とまとめて表示する。
          // 複数人で同じ現場対応をした際、それぞれが個別に書いた日報を
          // 後から突き合わせやすくするための機能。
          if (report.caseId.isNotEmpty)
            _RelatedReportsSection(report: report),

          const SizedBox(height: 16),
          Text(
            '作成: ${DateFormat('yyyy/MM/dd HH:mm').format(report.createdAt)}\n更新: ${DateFormat('yyyy/MM/dd HH:mm').format(report.updatedAt)}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

/// 日報に添付された写真のサムネイル一覧。タップすると全画面表示になる。
///
/// 【不具合修正・2026-08】旧データ(Firebase Storage対応前に保存された、
/// ローカルファイルパスのみのレコード)はURL形式でないため実体が存在せず、
/// 表示できない。その場合は「(この写真は他の端末では表示できません)」
/// という案内を表示し、単に空白/エラーアイコンだけになるのを防ぐ。
class _PhotoGalleryView extends StatelessWidget {
  final List<String> photoUrls;
  const _PhotoGalleryView(this.photoUrls);

  @override
  Widget build(BuildContext context) {
    final legacyCount = photoUrls.where((p) => !p.startsWith('http')).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photoUrls.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final url = photoUrls[i];
              final isRemote = url.startsWith('http');
              return GestureDetector(
                onTap: isRemote
                    ? () => _openFullScreen(context, photoUrls, i)
                    : null,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 90,
                    height: 90,
                    color: Colors.grey.shade200,
                    child: isRemote
                        ? Image.network(
                            url,
                            width: 90,
                            height: 90,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stack) =>
                                const Icon(
                                  Icons.broken_image,
                                  color: Colors.grey,
                                ),
                          )
                        : const Icon(
                            Icons.image_not_supported,
                            color: Colors.grey,
                          ),
                  ),
                ),
              );
            },
          ),
        ),
        if (legacyCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '※ 一部の写真($legacyCount枚)は撮影した端末以外では'
              '表示できません(アップデート前に保存されたデータのため)。',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
          ),
      ],
    );
  }

  void _openFullScreen(
    BuildContext context,
    List<String> photoUrls,
    int initialIndex,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PhotoFullScreenView(
          photoUrls: photoUrls,
          initialIndex: initialIndex,
        ),
      ),
    );
  }
}

/// 写真の全画面表示(左右スワイプで複数枚を切り替え可能)。
class _PhotoFullScreenView extends StatefulWidget {
  final List<String> photoUrls;
  final int initialIndex;
  const _PhotoFullScreenView({
    required this.photoUrls,
    required this.initialIndex,
  });

  @override
  State<_PhotoFullScreenView> createState() => _PhotoFullScreenViewState();
}

class _PhotoFullScreenViewState extends State<_PhotoFullScreenView> {
  late final PageController _controller;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_currentIndex + 1} / ${widget.photoUrls.length}'),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.photoUrls.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (context, i) {
          return InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: Center(
              child: Image.network(
                widget.photoUrls[i],
                errorBuilder: (context, error, stack) => const Icon(
                  Icons.broken_image,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreSystemReportView extends StatelessWidget {
  final StoreSystemReport data;
  const _StoreSystemReportView(this.data);

  @override
  Widget build(BuildContext context) {
    final rows = <MapEntry<String, String>>[
      MapEntry('弊社受付No.', data.receiptNumber),
      // 【AIスキャン機能で追加】店番・住所・TELは作業報告書AIスキャン
      // (Azure Document Intelligence)で読み取った内容。
      MapEntry('店番', data.storeNumber),
      MapEntry('住所(報告書記載)', data.scannedAddress),
      MapEntry('TEL(報告書記載)', data.scannedTel),
      // 【表記統一・2026-08】SE店舗側は半角英数のみ入力可のため「NONE」が
      // 未充填の統一表記。日報詳細画面でも「未充填」とわかりやすく表示する。
      // (未入力=空文字の場合は従来通り行自体を非表示にするため、ここでは
      // 判定せず後段のisNotEmptyフィルタに委ねる)
      MapEntry(
        '冷媒種類',
        (data.refrigerantType.isNotEmpty &&
                WorkReport.isNotFilledType(data.refrigerantType))
            ? '未充填'
            : data.refrigerantType,
      ),
      MapEntry(
        '充填量',
        (data.refrigerantAmount.isNotEmpty &&
                WorkReport.isNotFilledAmount(data.refrigerantAmount))
            ? '未充填(0kg)'
            : data.refrigerantAmount,
      ),
      MapEntry('冷媒回収量', data.recoveryAmount),
      MapEntry('依頼内容', data.requestContent),
      MapEntry('設備名称', data.equipmentName),
      MapEntry('メーカー', data.maker),
      MapEntry('型式', data.modelNumber),
      // 【AIスキャン機能で追加】機番・資産管理No・バーコード・納品日・
      // 作業者氏名も報告書AIスキャンで読み取った内容。
      MapEntry('機番', data.machineNo),
      MapEntry('資産管理No', data.assetNo),
      MapEntry('バーコード', data.barcode),
      MapEntry('納品日', data.deliveryDate),
      MapEntry('作業者氏名', data.workerName),
      MapEntry('部位', data.part),
      MapEntry('詳細部位', data.detailPart),
      MapEntry('事象', data.phenomenon),
      MapEntry('事象補足', data.phenomenonNote),
      MapEntry('原因', data.cause),
      MapEntry('処置内容', data.treatmentContent),
      MapEntry('処置内容2', data.treatmentContent2),
      MapEntry('部品1', data.part1),
      MapEntry('部品2', data.part2),
      MapEntry('部品3', data.part3),
      MapEntry('部品4', data.part4),
      MapEntry('部品5', data.part5),
      MapEntry('備考', data.remarks),
    ].where((e) => e.value.isNotEmpty).toList();

    if (rows.isEmpty) {
      return Text(
        '(未記入)',
        style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows
          .map(
            (e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      e.key,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      e.value,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ProWanReportDetailView extends StatelessWidget {
  final ProWanReportDetail data;
  const _ProWanReportDetailView(this.data);

  @override
  Widget build(BuildContext context) {
    final rows = <MapEntry<String, String>>[
      MapEntry('店舗住所', data.storeAddress),
      MapEntry('得意先名', data.clientName),
      MapEntry('受付日', data.receiptDate),
      MapEntry('部門', data.department),
      MapEntry('系統番号・名', data.systemNumber),
      MapEntry('ケースNo', data.caseNo),
      MapEntry('修理機器・場所', data.equipmentLocation),
      MapEntry('ご依頼内容', data.requestContent),
      MapEntry('原因', data.cause),
      MapEntry('訪問結果', data.visitResult),
      MapEntry('今後の予定', data.futurePlan),
      MapEntry('技術者氏名', data.technicianName),
    ].where((e) => e.value.isNotEmpty).toList();

    if (rows.isEmpty) {
      return Text(
        '(未記入)',
        style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows
          .map(
            (e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      e.key,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      e.value,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Color? iconColor;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: iconColor ?? AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// 「この案件の他の日報」セクション。
///
/// 【背景】日報機能は1人1回の対応記録を書くためのものであり、複数人で
/// 同じ現場対応をした場合、それぞれが個別に日報を書く運用は変えない
/// (現場の入力負担を増やさないため)。その代わり、伝票No等の客観的な
/// キーが一致する日報、または内容が酷似している日報はアプリが裏側で
/// 自動的に「同じ案件」としてグルーピングしており、ここではその
/// 他の日報を一覧表示することで、後からのデータ整理・案件把握を
/// 容易にする。
class _RelatedReportsSection extends StatelessWidget {
  final WorkReport report;
  const _RelatedReportsSection({required this.report});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final related = appState.getRelatedReports(report);
    if (related.isEmpty) return const SizedBox.shrink();

    final dateFmt = DateFormat('M/d (E)', 'ja_JP');

    return _SectionCard(
      title: 'この案件の他の日報 (${related.length}件)',
      icon: Icons.link,
      iconColor: AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '同じ案件(伝票No/受付No、または内容の一致)として自動的にまとめられた、他の担当者による日報です。',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          ...related.map(
            (r) => Card(
              margin: const EdgeInsets.only(bottom: 6),
              color: Colors.grey.shade50,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.person_outline, size: 20),
                title: Text(
                  r.authorName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${dateFmt.format(r.visitDate)} ・ ${r.workContent}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right, size: 18),
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
