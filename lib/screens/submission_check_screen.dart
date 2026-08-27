import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/submission_check_record.dart';
import '../models/work_report.dart';
import '../providers/app_state.dart';
import '../services/document_scan_service.dart';
import '../services/submission_check_service.dart';
import '../theme/app_theme.dart';
import '../utils/scan_date_parser.dart';
import '../utils/web_pdf_picker.dart';

/// 【月末チェック(日報記入率)機能】
///
/// 管理者が月末に、紙の作業報告書をコピー機でまとめてスキャンした
/// PDF(1ページ=1案件)をアップロードすると、ページ単位に分割して
/// AI-OCR解析し、アプリ側の日報データと自動突合する。突合できなかった
/// ページ = 未提出(記入漏れ)の可能性がある案件として一覧表示する。
///
/// 【全案件対応・SE店舗分/プロワン管轄分の両対応】
/// 1ページごとにSE用モデル・プロワン用モデルの両方で解析し、
/// confidenceが高い方を採用した書式判定結果(docType)に応じて、
/// 突合キーを切り替える:
///   - SEDocType   : 弊社受付No (WorkReport.storeSystemReportCopy.receiptNumber)
///   - ProWanDocType: 伝票No/案件管理番号 (WorkReport.proWanRefNumber)
///
/// 【設計方針】
/// - 主キー(受付No or 伝票No)のみを突合対象とする。「他◯名」(SE用紙のみ
///   記載)はヘルパー個人の特定まではできないため、あくまで参考情報
///   (人数の目安)として表示するのみに留める。
/// - Azure Functions側の実行時間上限対策として、1回のリクエストで
///   最大 DocumentScanService.maxPagesPerRequest ページまでしか
///   処理できないため、進捗バーを見せながら分割リクエストする。
///
/// 【重要・同一伝票No/受付Noに複数日程がある場合の対応・2026-08-28】
/// プロワン案件は1つの伝票No(案件管理番号)に対して複数の作業日程
/// (=複数ページの紙報告書、複数のWorkReport)が存在することがある。
/// 伝票Noだけで突合すると、2ページとも同じ1件のWorkReportにマッチして
/// しまい、実際には2日目分の日報が未入力(記入漏れ)であっても
/// 検出できないという不具合があった。これを避けるため:
///   1. 一度マッチしたWorkReportは「消費済み」として記録し、以後の
///      ページから再度マッチさせない(1ページ=1WorkReportの1対1対応)。
///   2. 同じ伝票Noの未消費候補が複数残っている場合は、OCRの
///      WorkStartDateと日報のvisitDateが一致するものを優先して選ぶ
///      (WorkStartDateのAI信頼度はまだ低いため、あくまで優先度判定の
///      補助情報として使い、一致しない場合も未消費の候補があれば
///      それを消費してmatchedとする)。
///   3. 同じ伝票Noの候補をすべて消費し尽くした状態でさらに同じ伝票No
///      のページが来た場合は unmatched(=記入漏れの可能性)として扱う。
class SubmissionCheckScreen extends StatefulWidget {
  const SubmissionCheckScreen({super.key});

  @override
  State<SubmissionCheckScreen> createState() => _SubmissionCheckScreenState();
}

enum _MatchStatus { matched, unmatched, lowConfidence, error }

class _PageCheckResult {
  final PageScanResult scan;
  final _MatchStatus matchStatus;
  final WorkReport? matchedReport;
  // Firestoreから復元した場合、matchedReportそのものは保持しないため
  // 表示用に作成者名だけをキャッシュしておく。
  final String? matchedReportAuthorName;

  const _PageCheckResult({
    required this.scan,
    required this.matchStatus,
    this.matchedReport,
    this.matchedReportAuthorName,
  });

  String get displayAuthorName =>
      matchedReport?.authorName ?? matchedReportAuthorName ?? '';
}

