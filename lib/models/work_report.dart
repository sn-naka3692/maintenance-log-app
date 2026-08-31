import 'part_used.dart';
import 'prowan_report_detail.dart';
import 'store_system_report.dart';

/// 対応区分
enum ResponseType {
  regularInspection, // 定期点検
  breakdown, // 故障対応
  repair, // 修理
  installation, // 新設・設置
  officeWork, // 事務
  fieldOffice, // 現場事務
  warehouseWork, // 倉庫作業(倉庫整理・在庫管理を含む)
  environmentalMaintenance, // 環境整備(清掃・整理整頓・草刈り等)
  other, // その他
}

/// 「案件においての役割」のプルダウン選択肢(定型)。
///
/// 【今後の開発方向・人事評価制度連携について】(2026-08 導入)
/// 現段階ではまず「案件ごとにどんな役割を担ったか」というデータを
/// 蓄積することが目的であり、点数化や評価指標との自動連携は行わない。
/// 将来的には、ここで蓄積したデータ(役割の分布・頻度など)を人事評価
/// 制度上の評価指標(主担当としての遂行実績、後輩指導の実績等)に
/// 紐づけ、定量的な点数化を検討する。そのため、この選択肢リストの
/// 文言・粒度は将来の評価指標との対応付けを見据えて設計しており、
/// 安易に文言を変更する場合は人事評価制度側との整合性に注意すること。
class CaseRoleOptions {
  CaseRoleOptions._();

  static const List<String> presets = [
    '主担当',
    '副担当・アシスト',
    '指導・OJT(後輩育成)',
    '同行・見学',
    'その他',
  ];
}

extension ResponseTypeLabel on ResponseType {
  String get label {
    switch (this) {
      case ResponseType.regularInspection:
        return '定期点検';
      case ResponseType.breakdown:
        return '故障対応';
      case ResponseType.repair:
        return '修理';
      case ResponseType.installation:
        return '新設・設置';
      case ResponseType.officeWork:
        return '事務';
      case ResponseType.fieldOffice:
        return '現場事務';
      case ResponseType.warehouseWork:
        return '倉庫作業';
      case ResponseType.environmentalMaintenance:
        return '環境整備';
      case ResponseType.other:
        return 'その他';
    }
  }

  /// バックオフィス系区分かどうか(現場作業と区別してUI表示等に使える)
  bool get isBackOffice {
    switch (this) {
      case ResponseType.officeWork:
      case ResponseType.fieldOffice:
      case ResponseType.warehouseWork:
      case ResponseType.environmentalMaintenance:
        return true;
      default:
        return false;
    }
  }

  /// 【設計方針・2026-09追加】「案件」として管理する対象かどうか。
  ///
  /// 【背景】案件管理は「お客様先での現場対応(定期点検・故障対応・修理・
  /// 新設設置)」を追跡するための仕組みであり、事務・現場事務・倉庫作業・
  /// 環境整備・その他といった社内業務は対象外とすべきだった。しかし
  /// CaseServiceは従来この区別を一切行わず全日報を無差別に案件化対象と
  /// していたため、本来は日報(現場対応)ありきで案件が生まれるはずの
  /// 設計が、実質「日報を書けば種別を問わず何でも案件になる」という
  /// 逆転した状態になっていた(2026-09にユーザー指摘により発覚)。
  bool get isCaseEligible {
    switch (this) {
      case ResponseType.regularInspection:
      case ResponseType.breakdown:
      case ResponseType.repair:
      case ResponseType.installation:
        return true;
      default:
        return false;
    }
  }

  String get value {
    switch (this) {
      case ResponseType.regularInspection:
        return 'regularInspection';
      case ResponseType.breakdown:
        return 'breakdown';
      case ResponseType.repair:
        return 'repair';
      case ResponseType.installation:
        return 'installation';
      case ResponseType.officeWork:
        return 'officeWork';
      case ResponseType.fieldOffice:
        return 'fieldOffice';
      case ResponseType.warehouseWork:
        return 'warehouseWork';
      case ResponseType.environmentalMaintenance:
        return 'environmentalMaintenance';
      case ResponseType.other:
        return 'other';
    }
  }

