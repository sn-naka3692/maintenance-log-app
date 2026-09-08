import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
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
/// 【運用基盤・2026-09拡張:学習用画像の一時保存】
/// 従来は「フィールド単位のテキスト差分」のみを記録し、元画像は保存
/// していなかったため、実際にどのPDF/写真が学習サンプルとして使えるか
/// 特定できないという限界があった。この拡張では、1件以上の手直しが
/// 発生したスキャンに限り、元画像をFirebase Storageの
/// `training_candidates/{docType}/{バッチID}.jpg` に一時保存し、
/// 対応する`scan_corrections`ドキュメントに`report_id`(どの日報の
/// スキャンか)と`training_image_path`(画像の保存先)を記録する。
///
/// 手直しが無かった(AIが完全に正解した)スキャンの画像は保存しない
/// (無駄な容量消費・個人情報保持を避けるため)。また、この一時画像は
/// 「次回のモデル再学習が完了するまで」の保管であり、再学習完了後は
/// 自動的に削除する運用とする(削除処理は別途、学習完了時のバッチで実施)。
///
/// 【失敗時の扱い】
/// このログ記録・画像保存はあくまで補助機能であり、業務の主目的
/// (日報の保存)を妨げてはならない。書き込み・アップロードに失敗しても
/// 例外を外に伝播させず、デバッグログのみ出力する。
///
/// 【2026-09拡張:半自動再学習フロー用 training_samples コレクション】
/// 従来の `scan_corrections` は「手直しされたフィールドの差分のみ」を
/// 記録する設計だったため、実際にAzureへ再学習投入する際に必要な
/// 「そのスキャンの全フィールドの最終確定値」がそのままでは分からず、
/// 手直しが1件でもあった元画像を都度目視で全項目転記し直す必要があった。
///
/// この拡張では、手直しが1件以上あったスキャンについて、finalValues
/// 全体(そのスキャンで確認・確定した全フィールド値)を新規コレクション
/// `training_samples` にも保存する。既存の `scan_corrections`
/// (フィールド単位の差分ログ)は運用・データ構造ともに変更しない
/// (後方互換を保つため、削除・改修は行わない)。
///
/// 【運用方針・段階導入】
/// - まずプロワン側(doc_type='ProWanDocType')を優先して半自動フロー
///   (閾値到達で管理者に通知→人間がラベリング→Azure再学習投入)の
///   運用対象とする。
/// - SE側(doc_type='SEDocType')は、SE側の正解データ提供が月1回程度・
///   手動Excelになる可能性がある(継続突合の頻度・形式がProWan側と
///   異なる)ため、当面はサンプル収集のみ行い、実際の学習投入運用は
///   後日順次進める。
/// - `doc_type` フィールドで完全に分離されているため、ProWan側の運用を
///   先に開始してもSE側のデータ収集自体は最初から並行して行われる
///   (取りこぼしがない)。
class ScanCorrectionLogService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;
  static const String _collection = 'scan_corrections';
  static const String _samplesCollection = 'training_samples';

  /// [aiValues]と[finalValues]を比較し、異なっているフィールドのみを
  /// まとめてバッチ書き込みする。手直しが1件以上あった場合は、元画像
  /// ([imageBytes]、単一画像スキャンの場合のみ渡される)を学習候補として
  /// Firebase Storageへ一時保存し、その保存先パスを各ログに記録する。
  ///
  /// - [docType]: 'SEDocType' | 'ProWanDocType'
  /// - [reportId]: この修正がどの日報のスキャンによるものかを示すID。
  ///   将来、学習サンプルの元データを目視で辿る際の手がかりとして記録する
  ///   (テキスト差分だけでは元のPDF/写真を特定できなかった問題への対策)。
  /// - [aiValues]: AIが抽出した元の値(フィールドキー -> 値)
  /// - [confidences]: AIの抽出信頼度(フィールドキー -> 0.0〜1.0)
  /// - [finalValues]: 確認画面でユーザーが確定した最終値
  /// - [imageBytes]: 解析に使った元画像のバイト列(PDF一括解析の場合はnull)
  static Future<void> logCorrections({
    required String docType,
    required String reportId,
    required Map<String, String> aiValues,
    required Map<String, double> confidences,
    required Map<String, String> finalValues,
    Uint8List? imageBytes,
  }) async {
    try {
      final diffs = <MapEntry<String, String>>[]; // key -> finalValue
      for (final entry in finalValues.entries) {
        final key = entry.key;
        final aiValue = (aiValues[key] ?? '').trim();
        final finalValue = entry.value.trim();
        if (aiValue == finalValue) continue; // 手直しなし(記録不要)
        diffs.add(MapEntry(key, finalValue));
      }

      if (diffs.isEmpty) return;

      // 手直しが1件以上あった場合のみ、元画像を学習候補として一時保存する。
      String? trainingImagePath;
      if (imageBytes != null && imageBytes.isNotEmpty) {
        trainingImagePath = await _uploadTrainingCandidate(
          docType: docType,
          imageBytes: imageBytes,
        );
      }

      final batch = _db.batch();
      for (final entry in diffs) {
        final key = entry.key;
        final doc = _db.collection(_collection).doc();
        batch.set(doc, {
          'doc_type': docType,
          'report_id': reportId,
          'field_key': key,
          'ai_value': (aiValues[key] ?? '').trim(),
          'corrected_value': entry.value,
          'ai_confidence': confidences[key],
          'training_image_path': trainingImagePath,
          // 'pending' = 未学習(次回再学習の対象) / 'trained' = 学習済み
          'training_status': 'pending',
          'created_at': FieldValue.serverTimestamp(),
        });
      }

      // 【2026-09追加】半自動再学習フロー用に、そのスキャンの全フィールド
      // 最終確定値(finalValues)を1件のドキュメントとしてまとめて保存する。
      // (上記の scan_corrections への差分書き込みとは独立した別コレクション。
      // 既存の scan_corrections 側の運用・件数には一切影響しない。)
      final sampleDoc = _db.collection(_samplesCollection).doc();
      batch.set(sampleDoc, {
        'doc_type': docType,
        'report_id': reportId,
        'final_values': finalValues,
        'corrected_field_keys': diffs.map((e) => e.key).toList(),
        'training_image_path': trainingImagePath,
        // 'pending' = 未処理(閾値カウント対象) / 'labeled' = ラベリング済み
        // (座標特定完了・Azure投入待ち) / 'trained' = 再学習投入済み
        'training_status': 'pending',
        'created_at': FieldValue.serverTimestamp(),
      });

      await batch.commit();
    } catch (e) {
      // 【重要】学習データ収集はあくまで補助機能。ここで例外を投げて
      // 日報保存フロー自体を止めてしまうことは絶対に避ける。
      if (kDebugMode) {
        debugPrint('ScanCorrectionLogService.logCorrections failed: $e');
      }
    }
  }

  /// 学習候補の元画像をFirebase Storageへアップロードし、保存先パス
  /// (ダウンロードURLではなく `ref.fullPath`)を返す。
  ///
  /// 【保存先】training_candidates/{docType}/{タイムスタンプ}.jpg
  /// 【運用】再学習が完了した候補画像は、別途バッチ処理で削除される
  /// 想定のため、ここでは「一時保存」であることを前提にシンプルな
  /// パス構成にしている。
  static Future<String?> _uploadTrainingCandidate({
    required String docType,
    required Uint8List imageBytes,
  }) async {
    try {
      final fileName = '${DateTime.now().microsecondsSinceEpoch}.jpg';
      final ref = _storage
          .ref()
          .child('training_candidates')
          .child(docType)
          .child(fileName);
      await ref.putData(
        imageBytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      return ref.fullPath;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'ScanCorrectionLogService._uploadTrainingCandidate failed: $e',
        );
      }
      return null;
    }
  }
}
