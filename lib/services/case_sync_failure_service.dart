import 'package:cloud_firestore/cloud_firestore.dart';

/// 「日報→案件」自動グルーピング処理(CaseService.syncCaseForReport)が
/// 失敗した際の記録を管理するサービス。
///
/// 【背景・2026-08-31追加】
/// 従来、日報保存時の案件グルーピング処理(_syncCaseSilently)は
/// 「日報自体の保存を絶対に妨げない」ためにベストエフォート設計となって
/// おり、失敗してもデバッグモードでの `debugPrint` のみで、本番環境の
/// 管理者からは一切見えなかった。これにより「日報にはあるはずの情報が
/// 案件に反映されていない」という不整合が発生しても、管理者側は
/// 自分で気づく手段が無かった(=Firebase Admin SDK等で直接調査する
/// しかなかった)。
///
/// このサービスは、同期失敗が発生した際に `case_sync_failures`
/// コレクションへ記録を残し、管理画面(案件一覧)から一覧・再試行・
/// 解決マークができるようにする。
///
/// 【設計方針】
/// - あくまで「気づけるようにする」ための記録機能であり、この記録処理
///   自体が失敗しても日報保存には一切影響させない(try-catchで握りつぶす)。
/// - 同一日報について繰り返し失敗した場合、レコードを増やし続けるのでは
///   なく、日報ID(reportId)をドキュメントIDとして上書きする
///   (=常に「最新の失敗内容」のみを保持する)。
/// - 再同期に成功した場合、または管理者が「解決済み」にした場合は
///   レコードを削除する(未解決件数のバッジ表示をシンプルに保つため)。
class CaseSyncFailureService {
  static final CaseSyncFailureService instance =
      CaseSyncFailureService._internal();
  CaseSyncFailureService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('case_sync_failures');

  /// 日報1件分の同期失敗を記録する(同一日報IDは上書き)。
  /// この処理自体の失敗は握りつぶす(呼び出し元の処理を妨げないため)。
  Future<void> recordFailure({
    required String reportId,
    required String reportSummary,
    required String errorMessage,
  }) async {
    try {
      await _col.doc(reportId).set({
        'report_id': reportId,
        'report_summary': reportSummary,
        'error_message': errorMessage,
        'occurred_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // 記録処理自体の失敗は無視する(ベストエフォート)。
    }
  }

  /// 再同期に成功した場合や、手動で解決済みとした場合に記録を削除する。
  Future<void> clearFailure(String reportId) async {
    try {
      await _col.doc(reportId).delete();
    } catch (_) {
      // 削除失敗も無視する(次回一覧取得時にまた表示されるだけで実害なし)。
    }
  }

  /// 現在記録されている未解決の同期失敗一覧を取得する。
  Future<List<CaseSyncFailure>> getAllFailures() async {
    final snap = await _col.get();
    final list = snap.docs
        .map((d) => CaseSyncFailure.fromMap(d.id, d.data()))
        .toList();
    list.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return list;
  }

  /// 未解決件数のみを軽量に取得する(バッジ表示用)。
  Future<int> countFailures() async {
    final snap = await _col.count().get();
    return snap.count ?? 0;
  }
}

/// 1件の同期失敗記録。
class CaseSyncFailure {
  final String id; // = reportId
  final String reportId;
  final String reportSummary; // 一覧表示用の簡易説明(店舗名・訪問日等)
  final String errorMessage;
  final DateTime occurredAt;

  const CaseSyncFailure({
    required this.id,
    required this.reportId,
    required this.reportSummary,
    required this.errorMessage,
    required this.occurredAt,
  });

  factory CaseSyncFailure.fromMap(String id, Map<String, dynamic> map) {
    return CaseSyncFailure(
      id: id,
      reportId: map['report_id'] as String? ?? id,
      reportSummary: map['report_summary'] as String? ?? '',
      errorMessage: map['error_message'] as String? ?? '',
      occurredAt:
          DateTime.tryParse(map['occurred_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
