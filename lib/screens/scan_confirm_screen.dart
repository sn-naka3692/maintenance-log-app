import 'dart:async';

import 'package:flutter/material.dart';

import '../services/document_scan_service.dart';
import '../services/scan_correction_log_service.dart';

/// AI-OCRスキャン結果の確認・修正画面。
///
/// 【重要・社内方針】
/// AI(Azure Document Intelligence)による自動抽出はあくまで「下書き」であり、
/// 必ずこの画面でユーザーが内容を目視確認・修正した上で「この内容で反映する」を
/// 押してはじめて日報フォームへ反映される。AI一発登録の導線は一切用意しない。
///
/// 【必須確認フィールド・2026-08-28追加】
/// [_mustConfirmKeys] に列挙したフィールド(現時点ではWorkStartDate=作業開始日)
/// は、学習後もAI信頼度が低く(モデル再学習直後の実測値 confidence=0.346)、
/// 誤った日付が訪問日として日報に自動反映されてしまうと後工程(案件グルーピング・
/// 月末チェック等)に影響するリスクが高い。そのため信頼度の数値に関わらず、
/// このフィールドだけは「内容を目視確認しました」チェックボックスに
/// チェックが入るまで「この内容で反映する」ボタンを押せないようにする。
/// 将来、追加学習でこのフィールドの精度が十分に上がったと判断できた時点で
/// このリストから外す(=通常フィールドと同じ扱いに戻す)ことを想定している。
class ScanConfirmScreen extends StatefulWidget {
  final ScanResult scanResult;

  const ScanConfirmScreen({super.key, required this.scanResult});

  @override
  State<ScanConfirmScreen> createState() => _ScanConfirmScreenState();
}

class _ScanConfirmScreenState extends State<ScanConfirmScreen> {
  late Map<String, TextEditingController> _controllers;

  /// スキャン結果のdocType(SE用/プロワン用)に応じて表示する
  /// フィールド定義リストを切り替える。
  /// プロワン文書の場合は案件管理番号(伝票No)と店名の2項目のみ。
  late List<ScanFieldDef> _fieldDefs;

  /// 信頼度に関わらず必ず目視確認チェックを要求するフィールドキー。
  static const Set<String> _mustConfirmKeys = {'WorkStartDate'};

  /// [_mustConfirmKeys]各フィールドについて、チェック済みかどうか。
  final Map<String, bool> _confirmedChecks = {};

