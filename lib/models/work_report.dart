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
  warehouseWork, // 倉庫作業
  environmentalMaintenance, // 環境整備(清掃・整理整頓・草刈り等)
  other, // その他
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
  // プロワンCSVキャッシュ照合(重複入力削減機能)関連フィールド
  // ------------------------------------------------------------
  //
  // 【自動入力/手入力の区別】
  // フィールド名 -> "auto" | "manual" のマップ。
  // - "auto": OCRスキャン or CSVキャッシュ照合による自動入力
  //   (まだ人間が確認・修正していない値)
  // - "manual": 人間が入力・確定した値。
  //   月次CSV再照合バッチは "manual" のフィールドを絶対に上書きしない。
  // キーが存在しないフィールドは従来通りの手入力扱いとする(後方互換)。
  Map<String, String> fieldSources;

  // 「要確認」フラグ。スキャン時の照合が曖昧一致(完全一致でない)だった場合や、
  // 該当する伝票Noがキャッシュに見つからなかった場合に true となる。
  // 月次CSV再照合バッチはこのフラグが true のレコードのみを再照合対象とする。
  bool manualReviewNeeded;

  // スキャン時に照合したプロワンキャッシュの伝票No(参照用)。
  // 曖昧一致だった場合、月次再照合時に「このキャッシュキーとの再照合が
  // 依然正しいか」を再確認する際の起点として使う。
  String matchedCacheJobNumber;

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
    Map<String, String>? fieldSources,
    this.manualReviewNeeded = false,
    this.matchedCacheJobNumber = '',
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
  /// 【重要】このメソッドが呼ばれたフィールドは、月次CSV再照合バッチが
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
      'field_sources': fieldSources,
      'manual_review_needed': manualReviewNeeded,
      'matched_cache_job_number': matchedCacheJobNumber,
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
      fieldSources: (map['field_sources'] as Map<String, dynamic>? ?? {}).map(
        (k, v) => MapEntry(k, v.toString()),
      ),
      manualReviewNeeded: map['manual_review_needed'] as bool? ?? false,
      matchedCacheJobNumber:
          map['matched_cache_job_number'] as String? ?? '',
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
}
