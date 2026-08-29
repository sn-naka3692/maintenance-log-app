import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/parts_reconciliation_result.dart';

/// 【部品情報突合機能】突合結果の永続化を担当するサービス。
///
/// SubmissionCheckService(月末チェック)と同じ設計方針を踏襲する:
/// - Firestore `parts_reconciliations` コレクションに1件=1ドキュメントで保存。
/// - 対象月(check_month, "yyyy-MM")ごとに、再実行時は同月の既存レコードを
///   全削除してから新しい結果に差し替える。
/// - クエリは複合indexが不要な単純な `where('check_month', ...)` のみとし、
///   並び替えはアプリ側メモリ内で行う。
class PartsReconciliationStorageService {
  static final PartsReconciliationStorageService instance =
      PartsReconciliationStorageService._internal();
  PartsReconciliationStorageService._internal();

  static const String _collection = 'parts_reconciliations';

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection(_collection);

  static const int _batchChunkSize = 400;

  Future<void> saveResults({
    required String checkMonth,
    required List<PartsReconciliationResult> results,
  }) async {
    final existing = await _col
        .where('check_month', isEqualTo: checkMonth)
        .get();
    final deleteIds = existing.docs.map((d) => d.id).toList();

    final allOps = <_BatchOp>[
      ...deleteIds.map((id) => _BatchOp.delete(id)),
      ...results.map(
        (r) => _BatchOp.set({
          ...r.toMap(),
          'check_month': checkMonth,
          'created_at': FieldValue.serverTimestamp(),
        }),
      ),
    ];

    for (var i = 0; i < allOps.length; i += _batchChunkSize) {
      final chunk = allOps.sublist(
        i,
        (i + _batchChunkSize).clamp(0, allOps.length),
      );
      final batch = FirebaseFirestore.instance.batch();
      for (final op in chunk) {
        if (op.isDelete) {
          batch.delete(_col.doc(op.deleteId));
        } else {
          batch.set(_col.doc(), op.data);
        }
      }
      await batch.commit();
    }
  }

  Future<List<PartsReconciliationResult>> fetchResultsForMonth(
    String checkMonth,
  ) async {
    try {
      final snap = await _col
          .where('check_month', isEqualTo: checkMonth)
          .get();
      return snap.docs
          .map((d) => PartsReconciliationResult.fromMap(d.data()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> fetchAvailableMonths() async {
    try {
      final snap = await _col.get();
      final months = snap.docs
          .map((d) => d.data()['check_month'] as String? ?? '')
          .where((m) => m.isNotEmpty)
          .toSet()
          .toList();
      months.sort((a, b) => b.compareTo(a));
      return months;
    } catch (_) {
      return [];
    }
  }
}

class _BatchOp {
  final bool isDelete;
  final String? deleteId;
  final Map<String, dynamic>? data;

  _BatchOp._(this.isDelete, this.deleteId, this.data);

  factory _BatchOp.delete(String id) => _BatchOp._(true, id, null);
  factory _BatchOp.set(Map<String, dynamic> data) =>
      _BatchOp._(false, null, data);
}
