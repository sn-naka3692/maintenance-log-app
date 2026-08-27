/// プロワン作業報告書の「関連案件」1日程分の内訳を表すモデル。
///
/// 【背景・2026-08-27追加】プロワンの作業報告書は、関連する複数日の作業を
/// 1枚の伝票(伝票No)にまとめて記載できる仕様になっている(例:
/// 8/18に発見したガス漏れの点検と、8/27の本修理が同じ伝票Noで管理される)。
/// CSVインポート時(csv_cache_backend/import_prowan_csv.py)にこの内訳が
/// [ProwanJobCache.schedules] として全件保持されるため、OCRで読み取った
/// 「作業開始日」を使って、複数日程のうち該当する1件を選び出すことができる。
class ProwanScheduleEntry {
  final String scheduleStart; // 修理日程・工事予定開始日時("YYYY/MM/DD HH:MM")
  final String visitDate; // 訪問日(CSV上は空欄のことが多い)
  final String workContentDetail;
  final String workContent;
  final String troubleContent;
  final String troubleEquipment;
  final String futurePlan;
  final String visitResult;
  final String cause;
  final String requestContent;
  final String refrigerantType1;
  final String refrigerantAmount1;
  final String technicianName1;

  const ProwanScheduleEntry({
    this.scheduleStart = '',
    this.visitDate = '',
    this.workContentDetail = '',
    this.workContent = '',
    this.troubleContent = '',
    this.troubleEquipment = '',
    this.futurePlan = '',
    this.visitResult = '',
    this.cause = '',
    this.requestContent = '',
    this.refrigerantType1 = '',
    this.refrigerantAmount1 = '',
    this.technicianName1 = '',
  });

  factory ProwanScheduleEntry.fromMap(Map<String, dynamic> map) {
    return ProwanScheduleEntry(
      scheduleStart: map['schedule_start'] as String? ?? '',
      visitDate: map['visit_date'] as String? ?? '',
      workContentDetail: map['work_content_detail'] as String? ?? '',
      workContent: map['work_content'] as String? ?? '',
      troubleContent: map['trouble_content'] as String? ?? '',
      troubleEquipment: map['trouble_equipment'] as String? ?? '',
      futurePlan: map['future_plan'] as String? ?? '',
      visitResult: map['visit_result'] as String? ?? '',
      cause: map['cause'] as String? ?? '',
      requestContent: map['request_content'] as String? ?? '',
      refrigerantType1: map['refrigerant_type_1'] as String? ?? '',
      refrigerantAmount1: map['refrigerant_amount_1'] as String? ?? '',
      technicianName1: map['technician_name_1'] as String? ?? '',
    );
  }

