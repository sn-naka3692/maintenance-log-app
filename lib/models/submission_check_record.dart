import 'package:cloud_firestore/cloud_firestore.dart';

/// 【月末チェック(日報記入率)機能】突合結果1件(=スキャンPDFの1ページ分)を
/// Firestoreに永続化するためのモデル。
///
/// 【ドキュメントID】自動採番(Firestore auto-id)。
/// 同じ案件が複数月にわたって現れることは通常ないが、念のため
/// 「月ごとの実施履歴」として複数回分を残せるよう、月末チェックを
/// 実行するたびに新規ドキュメント群を作成する設計にしている
/// (同月の再アップロード時は既存分を削除してから差し替える)。
enum SubmissionMatchStatus { matched, unmatched, lowConfidence, error }

extension SubmissionMatchStatusX on SubmissionMatchStatus {
  String get value {
    switch (this) {
      case SubmissionMatchStatus.matched:
        return 'matched';
      case SubmissionMatchStatus.unmatched:
        return 'unmatched';
      case SubmissionMatchStatus.lowConfidence:
        return 'low_confidence';
      case SubmissionMatchStatus.error:
        return 'error';
    }
  }

  static SubmissionMatchStatus fromValue(String value) {
    switch (value) {
      case 'matched':
        return SubmissionMatchStatus.matched;
      case 'low_confidence':
        return SubmissionMatchStatus.lowConfidence;
      case 'error':
        return SubmissionMatchStatus.error;
      case 'unmatched':
      default:
        return SubmissionMatchStatus.unmatched;
    }
  }
}

class SubmissionCheckRecord {
  final String id; // Firestore auto-id(新規保存時は空文字)
  final String checkMonth; // "yyyy-MM" 形式。月末チェックを実行した対象月。
  final String docType; // "SEDocType" | "ProWanDocType" | ""
  final String matchingKey; // 受付No or 伝票No(突合に使ったキー)
  final SubmissionMatchStatus matchStatus;
  final String storeName; // OCR結果の店舗名(参考表示用)
  final String otherWorkersCount; // OCR結果の「他◯名」(SE用紙のみ、参考情報)
  final double documentConfidence;
  final int pageNumber; // 元PDF内でのページ番号(参考情報)
  final String? matchedReportId; // 突合できた場合のWorkReport.id
  final String? matchedReportAuthorName; // 表示用キャッシュ(日報作成者名)
  final String? errorMessage;
  final String uploadedById; // 実行した管理者のuid
  final String uploadedByName; // 実行した管理者の氏名
  final DateTime? createdAt;

  const SubmissionCheckRecord({
    this.id = '',
    required this.checkMonth,
    required this.docType,
    required this.matchingKey,
    required this.matchStatus,
    this.storeName = '',
    this.otherWorkersCount = '',
    this.documentConfidence = 0,
    this.pageNumber = 0,
    this.matchedReportId,
    this.matchedReportAuthorName,
    this.errorMessage,
    required this.uploadedById,
    required this.uploadedByName,
    this.createdAt,
  });

  bool get isProWan => docType == 'ProWanDocType';

  Map<String, dynamic> toMap() {
    return {
      'check_month': checkMonth,
      'doc_type': docType,
      'matching_key': matchingKey,
      'match_status': matchStatus.value,
      'store_name': storeName,
      'other_workers_count': otherWorkersCount,
      'document_confidence': documentConfidence,
      'page_number': pageNumber,
      'matched_report_id': matchedReportId ?? '',
      'matched_report_author_name': matchedReportAuthorName ?? '',
      'error_message': errorMessage ?? '',
      'uploaded_by_id': uploadedById,
      'uploaded_by_name': uploadedByName,
      'created_at': FieldValue.serverTimestamp(),
    };
  }

  factory SubmissionCheckRecord.fromMap(String id, Map<String, dynamic> map) {
    return SubmissionCheckRecord(
      id: id,
      checkMonth: map['check_month'] as String? ?? '',
      docType: map['doc_type'] as String? ?? '',
      matchingKey: map['matching_key'] as String? ?? '',
      matchStatus: SubmissionMatchStatusX.fromValue(
        map['match_status'] as String? ?? 'unmatched',
      ),
      storeName: map['store_name'] as String? ?? '',
      otherWorkersCount: map['other_workers_count'] as String? ?? '',
      documentConfidence: (map['document_confidence'] as num?)?.toDouble() ?? 0,
      pageNumber: (map['page_number'] as num?)?.toInt() ?? 0,
      matchedReportId: (map['matched_report_id'] as String?)?.isEmpty ?? true
          ? null
          : map['matched_report_id'] as String,
      matchedReportAuthorName:
          (map['matched_report_author_name'] as String?)?.isEmpty ?? true
          ? null
          : map['matched_report_author_name'] as String,
      errorMessage: (map['error_message'] as String?)?.isEmpty ?? true
          ? null
          : map['error_message'] as String,
      uploadedById: map['uploaded_by_id'] as String? ?? '',
      uploadedByName: map['uploaded_by_name'] as String? ?? '',
      createdAt: (map['created_at'] as Timestamp?)?.toDate(),
    );
  }
}