  static ResponseType fromValue(String value) {
    return ResponseType.values.firstWhere(
      (t) => t.value == value,
      orElse: () => ResponseType.other,
    );
  }
}

class WorkReport {
  String id;
  String authorId;
  String authorName;
  List<String> coWorkerIds; // 共同作業者ID(従業員マスタ参照、複数可)
  String? storeId; // 店舗マスタID(選択した場合のみ)
  String clientName; // 訪問先(顧客名・店舗マスタ選択時は自動セット、リスト外は自由入力)
  DateTime visitDate; // 訪問日
  DateTime startTime; // 作業開始時刻
  DateTime endTime; // 作業終了時刻
  String workContent; // 作業内容
  String equipmentModel; // 機器型番(プロワン参照用)
  ResponseType responseType; // 対応区分
  List<PartUsed> partsUsed; // 使用部品
  List<String> photoPaths; // 写真パス(ローカル/URL)
  String notes; // 備考
  String successPoints; // うまくいったこと(ナレッジ共有)
  String issuesPoints; // 課題・失敗・改善点(ナレッジ共有)
  List<String> tags; // タグ(症状/機種/対応区分など自由入力)
  String proWanRefNumber; // プロワン管理番号(参照用・将来API連携)
  StoreSystemReport storeSystemReportCopy; // コンビニ側システム入力内容の控え(社内保存用・構造化フォーム)
  // プロワン管轄案件(SE店舗以外)専用: 請求業務効率化のため事務から要望。
  // 充填していない場合は種類「なし」・量「0」を入力する運用(空欄は不可)。
  // ※SE店舗用のStoreSystemReport.refrigerantType/refrigerantAmountとは別物。
  String nonSeRefrigerantType; // 冷媒種類(プロワン管轄案件)
  String nonSeRefrigerantAmountKg; // 冷媒量・kg単位(プロワン管轄案件)

  // プロワン管轄案件(SE店舗以外)専用の案件詳細情報の控え。
  // SE店舗のstoreSystemReportCopyに相当する、プロワンCSVキャッシュ
  // (店舗住所・部門・系統番号・障害内容・原因・依頼内容等)の受け皿。
  ProWanReportDetail proWanReportDetail;

  // ------------------------------------------------------------
  // 「案件においての役割」(人事評価データ収集用・2026-08導入)
  // ------------------------------------------------------------
  //
  // 【今後の開発方向】
  // 現段階ではプルダウン選択+自由記述によるデータ収集のみを目的とし、
  // 点数化や評価指標への自動反映は行わない。将来的に人事評価制度の
  // 評価指標と紐づけ、定量的なスコアリングを行うことを検討している。
  // そのため、caseRolePreset の値(CaseRoleOptions.presets)は
  // 将来の評価指標との対応付けを見据えた選択肢設計にしてあり、
  // caseRoleNote(自由記述)は定型選択肢では拾いきれない具体的な
  // 役割・貢献内容を補足する目的で用意している。
  String caseRolePreset; // プルダウン選択値(CaseRoleOptions.presetsのいずれか、または空)
  String caseRoleNote; // 自由記述による補足

  // ------------------------------------------------------------
  // プロワンCSVキャッシュ照合(重複入力削減機能)関連フィールド
  // ------------------------------------------------------------
  //
  // 【自動入力/手入力の区別】
  // フィールド名 -> "auto" | "manual" のマップ。
  // - "auto": OCRスキャン or CSVキャッシュ照合による自動入力
  //   (まだ人間が確認・修正していない値)
  // - "manual": 人間が入力・確定した値。
  //   日次CSV再照合バッチは "manual" のフィールドを絶対に上書きしない。
  // キーが存在しないフィールドは従来通りの手入力扱いとする(後方互換)。
  Map<String, String> fieldSources;

  // 「要確認」フラグ。スキャン時の照合が曖昧一致(完全一致でない)だった場合や、
  // 該当する伝票Noがキャッシュに見つからなかった場合に true となる。
  // 日次CSV再照合バッチはこのフラグが true のレコードのみを再照合対象とする。
  bool manualReviewNeeded;

