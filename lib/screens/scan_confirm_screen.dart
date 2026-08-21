import 'package:flutter/material.dart';

import '../services/document_scan_service.dart';

/// AI-OCRスキャン結果の確認・修正画面。
///
/// 【重要・社内方針】
/// AI(Azure Document Intelligence)による自動抽出はあくまで「下書き」であり、
/// 必ずこの画面でユーザーが内容を目視確認・修正した上で「この内容で反映する」を
/// 押してはじめて日報フォームへ反映される。AI一発登録の導線は一切用意しない。
class ScanConfirmScreen extends StatefulWidget {
  final ScanResult scanResult;

  const ScanConfirmScreen({super.key, required this.scanResult});

  @override
  State<ScanConfirmScreen> createState() => _ScanConfirmScreenState();
}

class _ScanConfirmScreenState extends State<ScanConfirmScreen> {
  late Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final def in kScanFieldDefinitions)
        def.key: TextEditingController(text: widget.scanResult.value(def.key)),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _confirm() {
    final result = <String, String>{
      for (final entry in _controllers.entries) entry.key: entry.value.text.trim(),
    };
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final lowConfidenceCount = kScanFieldDefinitions
        .where((d) => widget.scanResult.isLowConfidence(d.key))
        .length;

    return Scaffold(
      appBar: AppBar(title: const Text('スキャン内容の確認・修正')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            color: Colors.amber.withValues(alpha: 0.15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Colors.amber.shade900),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'AIによる自動読み取り結果です。内容を必ず確認し、間違いがあれば修正してから反映してください。',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.amber.shade900,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
                if (lowConfidenceCount > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    '⚠ $lowConfidenceCount 項目は読み取り精度が低い可能性があります(オレンジ枠)。特に注意して確認してください。',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.deepOrange.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              itemCount: kScanFieldDefinitions.length,
              itemBuilder: (context, index) {
                final def = kScanFieldDefinitions[index];
                final lowConf = widget.scanResult.isLowConfidence(def.key);
                final confidence = widget.scanResult.confidences[def.key];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: TextFormField(
                    controller: _controllers[def.key],
                    decoration: InputDecoration(
                      labelText: def.label,
                      helperText: confidence != null
                          ? 'AI信頼度: ${(confidence * 100).toStringAsFixed(0)}%'
                          : '未検出(空欄)',
                      helperStyle: TextStyle(
                        color: lowConf ? Colors.deepOrange : Colors.grey.shade500,
                        fontSize: 11,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: lowConf
                            ? const BorderSide(color: Colors.deepOrange, width: 1.4)
                            : BorderSide.none,
                      ),
                      filled: true,
                      fillColor: lowConf
                          ? Colors.deepOrange.withValues(alpha: 0.06)
                          : Colors.grey.withValues(alpha: 0.06),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('キャンセル'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _confirm,
                      icon: const Icon(Icons.check),
                      label: const Text('この内容で反映する'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
