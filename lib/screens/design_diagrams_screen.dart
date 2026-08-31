import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/design_diagrams_data.dart';
import '../theme/app_theme.dart';

/// アプリの主要な動作フロー(設計図)を閲覧する画面。
///
/// 【運用ルール・2026-09-01追加(社長指示)】
/// 最新の設計図はここから常に閲覧できる状態を維持すること。
/// アクセス経路: プロフィール → システム構成・アカウント整理 → 設計図を見る
class DesignDiagramsScreen extends StatelessWidget {
  const DesignDiagramsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設計図(アプリの動作フロー)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.account_tree_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'ここには、日報の入力〜保存〜案件反映〜バージョン管理までの'
                    '主要な動作フローをまとめています。機能変更のたびに更新される'
                    '想定です。開発者向けにMermaid記法のソースもコピーできます。',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade800,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          for (final flow in designFlows) _DesignFlowCard(flow: flow),

          const SizedBox(height: 24),
          Text(
            '運用ルール',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 10),
          for (final rule in operationalRules) _RuleCard(rule: rule),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _DesignFlowCard extends StatelessWidget {
  final DesignFlow flow;
  const _DesignFlowCard({required this.flow});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              flow.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              flow.summary,
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.grey.shade700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.update, size: 13, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(
                  '最終更新: v${flow.lastUpdatedVersion} (${flow.lastUpdatedDate})',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
            const Divider(height: 20),
            for (int i = 0; i < flow.steps.length; i++)
              _StepRow(step: flow.steps[i], isLast: i == flow.steps.length - 1),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _copyMermaid(context, flow.mermaidSource),
                icon: const Icon(Icons.code, size: 16),
                label: const Text('Mermaidソースをコピー(開発者向け)'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyMermaid(BuildContext context, String source) async {
    await Clipboard.setData(ClipboardData(text: source.trim()));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('コピーしました。mermaid.live 等に貼り付けると図で確認できます。')),
      );
    }
  }
}

class _StepRow extends StatelessWidget {
  final FlowStep step;
  final bool isLast;
  const _StepRow({required this.step, required this.isLast});

  ({Color color, IconData icon}) _visual() {
    switch (step.type) {
      case FlowStepType.start:
        return (color: AppColors.primary, icon: Icons.play_circle_outline);
      case FlowStepType.process:
        return (color: Colors.blueGrey, icon: Icons.arrow_forward_ios);
      case FlowStepType.decision:
        return (color: Colors.orange.shade700, icon: Icons.help_outline);
      case FlowStepType.warning:
        return (color: AppColors.danger, icon: Icons.warning_amber_outlined);
      case FlowStepType.end:
        return (color: AppColors.success, icon: Icons.check_circle_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _visual();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Icon(v.icon, size: 18, color: v.color),
              if (!isLast)
                Container(
                  width: 1.5,
                  height: step.detail != null ? 36 : 12,
                  color: Colors.grey.shade300,
                  margin: const EdgeInsets.only(top: 4),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: v.color,
                  ),
                ),
                if (step.detail != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    step.detail!,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade700,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  final OperationalRule rule;
  const _RuleCard({required this.rule});

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
                  Icons.gavel_outlined,
                  size: 16,
                  color: Colors.amber.shade900,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    rule.title,
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
              rule.description,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '追加日: ${rule.addedDate}',
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}