  @override
  void initState() {
    super.initState();
    _fieldDefs = scanFieldDefinitionsFor(widget.scanResult.docType);
    _controllers = {
      for (final def in _fieldDefs)
        def.key: TextEditingController(text: widget.scanResult.value(def.key)),
    };
    for (final key in _mustConfirmKeys) {
      // 対象フィールドがそもそも存在しない場合(SE用文書など)は不要。
      // 値が未検出(空欄)の場合はユーザーが手入力するため、確認済み扱いにする
      // (空欄のまま反映してもリスクがないため確認を強制しない)。
      if (_controllers.containsKey(key)) {
        _confirmedChecks[key] = widget.scanResult.value(key).trim().isEmpty;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// [_mustConfirmKeys]のうち、この画面に表示されているが未確認のものが
  /// あるかどうか。1つでもあれば「反映する」ボタンを無効化する。
  bool get _hasUnconfirmedRequiredField {
    for (final key in _mustConfirmKeys) {
      if (!_controllers.containsKey(key)) continue;
      if (_confirmedChecks[key] != true) return true;
    }
    return false;
  }

  void _confirm() {
    if (_hasUnconfirmedRequiredField) return; // 二重防止(ボタン無効化済みだが念のため)

    final finalValues = <String, String>{
      for (final entry in _controllers.entries)
        entry.key: entry.value.text.trim(),
    };

    // AIの元の抽出結果と、ユーザーが最終的に確定した値との差分を記録する。
    // 【重要】Azure Document Intelligenceには本番解析結果からの自動継続
    // 学習機能がないため、このログが「次回の手動再学習でどのフィールドを
    // 優先的に改善すべきか」を判断する材料になる。保存の成否は日報保存の
    // 主フローに影響しない(サービス内部でエラーを握り込む設計)。
    unawaited(
      ScanCorrectionLogService.logCorrections(
        docType: widget.scanResult.docType,
        aiValues: widget.scanResult.values,
        confidences: widget.scanResult.confidences,
        finalValues: finalValues,
      ),
    );

    final result = <String, String>{
      ...finalValues,
      // 【予約キー】呼び出し元(report_edit_screen.dart)がSE用/プロワン用の
      // どちらの反映ロジックを実行すべきか判定するために、判定済みdocTypeを
      // 一緒に返す。Azureモデルのフィールドキーは全てPascalCaseのため、
      // 先頭に "_" を付けたこのキーと衝突することはない。
      '_docType': widget.scanResult.docType,
    };
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final lowConfidenceCount = _fieldDefs
        .where((d) => widget.scanResult.isLowConfidence(d.key))
        .length;
    final isProWan = widget.scanResult.isProWanDocument;

    return Scaffold(
      appBar: AppBar(
        title: Text(isProWan ? 'スキャン内容の確認・修正(プロワン)' : 'スキャン内容の確認・修正'),
      ),
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
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: Colors.amber.shade900,
                    ),
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
                if (isProWan) ...[
                  const SizedBox(height: 6),
                  Text(
                    'ℹ プロワンの作業報告書として判定されました。案件管理番号(伝票No)を'
                    '「反映」した後、日報編集画面の「照合」ボタンで顧客名・作業内容などを'
                    '自動入力できます。',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
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
              itemCount: _fieldDefs.length,
              itemBuilder: (context, index) {
                final def = _fieldDefs[index];
                final lowConf = widget.scanResult.isLowConfidence(def.key);
                final confidence = widget.scanResult.confidences[def.key];
                final mustConfirm = _mustConfirmKeys.contains(def.key);
                final checked = _confirmedChecks[def.key] ?? true;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _controllers[def.key],
                        decoration: InputDecoration(
                          labelText: def.label,
                          helperText: confidence != null
                              ? 'AI信頼度: ${(confidence * 100).toStringAsFixed(0)}%'
                              : '未検出(空欄)',
                          helperStyle: TextStyle(
                            color: (lowConf || (mustConfirm && !checked))
                                ? Colors.deepOrange
                                : Colors.grey.shade500,
                            fontSize: 11,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: (lowConf || (mustConfirm && !checked))
                                ? const BorderSide(
                                    color: Colors.deepOrange,
                                    width: 1.4,
                                  )
                                : BorderSide.none,
                          ),
                          filled: true,
                          fillColor: (lowConf || (mustConfirm && !checked))
                              ? Colors.deepOrange.withValues(alpha: 0.06)
                              : Colors.grey.withValues(alpha: 0.06),
                        ),
                        onChanged: mustConfirm
                            ? (_) {
                                // 【重要】値を修正したら再度確認が必要。
                                // 「修正したのにチェックだけ残る」事故を防ぐため、
                                // テキストが変更された時点でチェックを外す。
                                if (_confirmedChecks[def.key] == true) {
                                  setState(
                                    () => _confirmedChecks[def.key] = false,
                                  );
                                }
                              }
                            : null,
                      ),
                      if (mustConfirm) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: checked
                                ? Colors.green.withValues(alpha: 0.08)
                                : Colors.deepOrange.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: checked,
                                  activeColor: Colors.green.shade700,
                                  onChanged: (v) {
                                    setState(
                                      () => _confirmedChecks[def.key] =
                                          v ?? false,
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '⚠ このフィールドはAI読み取り精度がまだ低い項目です。'
                                  '報告書の実物と照らし合わせて内容を確認しました',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: checked
                                        ? Colors.green.shade800
                                        : Colors.deepOrange.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_hasUnconfirmedRequiredField)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '⚠ 精度がまだ低い項目の確認チェックが済んでいないため反映できません',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.deepOrange.shade700,
                        ),
                      ),
                    ),
                  Row(
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
                          onPressed: _hasUnconfirmedRequiredField
                              ? null
                              : _confirm,
                          icon: const Icon(Icons.check),
                          label: const Text('この内容で反映する'),
                        ),
                      ),
                    ],
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
