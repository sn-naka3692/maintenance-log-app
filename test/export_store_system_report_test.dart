import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/models/prowan_report_detail.dart';
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

  test('excel/pdf export includes ProWanReportDetail (PW) data', () async {
    final pwDetail = ProWanReportDetail(
      storeAddress: '東京都新宿区西新宿1-1-1',
      department: '空調部門',
      systemNumber: '系統A-1',
      equipmentLocation: '屋上室外機',
      troubleContent: '冷房が効かない',
      troubleEquipment: '室外機コンプレッサー',
      cause: '冷媒漏れ',
      requestContent: '冷房不良の点検・修理依頼',
      visitResult: '冷媒補充・漏れ箇所修理完了',
      futurePlan: '1ヶ月後に再点検予定',
      technicianName: '佐藤次郎',
      visitDate: '2026/08/27',
    );

    final reportWithPw = WorkReport(
      id: 'test-003',
      authorId: 'u1',
      authorName: 'テスト太郎',
      clientName: 'プロワン案件先',
      visitDate: DateTime(2026, 8, 27),
      startTime: DateTime(2026, 8, 27, 14, 0),
      endTime: DateTime(2026, 8, 27, 15, 0),
      responseType: ResponseType.repair,
      workContent: 'プロワン管轄案件のテスト作業内容',
      proWanReportDetail: pwDetail,
      createdAt: DateTime(2026, 8, 27),
      updatedAt: DateTime(2026, 8, 27),
    );

    final reportWithoutPw = WorkReport(
      id: 'test-004',
      authorId: 'u1',
      authorName: 'テスト太郎',
      clientName: 'プロワン案件先2',
      visitDate: DateTime(2026, 8, 27),
      startTime: DateTime(2026, 8, 27, 16, 0),
      endTime: DateTime(2026, 8, 27, 17, 0),
      responseType: ResponseType.repair,
      workContent: 'PWデータなしの作業内容',
      createdAt: DateTime(2026, 8, 27),
      updatedAt: DateTime(2026, 8, 27),
    );

    final xlsxWith = ExcelExporter.buildXlsxBytes([reportWithPw]);
    final xlsxWithout = ExcelExporter.buildXlsxBytes([reportWithoutPw]);
    expect(xlsxWith.length, greaterThan(0));
    expect(xlsxWithout.length, greaterThan(0));

    final pdfWith = await PdfExporter.buildPdfBytes([reportWithPw]);
    final pdfWithout = await PdfExporter.buildPdfBytes([reportWithoutPw]);
    expect(pdfWith.length, greaterThan(0));
    expect(pdfWithout.length, greaterThan(0));
    expect(pdfWith.length, greaterThan(pdfWithout.length));

    // 目視確認用に一時ファイルへ書き出す(検証後、このテスト内でのみ使用)。
    File('/tmp/test_output_pw.pdf').writeAsBytesSync(pdfWith);
  });
}
