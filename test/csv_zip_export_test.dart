import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/models/work_report.dart';
import 'package:flutter_app/utils/csv_exporter.dart';

/// 【2026-09追加・重要バグ修正の回帰テスト】
///
/// 月次CSVエクスポート機能は、従来 SE店舗分・プロワン案件分・社内業務分の
/// 3ファイルを連続してダウンロード/共有していたため、Webブラウザ・Android
/// 端末の「連続ダウンロードブロック」機能により一部カテゴリしか実際には
/// 保存されない不具合があった(実際にプロワン案件分のみ受信できた事例で発覚)。
/// 1つのZIPにまとめて1回だけ出力する方式に変更したため、
/// buildZipBytes() が全カテゴリのCSVを正しく1つのZIPへ含めることを
/// 検証する。
void main() {
  WorkReport makeReport(String id, String content) {
    final now = DateTime(2026, 8, 15, 10, 0);
    return WorkReport(
      id: id,
      authorId: 'u1',
      authorName: 'テスト太郎',
      clientName: 'テスト店舗',
      visitDate: now,
      startTime: now,
      endTime: now.add(const Duration(hours: 1)),
      workContent: content,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('buildZipBytes: 複数カテゴリが1つのZIPに全て含まれる', () {
    final categorized = {
      '日報データ_2026-08_SE店舗分': [makeReport('se-1', 'SE作業内容')],
      '日報データ_2026-08_プロワン案件分': [makeReport('pw-1', 'プロワン作業内容')],
      '日報データ_2026-08_社内業務分': [makeReport('bo-1', '社内業務内容')],
    };

    final zipBytes = CsvExporter.buildZipBytes(categorized);
    expect(zipBytes.isNotEmpty, true);

    final archive = ZipDecoder().decodeBytes(zipBytes);
    final fileNames = archive.files.map((f) => f.name).toSet();

    expect(fileNames, {
      '日報データ_2026-08_SE店舗分.csv',
      '日報データ_2026-08_プロワン案件分.csv',
      '日報データ_2026-08_社内業務分.csv',
    });

    // 各CSVの内容が正しく個別に保持されていること(取り違えがないこと)を確認。
    // 【注意】ZIP内のCSVはUTF-8バイト列のため、日本語を正しく検証するには
    // String.fromCharCodes ではなく utf8.decode を使う必要がある
    // (fromCharCodesはマルチバイト文字を1バイト単位で誤変換し文字化けする)。
    final seFile = archive.findFile('日報データ_2026-08_SE店舗分.csv')!;
    final seContent = utf8.decode(seFile.content as List<int>);
    expect(seContent.contains('SE作業内容'), true);
    expect(seContent.contains('プロワン作業内容'), false);

    final pwFile = archive.findFile('日報データ_2026-08_プロワン案件分.csv')!;
    final pwContent = utf8.decode(pwFile.content as List<int>);
    expect(pwContent.contains('プロワン作業内容'), true);
    expect(pwContent.contains('SE作業内容'), false);
  });

  test('buildZipBytes: 空リストのカテゴリはZIPに含めない', () {
    final categorized = {
      '日報データ_2026-08_SE店舗分': [makeReport('se-1', 'SE作業内容')],
      '日報データ_2026-08_プロワン案件分': <WorkReport>[], // 0件
    };

    final zipBytes = CsvExporter.buildZipBytes(categorized);
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final fileNames = archive.files.map((f) => f.name).toSet();

    expect(fileNames, {'日報データ_2026-08_SE店舗分.csv'});
    expect(fileNames.contains('日報データ_2026-08_プロワン案件分.csv'), false);
  });
}
