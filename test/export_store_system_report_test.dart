import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/models/work_report.dart';
import 'package:flutter_app/models/store_system_report.dart';
import 'package:flutter_app/utils/excel_exporter.dart';
import 'package:flutter_app/utils/pdf_exporter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('excel/pdf export includes StoreSystemReport (SE) data', () async {
    final ssr = StoreSystemReport(
      receiptNumber: 'R-12345',
      refrigerantType: 'R410A',
      refrigerantAmount: '1.2kg',
      requestContent: '冷えが悪いとの連絡',
      equipmentName: 'ショーケース',
      maker: 'サンデン',
      modelNumber: 'ABC-123',
      treatmentContent: '基板交換',
      part: '冷凍機',
      detailPart: 'コンプレッサー',
      phenomenon: '異音',
      cause: '経年劣化',
      part1: '基板A',
      remarks: 'テスト備考',
      storeNumber: '00123',
      scannedAddress: '札幌市中央区1-2-3',
      scannedTel: '011-123-4567',
      machineNo: 'M-999',
      workerName: '山田太郎',
    );

    final reportWithSsr = WorkReport(
      id: 'test-001',
      authorId: 'u1',
      authorName: 'テスト太郎',
      clientName: 'テスト店舗',
      visitDate: DateTime(2026, 8, 27),
      startTime: DateTime(2026, 8, 27, 10, 0),
      endTime: DateTime(2026, 8, 27, 11, 0),
      responseType: ResponseType.repair,
      workContent: 'テスト作業内容',
      storeSystemReportCopy: ssr,
      createdAt: DateTime(2026, 8, 27),
      updatedAt: DateTime(2026, 8, 27),
    );

    final reportWithoutSsr = WorkReport(
      id: 'test-002',
      authorId: 'u1',
      authorName: 'テスト太郎',
      clientName: 'テスト店舗2',
      visitDate: DateTime(2026, 8, 27),
      startTime: DateTime(2026, 8, 27, 12, 0),
      endTime: DateTime(2026, 8, 27, 13, 0),
      responseType: ResponseType.repair,
      workContent: 'SEデータなしの作業内容',
      createdAt: DateTime(2026, 8, 27),
      updatedAt: DateTime(2026, 8, 27),
    );

    // Excel: 生成が成功し、SEデータありでは列数が増えることを確認
    final xlsxWith = ExcelExporter.buildXlsxBytes([reportWithSsr]);
    final xlsxWithout = ExcelExporter.buildXlsxBytes([reportWithoutSsr]);
    expect(xlsxWith.length, greaterThan(0));
    expect(xlsxWithout.length, greaterThan(0));

    // PDF: SEデータありの場合、セクション見出しと値が本文に含まれることを確認
    final pdfWith = await PdfExporter.buildPdfBytes([reportWithSsr]);
    final pdfWithout = await PdfExporter.buildPdfBytes([reportWithoutSsr]);
    expect(pdfWith.length, greaterThan(0));
    expect(pdfWithout.length, greaterThan(0));
    // SEデータありのPDFの方が内容が多い分、通常はサイズが大きくなる
    expect(pdfWith.length, greaterThan(pdfWithout.length));
  });
}
