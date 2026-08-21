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
class DocumentScanService {
  // TODO: 本番運用前に、このAPIキーをクライアントへ直接埋め込む方式から
  // バックエンド経由の呼び出し(キーをサーバー側にのみ保持)に変更することを推奨。
  // 現状はプロトタイプとして直接呼び出している。
  static const String _endpoint =
      'https://nakano-doc-intelligence.cognitiveservices.azure.com';
  static const String _apiKey = String.fromEnvironment(
    'AZURE_DOC_INTEL_KEY',
    defaultValue: '<<AZURE_DOC_INTEL_KEY>>',
  );
  static const String _modelId = 'sdrs-repair-report-v1';
  static const String _apiVersion = '2024-11-30';

  /// 画像バイト列を渡してAzureで解析し、フィールド抽出結果を返す。
  /// 戻り値: フィールドキー(Pascal case) -> 値 のMap。未検出は空文字。
  static Future<ScanResult> analyzeImage(Uint8List imageBytes) async {
    final analyzeUri = Uri.parse(
      '$_endpoint/documentintelligence/documentModels/$_modelId:analyze'
      '?api-version=$_apiVersion',
    );

    final postResp = await http.post(
      analyzeUri,
      headers: {
        'Ocp-Apim-Subscription-Key': _apiKey,
        'Content-Type': 'application/octet-stream',
      },
      body: imageBytes,
    );

    if (postResp.statusCode != 202) {
      throw DocumentScanException(
        'スキャン解析の開始に失敗しました (HTTP ${postResp.statusCode})\n${postResp.body}',
      );
    }

    final opLocation = postResp.headers['operation-location'];
    if (opLocation == null) {
      throw DocumentScanException('解析結果の取得先(Operation-Location)が見つかりません');
    }

    // ポーリングで結果を待つ(最大30秒、1秒間隔)
    final resultUri = Uri.parse(opLocation);
    Map<String, dynamic>? resultJson;
    for (var i = 0; i < 30; i++) {
      await Future.delayed(const Duration(seconds: 1));
      final getResp = await http.get(
        resultUri,
        headers: {'Ocp-Apim-Subscription-Key': _apiKey},
      );
      if (getResp.statusCode != 200) {
        throw DocumentScanException(
          '解析結果の取得に失敗しました (HTTP ${getResp.statusCode})',
        );
      }
      final body = jsonDecode(utf8.decode(getResp.bodyBytes))
          as Map<String, dynamic>;
      final status = body['status'] as String?;
      if (status == 'succeeded') {
        resultJson = body;
        break;
      } else if (status == 'failed') {
        throw DocumentScanException('AI解析に失敗しました');
      }
      // status == 'running' or 'notStarted' -> 継続ポーリング
    }

    if (resultJson == null) {
      throw DocumentScanException('解析がタイムアウトしました。もう一度お試しください');
    }

    final analyzeResult =
        resultJson['analyzeResult'] as Map<String, dynamic>? ?? {};
    final documents = analyzeResult['documents'] as List<dynamic>? ?? [];
    if (documents.isEmpty) {
      throw DocumentScanException('作業報告書のフォーマットを認識できませんでした');
    }
    final doc = documents.first as Map<String, dynamic>;
    final docConfidence = (doc['confidence'] as num?)?.toDouble() ?? 0.0;
    final fieldsRaw = doc['fields'] as Map<String, dynamic>? ?? {};

    final values = <String, String>{};
    final confidences = <String, double>{};
    for (final entry in fieldsRaw.entries) {
      final fieldData = entry.value as Map<String, dynamic>;
      final content = fieldData['content'] as String? ?? '';
      final confidence = (fieldData['confidence'] as num?)?.toDouble() ?? 0.0;
      values[entry.key] = content;
      confidences[entry.key] = confidence;
    }

    // メーカー名の社名変更対応(ユーザー指示: 旧社名は新社名「SDRS株式会社」に統一)
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
  ScanFieldDef('WorkerName', '作業者氏名'),
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
