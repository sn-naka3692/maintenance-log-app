/// プロワン管轄案件(SE店舗以外)専用の案件詳細情報。
///
/// 【背景・2026-08】プロワンCSVキャッシュ(ProwanJobCache)には店舗住所・
/// 部門・系統番号・障害内容・障害機器・原因・依頼内容・訪問結果・今後の
/// 予定・技術者氏名・訪問日など、20項目近い情報が保持されているが、
/// これまでアプリ側の反映先はclient_name/work_content/equipment_model/
/// 冷媒情報の4~5項目のみで、残りの項目は照合しても捨てられていた。
/// SE店舗には「コンビニ側システム入力控え」(StoreSystemReport)という
/// 20項目の専用フォームが用意されているのに対し、プロワン管轄案件には
/// 同等の受け皿が存在しなかったことが「スキャンしてもデータが反映
/// されない」という不具合報告の実態だった。
///
/// このモデルはその受け皿として、ProwanJobCacheの未反映項目をすべて
/// 保持する。SE店舗のStoreSystemReportと同様、社内保存用の構造化
/// フォームであり、プロワン管轄案件かつ現場作業(修理・故障対応)の
/// 場合のみ画面に表示する。
class ProWanReportDetail {
  String storeAddress; // 店舗住所
  String department; // 部門
  String systemNumber; // 系統番号・名
  String equipmentLocation; // 修理機器・場所
  String troubleContent; // 障害内容
  String troubleEquipment; // 障害機器
  String cause; // 原因(故障箇所)
  String requestContent; // ご依頼内容
  String visitResult; // 訪問結果
  String futurePlan; // 未完了の場合の今後の予定
  String technicianName; // 技術者氏名(プロワン側記録の控え)
  String visitDate; // 訪問日(プロワンCSV上の文字列のまま保持)

  ProWanReportDetail({
    this.storeAddress = '',
    this.department = '',
    this.systemNumber = '',
    this.equipmentLocation = '',
    this.troubleContent = '',
    this.troubleEquipment = '',
    this.cause = '',
    this.requestContent = '',
    this.visitResult = '',
    this.futurePlan = '',
    this.technicianName = '',
    this.visitDate = '',
  });

  bool get isEmpty =>
      storeAddress.isEmpty &&
      department.isEmpty &&
      systemNumber.isEmpty &&
      equipmentLocation.isEmpty &&
      troubleContent.isEmpty &&
      troubleEquipment.isEmpty &&
      cause.isEmpty &&
      requestContent.isEmpty &&
      visitResult.isEmpty &&
      futurePlan.isEmpty &&
      technicianName.isEmpty &&
      visitDate.isEmpty;

  Map<String, dynamic> toMap() {
    return {
      'store_address': storeAddress,
      'department': department,
      'system_number': systemNumber,
      'equipment_location': equipmentLocation,
      'trouble_content': troubleContent,
      'trouble_equipment': troubleEquipment,
      'cause': cause,
      'request_content': requestContent,
      'visit_result': visitResult,
      'future_plan': futurePlan,
      'technician_name': technicianName,
      'visit_date': visitDate,
    };
  }

  factory ProWanReportDetail.fromMap(Map<String, dynamic>? map) {
    if (map == null) return ProWanReportDetail();
    return ProWanReportDetail(
      storeAddress: map['store_address'] as String? ?? '',
      department: map['department'] as String? ?? '',
      systemNumber: map['system_number'] as String? ?? '',
      equipmentLocation: map['equipment_location'] as String? ?? '',
      troubleContent: map['trouble_content'] as String? ?? '',
      troubleEquipment: map['trouble_equipment'] as String? ?? '',
      cause: map['cause'] as String? ?? '',
      requestContent: map['request_content'] as String? ?? '',
      visitResult: map['visit_result'] as String? ?? '',
      futurePlan: map['future_plan'] as String? ?? '',
      technicianName: map['technician_name'] as String? ?? '',
      visitDate: map['visit_date'] as String? ?? '',
    );
  }
}
