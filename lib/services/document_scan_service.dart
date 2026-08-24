import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../utils/maker_name_normalizer.dart';

/// Azure AI Document Intelligence カスタムテンプレートモデル
/// (sdrs-repair-report-v1) を使い、SE作業報告書の画像から
/// 23項目を自動抽出するサービス。
///
/// 【重要】AI一発登録は行わない。抽出結果は必ず
/// 「確認・修正画面」でユーザーが目視確認・修正してから
/// 登録するフローに限定する(社内方針)。
///
/// 【セキュリティ設計】
/// Document Intelligenceの Subscription Key はクライアント(このアプリ)には
/// 一切埋め込まない。代わりに Azure Functions の中継エンドポイント
/// (nakano-scan-proxy) を経由して解析を行う。中継Functionにのみ
/// Document Intelligenceキーを保持し、クライアントはFunction呼び出し用の
/// Function Key(呼び出し権限のみ、Document Intelligence自体は操作不可)を持つ。
class DocumentScanService {
  // 中継Function(Azure Functions)のエンドポイント。
  // Document Intelligence の Subscription Key はサーバー側(App Settings)に
  // のみ保持され、ここには含まれない。
  static const String _proxyEndpoint =
      'https://nakano-scan-proxy.azurewebsites.net/api/scan';

  // Function呼び出し用のキー。Document Intelligenceそのものへの権限はなく、
  // この中継Functionを呼び出す権限のみを持つ。ビルド時に埋め込む。
  static const String _functionKey = String.fromEnvironment(
    'SCAN_PROXY_FUNCTION_KEY',
    defaultValue: '<<SCAN_PROXY_FUNCTION_KEY>>',
  );

  /// 通信の最大リトライ回数。
  ///
  /// 【背景】作業現場(冷凍機械室・地下・バックヤードの鉄扉内など)は
  /// 電波が不安定な場所が多く、一度の通信失敗だけで即座にエラーとして
  /// ユーザーに撮影し直しを求めるのは負担が大きい。一時的な電波の乱れは
  /// 自動的に再送してカバーし、本当に電波が届かない場合のみユーザーに
  /// 伝える。
  static const int _maxAttempts = 3;

  /// 画像バイト列を渡して中継Function経由でAzureに解析させ、
  /// フィールド抽出結果を返す。
  /// 戻り値: フィールドキー(Pascal case) -> 値 のMap。未検出は空文字。
  static Future<ScanResult> analyzeImage(Uint8List imageBytes) async {
    final uri = Uri.parse('$_proxyEndpoint?code=$_functionKey');

    http.Response? resp;
    Object? lastError;

    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        resp = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/octet-stream'},
              body: imageBytes,
            )
            .timeout(const Duration(seconds: 25));
        break; // 成功したのでリトライループを抜ける
      } on TimeoutException catch (e) {
        lastError = e;
      } catch (e) {
        // 電波が不安定な現場(冷凍機械室・地下・バックヤード等)では、
        // 通信が一時的に切れることが多い。ここで即座にエラーとせず、
        // 電波が回復するのを期待して間隔を空けてリトライする。
        lastError = e;
      }

      if (attempt < _maxAttempts) {
        await Future.delayed(Duration(seconds: attempt * 2)); // 2秒, 4秒 と間隔を広げる
      }
    }

    if (resp == null) {
      // 【重要】$maxAttempts回すべて失敗 = 端末からAzureまで一度も
      // 通信が成立していない可能性が高い(電波が届いていない)。
      // 診断のため実際の例外の型名も付記する。
      final errorType = lastError?.runtimeType.toString() ?? '';
      throw DocumentScanException(
        '通信環境が不安定なため、サーバーに接続できませんでした($_maxAttempts回再送を試みました)。\n'
        '電波の良い場所(店舗事務所の出入口付近など)に移動してから、もう一度お試しください。'
        '${errorType.isNotEmpty ? '\n[$errorType]' : ''}',
      );
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw DocumentScanException(
        'サーバーからの応答を解釈できませんでした (HTTP ${resp.statusCode})',
      );
    }

    if (resp.statusCode != 200) {
      final errorMsg = body['error'] as String? ?? 'スキャン解析に失敗しました';
      throw DocumentScanException('$errorMsg (HTTP ${resp.statusCode})');
    }

    final valuesRaw = body['values'] as Map<String, dynamic>? ?? {};
    final confidencesRaw = body['confidences'] as Map<String, dynamic>? ?? {};
    final docConfidence =
        (body['documentConfidence'] as num?)?.toDouble() ?? 0.0;

    final values = <String, String>{
      for (final entry in valuesRaw.entries)
        entry.key: entry.value as String? ?? '',
    };
    final confidences = <String, double>{
      for (final entry in confidencesRaw.entries)
        entry.key: (entry.value as num?)?.toDouble() ?? 0.0,
    };

    // メーカー名の社名変更対応(サーバー側でも正規化済みだが、念のため
    // クライアント側でも冪等に正規化しておく)
    if (values.containsKey('MakerName')) {
      values['MakerName'] = normalizeMakerName(values['MakerName']);
    }

    return ScanResult(
      values: values,
      confidences: confidences,
      documentConfidence: docConfidence,
    );
  }
}

