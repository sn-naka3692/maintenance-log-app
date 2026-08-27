/// プロワン管轄案件(SE店舗以外)専用の案件詳細情報。
///
/// 【設計方針・2026-08-28改訂】
/// 従来はプロワンCSVキャッシュ(ProwanJobCache)から照合結果を反映する
/// 受け皿として設計されていた(store_address/department/system_number/
/// trouble_content/trouble_equipment/cause/request_content/visit_result/
/// future_plan/technician_name/visit_date の12項目)。
///
/// しかし、現場の日報入力(スキャン)は事務所側のCSVエクスポートより
/// 時系列的に先行するため、リアルタイムのCSV照合は原理的に成立しない
/// (該当データがまだCSVに存在しない、または既にエクスポート対象外に
/// なっている)ことが判明した。作業報告書PDF自体に必要な情報が全て
/// 印字されているため、AI-OCRで直接読み取る設計に変更した。
///
/// この変更に伴い、フィールド構成も見直した:
/// - trouble_content(障害内容)/trouble_equipment(障害機器):
///   PDF上に対応するラベル・印字が存在しない(CSVにのみ存在する
///   事務所側の受付分類メモだったため)ため廃止。
/// - visit_date(訪問日): PDFには「受付日」としてのみ印字されており、
///   CSVの visit_date は実データが常に空欄だったため receiptDate に
///   置き換え。
/// - case_no(ケースNo)を新規追加(PDFに印字されている)。
/// - client_name(得意先名/法人名)を新規追加(PDFに印字されている。
///   店舗名(WorkReport.clientName/店舗マスタ)とは別の、法人・得意先
///   単位の名称のため、混同を避けてここに保持する)。
/// - refrigerant_type(冷媒の種類)/refrigerant_amount(冷媒量)は、
///   既にWorkReport本体にnonSeRefrigerantType/nonSeRefrigerantAmountKg
///   という反映先(表示・CSV/Excel/PDF出力とも対応済み)があるため、
///   重複を避けてそちらへ統合。ここでは持たない。
/// - department/system_number/equipment_location/cause/request_content/
///   visit_result/future_plan/technician_name は維持(全てPDFに印字)。
/// - store_address(店舗住所)はOCR対象外(冷媒充填・回収証明書欄の
///   「機器の管理者住所」は別紙扱いのため)。引き続き手入力項目として残す。
class ProWanReportDetail {
  String storeAddress; // 店舗住所(冷媒充填・回収証明書欄の「機器の管理者住所」・手入力)
  String clientName; // 得意先名(法人名。店舗名とは別概念)
  String receiptDate; // 受付日
  String department; // 部門
  String systemNumber; // 系統番号・名
  String caseNo; // ケースNo
  String equipmentLocation; // 修理機器・場所
  String requestContent; // ご依頼内容
  String cause; // 原因(故障箇所)
  String visitResult; // 訪問結果
  String futurePlan; // 未完了の場合の今後の予定
  String technicianName; // 技術者氏名(冷媒充填・回収証明書欄)

  ProWanReportDetail({
    this.storeAddress = '',
    this.clientName = '',
    this.receiptDate = '',
    this.department = '',
    this.systemNumber = '',
    this.caseNo = '',
    this.equipmentLocation = '',
    this.requestContent = '',
    this.cause = '',
    this.visitResult = '',
    this.futurePlan = '',
    this.technicianName = '',
  });

  bool get isEmpty =>
      storeAddress.isEmpty &&
      clientName.isEmpty &&
      receiptDate.isEmpty &&
      department.isEmpty &&
      systemNumber.isEmpty &&
      caseNo.isEmpty &&
      equipmentLocation.isEmpty &&
      requestContent.isEmpty &&
      cause.isEmpty &&
      visitResult.isEmpty &&
      futurePlan.isEmpty &&
      technicianName.isEmpty;

  Map<String, dynamic> toMap() {
    return {
      'store_address': storeAddress,
      'client_name': clientName,
      'receipt_date': receiptDate,
      'department': department,
      'system_number': systemNumber,
      'case_no': caseNo,
      'equipment_location': equipmentLocation,
      'request_content': requestContent,
      'cause': cause,
      'visit_result': visitResult,
      'future_plan': futurePlan,
      'technician_name': technicianName,
    };
  }

  factory ProWanReportDetail.fromMap(Map<String, dynamic>? map) {
    if (map == null) return ProWanReportDetail();
    return ProWanReportDetail(
      storeAddress: map['store_address'] as String? ?? '',
      clientName: map['client_name'] as String? ?? '',
      // 【後方互換】旧フィールド visit_date に受付日相当の値が入っている
      // 既存データを引き続き表示できるよう、receipt_date が空の場合は
      // visit_date を代替として読む。
      receiptDate:
          map['receipt_date'] as String? ?? map['visit_date'] as String? ?? '',
      department: map['department'] as String? ?? '',
      systemNumber: map['system_number'] as String? ?? '',
      caseNo: map['case_no'] as String? ?? '',
      equipmentLocation: map['equipment_location'] as String? ?? '',
      requestContent: map['request_content'] as String? ?? '',
      cause: map['cause'] as String? ?? '',
      visitResult: map['visit_result'] as String? ?? '',
      futurePlan: map['future_plan'] as String? ?? '',
      // 【後方互換】旧フィールド technician_name はそのまま引き継ぐ。
      technicianName: map['technician_name'] as String? ?? '',
    );
  }
}
