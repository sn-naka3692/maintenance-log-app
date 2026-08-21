/// コンビニ側システム入力控え
///
/// コンビニ各社の業務システムはデータ抽出ができないため、
/// 社内保管用に同じ内容をこの構造化フォームへ控えとして記録する。
/// 項目は「SE.xlsx」(コンビニ側システムの入力項目一覧)に準拠。
/// 自由記述だと項目の記入漏れが起きやすいため、項目ごとに入力欄を分ける。
class StoreSystemReport {
  String receiptNumber; // 弊社受付No.
  String refrigerantType; // 冷媒種類
  String refrigerantAmount; // 充填量
  String requestContent; // 依頼内容
  String equipmentName; // 設備名称
  String maker; // メーカー
  String modelNumber; // 型式
  String treatmentContent; // 処置内容
  String part; // 部位
  String detailPart; // 詳細部位
  String phenomenon; // 事象
  String phenomenonNote; // 事象補足
  String cause; // 原因
  String treatmentContent2; // 処置内容2
  String part1; // 部品1
  String part2; // 部品2
  String part3; // 部品3
  String part4; // 部品4
  String part5; // 部品5
  String remarks; // 備考

  // 以下、作業報告書AIスキャン(Azure Document Intelligence)機能で
  // 追加された項目。既存データにはないため空文字がデフォルト。
  String storeNumber; // 店番(スキャン取り込み用)
  String scannedAddress; // 住所(スキャン取り込み用)
  String scannedTel; // TEL(スキャン取り込み用)
  String machineNo; // 機番
  String assetNo; // 資産管理No
  String barcode; // ランダムバーコード
  String deliveryDate; // 納品日
  String workerName; // 作業者氏名(報告書に印字された氏名の控え)
  String recoveryAmount; // 冷媒回収量(kg)

  StoreSystemReport({
    this.receiptNumber = '',
    this.refrigerantType = '',
    this.refrigerantAmount = '',
    this.requestContent = '',
    this.equipmentName = '',
    this.maker = '',
    this.modelNumber = '',
    this.treatmentContent = '',
    this.part = '',
    this.detailPart = '',
    this.phenomenon = '',
    this.phenomenonNote = '',
    this.cause = '',
    this.treatmentContent2 = '',
    this.part1 = '',
    this.part2 = '',
    this.part3 = '',
    this.part4 = '',
    this.part5 = '',
    this.remarks = '',
    this.storeNumber = '',
    this.scannedAddress = '',
    this.scannedTel = '',
    this.machineNo = '',
    this.assetNo = '',
    this.barcode = '',
    this.deliveryDate = '',
    this.workerName = '',
    this.recoveryAmount = '',
  });

  /// すべての項目が空かどうか(未入力判定用)
  bool get isEmpty =>
      receiptNumber.isEmpty &&
      refrigerantType.isEmpty &&
      refrigerantAmount.isEmpty &&
      requestContent.isEmpty &&
      equipmentName.isEmpty &&
      maker.isEmpty &&
      modelNumber.isEmpty &&
      treatmentContent.isEmpty &&
      part.isEmpty &&
      detailPart.isEmpty &&
      phenomenon.isEmpty &&
      phenomenonNote.isEmpty &&
      cause.isEmpty &&
      treatmentContent2.isEmpty &&
      part1.isEmpty &&
      part2.isEmpty &&
      part3.isEmpty &&
      part4.isEmpty &&
      part5.isEmpty &&
      remarks.isEmpty;

  Map<String, dynamic> toMap() {
    return {
      'receipt_number': receiptNumber,
      'refrigerant_type': refrigerantType,
      'refrigerant_amount': refrigerantAmount,
      'request_content': requestContent,
      'equipment_name': equipmentName,
      'maker': maker,
      'model_number': modelNumber,
      'treatment_content': treatmentContent,
      'part': part,
      'detail_part': detailPart,
      'phenomenon': phenomenon,
      'phenomenon_note': phenomenonNote,
      'cause': cause,
      'treatment_content2': treatmentContent2,
      'part1': part1,
      'part2': part2,
      'part3': part3,
      'part4': part4,
      'part5': part5,
      'remarks': remarks,
      'store_number': storeNumber,
      'scanned_address': scannedAddress,
      'scanned_tel': scannedTel,
      'machine_no': machineNo,
      'asset_no': assetNo,
      'barcode': barcode,
      'delivery_date': deliveryDate,
      'worker_name': workerName,
      'recovery_amount': recoveryAmount,
    };
  }

  factory StoreSystemReport.fromMap(Map<String, dynamic>? map) {
    if (map == null) return StoreSystemReport();
    return StoreSystemReport(
      receiptNumber: map['receipt_number'] as String? ?? '',
      refrigerantType: map['refrigerant_type'] as String? ?? '',
      refrigerantAmount: map['refrigerant_amount'] as String? ?? '',
      requestContent: map['request_content'] as String? ?? '',
      equipmentName: map['equipment_name'] as String? ?? '',
      maker: map['maker'] as String? ?? '',
      modelNumber: map['model_number'] as String? ?? '',
      treatmentContent: map['treatment_content'] as String? ?? '',
      part: map['part'] as String? ?? '',
      detailPart: map['detail_part'] as String? ?? '',
      phenomenon: map['phenomenon'] as String? ?? '',
      phenomenonNote: map['phenomenon_note'] as String? ?? '',
      cause: map['cause'] as String? ?? '',
      treatmentContent2: map['treatment_content2'] as String? ?? '',
      part1: map['part1'] as String? ?? '',
      part2: map['part2'] as String? ?? '',
      part3: map['part3'] as String? ?? '',
      part4: map['part4'] as String? ?? '',
      part5: map['part5'] as String? ?? '',
      remarks: map['remarks'] as String? ?? '',
      storeNumber: map['store_number'] as String? ?? '',
      scannedAddress: map['scanned_address'] as String? ?? '',
      scannedTel: map['scanned_tel'] as String? ?? '',
      machineNo: map['machine_no'] as String? ?? '',
      assetNo: map['asset_no'] as String? ?? '',
      barcode: map['barcode'] as String? ?? '',
      deliveryDate: map['delivery_date'] as String? ?? '',
      workerName: map['worker_name'] as String? ?? '',
      recoveryAmount: map['recovery_amount'] as String? ?? '',
    );
  }
}
