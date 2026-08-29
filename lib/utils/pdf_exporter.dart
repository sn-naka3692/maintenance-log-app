import 'dart:typed_data';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../models/part_used.dart';
import '../models/prowan_report_detail.dart';
import '../models/store_system_report.dart';
import '../models/work_report.dart';

/// 日報・ナレッジ検索結果をA4サイズのPDF帳票に変換し、共有(ダウンロード/
/// 送信)・端末保存するユーティリティ。
///
/// [csv_exporter.dart] / [excel_exporter.dart] と同じ設計方針
/// (buildXxx -> exportAndShare / exportAndSaveToDevice の2ルート提供)を
/// 踏襲している。日本語を表示するため、Noto Sans JPフォントを埋め込む。
class PdfExporter {
  static final DateFormat _dateFmt = DateFormat('yyyy/MM/dd');
  static final DateFormat _timeFmt = DateFormat('HH:mm');
  static final DateFormat _dateTimeFmt = DateFormat('yyyy/MM/dd HH:mm');

  static pw.Font? _regularFont;
  static pw.Font? _boldFont;

  static Future<void> _ensureFontsLoaded() async {
    if (_regularFont != null && _boldFont != null) return;
    final regularData = await rootBundle.load(
      'assets/fonts/NotoSansJP-Regular.ttf',
    );
    final boldData = await rootBundle.load('assets/fonts/NotoSansJP-Bold.ttf');
    _regularFont = pw.Font.ttf(regularData);
    _boldFont = pw.Font.ttf(boldData);
  }

  static String _partsText(WorkReport r) {
    return r.partsUsed.map(_singlePartText).join(' / ');
  }

  /// 部品1件分の表示テキストを組み立てる(図番・補足があれば併記)。
  static String _singlePartText(PartUsed p) {
    final hasPartNumber = p.partNumber != null && p.partNumber!.trim().isNotEmpty;
    final hasNote = p.note != null && p.note!.trim().isNotEmpty;
    final extras = [
      if (hasPartNumber) '図番:${p.partNumber}',
      if (hasNote) p.note!,
    ].join(',');
    return extras.isEmpty
        ? '${p.name}×${p.quantity}'
        : '${p.name}×${p.quantity}($extras)';
  }

  /// コンビニ側システム入力控えの「冷媒種類」表示テキスト。
  /// 日報詳細画面と同じく、SE店舗の未充填統一表記(NONE等)は
  /// 「未充填」とわかりやすく変換する。
  static String _ssrRefrigerantType(StoreSystemReport ssr) {
    if (ssr.refrigerantType.isNotEmpty &&
        WorkReport.isNotFilledType(ssr.refrigerantType)) {
      return '未充填';
    }
    return ssr.refrigerantType;
  }

  /// コンビニ側システム入力控えの「充填量」表示テキスト。
  static String _ssrRefrigerantAmount(StoreSystemReport ssr) {
    if (ssr.refrigerantAmount.isNotEmpty &&
        WorkReport.isNotFilledAmount(ssr.refrigerantAmount)) {
      return '未充填(0kg)';
    }
    return ssr.refrigerantAmount;
  }