  /// scheduleStart("YYYY/MM/DD HH:MM" または "YYYY/MM/DD")をDateTimeへ変換する。
  /// パース不可・空欄の場合はnullを返す。
  DateTime? get scheduleStartDate {
    final s = scheduleStart.trim();
    if (s.isEmpty) return null;
    // "YYYY/MM/DD HH:MM" or "YYYY/MM/DD"
    final match = RegExp(
      r'^(\d{4})/(\d{1,2})/(\d{1,2})(?:\s+(\d{1,2}):(\d{1,2}))?$',
    ).firstMatch(s);
    if (match == null) return null;
    try {
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        match.group(4) != null ? int.parse(match.group(4)!) : 0,
        match.group(5) != null ? int.parse(match.group(5)!) : 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// この日程内訳を work_report フィールド値マップへ変換する
  /// (ProwanJobCache.toWorkReportFieldValues()と同じキー体系)。
  Map<String, String> toWorkReportFieldValues() {
    return {
      'work_content': workContent.isNotEmpty ? workContent : workContentDetail,
      'non_se_refrigerant_type': refrigerantType1,
      'non_se_refrigerant_amount_kg': refrigerantAmount1,
      'pro_wan_report_detail.trouble_content': troubleContent,
      'pro_wan_report_detail.trouble_equipment': troubleEquipment,
      'pro_wan_report_detail.cause': cause,
      'pro_wan_report_detail.request_content': requestContent,
      'pro_wan_report_detail.visit_result': visitResult,
      'pro_wan_report_detail.future_plan': futurePlan,
      'pro_wan_report_detail.technician_name': technicianName1,
      'pro_wan_report_detail.visit_date': visitDate,
    };
  }
}

/// プロワンCSV(日次エクスポート)のキャッシュ1件分を表すモデル。
///
/// Firestoreの `prowan_job_cache` コレクションと対応する。
/// ドキュメントID = jobManagementNumber(伝票No/案件管理番号)。
///
/// 【運用】
/// 事務所側が毎日1回(2026-08-27改訂: 月1回から変更)、プロワンから出力した
/// CSVを取り込むことで、このコレクションが
/// 最新化される(取込処理は Python スクリプト側=csv_cache_backend/import_prowan_csv.py
/// が担当。Flutterアプリからは読み取り専用)。
/// 現場では作業報告書の「伝票No」欄をAI-OCRで読み取り、このキャッシュと照合することで、
/// 顧客名・店舗名・作業内容等の重複入力を避けることができる。
///
/// 【2026-08-27追加: 関連案件対応】
/// 1つの伝票Noに複数の作業日程(関連案件)が存在する場合、[schedules] に
/// 全日程の内訳(日付昇順)が保持される。トップレベルの各フィールド
/// (workContent等)は後方互換のため「最新の日程」の値を保持し続けるが、
/// OCRで「作業開始日」が読み取れた場合は、report_edit_screen.dart側で
/// [schedules] から該当日程を選んで反映する(_ProwanScheduleSelector参照)。
class ProwanJobCache {
  final String jobManagementNumber; // 案件管理番号 = 伝票No(ドキュメントID)
  final String clientName; // 顧客名
  final String storeAddress; // 店舗住所
  final String storeName; // 店舗名
  final String modelSerial; // 型式/製造番号
  final String workContentDetail; // 作業内容詳細
  final String department; // 部門
  final String systemNumber; // 系統番号・名
  final String equipmentLocation; // 修理機器・場所
  final String troubleContent; // 障害内容
  final String troubleEquipment; // 障害機器
  final String futurePlan; // 未完了の場合の今後の予定
  final String visitResult; // 訪問結果
  final String cause; // 原因(故障箇所)
  final String requestContent; // ご依頼内容
  final String workContent; // 作業内容
  final String refrigerantType1; // 冷媒の種類①
  final String refrigerantAmount1; // 冷媒量①
  final String technicianName1; // 技術者氏名①
  final String visitDate; // 訪問日(CSV上は文字列のまま保持)
  final DateTime? updatedAt; // このキャッシュが最後に更新された日時(取込時刻)
  final List<ProwanScheduleEntry> schedules; // 関連案件の全日程内訳(日付昇順)

  const ProwanJobCache({
    required this.jobManagementNumber,
    this.clientName = '',
    this.storeAddress = '',
    this.storeName = '',
    this.modelSerial = '',
    this.workContentDetail = '',
    this.department = '',
    this.systemNumber = '',
    this.equipmentLocation = '',
    this.troubleContent = '',
    this.troubleEquipment = '',
    this.futurePlan = '',
    this.visitResult = '',
    this.cause = '',
    this.requestContent = '',
    this.workContent = '',
    this.refrigerantType1 = '',
    this.refrigerantAmount1 = '',
    this.technicianName1 = '',
    this.visitDate = '',
    this.updatedAt,
    this.schedules = const [],
  });

  factory ProwanJobCache.fromMap(String id, Map<String, dynamic> map) {
    return ProwanJobCache(
      jobManagementNumber: id,
      clientName: map['client_name'] as String? ?? '',
      storeAddress: map['store_address'] as String? ?? '',
      storeName: map['store_name'] as String? ?? '',
      modelSerial: map['model_serial'] as String? ?? '',
      workContentDetail: map['work_content_detail'] as String? ?? '',
      department: map['department'] as String? ?? '',
      systemNumber: map['system_number'] as String? ?? '',
      equipmentLocation: map['equipment_location'] as String? ?? '',
      troubleContent: map['trouble_content'] as String? ?? '',
      troubleEquipment: map['trouble_equipment'] as String? ?? '',
      futurePlan: map['future_plan'] as String? ?? '',
      visitResult: map['visit_result'] as String? ?? '',
      cause: map['cause'] as String? ?? '',
      requestContent: map['request_content'] as String? ?? '',
      workContent: map['work_content'] as String? ?? '',
      refrigerantType1: map['refrigerant_type_1'] as String? ?? '',
      refrigerantAmount1: map['refrigerant_amount_1'] as String? ?? '',
      technicianName1: map['technician_name_1'] as String? ?? '',
      visitDate: map['visit_date'] as String? ?? '',
      updatedAt: _parseDate(map['updated_at']),
      schedules: _parseSchedules(map['schedules']),
    );
  }

  /// Firestoreの'schedules'配列(List<dynamic> of Map)を
  /// List<ProwanScheduleEntry>へ変換する。旧形式のキャッシュ
  /// (schedulesフィールド未取込)の場合は空リストを返す(後方互換)。
  static List<ProwanScheduleEntry> _parseSchedules(dynamic value) {
    if (value == null) return const [];
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((m) => ProwanScheduleEntry.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    try {
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }

  /// このキャッシュ内容を、work_reportの各フィールドへマッピングする際に
  /// 使いやすい形(フィールド名 -> 値)で返す。
  /// キーは WorkReport.toMap() のキー名とできるだけ揃えている。
  ///
  /// 【2026-08 不具合修正】従来はclient_name/work_content/equipment_model/
  /// 冷媒情報の5項目しか返しておらず、店舗住所・部門・系統番号・障害内容・
  /// 障害機器・原因・依頼内容・訪問結果・今後の予定・技術者氏名・訪問日
  /// といった大半のCSV項目が照合結果から捨てられていた
  /// (=「反映先の項目欄がない」という不具合の実態)。
  /// ProWanReportDetail(pro_wan_report_detail.*)を新設し、これらの項目も
  /// 反映できるようにした。
  Map<String, String> toWorkReportFieldValues() {
    return {
      'client_name': clientName,
      'work_content': workContent.isNotEmpty ? workContent : workContentDetail,
      'equipment_model': modelSerial,
      'pro_wan_ref_number': jobManagementNumber,
      'non_se_refrigerant_type': refrigerantType1,
      'non_se_refrigerant_amount_kg': refrigerantAmount1,
      // ProWanReportDetail側のフィールド(以下、report.proWanReportDetail.*)
      'pro_wan_report_detail.store_address': storeAddress,
      'pro_wan_report_detail.department': department,
      'pro_wan_report_detail.system_number': systemNumber,
      'pro_wan_report_detail.equipment_location': equipmentLocation,
      'pro_wan_report_detail.trouble_content': troubleContent,
      'pro_wan_report_detail.trouble_equipment': troubleEquipment,
      'pro_wan_report_detail.cause': cause,
      'pro_wan_report_detail.request_content': requestContent,
      'pro_wan_report_detail.visit_result': visitResult,
      'pro_wan_report_detail.future_plan': futurePlan,
      'pro_wan_report_detail.technician_name': technicianName1,
      'pro_wan_report_detail.visit_date': visitDate,
    };
  }

  /// OCRで読み取った「作業開始日」文字列(scan_confirm_screen.dartで
  /// ユーザーが確認・修正した値)から、[schedules] 内で最も日付が近い
  /// 日程を選ぶ。
  ///
  /// 【方針】
  /// - [schedules] が0件または1件の場合は選択の余地がないため常にnullを返す
  ///   (呼び出し元は既存のトップレベル値をそのまま使えばよい)。
  /// - 2件以上あり、scannedWorkStartDateが解析できた場合は、日付差が
  ///   最小の日程を返す(同日・同時刻が複数あるような特殊ケースは
  ///   先勝ちとする)。
  /// - scannedWorkStartDateが空欄・解析不能な場合はnullを返す
  ///   (呼び出し元はユーザーに複数候補から選ばせるなどのフォールバックへ)。
  ProwanScheduleEntry? findScheduleByScannedWorkStartDate(
    String scannedWorkStartDate,
  ) {
    if (schedules.length < 2) return null;
    final scannedDate = _parseFlexibleDate(scannedWorkStartDate);
    if (scannedDate == null) return null;

    ProwanScheduleEntry? best;
    Duration? bestDiff;
    for (final entry in schedules) {
      final entryDate = entry.scheduleStartDate;
      if (entryDate == null) continue;
      final diff = entryDate.difference(scannedDate).abs();
      if (bestDiff == null || diff < bestDiff) {
        best = entry;
        bestDiff = diff;
      }
    }
    return best;
  }

  /// OCR読み取り値("2026/08/18"や"2026年08月18日"等、表記揺れがありうる)
  /// を柔軟にDateTimeへ変換する。解析不能な場合はnullを返す。
  static DateTime? _parseFlexibleDate(String value) {
    final s = value.trim();
    if (s.isEmpty) return null;
    // "2026/08/18" "2026/08/18 13:00" 等
    final slashMatch = RegExp(
      r'(\d{4})[/\-](\d{1,2})[/\-](\d{1,2})',
    ).firstMatch(s);
    if (slashMatch != null) {
      try {
        return DateTime(
          int.parse(slashMatch.group(1)!),
          int.parse(slashMatch.group(2)!),
          int.parse(slashMatch.group(3)!),
        );
      } catch (_) {
        // fall through
      }
    }
    // "2026年08月18日" 等の和暦風表記
    final jpMatch = RegExp(
      r'(\d{4})年\s*(\d{1,2})月\s*(\d{1,2})日?',
    ).firstMatch(s);
    if (jpMatch != null) {
      try {
        return DateTime(
          int.parse(jpMatch.group(1)!),
          int.parse(jpMatch.group(2)!),
          int.parse(jpMatch.group(3)!),
        );
      } catch (_) {
        // fall through
      }
    }
    return null;
  }
}
