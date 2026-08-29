/// SDRS(サンデン・リテールシステム)から毎月末頃に届く
/// 「SE請求明細書」Excelから読み取った、部品使用に関する1案件分の記録。
///
/// 【背景・2026-08-28】現場での作業報告書スキャン(OCR)や手入力による
/// 部品情報は、読み取り精度・入力漏れの限界がある。SDRS側の請求明細
/// (=部品代を実際に請求している以上、正確性が高い一次情報)と突き合わせる
/// ことで、次のようなズレを検知できる:
///   - 現場側で部品使用が未記録なのに、請求明細には部品代が計上されている
///     (入力漏れの可能性)
///   - 現場側と請求明細で部品名・数量が食い違っている(記録ミスの可能性)
/// このクラスは、その突合処理の入力データ(請求明細側)を表す。
class BillingPartRecordItem {
  final String name; // 使用部品名(請求明細のExcelそのまま)
  final int quantity; // 使用個数

  const BillingPartRecordItem({required this.name, required this.quantity});
}

class BillingPartRecord {
  final String receiptNumber; // 弊社受付No.(WorkReportのreceiptNumberと突合するキー)
  final String storeName; // 店舗名称(参考表示用)
  final String storeNumber; // 店番(参考表示用)
  final DateTime? repairDate; // 修理年月日(参考表示用)
  final String equipmentName; // 設備名称(参考表示用)
  final List<BillingPartRecordItem> parts; // この案件で計上された部品一覧

  const BillingPartRecord({
    required this.receiptNumber,
    required this.storeName,
    required this.storeNumber,
    required this.repairDate,
    required this.equipmentName,
    required this.parts,
  });

  /// 突合キーとして使う正規化済み受付No(大文字化・前後空白除去)。
  /// SDRS側は小文字混じり('2606sa0000356185')、アプリ側は大文字
  /// ('2608SA0000368867')で保存されているケースがあるため統一する。
  String get normalizedReceiptNumber => receiptNumber.trim().toUpperCase();

  bool get hasParts => parts.isNotEmpty;
}
