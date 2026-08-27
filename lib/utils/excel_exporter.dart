import 'dart:typed_data';
import 'package:excel/excel.dart' as xls;
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
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
    '作成日時',
    '更新日時',
  ];

  static String _partsText(WorkReport r) {
    return r.partsUsed
        .map(
          (p) => p.note != null && p.note!.trim().isNotEmpty
              ? '${p.name}×${p.quantity}(${p.note})'
              : '${p.name}×${p.quantity}',
        )
        .join(' / ');
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
        _dateTimeFmt.format(r.createdAt),
        _dateTimeFmt.format(r.updatedAt),
      ];
      for (var col = 0; col < values.length; col++) {
        final cell = sheet.cell(
          xls.CellIndex.indexByColumnRow(
            columnIndex: col,
            rowIndex: rowIndex,
          ),
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
