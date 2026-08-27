import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// AI-OCR(Azure Document Intelligence)自動抽出結果を、ユーザーが
/// 確認・修正画面(ScanConfirmScreen)で手直しした場合に、その差分を
/// 記録しておくためのサービス。
///
/// 【背景・目的】
/// Azure Document Intelligenceのカスタムテンプレートモデルには、
/// 本番解析結果を使って自動的に継続学習していく機能は存在しない
/// (2026-08-28に社内で確認済み)。精度を上げていくには、人間が明示的に
/// 正解データ(ground truth)を追加し、`begin_build_document_model`を
/// 再実行して手動で再学習する必要がある。
///
/// そのため、現場で実際にどのフィールドが・どの程度・どのように手直し
/// されているかを日々のスキャン作業の中で自動的に収集しておき、
/// 次回のモデル再学習の判断材料(優先的に精度改善すべきフィールドの特定、
/// 追加学習サンプルとして使うべきPDFの洗い出し)に使う。
///
/// 【記録タイミング】
/// ScanConfirmScreenで「この内容で反映する」を押した時点。AIの抽出値
/// (ScanResult.value(key))と、確認画面上でユーザーが最終的に確定した
/// 値を比較し、異なっているフィールドのみを1件ずつログとして
/// `scan_corrections` コレクションへ書き込む。一致している(=手直し
/// 不要だった)フィールドは記録しない(ノイズを増やさないため)。
///
/// 【学習データ収集としての限界】
/// ここに記録されるのは「フィールド単位のテキスト差分」のみであり、
/// 元のPDF/画像そのものは保存しない(容量・個人情報の観点から)。
/// そのため、このログは「どのフィールドの精度が低いか」の傾向把握には
/// 使えるが、そのままAzureの学習データ(ground truth)には使えない。
/// 実際に再学習する際は、このログで精度が低いと判明したフィールドを
/// 中心に、該当する報告書PDFを別途サンプルとして追加収集する運用とする。
///
/// 【失敗時の扱い】
/// このログ記録はあくまで補助機能であり、業務の主目的(日報の保存)を
/// 妨げてはならない。書き込みに失敗しても例外を外に伝播させず、
/// デバッグログのみ出力する。
class ScanCorrectionLogService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _collection = 'scan_corrections';

  /// [aiValues]と[finalValues]を比較し、異なっているフィールドのみを
  /// まとめてバッチ書き込みする。
  ///
  /// - [docType]: 'SEDocType' | 'ProWanDocType'
  /// - [aiValues]: AIが抽出した元の値(フィールドキー -> 値)
  /// - [confidences]: AIの抽出信頼度(フィールドキー -> 0.0〜1.0)
  /// - [finalValues]: 確認画面でユーザーが確定した最終値
  static Future<void> logCorrections({
    required String docType,
    required Map<String, String> aiValues,
    required Map<String, double> confidences,
    required Map<String, String> finalValues,
  }) async {
    try {
      final batch = _db.batch();
      var any = false;

      for (final entry in finalValues.entries) {
        final key = entry.key;
        final aiValue = (aiValues[key] ?? '').trim();
        final finalValue = entry.value.trim();
        if (aiValue == finalValue) continue; // 手直しなし(記録不要)

        any = true;
        final doc = _db.collection(_collection).doc();
        batch.set(doc, {
          'doc_type': docType,
          'field_key': key,
          'ai_value': aiValue,
          'corrected_value': finalValue,
          'ai_confidence': confidences[key],
          'created_at': FieldValue.serverTimestamp(),
        });
      }

      if (!any) return;
      await batch.commit();
    } catch (e) {
      // 【重要】学習データ収集はあくまで補助機能。ここで例外を投げて
      // 日報保存フロー自体を止めてしまうことは絶対に避ける。
      if (kDebugMode) {
        debugPrint('ScanCorrectionLogService.logCorrections failed: $e');
      }
    }
  }
}
