import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/work_report.dart';
import '../theme/app_theme.dart';

class ReportCard extends StatelessWidget {
  final WorkReport report;
  final VoidCallback onTap;
  final bool showAuthor;

  /// 【出力対象選択機能・2026-08追加】
  /// trueの場合、カード先頭にチェックボックスを表示し、タップ操作は
  /// [onTap](詳細画面遷移)ではなく選択トグルとして扱われる。
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onSelectToggle;

  const ReportCard({
    super.key,
    required this.report,
    required this.onTap,
    this.showAuthor = false,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectToggle,
  });

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('yyyy/MM/dd (E)', 'ja_JP');
    final timeFmt = DateFormat('HH:mm');
    final typeColor = responseTypeColor(report.responseType.label);

    return Card(
      shape: selectionMode && selected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppColors.primary, width: 1.6),
            )
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: selectionMode ? onSelectToggle : onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (selectionMode) ...[
                    Checkbox(
                      value: selected,
                      onChanged: (_) => onSelectToggle?.call(),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      report.responseType.label,
                      style: TextStyle(
                        color: typeColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    dateFmt.format(report.visitDate),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                report.clientName.isNotEmpty
                    ? report.clientName
                    : report.responseType.label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                report.workContent,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.access_time,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${timeFmt.format(report.startTime)} - ${timeFmt.format(report.endTime)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (showAuthor) ...[
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.person,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      report.authorName,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (report.hasSuccess)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.thumb_up,
                        size: 15,
                        color: AppColors.success,
                      ),
                    ),
                  if (report.hasIssues)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.report_problem,
                        size: 15,
                        color: AppColors.warning,
                      ),
                    ),
                  if (report.hasRefrigerantFilling)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.propane_tank,
                        size: 15,
                        color: AppColors.primary,
                      ),
                    ),
                  if (report.photoPaths.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.photo,
                        size: 15,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
