import 'package:flutter/material.dart';
import '../data/manual_data.dart';
import '../theme/app_theme.dart';

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
        itemCount: manualSections.length,
        itemBuilder: (context, index) {
          final section = manualSections[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: index == 0,
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