  /// コンビニ側システム入力控え(StoreSystemReport)の項目一覧を
  /// 日報詳細画面(report_detail_screen.dart)と同じ項目・並び順で返す
  /// (値が空の項目は呼び出し側でフィルタする)。
  static List<MapEntry<String, String>> _ssrRows(StoreSystemReport ssr) {
    return [
      MapEntry('弊社受付No.', ssr.receiptNumber),
      MapEntry('店番', ssr.storeNumber),
      MapEntry('住所(報告書記載)', ssr.scannedAddress),
      MapEntry('TEL(報告書記載)', ssr.scannedTel),
      MapEntry('冷媒種類', _ssrRefrigerantType(ssr)),
      MapEntry('充填量', _ssrRefrigerantAmount(ssr)),
      MapEntry('冷媒回収量', ssr.recoveryAmount),
      MapEntry('依頼内容', ssr.requestContent),
      MapEntry('設備名称', ssr.equipmentName),
      MapEntry('メーカー', ssr.maker),
      MapEntry('型式', ssr.modelNumber),
      MapEntry('機番', ssr.machineNo),
      MapEntry('資産管理No', ssr.assetNo),
      MapEntry('バーコード', ssr.barcode),
      MapEntry('納品日', ssr.deliveryDate),
      MapEntry('作業者氏名', ssr.workerName),
      MapEntry('部位', ssr.part),
      MapEntry('詳細部位', ssr.detailPart),
      MapEntry('事象', ssr.phenomenon),
      MapEntry('事象補足', ssr.phenomenonNote),
      MapEntry('原因', ssr.cause),
      MapEntry('処置内容', ssr.treatmentContent),
      MapEntry('処置内容2', ssr.treatmentContent2),
      MapEntry('部品1', ssr.part1),
      MapEntry('部品2', ssr.part2),
      MapEntry('部品3', ssr.part3),
      MapEntry('部品4', ssr.part4),
      MapEntry('部品5', ssr.part5),
      MapEntry('備考', ssr.remarks),
    ].where((e) => e.value.trim().isNotEmpty).toList();
  }

  /// プロワン管轄案件詳細(ProWanReportDetail)の項目一覧を
  /// 日報詳細画面(report_detail_screen.dart)と同じ項目・並び順で返す
  /// (値が空の項目は呼び出し側でフィルタする)。
  static List<MapEntry<String, String>> _pwRows(ProWanReportDetail pwDetail) {
    return [
      MapEntry('店舗住所', pwDetail.storeAddress),
      MapEntry('得意先名', pwDetail.clientName),
      MapEntry('受付日', pwDetail.receiptDate),
      MapEntry('部門', pwDetail.department),
      MapEntry('系統番号・名', pwDetail.systemNumber),
      MapEntry('ケースNo', pwDetail.caseNo),
      MapEntry('修理機器・場所', pwDetail.equipmentLocation),
      MapEntry('ご依頼内容', pwDetail.requestContent),
      MapEntry('原因', pwDetail.cause),
      MapEntry('訪問結果', pwDetail.visitResult),
      MapEntry('今後の予定', pwDetail.futurePlan),
      MapEntry('技術者氏名', pwDetail.technicianName),
    ].where((e) => e.value.trim().isNotEmpty).toList();
  }

