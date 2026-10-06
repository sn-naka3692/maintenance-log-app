// 【回帰テスト・2026-10-06追加】
//
// 作業報告書スキャン機能(Azure Document Intelligence経由)の
// レスポンス解析ロジックを検証する。
//
// 【背景】2026-10-01に実際に発生した事故(HTTP 401エラー)は
// Azure Functions中継エンドポイントの認証キーの問題だったが、
// その調査時に「サーバーが想定外のレスポンス形式を返した場合に
// クライアント側がどう振る舞うか」の既存テストが一切なかったことが
// 判明した。本テストでは、HTTP通信自体は行わず、
// 「サーバーが返すJSON構造」→「ScanResultに格納される値」の
// 変換ロジック(parseScanResultBody)のみを検証する。
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/services/document_scan_service.dart';

void main() {
  group('parseScanResultBody(サーバーレスポンス解析)', () {
    test('正常なレスポンス(全フィールド揃っている)を正しく解析する', () {
      final body = {
        'values': {'MakerName': 'ダイキン', 'StoreName': '札幌本店'},
        'confidences': {'MakerName': 0.95, 'StoreName': 0.88},
        'documentConfidence': 0.9,
        'docType': 'SEDocType',
      };

      final result = parseScanResultBody(body);

      expect(result.values['StoreName'], '札幌本店');
      expect(result.confidences['MakerName'], 0.95);
      expect(result.documentConfidence, 0.9);
      expect(result.docType, 'SEDocType');
    });

    test(
      '古い(docType未対応)サーバーレスポンスでも例外にならず、'
      'docTypeが空文字になる(SE用フィールド定義へのフォールバック用)',
      () {
        final body = {
          'values': {'StoreName': '札幌本店'},
          'confidences': <String, dynamic>{},
          'documentConfidence': 0.5,
          // docTypeキー自体が存在しない
        };

        final result = parseScanResultBody(body);

        expect(result.docType, '');
      },
    );

    test('values/confidencesキーが欠落していても例外にならず空のMapになる', () {
      final body = <String, dynamic>{};

      final result = parseScanResultBody(body);

      expect(result.values, isEmpty);
      expect(result.confidences, isEmpty);
      expect(result.documentConfidence, 0.0);
      expect(result.docType, '');
    });

    test('MakerNameの正規化(社名変更対応)が適用される', () {
      // normalizeMakerNameが実際に何らかの変換を行う既知の入力がない場合、
      // 「値が保持されたまま存在する」ことだけを確認する(正規化ロジック
      // 自体はmaker_name_normalizer側の既存テストが担当)。
      final body = {
        'values': {'MakerName': '三菱電機'},
        'confidences': <String, dynamic>{},
        'documentConfidence': 0.5,
        'docType': 'SEDocType',
      };

      final result = parseScanResultBody(body);

      expect(result.values.containsKey('MakerName'), true);
      expect(result.values['MakerName'], isNotEmpty);
    });

    test('Barcodeフィールドの正規化処理が例外なく通る', () {
      final body = {
        'values': {'Barcode': '1234567890'},
        'confidences': <String, dynamic>{},
        'documentConfidence': 0.5,
        'docType': 'SEDocType',
      };

      final result = parseScanResultBody(body);

      expect(result.values.containsKey('Barcode'), true);
    });

    test('日付系フィールド(VisitDate等)の正規化処理が例外なく通る', () {
      final body = {
        'values': {'VisitDate': '2026年10月6日'},
        'confidences': <String, dynamic>{},
        'documentConfidence': 0.5,
        'docType': 'SEDocType',
      };

      final result = parseScanResultBody(body);

      expect(result.values.containsKey('VisitDate'), true);
    });

    test('confidence値が数値型(int/double混在)でも正しく変換される', () {
      final body = {
        'values': {'StoreName': '札幌本店'},
        'confidences': {'StoreName': 1}, // int型で返るケースも想定
        'documentConfidence': 1,
        'docType': 'SEDocType',
      };

      final result = parseScanResultBody(body);

      expect(result.confidences['StoreName'], 1.0);
      expect(result.documentConfidence, 1.0);
    });
  });

  group('ScanResult', () {
    test('isProWanDocumentはdocTypeがProWanDocTypeの場合のみtrue', () {
      final seResult = ScanResult(
        values: const {},
        confidences: const {},
        documentConfidence: 0,
        docType: 'SEDocType',
      );
      final proWanResult = ScanResult(
        values: const {},
        confidences: const {},
        documentConfidence: 0,
        docType: 'ProWanDocType',
      );

      expect(seResult.isProWanDocument, false);
      expect(proWanResult.isProWanDocument, true);
    });

    test('isLowConfidenceは信頼度が閾値未満の場合trueを返す', () {
      final result = ScanResult(
        values: const {'StoreName': '札幌本店'},
        confidences: const {'StoreName': 0.5},
        documentConfidence: 0.5,
      );

      expect(result.isLowConfidence('StoreName', threshold: 0.7), true);
      expect(result.isLowConfidence('StoreName', threshold: 0.3), false);
    });

    test('isLowConfidenceは信頼度情報がないフィールドは要注意(true)扱いにする', () {
      final result = ScanResult(
        values: const {},
        confidences: const {},
        documentConfidence: 0,
      );

      expect(result.isLowConfidence('存在しないキー'), true);
    });

    test('value()は未検出フィールドに対して空文字を返す(nullを返さない)', () {
      final result = ScanResult(
        values: const {},
        confidences: const {},
        documentConfidence: 0,
      );

      expect(result.value('存在しないキー'), '');
    });
  });

  group('scanFieldDefinitionsFor(フィールド定義の切り替え)', () {
    test('docTypeがProWanDocTypeの場合プロワン用フィールド定義を返す', () {
      final defs = scanFieldDefinitionsFor('ProWanDocType');
      expect(defs, kProWanScanFieldDefinitions);
    });

    test('docTypeがSEDocTypeの場合SE用フィールド定義を返す', () {
      final defs = scanFieldDefinitionsFor('SEDocType');
      expect(defs, kScanFieldDefinitions);
    });

    test(
      'docTypeが空文字・不明な値の場合、後方互換のためSE用フィールド定義に'
      'フォールバックする',
      () {
        expect(scanFieldDefinitionsFor(''), kScanFieldDefinitions);
        expect(scanFieldDefinitionsFor('不明な値'), kScanFieldDefinitions);
      },
    );
  });
}
