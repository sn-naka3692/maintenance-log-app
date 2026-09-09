import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../screens/scan_confirm_screen.dart';
import '../services/document_scan_service.dart';
import '../utils/blur_detector.dart';
import '../utils/web_pdf_picker.dart';

/// 「作業報告書をAIで読み取る」機能の一連の流れをまとめたヘルパー。
///
/// 【入力ルート・2026-08拡張】
/// 従来の「カメラで撮影」に加え、以下2つの取り込みルートを用意する:
///   - PDFファイルをアップロード(現場の業務システム=プロワン・店舗カルテ
///     アプリ側から直接PDF出力できる場合、撮影せずそのまま取り込める)
///   - 端末内の画像を選択(既に写真として保存済みの報告書向け)
/// 実際の解析対象がどのルート経由でも、以降の流れは共通:
///   1. Azure Document Intelligenceで解析(ローディング表示)
///   2. 確認・修正画面(ScanConfirmScreen)で必ずユーザー確認を挟む
///   3. 確認済みの値(フィールドキー→値のMap)を呼び出し元に返す
///
/// どのステップでキャンセル・失敗しても null を返し、フォームには一切反映しない。
class DocumentScanFlow {
  /// [reportId]: 呼び出し元(日報編集画面)が確定済みの日報IDを渡す。
  /// 学習ログ(scan_corrections)に「どの日報のスキャンか」を記録するために
  /// ScanConfirmScreenへそのまま引き渡す(2026-09追加)。
  static Future<Map<String, String>?> run(
    BuildContext context, {
    required String reportId,
  }) async {
    final source = await _pickSource(context);
    if (source == null || !context.mounted) return null;

    ScanResult? result;
    String? errorMessage;

    if (source == _ScanSource.pdf) {
      // PDFファイル選択(解析中ダイアログを出す前に選択させる)
      Uint8List? pdfBytes;
      try {
        if (kIsWeb) {
          // 【不具合修正・2026-08-27】Web版はfile_pickerパッケージ経由
          // だと、ビルド環境のキャッシュ状態次第でWeb実装が正しく
          // 登録されず「MissingPluginException」が発生する不具合が
          // 本番で発生した。file_pickerのプラグイン登録の仕組みを
          // 一切経由しない、package:web直接操作の自前実装
          // (web_pdf_picker.dart)に切り替えることで根本回避する。
          // 端末のダウンロードフォルダを含め、ブラウザのファイル選択
          // ダイアログでアクセスできる場所ならどこからでも選択可能。
          final webPicked = await pickPdfFileWeb();
          if (webPicked == null) return null; // キャンセル
          pdfBytes = webPicked.bytes;
        } else {
          // APK版(Android)は従来通りfile_pickerのネイティブ実装
          // (Storage Access Framework経由)を使う。
          final picked = await FilePicker.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['pdf'],
            withData: true,
          );
          if (picked == null || picked.files.isEmpty) return null; // キャンセル
          pdfBytes = picked.files.single.bytes;
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('PDFファイルの選択に失敗しました: $e')));
        }
        return null;
      }
      if (pdfBytes == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('ファイルの読み込みに失敗しました')));
        }
        return null;
      }
      if (!context.mounted) return null;

      final dismiss = _showAnalyzingDialog(context);
      try {
        result = await DocumentScanService.analyzePdf(pdfBytes);
      } catch (e) {
        errorMessage = e is DocumentScanException
            ? e.message
            : 'AI読み取り中にエラーが発生しました: $e';
      }
      dismiss();
    } else {
      // カメラ撮影 or 端末内画像選択
      final picker = ImagePicker();
      Uint8List? bytes;

      // 【ブレ検出・2026-09追加】カメラ撮影のみが対象。撮影しなおせるのは
      // カメラ撮影の場合だけなので、端末内の既存画像選択(ギャラリー)には
      // このループを適用しない(既存挙動を変えないため)。
      // 画像そのものは一切加工せず、判定のみ行う(判定不能時は安全側=
      // ブレなし判定として素通りさせる)。
      bool keepGoing = true;
      while (keepGoing) {
        keepGoing = false;
        XFile? photo;
        try {
          photo = await picker.pickImage(
            source: source == _ScanSource.camera
                ? ImageSource.camera
                : ImageSource.gallery,
            imageQuality: 85,
            maxWidth: 2400,
          );
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  source == _ScanSource.camera
                      ? 'カメラを起動できませんでした(Web環境では制限があります)'
                      : '画像の選択に失敗しました: $e',
                ),
              ),
            );
          }
          return null;
        }
        if (photo == null) return null; // ユーザーがキャンセル
        if (!context.mounted) return null;

        final pickedBytes = await photo.readAsBytes();

        if (source == _ScanSource.camera) {
          final blurResult = detectBlur(pickedBytes);
          if (blurResult.isLikelyBlurry) {
            if (!context.mounted) return null;
            final retake = await _showBlurWarningDialog(context);
            if (retake == true) {
              keepGoing = true; // 撮影しなおす
              continue;
            }
            // 「このまま続行」が選択された場合はそのまま次へ
          }
        }

        bytes = pickedBytes;
      }

      if (bytes == null) return null;
      if (!context.mounted) return null;

      final dismiss = _showAnalyzingDialog(context);
      try {
        result = await DocumentScanService.analyzeImage(bytes);
      } catch (e) {
        errorMessage = e is DocumentScanException
            ? e.message
            : 'AI読み取り中にエラーが発生しました: $e';
      }
      dismiss();
    }

    if (errorMessage != null) {
      if (context.mounted) {
        // 診断情報(実行環境・バージョン・エラー種別)を含む長文になる場合が
        // あるため、通常より長めに表示し、手動で消せるようにする。
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            duration: const Duration(seconds: 12),
            action: SnackBarAction(
              label: '閉じる',
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
      return null;
    }

    if (result == null || !context.mounted) return null;

    // 必須: 確認・修正画面を必ず経由する(AI一発登録は行わない)
    final confirmed = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        builder: (_) => ScanConfirmScreen(
          scanResult: result!,
          reportId: reportId,
        ),
      ),
    );
    return confirmed;
  }

  /// ブレ検出時の確認ダイアログ。「再撮影する」を選ぶとtrueを返す。
  /// 【ブレ検出・2026-09追加】画像を送信するかどうかの最終判断は必ず
  /// ユーザーに委ね、自動でブロックはしない(判定のみ・無加工方針)。
  static Future<bool?> _showBlurWarningDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('画像がぼやけている可能性があります'),
        content: const Text(
          '撮影した画像がブレているか、ピントが合っていない可能性があります。'
          'このまま読み取りに進むと文字が正しく認識されない場合があります。\n\n'
          '再撮影しますか?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('このまま続行'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('再撮影する'),
          ),
        ],
      ),
    );
  }

  /// 解析中ダイアログを表示し、閉じるための関数を返す。
  static VoidCallback _showAnalyzingDialog(BuildContext context) {
    bool shown = true;
    unawaited(
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _AnalyzingDialog(),
      ),
    );
    return () {
      if (context.mounted && shown) {
        Navigator.of(context, rootNavigator: true).pop();
        shown = false;
      }
    };
  }

  /// 読み取り元(PDFアップロード/カメラ撮影/端末内画像)を選ばせるボトムシート。
  ///
  /// 【表示順・2026-09見直し】
  /// 各システム(プロワン・店舗カルテ等)から出力したPDFをそのまま取り込む
  /// 方が、カメラ撮影に比べて文字認識精度が安定するため、PDFアップロードを
  /// 最優先の選択肢として最上位に配置し、「推奨」バッジを付けて誘導する。
  /// カメラ撮影は「PDF出力できない場合の補助的な手段」という位置づけに
  /// 変更し、2番目に表示する(廃止はしない)。
  static Future<_ScanSource?> _pickSource(BuildContext context) {
    return showModalBottomSheet<_ScanSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '作業報告書の読み取り方法を選択',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.picture_as_pdf_outlined,
                color: Colors.indigo,
              ),
              title: Row(
                children: [
                  const Text('PDFファイルをアップロード'),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.indigo.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '推奨',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.indigo,
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: const Text(
                'プロワン・店舗カルテ等から出力したPDFを取り込みます\n'
                '文字が正確に読み取れるため、可能な場合はこちらをご利用ください',
              ),
              isThreeLine: true,
              onTap: () => Navigator.of(ctx).pop(_ScanSource.pdf),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('カメラで撮影'),
              subtitle: const Text(
                'PDFが用意できない場合の補助的な読み取り方法です\n'
                '紙の作業報告書をその場で撮影します',
              ),
              isThreeLine: true,
              onTap: () => Navigator.of(ctx).pop(_ScanSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('端末内の画像を選択'),
              subtitle: const Text('保存済みの写真から選びます'),
              onTap: () => Navigator.of(ctx).pop(_ScanSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

enum _ScanSource { camera, pdf, gallery }

class _AnalyzingDialog extends StatelessWidget {
  const _AnalyzingDialog();

  @override
  Widget build(BuildContext context) {
    return const Dialog(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('AIが作業報告書を読み取っています…'),
            SizedBox(height: 4),
            Text(
              '数秒〜1分程度かかる場合があります',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