class _SubmissionCheckScreenState extends State<SubmissionCheckScreen> {
  Uint8List? _pdfBytes;
  String? _pdfFileName;
  int _totalPages = 0;

  bool _processing = false;
  int _processedPages = 0;
  String? _errorMessage;

  bool _saving = false;
  bool _saved = false;

  final List<_PageCheckResult> _results = [];

  /// この画面で扱う対象月(実行時点の年月、"yyyy-MM")。
  /// 保存/履歴読込のキーとして使う。
  late final String _checkMonth = DateFormat('yyyy-MM').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSavedResults());
  }

  /// 今月分の突合結果が既にFirestoreに保存されていれば読み込んで表示する
  /// (画面を閉じて再度開いた場合に前回結果を確認できるようにするため)。
  Future<void> _loadSavedResults() async {
    final saved = await SubmissionCheckService.instance.fetchResultsForMonth(
      _checkMonth,
    );
    if (!mounted || saved.isEmpty) return;
    setState(() {
      _results
        ..clear()
        ..addAll(saved.map(_toPageCheckResult));
      _totalPages = saved.length;
      _saved = true;
    });
  }

  /// Firestoreから読み込んだ保存済みレコードを、画面表示用の
  /// _PageCheckResult(スキャン直後の形式と同じ)に変換する。
  /// PDF再アップロードなしで一覧表示するための簡易的な変換であり、
  /// confidencesマップ等の詳細情報までは復元しない。
  _PageCheckResult _toPageCheckResult(SubmissionCheckRecord record) {
    final scan = PageScanResult(
      pageNumber: record.pageNumber,
      status: record.matchStatus == SubmissionMatchStatus.error
          ? 'error'
          : record.matchStatus == SubmissionMatchStatus.lowConfidence
          ? 'low_confidence'
          : 'ok',
      docType: record.docType,
      documentConfidence: record.documentConfidence,
      values: {
        if (record.isProWan) 'ProWanRefNumber': record.matchingKey,
        if (!record.isProWan) 'CompanyReceiptNumber': record.matchingKey,
        'StoreName': record.storeName,
        'OtherWorkersCount': record.otherWorkersCount,
      },
      confidences: const {},
      error: record.errorMessage,
    );
    late final _MatchStatus matchStatus;
    switch (record.matchStatus) {
      case SubmissionMatchStatus.matched:
        matchStatus = _MatchStatus.matched;
        break;
      case SubmissionMatchStatus.unmatched:
        matchStatus = _MatchStatus.unmatched;
        break;
      case SubmissionMatchStatus.lowConfidence:
        matchStatus = _MatchStatus.lowConfidence;
        break;
      case SubmissionMatchStatus.error:
        matchStatus = _MatchStatus.error;
        break;
    }
    return _PageCheckResult(
      scan: scan,
      matchStatus: matchStatus,
      matchedReport: null,
      matchedReportAuthorName: record.matchedReportAuthorName,
    );
  }

  Future<void> _pickPdf() async {
    setState(() {
      _errorMessage = null;
    });
    try {
      Uint8List? bytes;
      String? fileName;
      if (kIsWeb) {
        // 【不具合修正・2026-08-27】document_scan_flow.dartと同様、
        // file_pickerパッケージ経由だとビルド環境のキャッシュ状態次第で
        // Web実装が正しく登録されず「MissingPluginException」が発生する
        // 不具合が本番で発生した。package:web直接操作の自前実装に
        // 切り替えて根本回避する。
        final webPicked = await pickPdfFileWeb();
        if (webPicked == null) return; // キャンセル
        bytes = webPicked.bytes;
        fileName = webPicked.name;
      } else {
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf'],
          withData: true,
        );
        if (result == null || result.files.isEmpty) return;
        final file = result.files.single;
        bytes = file.bytes;
        fileName = file.name;
      }
      if (bytes == null) {
        setState(() {
          _errorMessage = 'ファイルの読み込みに失敗しました';
        });
        return;
      }
      setState(() {
        _pdfBytes = bytes;
        _pdfFileName = fileName;
        _totalPages = 0;
        _results.clear();
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'ファイル選択に失敗しました: $e';
      });
    }
  }

  Future<void> _startProcessing() async {
    final pdfBytes = _pdfBytes;
    if (pdfBytes == null) return;

    final appState = context.read<AppState>();
    final allReports = appState.reports;

    // 【同一伝票No複数日程対応】このPDF一括処理の実行中、既にどの
    // WorkReport.idがマッチ済み(消費済み)かを追跡する。ページごとに
    // 都度リセットせず、同一PDF内の全ページを通して共有することで、
    // 同じ伝票Noの2ページ目以降が1ページ目と同じ日報に重複マッチする
    // ことを防ぐ。
    final consumedReportIds = <String>{};

    setState(() {
      _processing = true;
      _processedPages = 0;
      _errorMessage = null;
      _saved = false;
      _results.clear();
    });

    try {
      int startPage = 1;
      int? totalPages;

      while (totalPages == null || startPage <= totalPages) {
        final endPage = totalPages == null
            ? startPage + DocumentScanService.maxPagesPerRequest - 1
            : (startPage + DocumentScanService.maxPagesPerRequest - 1).clamp(
                1,
                totalPages,
              );

        final batch = await DocumentScanService.analyzeBatch(
          pdfBytes,
          startPage: startPage,
          endPage: endPage,
        );

        totalPages = batch.totalPages;
        if (mounted) {
          setState(() => _totalPages = totalPages!);
        }

        for (final pageResult in batch.pageResults) {
          final matched = _matchAgainstReports(
            pageResult,
            allReports,
            consumedReportIds,
          );
          if (matched.matchedReport != null) {
            consumedReportIds.add(matched.matchedReport!.id);
          }
          if (mounted) {
            setState(() {
              _results.add(matched);
              _processedPages++;
            });
          }
        }

        startPage = endPage + 1;
      }

      // 全ページの解析が完了したら、突合結果をFirestoreに永続化する。
      // (同月の既存結果があれば内部で上書きされる)
      if (mounted && _results.isNotEmpty) {
        await _saveResultsToFirestore();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '解析に失敗しました: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  /// 突合結果一覧をFirestore `submission_checks` コレクションに保存する。
  /// 対象月は実行時点の年月(_checkMonth)。同月の既存レコードがあれば
  /// サービス側で自動的に削除→差し替えされる。
  Future<void> _saveResultsToFirestore() async {
    final appState = context.read<AppState>();
    final currentUser = appState.currentUser;

    setState(() => _saving = true);
    try {
      final records = _results
          .map((r) => _toSubmissionCheckRecord(r, currentUser))
          .toList();
      await SubmissionCheckService.instance.saveResults(
        checkMonth: _checkMonth,
        records: records,
      );
      if (mounted) {
        setState(() => _saved = true);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('突合結果を保存しました')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('突合結果の保存に失敗しました: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  SubmissionCheckRecord _toSubmissionCheckRecord(
    _PageCheckResult result,
    dynamic currentUser,
  ) {
    final scan = result.scan;
    late final SubmissionMatchStatus status;
    switch (result.matchStatus) {
      case _MatchStatus.matched:
        status = SubmissionMatchStatus.matched;
        break;
      case _MatchStatus.unmatched:
        status = SubmissionMatchStatus.unmatched;
        break;
      case _MatchStatus.lowConfidence:
        status = SubmissionMatchStatus.lowConfidence;
        break;
      case _MatchStatus.error:
        status = SubmissionMatchStatus.error;
        break;
    }
    return SubmissionCheckRecord(
      checkMonth: _checkMonth,
      docType: scan.docType,
      matchingKey: scan.matchingKey,
      matchStatus: status,
      storeName: scan.values['StoreName'] ?? '',
      otherWorkersCount: scan.otherWorkersCount,
      documentConfidence: scan.documentConfidence,
      pageNumber: scan.pageNumber,
      matchedReportId: result.matchedReport?.id,
      matchedReportAuthorName: result.matchedReport?.authorName,
      errorMessage: scan.error,
      uploadedById: currentUser?.id ?? '',
      uploadedByName: currentUser?.name ?? '',
    );
  }

  /// docType(SE/プロワン)に応じた主キーで、アプリ側の日報データと突合する。
  ///
  /// [consumedReportIds] には、このPDF一括処理内で既にマッチ済みの
  /// WorkReport.idを渡す。マッチが決まった場合、呼び出し元で
  /// このSetに追加してもらうことで、同じ伝票No(案件管理番号)を持つ
  /// 複数ページが同じ1件の日報に重複マッチすることを防ぐ
  /// (1ページ=1WorkReportの1対1対応を保証する)。
  _PageCheckResult _matchAgainstReports(
    PageScanResult scan,
    List<WorkReport> reports,
    Set<String> consumedReportIds,
  ) {
    if (scan.isError) {
      return _PageCheckResult(scan: scan, matchStatus: _MatchStatus.error);
    }
    if (scan.isLowConfidence) {
      return _PageCheckResult(
        scan: scan,
        matchStatus: _MatchStatus.lowConfidence,
      );
    }

    // 【全案件対応】書式種別(docType)に応じて突合キーを切り替える。
    // - SE店舗案件: 弊社受付No (WorkReport.storeSystemReportCopy.receiptNumber)
    // - プロワン管轄案件: 伝票No/案件管理番号 (WorkReport.proWanRefNumber)
    final matchingKey = scan.matchingKey.trim();
    if (matchingKey.isEmpty) {
      return _PageCheckResult(scan: scan, matchStatus: _MatchStatus.unmatched);
    }

    // 伝票No/受付Noが一致する「未消費」の候補を全て集める
    // (同一キーで複数日程の案件がある場合、複数件になり得る)。
    final candidates = <WorkReport>[];
    if (scan.isProWanDocument) {
      for (final r in reports) {
        if (consumedReportIds.contains(r.id)) continue;
        if (r.proWanRefNumber.trim() == matchingKey) {
          candidates.add(r);
        }
      }
    } else {
      // isSeDocument、または将来docType未設定の古いレスポンスへの
      // 後方互換フォールバックとしてもSE側キーで突合を試みる。
      for (final r in reports) {
        if (consumedReportIds.contains(r.id)) continue;
        if (r.storeSystemReportCopy.receiptNumber.trim() == matchingKey) {
          candidates.add(r);
        }
      }
    }

    WorkReport? found;
    if (candidates.length <= 1) {
      found = candidates.isEmpty ? null : candidates.first;
    } else {
      // 【同一伝票Noに複数日程がある場合】OCRのWorkStartDateと
      // 日報のvisitDateが同じ日(年月日)である候補を優先する。
      // WorkStartDateのAI信頼度はまだ低いため、あくまで優先度判定の
      // 補助情報として使う(一致しなくても未消費の候補があれば
      // 先頭の1件を採用してmatchedとする。全く突合できないより、
      // 「候補は複数あるが日付未確定」の状態で1件を仮に消費する方が、
      // 残り件数を正しく減らせて記入漏れ検出の精度が上がるため)。
      final scanDate = tryParseScanDate(scan.workStartDate);
      if (scanDate != null) {
        for (final c in candidates) {
          if (isSameCalendarDay(c.visitDate, scanDate)) {
            found = c;
            break;
          }
        }
      }
      found ??= candidates.first;
    }

    if (found != null) {
      return _PageCheckResult(
        scan: scan,
        matchStatus: _MatchStatus.matched,
        matchedReport: found,
      );
    }
    return _PageCheckResult(scan: scan, matchStatus: _MatchStatus.unmatched);
  }

  List<_PageCheckResult> get _unmatchedResults => _results
      .where(
        (r) =>
            r.matchStatus == _MatchStatus.unmatched ||
            r.matchStatus == _MatchStatus.lowConfidence ||
            r.matchStatus == _MatchStatus.error,
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    final matchedCount = _results
        .where((r) => r.matchStatus == _MatchStatus.matched)
        .length;
    final unmatchedCount = _unmatchedResults.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('月末チェック(日報記入率)'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else if (_saved)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: Icon(Icons.cloud_done_outlined, color: Colors.white),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '紙の作業報告書をまとめてスキャンしたPDF(1ページ=1案件)を'
                'アップロードしてください。SE店舗分(弊社受付No)・プロワン'
                '管轄分(伝票No)の両方を自動判定し、アプリ側の日報データと'
                '突合します。結果は対象月($_checkMonth)ごとにFirestoreへ'
                '自動保存され、同月内に再実行すると前回結果が上書きされます。',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
              ),
              if (_saved && !_processing) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.cloud_done_outlined,
                      size: 16,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$_checkMonth 分の結果は保存済みです',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.picture_as_pdf_outlined,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _pdfFileName ?? 'PDFファイルが選択されていません',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _processing ? null : _pickPdf,
                              icon: const Icon(Icons.folder_open, size: 18),
                              label: const Text('PDFを選択'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: (_pdfBytes == null || _processing)
                                  ? null
                                  : _startProcessing,
                              icon: const Icon(Icons.play_arrow, size: 18),
                              label: const Text('解析を開始'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: AppColors.danger, fontSize: 12.5),
                  ),
                ),
              ],
              if (_processing || _results.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  _totalPages > 0
                      ? '進捗: $_processedPages / $_totalPages ページ'
                      : '解析中...',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: _totalPages > 0 ? _processedPages / _totalPages : null,
                ),
              ],
              if (_results.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    _resultChip(
                      '突合OK',
                      matchedCount,
                      AppColors.success,
                      Icons.check_circle_outline,
                    ),
                    const SizedBox(width: 10),
                    _resultChip(
                      '要確認',
                      unmatchedCount,
                      AppColors.warning,
                      Icons.warning_amber,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (unmatchedCount > 0) ...[
                  Text(
                    '未提出の可能性がある案件(要確認)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.warning,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._unmatchedResults.map(_buildResultTile),
                  const SizedBox(height: 16),
                ],
                Text(
                  '全結果(全$_totalPagesページ)',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                ..._results.map(_buildResultTile),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultChip(String label, int count, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(
              '$label $count件',
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultTile(_PageCheckResult result) {
    final scan = result.scan;
    late final IconData icon;
    late final Color color;
    late final String statusLabel;

    switch (result.matchStatus) {
      case _MatchStatus.matched:
        icon = Icons.check_circle_outline;
        color = AppColors.success;
        statusLabel = '突合OK(${result.displayAuthorName})';
        break;
      case _MatchStatus.unmatched:
        icon = Icons.help_outline;
        color = AppColors.warning;
        statusLabel = '該当する日報が見つかりません';
        break;
      case _MatchStatus.lowConfidence:
        icon = Icons.warning_amber;
        color = AppColors.warning;
        statusLabel = '読み取り精度が低いため要目視確認';
        break;
      case _MatchStatus.error:
        icon = Icons.error_outline;
        color = AppColors.danger;
        statusLabel = scan.error ?? '解析エラー';
        break;
    }

    final matchingKey = scan.matchingKey;
    final keyLabel = scan.isProWanDocument ? '伝票No' : '受付No';
    final otherWorkers = scan.otherWorkersCount;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(
          matchingKey.isNotEmpty
              ? '$keyLabel: $matchingKey'
              : 'ページ${scan.pageNumber}($keyLabel未読取)',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '$statusLabel'
          '${otherWorkers.isNotEmpty ? ' / 他$otherWorkers名' : ''}'
          ' (${scan.pageNumber}ページ目)',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
      ),
    );
  }
}
