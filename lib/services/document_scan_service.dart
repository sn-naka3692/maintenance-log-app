import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

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
  /// 【背景】ネットワークが一時的に不安定な場合に、一度の通信失敗だけで
  /// 即座にエラーとしてユーザーに撮影し直しを求めるのは負担が大きい。
  /// 一時的な通信の乱れは自動的に再送してカバーし、本当に接続できない
  /// 場合のみユーザーに伝える。
  static const int _maxAttempts = 3;

  /// 1回の通信あたりのタイムアウト秒数。
  ///
  /// 【重要】中継Function(nakano-scan-proxy)は、Azure Document
  /// Intelligenceの解析完了を最大30秒間ポーリングしてから応答を返す
  /// 設計になっている(function_app.py参照)。そのため、この値は
  /// 必ず35秒より長く設定すること。過去に25秒に短縮してしまった際、
  /// Azure側が正常に処理していても常にクライアント側が先にタイムアウト
  /// してしまい、通信環境の良し悪しに関わらず(事務所のWi-Fiでも)必ず
  /// 失敗するという不具合を起こした。
  static const int _timeoutSeconds = 45;

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
            .timeout(Duration(seconds: _timeoutSeconds));
        break; // 成功したのでリトライループを抜ける
      } on TimeoutException catch (e) {
        lastError = e;
      } catch (e) {
        // 通信が一時的に不安定な場合、ここで即座にエラーとせず、
        // 通信環境が回復するのを期待して間隔を空けてリトライする。
        lastError = e;
      }

      if (attempt < _maxAttempts) {
        await Future.delayed(Duration(seconds: attempt * 2)); // 2秒, 4秒 と間隔を広げる
      }
    }

    if (resp == null) {
      // 【重要】$maxAttempts回すべて失敗。診断のため以下を全て付記する:
      // - 実際の例外の型名・内容(サポート対応時に伝えてもらうことで
      //   原因の切り分けがしやすくなる)
      // - 実行プラットフォーム(Web版かAndroidネイティブか)
      // - アプリのバージョン・ビルド番号(古いバージョンを使っていないか確認用)
      final errorType = lastError?.runtimeType.toString() ?? '';
      final errorDetail = lastError?.toString() ?? '';
      final platform = kIsWeb ? 'Web版(ブラウザ/ホーム画面PWA)' : 'Androidアプリ(APK)';

      String versionInfo = '';
      try {
        final info = await PackageInfo.fromPlatform();
        versionInfo = 'v${info.version}+${info.buildNumber}';
      } catch (_) {
        // バージョン情報の取得に失敗しても診断メッセージ自体は表示する
      }

      final sizeKb = (imageBytes.length / 1024).toStringAsFixed(0);
      throw DocumentScanException(
        'サーバーへの接続に失敗しました($_maxAttempts回再送しましたが成功しませんでした)。\n'
        'しばらく時間をおくか、通信環境の良い場所でもう一度お試しください。\n'
        '[実行環境: $platform${versionInfo.isNotEmpty ? ' $versionInfo' : ''} / 画像サイズ: ${sizeKb}KB]'
        '${errorType.isNotEmpty ? '\n[エラー種別: $errorType]' : ''}'
        '${errorDetail.isNotEmpty && errorDetail != errorType ? '\n[詳細: $errorDetail]' : ''}',
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
    // サーバー側(function_app.py)が判定した書式種別。
    // "SEDocType" | "ProWanDocType"。未対応の古いレスポンスの場合は
    // 空文字となり、呼び出し元はSE用フィールド定義にフォールバックする。
    final docType = body['docType'] as String? ?? '';

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
      docType: docType,
    );
  }

  // ------------------------------------------------------------
  // 【月末チェック(日報記入率)機能】複数ページPDF一括解析
  // ------------------------------------------------------------
  //
  // 管理者が月末に紙の作業報告書をコピー機でまとめてスキャンしたPDF
  // (1ページ=1案件)をアップロードし、ページ単位に分割して一括OCR解析する。
  // Azure Functions側の実行時間上限対策のため、[maxPagesPerRequest]件ずつ
  // ページ範囲を指定して複数回リクエストする。
  static const String _batchProxyEndpoint =
      'https://nakano-scan-proxy.azurewebsites.net/api/scanBatch';

  /// サーバー側(Azure Function)の1リクエストあたりページ数上限。
  /// function_app.py の BATCH_MAX_PAGES_PER_REQUEST と一致させること。
  static const int maxPagesPerRequest = 15;

  /// 1ページあたりの解析に要する見込み秒数(タイムアウト算出用)。
  /// サーバー側は1ページごとに最大45秒ポーリングするため、
  /// 直列換算での安全マージンを見て設定する。
  static const int _perPageTimeoutSeconds = 50;

  /// PDFバイト列のうち [startPage]〜[endPage](1始まり・両端含む)の範囲を
  /// バッチ解析する。1回の呼び出しで最大 [maxPagesPerRequest] ページまで。
  static Future<BatchScanResult> analyzeBatch(
    Uint8List pdfBytes, {
    required int startPage,
    required int endPage,
  }) async {
    final pageCount = endPage - startPage + 1;
    if (pageCount > maxPagesPerRequest) {
      throw DocumentScanException(
        '1回のリクエストで処理できるページ数は$maxPagesPerRequestページまでです',
      );
    }

    final uri = Uri.parse(
      '$_batchProxyEndpoint?code=$_functionKey&startPage=$startPage&endPage=$endPage',
    );

    http.Response? resp;
    Object? lastError;

    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        resp = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/pdf'},
              body: pdfBytes,
            )
            .timeout(Duration(seconds: pageCount * _perPageTimeoutSeconds));
        break;
      } on TimeoutException catch (e) {
        lastError = e;
      } catch (e) {
        lastError = e;
      }

      if (attempt < _maxAttempts) {
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }

    if (resp == null) {
      final errorType = lastError?.runtimeType.toString() ?? '';
      final errorDetail = lastError?.toString() ?? '';
      throw DocumentScanException(
        'サーバーへの接続に失敗しました($_maxAttempts回再送しましたが成功しませんでした)。\n'
        'しばらく時間をおくか、通信環境の良い場所でもう一度お試しください。\n'
        '[対象ページ: $startPage-$endPage]'
        '${errorType.isNotEmpty ? '\n[エラー種別: $errorType]' : ''}'
        '${errorDetail.isNotEmpty && errorDetail != errorType ? '\n[詳細: $errorDetail]' : ''}',
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
      final errorMsg = body['error'] as String? ?? 'PDF一括解析に失敗しました';
      throw DocumentScanException('$errorMsg (HTTP ${resp.statusCode})');
    }

    final totalPages = (body['totalPages'] as num?)?.toInt() ?? 0;
    final resultsRaw = body['results'] as List<dynamic>? ?? [];
    final pageResults = resultsRaw
        .map((e) => PageScanResult.fromMap(e as Map<String, dynamic>))
        .toList();

    return BatchScanResult(totalPages: totalPages, pageResults: pageResults);
  }

  // ------------------------------------------------------------
  // 【現場からのPDFアップロード対応・2026-08追加】
  // ------------------------------------------------------------
  //
  // 現場サイド(プロワン・店舗カルテ等の業務システム)から、作業報告書を
  // 直接PDFとして出力できる環境があるという要望を受け、カメラ撮影に加えて
  // 「PDFファイルをアップロードして読み取る」ルートを追加する。
  //
  // 【実装方針】サーバー側(nakano-scan-proxy)には新しいエンドポイントを
  // 追加せず、既存の /scanBatch(月末チェック機能で使用中の複数ページ対応
  // エンドポイント)を「1ページのみ処理する」形で呼び出すことで実現する。
  // これにより、月末チェック機能と全く同じOCRロジック(SE用/プロワン用
  // 両モデル並行解析・docType自動判定)がそのまま使え、サーバー側の
  // 二重実装を避けられる。
  //
  // PDFが複数ページの場合は「1ページ目のみ」を解析対象とする
  // (作業報告書アプリの出力は通常1案件=1ページのため)。
  static Future<ScanResult> analyzePdf(Uint8List pdfBytes) async {
    final batch = await analyzeBatch(pdfBytes, startPage: 1, endPage: 1);
    if (batch.pageResults.isEmpty) {
      throw DocumentScanException('PDFの解析結果を取得できませんでした');
    }
    final page = batch.pageResults.first;
    if (page.isError) {
      throw DocumentScanException(page.error ?? 'PDFの解析に失敗しました');
    }
    if (page.isLowConfidence) {
      // 単発画像スキャン(/scan)と挙動を揃え、全体信頼度が閾値未満の場合は
      // 確認画面へは進ませず、撮り直し(選び直し)を促す。
      throw DocumentScanException(
        '作業報告書のフォーマットを認識できませんでした。'
        '別のPDFを選ぶか、カメラで撮影してお試しください'
        '(信頼度: ${(page.documentConfidence * 100).toStringAsFixed(0)}%)',
      );
    }
    return ScanResult(
      values: page.values,
      confidences: page.confidences,
      documentConfidence: page.documentConfidence,
      docType: page.docType,
    );
  }
}

