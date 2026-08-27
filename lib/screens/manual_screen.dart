import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/manual_data.dart';
import '../theme/app_theme.dart';

/// マニュアルのダウンロード版(PDF/Web版/編集可能版)の公開先。
/// Firebase Hosting(web/ 配下)に配置されているファイルをそのまま参照する。
const String _manualBaseUrl = 'https://sn-report.web.app';
const String _manualPdfUrl =
    '$_manualBaseUrl/%E6%97%A5%E5%A0%B1%E3%82%A2%E3%83%97%E3%83%AA%E6%93%8D%E4%BD%9C%E3%83%9E%E3%83%8B%E3%83%A5%E3%82%A2%E3%83%AB.pdf';
const String _manualHtmlUrl = '$_manualBaseUrl/manual.html';
const String _manualMdUrl =
    '$_manualBaseUrl/%E6%97%A5%E5%A0%B1%E3%82%A2%E3%83%97%E3%83%AA%E6%93%8D%E4%BD%9C%E3%83%9E%E3%83%8B%E3%83%A5%E3%82%A2%E3%83%AB.md';

Future<void> _openManualLink(BuildContext context, String url) async {
  final uri = Uri.parse(url);
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('リンクを開けませんでした。通信環境をご確認ください。')));
  }
}

IconData _iconFor(String key) {
  switch (key) {
    case 'edit_note':
      return Icons.edit_note;
    case 'ac_unit':
      return Icons.ac_unit;
    case 'storefront':
      return Icons.storefront;
    case 'lightbulb_outline':
      return Icons.lightbulb_outline;
    case 'system_update':
      return Icons.system_update;
    case 'folder_shared':
      return Icons.folder_shared;
    case 'search':
      return Icons.search;
    case 'cleaning_services':
      return Icons.cleaning_services;
    case 'document_scanner':
      return Icons.document_scanner;
    default:
      return Icons.info_outline;
  }
}

/// 現場での入力ルールを確認できるマニュアル画面。
class ManualScreen extends StatelessWidget {
  const ManualScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('入力マニュアル')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: manualSections.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _ManualDownloadCard(
              onTapLink: (url) => _openManualLink(context, url),
            );
          }
          final section = manualSections[index - 1];
          return Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: index == 1,
                leading: Icon(_iconFor(section.icon), color: AppColors.primary),
                title: Text(
                  section.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: section.body
                    .map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Icon(
                                Icons.circle,
                                size: 6,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                line,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// マニュアルのダウンロード版(PDF/Web版/編集可能版)への導線カード。
class _ManualDownloadCard extends StatelessWidget {
  final void Function(String url) onTapLink;
  const _ManualDownloadCard({required this.onTapLink});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      color: AppColors.primary.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.download_outlined, color: AppColors.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'マニュアルをダウンロード',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '印刷や共有用に、以下の形式でダウンロード・保存できます。',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            _DownloadTile(
              icon: Icons.picture_as_pdf_outlined,
              label: 'PDF版',
              subtitle: '印刷・保存に最適',
              onTap: () => onTapLink(_manualPdfUrl),
            ),
            const Divider(height: 1),
            _DownloadTile(
              icon: Icons.language_outlined,
              label: 'Web版',
              subtitle: 'ブラウザでそのまま読める',
              onTap: () => onTapLink(_manualHtmlUrl),
            ),
            const Divider(height: 1),
            _DownloadTile(
              icon: Icons.edit_document,
              label: '編集可能版(Markdown)',
              subtitle: '社内での修正・カスタマイズ用',
              onTap: () => onTapLink(_manualMdUrl),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  const _DownloadTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon, color: AppColors.primary),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11.5)),
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: onTap,
    );
  }
}
