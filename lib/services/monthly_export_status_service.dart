import 'package:cloud_firestore/cloud_firestore.dart';

/// 「月次CSVエクスポート(SE店舗分・プロワン案件分・社内業務分)」の
/// 実施状況をFirestoreで管理するサービス。
///
/// 【目的】
/// 月次CSVエクスポートは完全自動化(NAS常時接続PCなし)ではなく、
/// 管理者がアプリを開いた際に「まだ先月分を出力していません」と
/// 気づける状態にするための記録用データ。
///
/// 【設計】
/// - Firestoreの `monthly_export_status` コレクションに、
///   月ごと(ドキュメントID = "yyyy-MM")で1件記録する。
/// - 3種別(SE店舗 / プロワン案件 / 社内業務)それぞれの出力済みフラグと
///   出力日時・件数を保持する。全社員がFirestoreを共有しているため、
///   どのデバイス・どの管理者が確認しても同じ状況が見える。
/// - 記録の作成/更新は管理者のみ(Firestore Rulesで制御)。
class MonthlyExportStatusService {
  static final MonthlyExportStatusService instance =
      MonthlyExportStatusService._internal();
  MonthlyExportStatusService._internal();

  static const String _collection = 'monthly_export_status';

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection(_collection);

  /// 指定した対象月(yyyy-MM形式)の出力状況を取得する。
  /// ドキュメントが存在しない場合は「全て未出力」のデフォルト値を返す。
  Future<MonthlyExportStatus> fetchStatus(String monthKey) async {
    try {
      final snap = await _col.doc(monthKey).get();
      if (!snap.exists || snap.data() == null) {
        return MonthlyExportStatus.empty(monthKey);
      }
      return MonthlyExportStatus.fromMap(monthKey, snap.data()!);
    } catch (_) {
      // 通信エラー時は「未出力」扱い(fail-safe: 見逃しよりリマインドの方が安全)。
      return MonthlyExportStatus.empty(monthKey);
    }
  }

  /// 指定カテゴリの出力完了を記録する。
  Future<void> markExported({
    required String monthKey,
    required String category, // 'se' | 'prowan' | 'backoffice'
    required int count,
    required String exportedByName,
  }) async {
    await _col.doc(monthKey).set({
      '${category}_exported': true,
      '${category}_count': count,
      '${category}_exported_at': FieldValue.serverTimestamp(),
      '${category}_exported_by': exportedByName,
    }, SetOptions(merge: true));
  }
}

/// 1ヶ月分(SE店舗/プロワン案件/社内業務)の出力状況。
class MonthlyExportStatus {
  final String monthKey; // "yyyy-MM"
  final bool seExported;
  final int seCount;
  final bool prowanExported;
  final int prowanCount;
  final bool backofficeExported;
  final int backofficeCount;

  const MonthlyExportStatus({
    required this.monthKey,
    required this.seExported,
    required this.seCount,
    required this.prowanExported,
    required this.prowanCount,
    required this.backofficeExported,
    required this.backofficeCount,
  });

  factory MonthlyExportStatus.empty(String monthKey) => MonthlyExportStatus(
    monthKey: monthKey,
    seExported: false,
    seCount: 0,
    prowanExported: false,
    prowanCount: 0,
    backofficeExported: false,
    backofficeCount: 0,
  );

  factory MonthlyExportStatus.fromMap(
    String monthKey,
    Map<String, dynamic> map,
  ) {
    return MonthlyExportStatus(
      monthKey: monthKey,
      seExported: map['se_exported'] as bool? ?? false,
      seCount: (map['se_count'] as num?)?.toInt() ?? 0,
      prowanExported: map['prowan_exported'] as bool? ?? false,
      prowanCount: (map['prowan_count'] as num?)?.toInt() ?? 0,
      backofficeExported: map['backoffice_exported'] as bool? ?? false,
      backofficeCount: (map['backoffice_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// 3種別すべて出力済みかどうか(データが1件も無いカテゴリはtrue扱いにするため、
  /// 呼び出し側で「対象件数が0のカテゴリ」は最初から出力済みとみなして渡すこと)。
  bool get allExported => seExported && prowanExported && backofficeExported;
}
