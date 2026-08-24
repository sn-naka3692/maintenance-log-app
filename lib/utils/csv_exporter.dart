import 'dart:convert';
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../models/work_report.dart';

/// 日報データをCSV形式に変換し、共有(ダウンロード/送信)するユーティリティ。
///
/// - Excelでの文字化けを防ぐため、UTF-8 BOM付きで出力する。
/// - フィールド内にカンマ・改行・ダブルクオートが含まれる場合は
///   CSV仕様に従いダブルクオートでエスケープする。
class CsvExporter {
  static final DateFormat _dateFmt = DateFormat('yyyy/MM/dd');
  static final DateFormat _timeFmt = DateFormat('HH:mm');
  static final DateFormat _dateTimeFmt = DateFormat('yyyy/MM/dd HH:mm');

  /// 1つのフィールド値をCSV仕様に沿ってエスケープする。
  static String _escape(Object? value) {
    final s = (value ?? '').toString();
    if (s.contains(',') ||
        s.contains('"') ||
        s.contains('\n') ||
        s.contains('\r')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static String _rowToLine(List<Object?> row) {
    return row.map(_escape).join(',');
  }

  /// 日報一覧をCSV文字列に変換する。
  ///
  /// [reports] エクスポート対象の日報リスト
  static String buildCsv(List<WorkReport> reports) {
    final buffer = StringBuffer();

    final headers = [
      '日報ID',
      '作成者',
      '共同作業者',
      '訪問先(店舗)',
      '訪問日',
      '開始時刻',
      '終了時刻',
      '作業時間(分)',
      '対応区分',
      '機器型番(プロワン参照)',
      'プロワン管理番号',
      '作業内容',
      '使用部品',
      '写真枚数',
      'うまくいったこと',
      '課題・失敗・改善点',
      'タグ',
      '備考',
      // コンビニ側システム入力控え
      'SE:弊社受付No.',
      'SE:冷媒種類',
      'SE:充填量',
      'SE:依頼内容',
      'SE:設備名称',
      'SE:メーカー',
      'SE:型式',
      'SE:処置内容',
      'SE:部位',
      'SE:詳細部位',
      'SE:事象',
      'SE:事象補足',
      'SE:原因',
      'SE:処置内容2',
      'SE:部品1',
      'SE:部品2',
      'SE:部品3',
      'SE:部品4',
      'SE:部品5',
      'SE:備考',
      // プロワン管轄案件(SE店舗以外)専用・請求業務用
      '冷媒種類(プロワン案件)',
      '冷媒量kg(プロワン案件)',
      '作成日時',
      '更新日時',
    ];
    buffer.writeln(_rowToLine(headers));

    for (final r in reports) {
      final ssr = r.storeSystemReportCopy;
      final partsText = r.partsUsed
          .map(
            (p) => p.note != null && p.note!.trim().isNotEmpty
                ? '${p.name}×${p.quantity}(${p.note})'
                : '${p.name}×${p.quantity}',
          )
          .join(' / ');

      final row = <Object?>[
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
        partsText,
        r.photoPaths.length,
        r.successPoints,
        r.issuesPoints,
        r.tags.join(' / '),
        r.notes,
        ssr.receiptNumber,
        ssr.refrigerantType,
        ssr.refrigerantAmount,
        ssr.requestContent,
        ssr.equipmentName,
        ssr.maker,
        ssr.modelNumber,
        ssr.treatmentContent,
        ssr.part,
        ssr.detailPart,
        ssr.phenomenon,
        ssr.phenomenonNote,
        ssr.cause,
        ssr.treatmentContent2,
        ssr.part1,
        ssr.part2,
        ssr.part3,
        ssr.part4,
        ssr.part5,
        ssr.remarks,
        r.nonSeRefrigerantType,
        r.nonSeRefrigerantAmountKg,
        _dateTimeFmt.format(r.createdAt),
        _dateTimeFmt.format(r.updatedAt),
      ];
      buffer.writeln(_rowToLine(row));
    }

    return buffer.toString();
  }

  /// CSVを生成し、share_plusでダウンロード/共有する。
  ///
  /// Web: ブラウザのダウンロードとして保存される。
  /// Android: 共有シート(メール添付・LINE送信・保存等)が開く。
  static Future<void> exportAndShare(
    List<WorkReport> reports, {
    String fileNamePrefix = '日報データ',
  }) async {
    final csvBody = buildCsv(reports);
    // Excel(特にWindows版)で文字化けしないよう UTF-8 BOM を先頭に付与する。
    const bom = '\uFEFF';
    final bytes = utf8.encode(bom + csvBody);

    final now = DateTime.now();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(now);
    final fileName = '${fileNamePrefix}_$stamp.csv';

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: fileName, mimeType: 'text/csv')],
        fileNameOverrides: [fileName],
        subject: fileNamePrefix,
      ),
    );
  }

  /// CSVを生成し、端末のダウンロード/保存フォルダへ直接保存する。
  ///
  /// - Android: 「ダウンロード」フォルダへ直接保存され、共有シートを
  ///   経由しない(file_saverパッケージ経由)。
  /// - Web: ブラウザの標準ダウンロード動作として保存される。
  ///
  /// 戻り値は保存先の情報(端末に表示可能な簡易な説明文字列)。
  static Future<String> exportAndSaveToDevice(
    List<WorkReport> reports, {
    String fileNamePrefix = '日報データ',
  }) async {
    final csvBody = buildCsv(reports);
    // Excel(特にWindows版)で文字化けしないよう UTF-8 BOM を先頭に付与する。
    const bom = '\uFEFF';
    final bytes = utf8.encode(bom + csvBody);

    final now = DateTime.now();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(now);
    final fileName = '${fileNamePrefix}_$stamp';

    await FileSaver.instance.saveFile(
      name: fileName,
      bytes: bytes,
      fileExtension: 'csv',
      mimeType: MimeType.csv,
    );

    return '$fileName.csv';
  }
}