  // スキャン時に照合したプロワンキャッシュの伝票No(参照用)。
  // 曖昧一致だった場合、日次再照合時に「このキャッシュキーとの再照合が
  // 依然正しいか」を再確認する際の起点として使う。
  String matchedCacheJobNumber;

  // ------------------------------------------------------------
  // 案件グルーピング機能(2026-08導入)
  // ------------------------------------------------------------
  //
  // 【設計方針】
  // 日報の入力項目・入力負担は一切増やさない。保存時にアプリが裏側で
  // 自動的に「同じ案件と思われる日報」を判定し、cases コレクションへの
  // 紐付けとしてこの caseId を自動セットする(CaseService が担当)。
  // 従業員がこのフィールドを直接編集することはない。
  String caseId; // 紐づく WorkCase のドキュメントID(未グルーピングなら空)

  // ------------------------------------------------------------
  // 管理者による代筆編集の記録(監査証跡・2026-08導入)
  // ------------------------------------------------------------
  //
  // 【目的】現場での入力もれ・訂正対応のため、一般管理者以上(admin/superAdmin)
  // には本人以外の日報も編集できる権限を付与する。ただし無制限な代筆を
  // 事故なく運用するため、「誰が・いつ代筆編集したか」を必ず記録し、
  // 日報詳細画面に明示する(本人・他の閲覧者が後から気づける状態にする)。
  // 本人が自分の日報を編集した場合はこれらのフィールドは更新しない。
  String? lastEditedByAdminId; // 代筆編集した管理者のユーザーID
  String? lastEditedByAdminName; // 代筆編集した管理者の氏名(表示用)
  DateTime? lastEditedByAdminAt; // 代筆編集した日時

  DateTime createdAt;
  DateTime updatedAt;

  WorkReport({
    required this.id,
    required this.authorId,
    required this.authorName,
    List<String>? coWorkerIds,
    this.storeId,
    required this.clientName,
    required this.visitDate,
    required this.startTime,
    required this.endTime,
    required this.workContent,
    this.equipmentModel = '',
    this.responseType = ResponseType.regularInspection,
    List<PartUsed>? partsUsed,
    List<String>? photoPaths,
    this.notes = '',
    this.successPoints = '',
    this.issuesPoints = '',
    List<String>? tags,
    this.proWanRefNumber = '',
    StoreSystemReport? storeSystemReportCopy,
    this.nonSeRefrigerantType = '',
    this.nonSeRefrigerantAmountKg = '',
    ProWanReportDetail? proWanReportDetail,
    this.caseRolePreset = '',
    this.caseRoleNote = '',
    Map<String, String>? fieldSources,
    this.manualReviewNeeded = false,
    this.matchedCacheJobNumber = '',
    this.caseId = '',
    this.lastEditedByAdminId,
    this.lastEditedByAdminName,
    this.lastEditedByAdminAt,
    required this.createdAt,
    required this.updatedAt,
  }) : partsUsed = partsUsed ?? [],
       photoPaths = photoPaths ?? [],
       tags = tags ?? [],
       coWorkerIds = coWorkerIds ?? [],
       storeSystemReportCopy = storeSystemReportCopy ?? StoreSystemReport(),
       proWanReportDetail = proWanReportDetail ?? ProWanReportDetail(),
       fieldSources = fieldSources ?? {};

  Duration get workDuration => endTime.difference(startTime);

  bool get hasIssues => issuesPoints.trim().isNotEmpty;
  bool get hasSuccess => successPoints.trim().isNotEmpty;