/// PDF一括解析の結果(全体)
class BatchScanResult {
  final int totalPages;
  final List<PageScanResult> pageResults;

  const BatchScanResult({required this.totalPages, required this.pageResults});
}

/// PDF一括解析の1ページ分の結果
class PageScanResult {
  final int pageNumber;
  final String status; // "ok" | "low_confidence" | "error"

  /// サーバー側(function_app.py)がSE用・プロワン用の2モデルを並行解析し、
  /// confidence比較の結果判定した書式種別。
  /// "SEDocType" | "ProWanDocType"。月末チェックは全案件対象のため、
  /// このdocTypeに応じて突合キー(弊社受付No or 伝票No)を切り替えること。
  final String docType;
  final double documentConfidence;
  final Map<String, String> values;
  final Map<String, double> confidences;
  final String? error;

  const PageScanResult({
    required this.pageNumber,
    required this.status,
    required this.docType,
    required this.documentConfidence,
    required this.values,
    required this.confidences,
    this.error,
  });

  bool get isOk => status == 'ok';
  bool get isLowConfidence => status == 'low_confidence';
  bool get isError => status == 'error';

  bool get isSeDocument => docType == 'SEDocType';
  bool get isProWanDocument => docType == 'ProWanDocType';

  /// SE店舗案件の突合キーとして使う「弊社受付No」(SEDocTypeの場合のみ意味を持つ)
  String get companyReceiptNumber => values['CompanyReceiptNumber'] ?? '';