  /// 日報一覧からA4帳票形式のPDFバイト列を生成する。
  ///
  /// 1件ごとに見出し付きのカードを並べ、A4縦向きで複数件をまとめて
  /// 1つのPDFに出力する(件数が多い場合は自動的に複数ページに分かれる)。
  static Future<Uint8List> buildPdfBytes(
    List<WorkReport> reports, {
    String title = '日報・ナレッジ 出力レポート',
  }) async {
    await _ensureFontsLoaded();

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: _regularFont!, bold: _boldFont!),
    );

    const primaryColor = PdfColor.fromInt(0xFF1565EF);
    final now = DateTime.now();

    pw.Widget buildHeader(pw.Context context) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  font: _boldFont,
                  fontSize: 16,
                  color: primaryColor,
                ),
              ),
              pw.Text(
                '出力日時: ${_dateTimeFmt.format(now)}',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '対象件数: ${reports.length}件',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 6),
          pw.Divider(color: primaryColor, thickness: 1.2),
        ],
      );
    }

    pw.Widget buildFooter(pw.Context context) {
      return pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            '${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ],
      );
    }

    pw.Widget infoRow(String label, String value) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 78,
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  font: _boldFont,
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
              ),
            ),
            pw.Expanded(
              child: pw.Text(
                value.isEmpty ? '-' : value,
                style: const pw.TextStyle(fontSize: 9.5),
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget buildReportCard(WorkReport r) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 10),
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.7),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  r.clientName.isEmpty ? '(訪問先未設定)' : r.clientName,
                  style: pw.TextStyle(
                    font: _boldFont,
                    fontSize: 12,
                    color: primaryColor,
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.blue50,
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(3),
                    ),
                  ),
                  child: pw.Text(
                    r.responseType.label,
                    style: pw.TextStyle(
                      font: _boldFont,
                      fontSize: 8.5,
                      color: primaryColor,
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Divider(color: PdfColors.grey300, thickness: 0.5),
            pw.SizedBox(height: 4),
            infoRow(
              '訪問日',
              '${_dateFmt.format(r.visitDate)}  ${_timeFmt.format(r.startTime)}〜${_timeFmt.format(r.endTime)}',
            ),
            infoRow('作成者', r.authorName),
            if (r.equipmentModel.trim().isNotEmpty)
              infoRow('機器型番', r.equipmentModel),
            if (r.workContent.trim().isNotEmpty)
              infoRow('作業内容', r.workContent),
            if (_partsText(r).trim().isNotEmpty)
              infoRow('使用部品', _partsText(r)),
            if (r.successPoints.trim().isNotEmpty)
              infoRow('うまくいったこと', r.successPoints),
            if (r.issuesPoints.trim().isNotEmpty)
              infoRow('課題・失敗・改善点', r.issuesPoints),
            if (r.tags.isNotEmpty) infoRow('タグ', r.tags.join(' / ')),
            if (r.notes.trim().isNotEmpty) infoRow('備考', r.notes),
            // 【追加】コンビニ側システム入力控え(StoreSystemReport)。
            // 日報詳細画面と同じ項目・並び順・未充填表記ルールで出力する。
            if (!r.storeSystemReportCopy.isEmpty) ...[
              pw.SizedBox(height: 6),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 3,
                ),
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                child: pw.Text(
                  'コンビニ側システム入力控え',
                  style: pw.TextStyle(
                    font: _boldFont,
                    fontSize: 9,
                    color: PdfColors.grey800,
                  ),
                ),
              ),
              pw.SizedBox(height: 4),
              for (final e in _ssrRows(r.storeSystemReportCopy))
                infoRow(e.key, e.value),
            ],
            // 【追加】プロワン管轄案件(SE店舗以外)の案件詳細
            // (ProWanReportDetail)。日報詳細画面と同じ項目・並び順で出力する。
            if (!r.proWanReportDetail.isEmpty) ...[
              pw.SizedBox(height: 6),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 3,
                ),
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                child: pw.Text(
                  'プロワン案件詳細',
                  style: pw.TextStyle(
                    font: _boldFont,
                    fontSize: 9,
                    color: PdfColors.grey800,
                  ),
                ),
              ),
              pw.SizedBox(height: 4),
              for (final e in _pwRows(r.proWanReportDetail))
                infoRow(e.key, e.value),
            ],
          ],
        ),
      );
    }

    // 1ページに全件詰め込むのではなく、pw.MultiPage側の自動改ページに任せる。
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 24),
        header: buildHeader,
        footer: buildFooter,
        build: (context) => [
          for (final r in reports) buildReportCard(r),
        ],
      ),
    );

    return doc.save();
  }

  /// PDFを生成し、share_plusでダウンロード/共有する。
  static Future<void> exportAndShare(
    List<WorkReport> reports, {
    String fileNamePrefix = '日報・ナレッジ',
  }) async {
    final bytes = await buildPdfBytes(reports, title: fileNamePrefix);
    final now = DateTime.now();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(now);
    final fileName = '${fileNamePrefix}_$stamp.pdf';

    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(bytes, name: fileName, mimeType: 'application/pdf'),
        ],
        fileNameOverrides: [fileName],
        subject: fileNamePrefix,
      ),
    );
  }

  /// PDFを生成し、端末のダウンロード/保存フォルダへ直接保存する。
  static Future<String> exportAndSaveToDevice(
    List<WorkReport> reports, {
    String fileNamePrefix = '日報・ナレッジ',
  }) async {
    final bytes = await buildPdfBytes(reports, title: fileNamePrefix);
    final now = DateTime.now();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(now);
    final fileName = '${fileNamePrefix}_$stamp';

    await FileSaver.instance.saveFile(
      name: fileName,
      bytes: bytes,
      fileExtension: 'pdf',
      mimeType: MimeType.pdf,
    );

    return '$fileName.pdf';
  }
}