/// スキャン解析結果
class ScanResult {
  final Map<String, String> values; // フィールドキー -> 抽出値
  final Map<String, double> confidences; // フィールドキー -> 信頼度(0.0〜1.0)
  final double documentConfidence; // ドキュメント全体の信頼度

  ScanResult({
    required this.values,
    required this.confidences,
    required this.documentConfidence,
  });

  String value(String key) => values[key] ?? '';

  /// 信頼度が閾値未満のフィールドは要注意としてUI上で強調表示するために使う
  bool isLowConfidence(String key, {double threshold = 0.7}) {
    final c = confidences[key];
    if (c == null) return true;
    return c < threshold;
  }
}

class DocumentScanException implements Exception {
  final String message;
  DocumentScanException(this.message);
  @override
  String toString() => message;
}

/// 抽出フィールドの定義(Azureモデルのフィールドキー <-> 日本語ラベル)。
/// generate_training_labels.py の FIELD_DEFINITIONS と対応。
class ScanFieldDef {
  final String key; // Azureモデルのfield key (PascalCase)
  final String label; // 日本語ラベル

  const ScanFieldDef(this.key, this.label);
}

const List<ScanFieldDef> kScanFieldDefinitions = [
  ScanFieldDef('StoreNumber', '店番'),
  ScanFieldDef('StoreName', '店名'),
  ScanFieldDef('Address', '住所'),
  ScanFieldDef('Tel', 'TEL'),
  ScanFieldDef('VisitDate', '作業実施日'),
  ScanFieldDef('StartTime', '作業時間(開始)'),
  ScanFieldDef('EndTime', '作業時間(終了)'),
  // 【方針】作業者氏名はOCR対象外とする。
  // 現場作業者はほぼ全員アプリ登録済みの社員であるため、自由入力(OCR含む)より
  // 従業員マスタからの選択の方が精度・運用効率ともに優れる。
  // Azureモデル自体はWorkerNameフィールドを抽出するが、ここで定義から外すことで
  // 確認・修正画面(ScanConfirmScreen)には表示されず、抽出値も一切使用されない。
  // 作業者氏名の入力はreport_edit_screen.dartの「従業員選択+手入力併用」欄で行う。
  ScanFieldDef('RecoveryAmountKg', '冷媒回収量(kg)'),
  ScanFieldDef('ChargeAmountKg', '冷媒充填量(kg)'),
  ScanFieldDef('EquipmentName', '設備名称'),
  ScanFieldDef('DeliveryDate', '納品日'),
  ScanFieldDef('AssetNo', '資産管理No'),
  ScanFieldDef('Barcode', 'ランダムバーコード'),
  ScanFieldDef('MakerName', 'メーカー名'),
  ScanFieldDef('ModelNo', '型式'),
  ScanFieldDef('MachineNo', '機番'),
  ScanFieldDef('PartCategory', '部位'),
  ScanFieldDef('PartDetail', '詳細部位'),
  ScanFieldDef('Symptom', '事象'),
  ScanFieldDef('SymptomDetail', '事象補足'),
  ScanFieldDef('Cause', '原因'),
  ScanFieldDef('ActionContent', '処置内容'),
];
