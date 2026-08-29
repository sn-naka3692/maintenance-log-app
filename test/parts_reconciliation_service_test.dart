import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/models/billing_part_record.dart';
import 'package:flutter_app/models/part_used.dart';
import 'package:flutter_app/models/parts_reconciliation_result.dart';
import 'package:flutter_app/models/store_system_report.dart';
import 'package:flutter_app/models/work_report.dart';
import 'package:flutter_app/services/parts_reconciliation_service.dart';

/// PartsReconciliationService(部品情報突合ロジック)のテスト。
///
/// 【検証観点】
/// - 受付Noの大文字小文字・前後空白の正規化が正しく行われるか。
/// - 双方に部品記録がある/ない/一致する/しないの各パターンで正しい
///   PartsMatchStatusに判定されるか。
/// - 同一受付Noに複数のWorkReportがある場合、partsUsedが合算されて
///   比較されるか。
/// - 受付Noに対応するWorkReportが見つからない場合の判定。
void main() {
  WorkReport buildReport({
    required String id,
    required String receiptNumber,
    List<PartUsed>? partsUsed,
  }) {
    return WorkReport(
      id: id,
      authorId: 'u1',
      authorName: 'テスト太郎',
      clientName: 'テスト店舗',
      visitDate: DateTime(2026, 8, 10),
      startTime: DateTime(2026, 8, 10, 10, 0),
      endTime: DateTime(2026, 8, 10, 11, 0),
      responseType: ResponseType.repair,
      workContent: 'テスト作業',
      storeSystemReportCopy: StoreSystemReport(receiptNumber: receiptNumber),
      partsUsed: partsUsed ?? [],
      createdAt: DateTime(2026, 8, 10),
      updatedAt: DateTime(2026, 8, 10),
    );
  }

  BillingPartRecord buildBilling({
    required String receiptNumber,
    List<BillingPartRecordItem>? parts,
  }) {
    return BillingPartRecord(
      receiptNumber: receiptNumber,
      storeName: 'テスト店舗',
      storeNumber: '00123',
      repairDate: DateTime(2026, 8, 10),
      equipmentName: '冷凍ショーケース',
      parts: parts ?? [],
    );
  }

  test('受付Noが完全一致し、部品名も一致する場合はmatched', () {
    final billing = buildBilling(
      receiptNumber: '2606sa0000356185',
      parts: const [BillingPartRecordItem(name: 'コンプレッサー', quantity: 1)],
    );
    final report = buildReport(
      id: 'r1',
      receiptNumber: '2606SA0000356185', // 大文字違い
      partsUsed: [PartUsed(name: 'コンプレッサー', quantity: 1)],
    );

    final results = PartsReconciliationService.reconcile(
      billingRecords: [billing],
      allReports: [report],
    );

    expect(results.length, 1);
    expect(results.first.status, PartsMatchStatus.matched);
    expect(results.first.matchedWorkReportId, 'r1');
  });

  test('請求明細に部品計上があるが現場記録がない場合はmissingOnSite', () {
    final billing = buildBilling(
      receiptNumber: 'R-001',
      parts: const [BillingPartRecordItem(name: 'ファンモーター', quantity: 1)],
    );
    final report = buildReport(id: 'r2', receiptNumber: 'R-001', partsUsed: []);

    final results = PartsReconciliationService.reconcile(
      billingRecords: [billing],
      allReports: [report],
    );

    expect(results.first.status, PartsMatchStatus.missingOnSite);
  });

  test('現場記録があるが請求明細に部品計上がない場合はmissingOnBilling', () {
    final billing = buildBilling(receiptNumber: 'R-002', parts: const []);
    final report = buildReport(
      id: 'r3',
      receiptNumber: 'R-002',
      partsUsed: [PartUsed(name: '基板', quantity: 1)],
    );

    final results = PartsReconciliationService.reconcile(
      billingRecords: [billing],
      allReports: [report],
    );

    expect(results.first.status, PartsMatchStatus.missingOnBilling);
  });

  test('双方に部品記録はあるが部品名が食い違う場合はmismatch', () {
    final billing = buildBilling(
      receiptNumber: 'R-003',
      parts: const [BillingPartRecordItem(name: 'コンプレッサー', quantity: 1)],
    );
    final report = buildReport(
      id: 'r4',
      receiptNumber: 'R-003',
      partsUsed: [PartUsed(name: 'ファンモーター', quantity: 1)],
    );

    final results = PartsReconciliationService.reconcile(
      billingRecords: [billing],
      allReports: [report],
    );

    expect(results.first.status, PartsMatchStatus.mismatch);
  });

  test('双方とも部品記録がない場合はmatched(交換を伴わない対応)', () {
    final billing = buildBilling(receiptNumber: 'R-004', parts: const []);
    final report = buildReport(id: 'r5', receiptNumber: 'R-004', partsUsed: []);

    final results = PartsReconciliationService.reconcile(
      billingRecords: [billing],
      allReports: [report],
    );

    expect(results.first.status, PartsMatchStatus.matched);
  });

  test('受付Noに対応するWorkReportが見つからない場合はreportNotFound', () {
    final billing = buildBilling(
      receiptNumber: 'R-999',
      parts: const [BillingPartRecordItem(name: 'コンプレッサー', quantity: 1)],
    );

    final results = PartsReconciliationService.reconcile(
      billingRecords: [billing],
      allReports: const [],
    );

    expect(results.first.status, PartsMatchStatus.reportNotFound);
    expect(results.first.matchedWorkReportId, isNull);
  });

  test('同一受付Noに複数のWorkReportがある場合、partsUsedを合算して比較する', () {
    final billing = buildBilling(
      receiptNumber: 'R-005',
      parts: const [
        BillingPartRecordItem(name: 'コンプレッサー', quantity: 1),
        BillingPartRecordItem(name: 'ファンモーター', quantity: 1),
      ],
    );
    final report1 = buildReport(
      id: 'r6a',
      receiptNumber: 'R-005',
      partsUsed: [PartUsed(name: 'コンプレッサー', quantity: 1)],
    );
    final report2 = buildReport(
      id: 'r6b',
      receiptNumber: 'R-005',
      partsUsed: [PartUsed(name: 'ファンモーター', quantity: 1)],
    );

    final results = PartsReconciliationService.reconcile(
      billingRecords: [billing],
      allReports: [report1, report2],
    );

    expect(results.first.status, PartsMatchStatus.matched);
    expect(results.first.sitePartsRecorded.length, 2);
  });

  test('部品名の全角/半角スペース・大文字小文字の表記ゆれを吸収する', () {
    final billing = buildBilling(
      receiptNumber: 'R-006',
      parts: const [BillingPartRecordItem(name: 'ファン　モーター', quantity: 1)],
    );
    final report = buildReport(
      id: 'r7',
      receiptNumber: 'R-006',
      partsUsed: [PartUsed(name: 'ファンモーター', quantity: 1)],
    );

    final results = PartsReconciliationService.reconcile(
      billingRecords: [billing],
      allReports: [report],
    );

    expect(results.first.status, PartsMatchStatus.matched);
  });
}
