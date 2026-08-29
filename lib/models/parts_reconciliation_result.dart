/// 部品情報突合(現場入力 vs SDRS請求明細)の結果1件分。
///
/// 【設計方針・2026-08-28】
/// 月末チェック(submission_check_record.dart)と同じ考え方で、
/// 「弊社受付No」をキーに、現場側(WorkReport.partsUsed)と
/// 請求明細側(BillingPartRecord)の部品情報を突き合わせる。
/// 完全一致までは求めず、まずは「現場側の記録漏れ・大きな乖離」を
/// 検知できることを優先したシンプルな判定にする。
enum PartsMatchStatus {
  /// 現場記録・請求明細の双方に部品情報があり、内容が一致(部品名の
  /// 表記ゆれ・順序違いは許容)。
  matched,

  /// 請求明細には部品代の計上があるが、現場側の日報に使用部品の記録が
  /// ない(=入力漏れの可能性が高い)。
  missingOnSite,

  /// 現場側には部品の記録があるが、請求明細には部品代の計上がない
  /// (=請求漏れ、または現場記録の誤りの可能性)。
  missingOnBilling,

  /// 双方に部品記録はあるが、部品名・数量が一致しない。
  mismatch,

  /// 請求明細の受付Noに対応する日報がアプリ側に見つからない
  /// (月末チェック機能でいう「未提出」に相当するケースを含む)。
  reportNotFound,
}

class PartsReconciliationResult {
  final String receiptNumber; // 弊社受付No.
  final String storeName; // 店舗名称(請求明細側)
  final PartsMatchStatus status;
  final List<String> billingParts; // 請求明細側の部品表示(名前×数量)
  final List<String> sitePartsRecorded; // 現場側の部品表示(名前×数量)
  final String? matchedWorkReportId; // 突合できた場合のWorkReportドキュメントID
  final String? matchedAuthorName; // 突合できた場合の日報作成者名(表示用)

  const PartsReconciliationResult({
    required this.receiptNumber,
    required this.storeName,
    required this.status,
    required this.billingParts,
    required this.sitePartsRecorded,
    this.matchedWorkReportId,
    this.matchedAuthorName,
  });

  Map<String, dynamic> toMap() {
    return {
      'receipt_number': receiptNumber,
      'store_name': storeName,
      'status': status.name,
      'billing_parts': billingParts,
      'site_parts_recorded': sitePartsRecorded,
      'matched_work_report_id': matchedWorkReportId,
      'matched_author_name': matchedAuthorName,
    };
  }

  factory PartsReconciliationResult.fromMap(Map<String, dynamic> map) {
    return PartsReconciliationResult(
      receiptNumber: map['receipt_number'] as String? ?? '',
      storeName: map['store_name'] as String? ?? '',
      status: PartsMatchStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => PartsMatchStatus.reportNotFound,
      ),
      billingParts: (map['billing_parts'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      sitePartsRecorded: (map['site_parts_recorded'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      matchedWorkReportId: map['matched_work_report_id'] as String?,
      matchedAuthorName: map['matched_author_name'] as String?,
    );
  }
}

extension PartsMatchStatusLabel on PartsMatchStatus {
  String get label {
    switch (this) {
      case PartsMatchStatus.matched:
        return '一致';
      case PartsMatchStatus.missingOnSite:
        return '現場記録なし(入力漏れ疑い)';
      case PartsMatchStatus.missingOnBilling:
        return '請求明細になし';
      case PartsMatchStatus.mismatch:
        return '内容不一致';
      case PartsMatchStatus.reportNotFound:
        return '該当日報が見つかりません';
    }
  }

  /// 要注意(現場での確認・対応が必要)な状態かどうか。
  bool get needsAttention => this != PartsMatchStatus.matched;
}
