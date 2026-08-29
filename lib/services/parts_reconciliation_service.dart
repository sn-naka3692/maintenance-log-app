import '../models/billing_part_record.dart';
import '../models/part_used.dart';
import '../models/parts_reconciliation_result.dart';
import '../models/work_report.dart';

/// 「弊社受付No」をキーに、SDRS請求明細(BillingPartRecord)と
/// アプリ側の現場記録(WorkReport.partsUsed)の部品情報を突き合わせる。
///
/// 【設計方針・2026-08-28】
/// - 突合は「弊社受付No」の完全一致(大文字小文字・前後空白を無視)で行う。
///   同じ受付Noを持つWorkReportが複数ある場合(共同作業等で分割入力された
///   ケースを想定し)、対象となる全WorkReportの partsUsed を合算してから
///   比較する。
/// - 部品名の一致判定は表記ゆれ(全角/半角スペース、大文字小文字)を
///   ある程度吸収した上で「名前の集合が一致するか」で判定する。数量まで
///   厳密に一致させると現場入力の粒度差(補足欄に書いている等)で誤検知
///   が増えるため、まずは「名前ベースの一致/不一致」を基本方針とする。
class PartsReconciliationService {
  PartsReconciliationService._();

  static List<PartsReconciliationResult> reconcile({
    required List<BillingPartRecord> billingRecords,
    required List<WorkReport> allReports,
  }) {
    // 受付No(正規化済み) -> 該当するWorkReport一覧のインデックスを構築。
    final Map<String, List<WorkReport>> reportsByReceipt = {};
    for (final r in allReports) {
      final receipt = r.storeSystemReportCopy.receiptNumber.trim().toUpperCase();
      if (receipt.isEmpty) continue;
      reportsByReceipt.putIfAbsent(receipt, () => []).add(r);
    }

    final results = <PartsReconciliationResult>[];
    for (final billing in billingRecords) {
      final key = billing.normalizedReceiptNumber;
      final matchedReports = reportsByReceipt[key];

      final billingPartsText = billing.parts
          .map((p) => '${p.name}×${p.quantity}')
          .toList();

      if (matchedReports == null || matchedReports.isEmpty) {
        results.add(
          PartsReconciliationResult(
            receiptNumber: billing.receiptNumber,
            storeName: billing.storeName,
            status: PartsMatchStatus.reportNotFound,
            billingParts: billingPartsText,
            sitePartsRecorded: const [],
          ),
        );
        continue;
      }

      // 同じ受付Noの全WorkReportのpartsUsedを合算する。
      final List<PartUsed> combinedSiteParts = [
        for (final r in matchedReports) ...r.partsUsed,
      ];
      final sitePartsText = combinedSiteParts
          .map((p) => '${p.name}×${p.quantity}')
          .toList();

      final status = _judgeStatus(
        billingParts: billing.parts,
        siteParts: combinedSiteParts,
      );

      results.add(
        PartsReconciliationResult(
          receiptNumber: billing.receiptNumber,
          storeName: billing.storeName,
          status: status,
          billingParts: billingPartsText,
          sitePartsRecorded: sitePartsText,
          matchedWorkReportId: matchedReports.first.id,
          matchedAuthorName: matchedReports.first.authorName,
        ),
      );
    }

    return results;
  }

  static PartsMatchStatus _judgeStatus({
    required List<BillingPartRecordItem> billingParts,
    required List<PartUsed> siteParts,
  }) {
    final billingHasParts = billingParts.isNotEmpty;
    final siteHasParts = siteParts.isNotEmpty;

    if (!billingHasParts && !siteHasParts) {
      // どちらも部品使用なし(交換を伴わない対応) -> 一致とみなす。
      return PartsMatchStatus.matched;
    }
    if (billingHasParts && !siteHasParts) {
      return PartsMatchStatus.missingOnSite;
    }
    if (!billingHasParts && siteHasParts) {
      return PartsMatchStatus.missingOnBilling;
    }

    final billingNames = billingParts.map((p) => _normalizeName(p.name)).toSet();
    final siteNames = siteParts.map((p) => _normalizeName(p.name)).toSet();

    if (billingNames.length == siteNames.length &&
        billingNames.containsAll(siteNames)) {
      return PartsMatchStatus.matched;
    }
    return PartsMatchStatus.mismatch;
  }

  /// 部品名の表記ゆれ(全角/半角スペース除去・大文字小文字統一)を
  /// 吸収するための正規化。
  static String _normalizeName(String name) {
    return name
        .trim()
        .replaceAll('\u3000', '')
        .replaceAll(' ', '')
        .toUpperCase();
  }
}