  /// プロワン管轄案件の突合キーとして使う「伝票No(案件管理番号)」
  /// (ProWanDocTypeの場合のみ意味を持つ)
  String get proWanRefNumber => values['ProWanRefNumber'] ?? '';

  /// 【2026-08-28追加・月末チェックの同一伝票No複数案件対応】
  /// プロワン報告書の「作業開始日」(ProWanDocTypeの場合のみ意味を持つ)。
  /// 同じ伝票No(案件管理番号)で複数の日程(=複数ページ、複数WorkReport)
  /// が存在するケースがあり、伝票Noだけでは日報を一意に特定できない。
  /// この値を日報側のvisitDateと突合することで、どの日程のページかを
  /// 区別する補助キーとして使う。SE用紙にはこの項目はないため、
  /// SEDocTypeの場合は常に空文字。
  String get workStartDate => values['WorkStartDate'] ?? '';

  /// このページ種別に応じた突合キーを返す(未判定の場合は空文字)。
  String get matchingKey {
    if (isProWanDocument) return proWanRefNumber;
    if (isSeDocument) return companyReceiptNumber;
    return '';
  }

  /// 「他◯名」の人数部分(数字文字列、未検出は空文字)。SE用モデルのみ抽出。
  String get otherWorkersCount => values['OtherWorkersCount'] ?? '';

  factory PageScanResult.fromMap(Map<String, dynamic> map) {
    final valuesRaw = map['values'] as Map<String, dynamic>? ?? {};
    final confidencesRaw = map['confidences'] as Map<String, dynamic>? ?? {};
    return PageScanResult(
      pageNumber: (map['pageNumber'] as num?)?.toInt() ?? 0,
      status: map['status'] as String? ?? 'error',
      docType: map['docType'] as String? ?? '',
      documentConfidence:
          (map['documentConfidence'] as num?)?.toDouble() ?? 0.0,
      values: {
        for (final e in valuesRaw.entries) e.key: e.value as String? ?? '',
      },
      confidences: {
        for (final e in confidencesRaw.entries)
          e.key: (e.value as num?)?.toDouble() ?? 0.0,
      },
      error: map['error'] as String?,
    );
  }
}

/// スキャン解析結果
class ScanResult {
  final Map<String, String> values; // フィールドキー -> 抽出値
  final Map<String, double> confidences; // フィールドキー -> 信頼度(0.0〜1.0)
  final double documentConfidence; // ドキュメント全体の信頼度

  /// サーバー側(nakano-scan-proxy)がSE用・プロワン用の2モデルを並行解析し、
  /// confidence比較の結果判定した書式種別。
  /// "SEDocType" | "ProWanDocType"。
  /// 古いレスポンス(docType未対応)の場合は空文字となり、呼び出し元は
  /// SE用フィールド定義にフォールバックする。
  final String docType;

