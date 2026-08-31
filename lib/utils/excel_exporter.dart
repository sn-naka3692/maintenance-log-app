import 'dart:typed_data';
import 'package:excel/excel.dart' as xls;
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../models/part_used.dart';
import '../models/store_system_report.dart';
import '../models/work_report.dart';

/// 日報・ナレッジ検索結果をA4サイズのExcelファイル(.xlsx)に変換し、
/// 共有(ダウンロード/送信)・端末保存するユーティリティ。
///
/// [csv_exporter.dart]と同じ設計方針(buildXxx -> exportAndShare /
/// exportAndSaveToDevice の2ルート提供)を踏襲している。
class ExcelExporter {
  static final DateFormat _dateFmt = DateFormat('yyyy/MM/dd');
  static final DateFormat _timeFmt = DateFormat('HH:mm');
  static final DateFormat _dateTimeFmt = DateFormat('yyyy/MM/dd HH:mm');

  static const List<String> _headers = [
    '日報ID',
    '作成者',
    '共同作業者',
    '訪問先(店舗)',
    '訪問日',
    '開始時刻',
    '終了時刻',
    '作業時間(分)',
    '対応区分',
    '機器型番',
    'プロワン管理番号',
    '作業内容',
    '使用部品',
    'うまくいったこと',
    '課題・失敗・改善点',
    'タグ',
    '備考',
    // 【追加】コンビニ側システム入力控え(StoreSystemReport)。
    // 日報詳細画面(report_detail_screen.dart)の「コンビニ側システム
    // 入力控え」セクションと同じ項目・並び順・表記ルールで出力する。
    'SE:弊社受付No.',
    'SE:店番',
    'SE:住所(報告書記載)',
    'SE:TEL(報告書記載)',
    'SE:冷媒種類',
    'SE:充填量',
    'SE:冷媒回収量',
    'SE:依頼内容',
    'SE:設備名称',
    'SE:メーカー',
    'SE:型式',
    'SE:機番',
    'SE:資産管理No',
    'SE:バーコード',
    'SE:納品日',
    'SE:作業者氏名',
    'SE:部位',
    'SE:詳細部位',
    'SE:事象',
    'SE:事象補足',
    'SE:原因',
    'SE:処置内容',
    'SE:処置内容2',
    'SE:部品1',
    'SE:部品2',
    'SE:部品3',
    'SE:部品4',
    'SE:部品5',
    'SE:備考',
    // 【追加】プロワン管轄案件(SE店舗以外)の案件詳細(ProWanReportDetail)。
    // 日報詳細画面(report_detail_screen.dart)の「プロワン案件詳細」
    // セクションと同じ項目・並び順で出力する。
    'PW:店舗住所',
    'PW:得意先名',
    'PW:受付日',
    'PW:部門',
    'PW:系統番号・名',
    'PW:ケースNo',
    'PW:修理機器・場所',
    'PW:ご依頼内容',
    'PW:原因',
    'PW:訪問結果',
    'PW:今後の予定',
    'PW:技術者氏名',
    '作成日時',
    '更新日時',
  ];

  static String _partsText(WorkReport r) {
    return r.partsUsed.map(_singlePartText).join(' / ');
  }

  /// 部品1件分の表示テキストを組み立てる(図番・補足があれば併記)。
  static String _singlePartText(PartUsed p) {
    final hasPartNumber =
        p.partNumber != null && p.partNumber!.trim().isNotEmpty;
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

  /// 日報一覧からExcelワークブック(xlsx)のバイト列を生成する。
  ///
  /// A4サイズ・横向きの印刷設定を行い、見出し行を固定・太字にする。
  static Uint8List buildXlsxBytes(List<WorkReport> reports) {
    final workbook = xls.Excel.createExcel();
    final sheetName = '日報一覧';
    final sheet = workbook[sheetName];
    // デフォルトで作成される "Sheet1" は不要なため削除する。
    if (workbook.sheets.containsKey('Sheet1') && sheetName != 'Sheet1') {
      workbook.delete('Sheet1');
    }

    final headerStyle = xls.CellStyle(
      bold: true,
      backgroundColorHex: xls.ExcelColor.fromHexString('#1565EF'),
      fontColorHex: xls.ExcelColor.fromHexString('#FFFFFF'),
      horizontalAlign: xls.HorizontalAlign.Center,
      verticalAlign: xls.VerticalAlign.Center,
    );

    for (var col = 0; col < _headers.length; col++) {
      final cell = sheet.cell(
        xls.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0),
      );
      cell.value = xls.TextCellValue(_headers[col]);
      cell.cellStyle = headerStyle;
    }
    sheet.setRowHeight(0, 24);

    final wrapStyle = xls.CellStyle(
      verticalAlign: xls.VerticalAlign.Top,
      textWrapping: xls.TextWrapping.WrapText,
    );

    for (var i = 0; i < reports.length; i++) {
      final r = reports[i];
      final rowIndex = i + 1;
      final ssr = r.storeSystemReportCopy;
      final pw = r.proWanReportDetail;
      final values = <Object?>[
        r.id,
        r.authorName,
        r.coWorkerIds.join(' / '),
        r.clientName,
        _dateFmt.format(r.visitDate),
        _timeFmt.format(r.startTime),
        _timeFmt.format(r.endTime),
        r.workDuration.inMinutes,
        r.responseType.label,
        r.equipmentModel,
        r.proWanRefNumber,
        r.workContent,
        _partsText(r),
        r.successPoints,
        r.issuesPoints,
        r.tags.join(' / '),
        r.notes,
        ssr.receiptNumber,
        ssr.storeNumber,
        ssr.scannedAddress,
        ssr.scannedTel,
        _ssrRefrigerantType(ssr),
        _ssrRefrigerantAmount(ssr),
        ssr.recoveryAmount,
        ssr.requestContent,
        ssr.equipmentName,
        ssr.maker,
        ssr.modelNumber,
        ssr.machineNo,
        ssr.assetNo,
        ssr.barcode,
        ssr.deliveryDate,
        ssr.workerName,
        ssr.part,
        ssr.detailPart,
        ssr.phenomenon,
        ssr.phenomenonNote,
        ssr.cause,
        ssr.treatmentContent,
        ssr.treatmentContent2,
        ssr.part1,
        ssr.part2,
        ssr.part3,
        ssr.part4,
        ssr.part5,
        ssr.remarks,
        pw.storeAddress,
        pw.clientName,
        pw.receiptDate,
        pw.department,
        pw.systemNumber,
        pw.caseNo,
        pw.equipmentLocation,
        pw.requestContent,
        pw.cause,
        pw.visitResult,
        pw.futurePlan,
        pw.technicianName,
        _dateTimeFmt.format(r.createdAt),
        _dateTimeFmt.format(r.updatedAt),
      ];
      for (var col = 0; col < values.length; col++) {
        final cell = sheet.cell(
          xls.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIndex),
        );
        final v = values[col];
        if (v is int) {
          cell.value = xls.IntCellValue(v);
        } else {
          cell.value = xls.TextCellValue((v ?? '').toString());
        }
        cell.cellStyle = wrapStyle;
      }
    }

