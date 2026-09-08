import 'package:cloud_firestore/cloud_firestore.dart';

/// AI-OCR半自動再学習フロー(2026-09導入)における「未処理サンプル件数」を
/// 取得するサービス。
///
/// 【背景・設計方針】
/// Azure Document Intelligenceのカスタムモデルには本番結果からの自動継続
/// 学習機能がなく、座標付きラベル(labels.json)の生成が人間の目視作業に
/// 依存する。そのため「一定件数たまったら全自動で再学習」は実現できず、
/// 「一定件数たまったら管理者に通知し、ラベリング・Azure投入は人間が
/// 手動実行する」半自動フローを採用する。このサービスはその「通知」部分
/// (未処理件数のカウント・閾値判定)のみを担う。
///
/// 【段階導入】
/// まずプロワン側(ProWanDocType)を優先運用する。SE側(SEDocType)は
/// 正解データの提供が月1回程度・手動Excelになる可能性があり運用形態が
/// 異なるため、件数カウント自体はSE側も最初から行うが、ダッシュボード上の
/// 案内文言は「まずプロワン側の運用から」であることを明示する。
class TrainingSampleStatusService {
  static final TrainingSampleStatusService instance =
      TrainingSampleStatusService._internal();
  TrainingSampleStatusService._internal();

  static const String _collection = 'training_samples';

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection(_collection);

  /// 指定した [docType]('ProWanDocType' | 'SEDocType')について、
  /// training_status == 'pending'(未処理)のサンプル件数を取得する。
  ///
  /// 【実装上の注意】Firestoreの複合クエリ(where + orderBy)は
  /// 追加インデックスが必要になりがちなため、ここでは単純な
  /// where(doc_type) + where(training_status) の2条件のみに留め、
  /// orderByは使わない(件数カウントのみが目的のため不要)。
  Future<int> fetchPendingCount(String docType) async {
    try {
      final agg = await _col
          .where('doc_type', isEqualTo: docType)
          .where('training_status', isEqualTo: 'pending')
          .count()
          .get();
      return agg.count ?? 0;
    } catch (_) {
      // 通信エラー時は0件扱い(通知が出ないだけで、業務への影響はない)。
      return 0;
    }
  }

  /// SE/ProWan両方の未処理件数をまとめて取得する。
  Future<TrainingSampleCounts> fetchAllCounts() async {
    final prowan = await fetchPendingCount('ProWanDocType');
    final se = await fetchPendingCount('SEDocType');
    return TrainingSampleCounts(prowanPending: prowan, sePending: se);
  }
}

/// SE/ProWan別の未処理サンプル件数。
class TrainingSampleCounts {
  final int prowanPending;
  final int sePending;

  const TrainingSampleCounts({
    required this.prowanPending,
    required this.sePending,
  });
}
