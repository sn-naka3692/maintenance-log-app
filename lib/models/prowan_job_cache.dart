/// プロワンCSV(月次エクスポート)のキャッシュ1件分を表すモデル。
///
/// Firestoreの `prowan_job_cache` コレクションと対応する。
/// ドキュメントID = jobManagementNumber(伝票No/案件管理番号)。
///
/// 【運用】
/// 事務所側が月1回、プロワンから出力したCSVを取り込むことで、このコレクションが
/// 最新化される(取込処理は Python スクリプト側=csv_cache_backend/import_prowan_csv.py
/// が担当。Flutterアプリからは読み取り専用)。
/// 現場では作業報告書の「伝票No」欄をAI-OCRで読み取り、このキャッシュと照合することで、
/// 顧客名・店舗名・作業内容等の重複入力を避けることができる。
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
    );
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
  Map<String, String> toWorkReportFieldValues() {
    return {
      'client_name': clientName,
      'work_content': workContent.isNotEmpty ? workContent : workContentDetail,
      'equipment_model': modelSerial,
      'pro_wan_ref_number': jobManagementNumber,
      'non_se_refrigerant_type': refrigerantType1,
      'non_se_refrigerant_amount_kg': refrigerantAmount1,
    };
  }
}