    // 列幅の目安を設定(内容に応じて広め/狭めを調整)。
    const widths = <double>[
      14, // 日報ID
      10, // 作成者
      14, // 共同作業者
      16, // 訪問先
      11, // 訪問日
      8, // 開始時刻
      8, // 終了時刻
      10, // 作業時間
      10, // 対応区分
      14, // 機器型番
      14, // プロワン管理番号
      30, // 作業内容
      20, // 使用部品
      24, // うまくいったこと
      24, // 課題・失敗・改善点
      16, // タグ
      20, // 備考
      16, // SE:弊社受付No.
      10, // SE:店番
      22, // SE:住所(報告書記載)
      14, // SE:TEL(報告書記載)
      12, // SE:冷媒種類
      12, // SE:充填量
      12, // SE:冷媒回収量
      24, // SE:依頼内容
      16, // SE:設備名称
      12, // SE:メーカー
      14, // SE:型式
      12, // SE:機番
      14, // SE:資産管理No
      14, // SE:バーコード
      12, // SE:納品日
      12, // SE:作業者氏名
      10, // SE:部位
      12, // SE:詳細部位
      16, // SE:事象
      16, // SE:事象補足
      16, // SE:原因
      18, // SE:処置内容
      18, // SE:処置内容2
      12, // SE:部品1
      12, // SE:部品2
      12, // SE:部品3
      12, // SE:部品4
      12, // SE:部品5
      18, // SE:備考
      20, // PW:店舗住所
      16, // PW:得意先名
      12, // PW:受付日
      12, // PW:部門
      16, // PW:系統番号・名
      12, // PW:ケースNo
      16, // PW:修理機器・場所
      24, // PW:ご依頼内容
      16, // PW:原因
      20, // PW:訪問結果
      20, // PW:今後の予定
      12, // PW:技術者氏名
      16, // 作成日時
      16, // 更新日時
    ];
    for (var col = 0; col < widths.length; col++) {
      sheet.setColumnWidth(col, widths[col]);
    }

    final bytes = workbook.save();
    if (bytes == null) {
      throw Exception('Excelファイルの生成に失敗しました');
    }
    return Uint8List.fromList(bytes);
  }

  /// Excelを生成し、share_plusでダウンロード/共有する。
  static Future<void> exportAndShare(
    List<WorkReport> reports, {
    String fileNamePrefix = '日報・ナレッジ',
  }) async {
    final bytes = buildXlsxBytes(reports);
    final now = DateTime.now();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(now);
    final fileName = '${fileNamePrefix}_$stamp.xlsx';

    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            name: fileName,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ],
        fileNameOverrides: [fileName],
        subject: fileNamePrefix,
      ),
    );
  }

  /// Excelを生成し、端末のダウンロード/保存フォルダへ直接保存する。
  static Future<String> exportAndSaveToDevice(
    List<WorkReport> reports, {
    String fileNamePrefix = '日報・ナレッジ',
  }) async {
    final bytes = buildXlsxBytes(reports);
    final now = DateTime.now();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(now);
    final fileName = '${fileNamePrefix}_$stamp';

    await FileSaver.instance.saveFile(
      name: fileName,
      bytes: bytes,
      fileExtension: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );

    return '$fileName.xlsx';
  }
}
