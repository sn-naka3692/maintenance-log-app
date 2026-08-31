/// 「案件」(複数の日報を横断してまとめる単位)を表すモデル。
///
/// 【設計方針(2026-08導入)】
/// 日報機能はあくまで従業員が「1回の訪問・1回の作業」を記録するためのもの
/// であり、複数人で同じ現場対応をした場合、それぞれが個別に日報を書く運用は
/// 変えない(現場の入力負担を増やさないことを最優先とする)。
///
/// 一方で、経営・案件管理の観点では「同じ案件に対して誰が何時間対応したか」
/// をまとめて把握したいというニーズがある。そこで、日報の保存タイミングで
/// アプリが裏側で自動的に「同じ案件と思われる日報」をグルーピングし、
/// この `cases` コレクションへ反映する。
///
/// 【グルーピングの判定基準(優先度順)】
///  1. プロワン伝票No(WorkReport.proWanRefNumber)が完全一致
///     -> primaryKeyType = 'prowan_slip', status = 'confirmed'
///  2. SE店舗の弊社受付No(StoreSystemReport.receiptNumber)が完全一致
///     -> primaryKeyType = 'se_receipt', status = 'confirmed'
///  3. 番号が無い場合、同じ店舗・近い訪問日・作業内容の類似度が高い
///     -> primaryKeyType = 'provisional', status = 'suggested'
///     (要確認: 管理画面から手動で分離できる)
class WorkCase {
  final String id; // ドキュメントID(伝票No/受付Noがあればそれを正規化して使う。無ければ自動採番)
  String primaryKeyType; // 'prowan_slip' | 'se_receipt' | 'provisional'
  String primaryKeyValue; // 伝票No or 受付No(あれば)。provisionalの場合は空でも可
  String status; // 'confirmed' | 'suggested'
  String? storeId;
  String storeName;
  List<String> linkedReportIds; // 紐づく日報IDの一覧
  List<CaseParticipant> participants; // 関わった従業員一覧(自動集計)
  double totalWorkHours; // 合計作業時間(自動計算)
  DateTime? firstVisitDate;
  DateTime? lastVisitDate;
  DateTime createdAt;
  DateTime updatedAt;
  // 紐づく日報のいずれか1件でも冷媒充填を行っていれば true(自動集計)。
  // 「案件内容での絞り込み」ニーズ(特に冷媒充填の有無)に対応するため、
  // 日報1件ずつの WorkReport.hasRefrigerantFilling を OR で集約したもの。
  bool hasRefrigerantFilling;

  WorkCase({
    required this.id,
    required this.primaryKeyType,
    this.primaryKeyValue = '',
    this.status = 'suggested',
    this.storeId,
    this.storeName = '',
    List<String>? linkedReportIds,
    List<CaseParticipant>? participants,
    this.totalWorkHours = 0,
    this.firstVisitDate,
    this.lastVisitDate,
    required this.createdAt,
    required this.updatedAt,
    this.hasRefrigerantFilling = false,
  }) : linkedReportIds = linkedReportIds ?? [],
       participants = participants ?? [];

  bool get isConfirmed => status == 'confirmed';
  bool get isMultiPerson => participants.length > 1;
  // 【2026-09追加】伝票No/受付No等の確実なキーが無く、かつ曖眛グルーピングも
  // 成立しなかった日報を、誰でもその場で「単独案件」として登録できるように
  // した際のステータス。「案件の存在を全員が把握できる」ことを最低ラインとし、
  // 後から伝票No等が入力されれば正しい確定案件へ自動的に統合される(暫定状態)。
  bool get isStandalone => status == 'standalone';

  Map<String, dynamic> toMap() {
    return {
      'primary_key_type': primaryKeyType,
      'primary_key_value': primaryKeyValue,
      'status': status,
      'store_id': storeId,
      'store_name': storeName,
      'linked_report_ids': linkedReportIds,
      'participants': participants.map((p) => p.toMap()).toList(),
      'total_work_hours': totalWorkHours,
      'first_visit_date': firstVisitDate?.toIso8601String(),
      'last_visit_date': lastVisitDate?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'has_refrigerant_filling': hasRefrigerantFilling,
    };
  }

  factory WorkCase.fromMap(String id, Map<String, dynamic> map) {
    return WorkCase(
      id: id,
      primaryKeyType: map['primary_key_type'] as String? ?? 'provisional',
      primaryKeyValue: map['primary_key_value'] as String? ?? '',
      status: map['status'] as String? ?? 'suggested',
      storeId: map['store_id'] as String?,
      storeName: map['store_name'] as String? ?? '',
      linkedReportIds: (map['linked_report_ids'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      participants: (map['participants'] as List<dynamic>? ?? [])
          .map(
            (e) => CaseParticipant.fromMap(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      totalWorkHours: (map['total_work_hours'] as num?)?.toDouble() ?? 0,
      firstVisitDate: _parseDate(map['first_visit_date']),
      lastVisitDate: _parseDate(map['last_visit_date']),
      createdAt: _parseDate(map['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(map['updated_at']) ?? DateTime.now(),
      hasRefrigerantFilling: map['has_refrigerant_filling'] as bool? ?? false,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value);
    }
    try {
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }
}

/// 案件に関わった従業員1名分の情報。
class CaseParticipant {
  final String authorId;
  final String authorName;
  final int reportCount; // この案件で書いた日報の数(通常1件だが念のため)

  const CaseParticipant({
    required this.authorId,
    required this.authorName,
    this.reportCount = 1,
  });

  Map<String, dynamic> toMap() => {
    'author_id': authorId,
    'author_name': authorName,
    'report_count': reportCount,
  };

  factory CaseParticipant.fromMap(Map<String, dynamic> map) {
    return CaseParticipant(
      authorId: map['author_id'] as String? ?? '',
      authorName: map['author_name'] as String? ?? '',
      reportCount: (map['report_count'] as num?)?.toInt() ?? 1,
    );
  }
}
