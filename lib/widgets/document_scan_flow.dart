import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../screens/scan_confirm_screen.dart';
import '../services/document_scan_service.dart';

/// 「作業報告書を撮影してAIで読み取る」機能の一連の流れをまとめたヘルパー。
///
/// 1. カメラで作業報告書を撮影
/// 2. Azure Document Intelligenceで解析(ローディング表示)
/// 3. 確認・修正画面(ScanConfirmScreen)で必ずユーザー確認を挟む
/// 4. 確認済みの値(フィールドキー→値のMap)を呼び出し元に返す
///
/// どのステップでキャンセル・失敗しても null を返し、フォームには一切反映しない。
class DocumentScanFlow {
  static Future<Map<String, String>?> run(BuildContext context) async {
    final picker = ImagePicker();
    XFile? photo;
    try {
      photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 2400,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('カメラを起動できませんでした(Web環境では制限があります)')),
        );
      }
      return null;
    }
    if (photo == null) return null; // ユーザーがキャンセル

    if (!context.mounted) return null;

    // 解析中ダイアログ
    bool dialogShown = true;
    unawaited(
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _AnalyzingDialog(),
      ),
    );

    ScanResult? result;
    String? errorMessage;
    try {
      final bytes = await photo.readAsBytes();
      result = await DocumentScanService.analyzeImage(bytes);
    } catch (e) {
      errorMessage = e is DocumentScanException ? e.message : 'AI読み取り中にエラーが発生しました: $e';
    }

    if (context.mounted && dialogShown) {
      Navigator.of(context, rootNavigator: true).pop();
      dialogShown = false;
    }

    if (errorMessage != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
      return null;
    }

    if (result == null || !context.mounted) return null;

    // 必須: 確認・修正画面を必ず経由する(AI一発登録は行わない)
    final confirmed = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(builder: (_) => ScanConfirmScreen(scanResult: result!)),
    );
    return confirmed;
  }
}

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