  /// 「未充填」を意味する入力値の一覧(冷媒種類欄用)。
  ///
  /// 【表記統一・2026-08修正】
  /// - プロワン管轄案件側の入力欄は自由入力のため「なし」「無し」等の
  ///   漢字表記も許容する。
  /// - SE店舗側(コンビニ側システム入力控え)の入力欄は半角英数のみ許可
  ///   のバリデーションがあるため、日本語は入力できない。そのため
  ///   「NONE」(大文字/小文字問わず)を未充填の統一表記として扱う。
  /// 【不具合修正・2026-08】以前はSE店舗側で「NONE」と入力しても
  /// この一覧に含まれておらず、単に「入力欄が空でなければ充填あり」と
  /// 誤判定していた(=正しく「未充填」と入力したのに「充填あり」扱いに
  /// なってしまうバグ)。両ルートで同じ判定基準を使うよう統一する。
  static const Set<String> _notFilledTypeValues = {'', 'なし', '無し', 'none'};

  /// 「未充填」を意味する入力値の一覧(充填量欄用)。
  static const Set<String> _notFilledAmountValues = {'', '0', '0.0', '0.00'};

  static bool _isNotFilledType(String v) =>
      _notFilledTypeValues.contains(v.trim().toLowerCase());
  static bool _isNotFilledAmount(String v) =>
      _notFilledAmountValues.contains(v.trim());

  /// [_isNotFilledType]の公開版。日報詳細画面など他画面から「未充填」表記の
  /// 統一表示に使うための入口(表記統一・2026-08)。
  static bool isNotFilledType(String v) => _isNotFilledType(v);

  /// [_isNotFilledAmount]の公開版。日報詳細画面など他画面から「未充填」表記の
  /// 統一表示に使うための入口(表記統一・2026-08)。
  static bool isNotFilledAmount(String v) => _isNotFilledAmount(v);

  /// 冷媒充填を行った案件かどうか。
  ///
  /// SE店舗案件(storeSystemReportCopy.refrigerantType/refrigerantAmount)と
  /// プロワン管轄案件(nonSeRefrigerantType/nonSeRefrigerantAmountKg)の
  /// 両方をチェックする。種類・量のいずれか一方でも「充填あり」を示す値
  /// であれば充填ありと判定する(両方が未充填の値である場合のみ未充填)。
  bool get hasRefrigerantFilling {
    final seType = storeSystemReportCopy.refrigerantType;
    final seAmount = storeSystemReportCopy.refrigerantAmount;
    if (!_isNotFilledType(seType) || !_isNotFilledAmount(seAmount)) {
      return true;
    }
    final nonSeType = nonSeRefrigerantType;
    final nonSeAmount = nonSeRefrigerantAmountKg;
    if (!_isNotFilledType(nonSeType) || !_isNotFilledAmount(nonSeAmount)) {
      return true;
    }
    return false;
  }

  // ------------------------------------------------------------
  // 自動入力/手入力フラグ管理ヘルパー
  // ------------------------------------------------------------

  /// 指定フィールドが自動入力(OCR/CSVキャッシュ照合)由来かどうか。
  /// fieldSourcesに記録がない場合は false(=手入力扱い、後方互換)。
  bool isFieldAutoFilled(String fieldKey) => fieldSources[fieldKey] == 'auto';

  /// 指定フィールドを「自動入力」としてマークする。
  /// (スキャン結果やCSVキャッシュ照合で値をセットした直後に呼ぶ)
  void markFieldAsAuto(String fieldKey) {
    fieldSources[fieldKey] = 'auto';
  }

  /// 指定フィールドを「手入力確定」としてマークする。
  /// (ユーザーがフォーム上でそのフィールドを編集・確認した際に呼ぶ)
  ///
  /// 【重要】このメソッドが呼ばれたフィールドは、日次CSV再照合バッチが
  /// 絶対に上書きしない(常時手入力修正可能・自動入力より優先、という
  /// 前セッションで確定した設計方針を反映する)。
  void markFieldAsManual(String fieldKey) {
    fieldSources[fieldKey] = 'manual';
  }

