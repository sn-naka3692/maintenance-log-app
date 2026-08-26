import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/work_report.dart';
import '../providers/app_state.dart';
import '../services/document_scan_service.dart';
import '../theme/app_theme.dart';

/// 【月末チェック(日報記入率)機能】
///
/// 管理者が月末に、紙の作業報告書をコピー機でまとめてスキャンした
/// PDF(1ページ=1案件)をアップロードすると、ページ単位に分割して
/// AI-OCR解析し、各ページの「弊社受付No」を主キーにアプリ側の
/// 日報データ(WorkReport.storeSystemReportCopy.receiptNumber)と
/// 自動突合する。突合できなかったページ = 未提出(記入漏れ)の
/// 可能性がある案件として一覧表示する。
///
/// 【設計方針】
/// - 弊社受付Noのみを主キーとした突合。「他◯名」はヘルパー個人の
///   特定まではできないため、あくまで参考情報(人数の目安)として
///   表示するのみに留める。
/// - Azure Functions側の実行時間上限対策として、1回のリクエストで
///   最大 DocumentScanService.maxPagesPerRequest ページまでしか
///   処理できないため、進捗バーを見せながら分割リクエストする。
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

  const _PageCheckResult({
    required this.scan,
    required this.matchStatus,
    this.matchedReport,
  });
}

class _SubmissionCheckScreenState extends State<SubmissionCheckScreen> {
  Uint8List? _pdfBytes;
  String? _pdfFileName;
  int _totalPages = 0;

  bool _processing = false;
  int _processedPages = 0;
  String? _errorMessage;

  final List<_PageCheckResult> _results = [];

  Future<void> _pickPdf() async {
    setState(() {
      _errorMessage = null;
    });
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        setState(() {
          _errorMessage = 'ファイルの読み込みに失敗しました';
        });
        return;
      }
      setState(() {
        _pdfBytes = bytes;
        _pdfFileName = file.name;
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

    setState(() {
      _processing = true;
      _processedPages = 0;
      _errorMessage = null;
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
          final matched = _matchAgainstReports(pageResult, allReports);
          if (mounted) {
            setState(() {
              _results.add(matched);
              _processedPages++;
            });
          }
        }

        startPage = endPage + 1;
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

  /// 弊社受付Noを主キーとして、アプリ側の日報データと突合する。
  _PageCheckResult _matchAgainstReports(
    PageScanResult scan,
    List<WorkReport> reports,
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

    final receiptNumber = scan.companyReceiptNumber.trim();
    if (receiptNumber.isEmpty) {
      return _PageCheckResult(scan: scan, matchStatus: _MatchStatus.unmatched);
    }

    WorkReport? found;
    for (final r in reports) {
      if (r.storeSystemReportCopy.receiptNumber.trim() == receiptNumber) {
        found = r;
        break;
      }
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
      appBar: AppBar(title: const Text('月末チェック(日報記入率)')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '紙の作業報告書をまとめてスキャンしたPDF(1ページ=1案件)を'
                'アップロードしてください。弊社受付Noを読み取り、アプリ側の'
                '日報データと自動で突合します。',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
              ),
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
        statusLabel = '突合OK(${result.matchedReport?.authorName ?? ''})';
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

    final receiptNumber = scan.companyReceiptNumber;
    final otherWorkers = scan.otherWorkersCount;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(
          receiptNumber.isNotEmpty
              ? '受付No: $receiptNumber'
              : 'ページ${scan.pageNumber}(受付No未読取)',
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
