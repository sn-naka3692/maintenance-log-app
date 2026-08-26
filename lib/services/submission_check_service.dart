import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/submission_check_record.dart';

/// 【月末チェック(日報記入率)機能】突合結果の永続化を担当するサービス。
///
/// 【設計方針】
/// - Firestore `submission_checks` コレクションに、スキャンPDFの1ページ = 1件
///   のドキュメントとして保存する(ドキュメントIDはauto-id)。
/// - 対象月(check_month, "yyyy-MM")ごとに、月末チェックを再実行した場合は
///   同月の既存レコードを全削除してから新しい結果に差し替える
///   (「今月分は常に最新の実行結果のみ」というシンプルな運用のため)。
/// - クエリは複合indexが不要な単純な `where('check_month', ...)` のみとし、
///   並び替え(ページ番号順など)はアプリ側メモリ内で行う。
class SubmissionCheckService {
  static final SubmissionCheckService instance =
      SubmissionCheckService._internal();
  SubmissionCheckService._internal();

  static const String _collection = 'submission_checks';

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection(_collection);

  /// Firestoreバッチの書き込み上限(1バッチ最大500件操作)を考慮した
  /// 安全マージン付きチャンクサイズ。
  static const int _batchChunkSize = 400;

  /// 指定した対象月の突合結果を保存する。
  ///
  /// 既に同月の結果が存在する場合は、先に全件削除してから新規保存する
  /// (月末チェックの再実行 = 前回結果の上書きという仕様)。
  Future<void> saveResults({
    required String checkMonth,
    required List<SubmissionCheckRecord> records,
  }) async {
    // 1. 同月の既存レコードを取得して削除対象IDを集める(単純クエリ)。
    final existing = await _col
        .where('check_month', isEqualTo: checkMonth)
        .get();

    final deleteIds = existing.docs.map((d) => d.id).toList();

    // 2. 削除 + 新規追加をバッチで実行(件数が多い場合はチャンク分割)。
    final allOps = <_BatchOp>[
      ...deleteIds.map((id) => _BatchOp.delete(id)),
      ...records.map((r) => _BatchOp.set(r.toMap())),
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

  /// 指定した対象月の突合結果一覧を取得する(ページ番号順にソートして返す)。
  Future<List<SubmissionCheckRecord>> fetchResultsForMonth(
    String checkMonth,
  ) async {
    try {
      final snap = await _col.where('check_month', isEqualTo: checkMonth).get();
      final records = snap.docs
          .map((d) => SubmissionCheckRecord.fromMap(d.id, d.data()))
          .toList();
      records.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
      return records;
    } catch (_) {
      return [];
    }
  }

  /// 過去に月末チェックを実行したことがある対象月の一覧(新しい順)を取得する。
  /// 履歴表示・月選択ドロップダウン用。
  Future<List<String>> fetchAvailableMonths() async {
    try {
      final snap = await _col.get();
      final months = snap.docs
          .map((d) => d.data()['check_month'] as String? ?? '')
          .where((m) => m.isNotEmpty)
          .toSet()
          .toList();
      months.sort((a, b) => b.compareTo(a)); // "yyyy-MM"文字列比較で新しい順
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