  /// 複数フィールドを一括で「自動入力」としてマークする。
  /// (ProwanJobCacheとの照合結果を反映する際に使う)
  void markFieldsAsAuto(Iterable<String> fieldKeys) {
    for (final key in fieldKeys) {
      fieldSources[key] = 'auto';
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'author_id': authorId,
      'author_name': authorName,
      'co_worker_ids': coWorkerIds,
      'store_id': storeId,
      'client_name': clientName,
      'visit_date': visitDate,
      'start_time': startTime,
      'end_time': endTime,
      'work_content': workContent,
      'equipment_model': equipmentModel,
      'response_type': responseType.value,
      'parts_used': partsUsed.map((p) => p.toMap()).toList(),
      'photo_paths': photoPaths,
      'notes': notes,
      'success_points': successPoints,
      'issues_points': issuesPoints,
      'tags': tags,
      'pro_wan_ref_number': proWanRefNumber,
      'store_system_report': storeSystemReportCopy.toMap(),
      'non_se_refrigerant_type': nonSeRefrigerantType,
      'non_se_refrigerant_amount_kg': nonSeRefrigerantAmountKg,
      'pro_wan_report_detail': proWanReportDetail.toMap(),
      'case_role_preset': caseRolePreset,
      'case_role_note': caseRoleNote,
      'field_sources': fieldSources,
      'manual_review_needed': manualReviewNeeded,
      'matched_cache_job_number': matchedCacheJobNumber,
      'case_id': caseId,
      'last_edited_by_admin_id': lastEditedByAdminId,
      'last_edited_by_admin_name': lastEditedByAdminName,
      'last_edited_by_admin_at': lastEditedByAdminAt,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory WorkReport.fromMap(String id, Map<String, dynamic> map) {
    return WorkReport(
      id: id,
      authorId: map['author_id'] as String? ?? '',
      authorName: map['author_name'] as String? ?? '',
      coWorkerIds: (map['co_worker_ids'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      storeId: map['store_id'] as String?,
      clientName: map['client_name'] as String? ?? '',
      visitDate: _parseDate(map['visit_date']),
      startTime: _parseDate(map['start_time']),
      endTime: _parseDate(map['end_time']),
      workContent: map['work_content'] as String? ?? '',
      equipmentModel: map['equipment_model'] as String? ?? '',
      responseType: ResponseTypeLabel.fromValue(
        map['response_type'] as String? ?? '',
      ),
      partsUsed: (map['parts_used'] as List<dynamic>? ?? [])
          .map((e) => PartUsed.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      photoPaths: (map['photo_paths'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      notes: map['notes'] as String? ?? '',
      successPoints: map['success_points'] as String? ?? '',
      issuesPoints: map['issues_points'] as String? ?? '',
      tags: (map['tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      proWanRefNumber: map['pro_wan_ref_number'] as String? ?? '',
      storeSystemReportCopy: StoreSystemReport.fromMap(
        map['store_system_report'] as Map<String, dynamic>?,
      ),
      nonSeRefrigerantType: map['non_se_refrigerant_type'] as String? ?? '',
      nonSeRefrigerantAmountKg:
          map['non_se_refrigerant_amount_kg'] as String? ?? '',
      proWanReportDetail: ProWanReportDetail.fromMap(
        map['pro_wan_report_detail'] as Map<String, dynamic>?,
      ),
      caseRolePreset: map['case_role_preset'] as String? ?? '',
      caseRoleNote: map['case_role_note'] as String? ?? '',
      fieldSources: (map['field_sources'] as Map<String, dynamic>? ?? {}).map(
        (k, v) => MapEntry(k, v.toString()),
      ),
      manualReviewNeeded: map['manual_review_needed'] as bool? ?? false,
      matchedCacheJobNumber: map['matched_cache_job_number'] as String? ?? '',
      caseId: map['case_id'] as String? ?? '',
      lastEditedByAdminId: map['last_edited_by_admin_id'] as String?,
      lastEditedByAdminName: map['last_edited_by_admin_name'] as String?,
      lastEditedByAdminAt: _parseNullableDate(map['last_edited_by_admin_at']),
      createdAt: _parseDate(map['created_at']),
      updatedAt: _parseDate(map['updated_at']),
    );
  }

  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    try {
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {
      return DateTime.now();
    }
  }

  /// 未入力(null)を許容する版の日付パーサー。
  /// 代筆編集記録(lastEditedByAdminAt)など、「一度も発生していない」
  /// ことを null で表現したいフィールド用。
  static DateTime? _parseNullableDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    try {
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }
}