  ScanResult({
    required this.values,
    required this.confidences,
    required this.documentConfidence,
    this.docType = '',
  });

  /// プロワン作業報告書として判定されたかどうか。
  bool get isProWanDocument => docType == 'ProWanDocType';

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
  // 【2026-XX追加】月末チェック(日報記入率)機能のための2項目。
  // 案件マッチングの主キーとなる「弊社受付No」と、紙報告書に記載された
  // 「他◯名」の人数(ヘルパー個人特定はアプリ側データとの突合が必要)。
  ScanFieldDef('CompanyReceiptNumber', '弊社受付No'),
  ScanFieldDef('OtherWorkersCount', '他◯名(人数)'),
];

/// プロワン作業報告書用の抽出フィールド定義。
/// generate_training_labels.py の FIELD_DEFINITIONS(プロワン用モデル
/// prowan-report-v1)と対応。
///
/// 【設計方針・2026-08-28改訂】
/// 従来はCSVキャッシュ(プロワンから毎日書き出されるエクスポート)との
/// 照合キーとなる3項目(伝票No・店名・作業開始日)のみを抽出し、実際の
/// 顧客名・作業内容等はCSV側の値を転記する設計だった。
/// しかし、現場の日報入力(このスキャン)は事務所側のCSVエクスポートより
/// 時系列的に先行するため、リアルタイムのスキャン時点ではCSVに該当データが
/// まだ存在しない(またはエクスポート対象外になっている)ケースが本番で
/// 発生し、「該当する案件が見つかりません」という不具合の温床になっていた。
/// 作業報告書PDF自体に顧客名・部門・系統番号・型式・依頼内容・原因・
/// 作業内容・訪問結果・冷媒情報等が全て印字されているため、これらを
/// 直接OCRで読み取ることで、CSV照合を介さずに完結させる設計に変更した。
/// (CSV照合ロジック自体は、月次の日報入力漏れチェック機能
/// (submission_checks)専用として別途維持する。)
/// 【方針・2026-08-28追記】技術者氏名(TechnicianName)はOCR対象外とする。
/// 「冷媒充填・回収証明書欄」の手書き署名を読み取る項目だったが、実際には
/// 日報作成者(ログインユーザー=WorkReport.authorName)と一致するケースが
/// 大半であり、二重管理・二重入力の温床になっていた。また手書き署名の
/// 認識精度はOCRとして本質的に不安定(学習後confidence 0.231)で、追加学習
/// による改善が見込みにくいフィールドだったため、抽出対象から除外した。
/// Azureモデル自体はTechnicianNameフィールドを抽出しなくなった
/// (generate_training_labels.py / fields.json も17項目に更新済み)。
/// 表示・PDF/Excel出力側は日報作成者(authorName)を使う。
const List<ScanFieldDef> kProWanScanFieldDefinitions = [
  ScanFieldDef('ProWanRefNumber', '案件管理番号(伝票No)'),
  ScanFieldDef('StoreName', '店名'),
  ScanFieldDef('ClientName', '得意先名'),
  ScanFieldDef('ReceiptDate', '受付日'),
  ScanFieldDef('WorkStartDate', '作業開始日'),
  ScanFieldDef('Department', '部門'),
  ScanFieldDef('SystemNumber', '系統番号・名'),
  ScanFieldDef('CaseNo', 'ケースNo'),
  ScanFieldDef('EquipmentLocation', '修理機器・場所'),
  ScanFieldDef('ModelSerial', '製造番号・型式'),
  ScanFieldDef('RequestContent', 'ご依頼内容'),
  ScanFieldDef('Cause', '原因(故障個所)'),
  ScanFieldDef('VisitResult', '訪問結果'),
  ScanFieldDef('WorkContent', '作業内容(処置)'),
  ScanFieldDef('FuturePlan', '今後の予定(未完了時)'),
  ScanFieldDef('RefrigerantType', '冷媒の種類'),
  ScanFieldDef('RefrigerantAmount', '冷媒量(kg)'),
];

/// スキャン結果のdocTypeに応じて、確認画面に表示すべきフィールド定義
/// リストを返す。docTypeが未設定・不明("SEDocType"以外かつ
/// "ProWanDocType"以外)の場合は、後方互換のためSE用リストへ
/// フォールバックする。
List<ScanFieldDef> scanFieldDefinitionsFor(String docType) {
  if (docType == 'ProWanDocType') {
    return kProWanScanFieldDefinitions;
  }
  return kScanFieldDefinitions;
}
