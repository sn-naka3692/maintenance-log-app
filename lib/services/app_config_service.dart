import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';
import '../build_info.dart';

/// アプリ全体の「最低利用可能バージョン(ビルド番号)」および
/// 「現在配布中の最新バージョン」を管理するサービス。
///
/// 【目的1・強制アップデートゲート】現場で古いバージョンのアプリ
/// (古いAPK)が使われ続けることで、仕様変更(例: 作業者氏名の入力方式
/// 変更など)が反映されず、情報の回収に支障が出る事態を防ぐための機能。
///
/// 【目的2・更新お知らせ(v1.2.13で追加)】強制ブロックとは異なり、
/// 「今より新しいバージョンが配布されている」ことを、ホーム画面上部で
/// やさしく気づかせるための機能。従来の`UpdateNoticeService`は
/// 「今動いているアプリに、すでに入っている更新履歴のうち未読のもの」
/// しか検知できず、まだ更新していない端末(=新しい更新履歴データ自体が
/// 入っていない端末)には永久に表示されないという欠陥があった。
/// この`latest_version`/`latest_build_number`を使うことで、
/// サーバー側(Firestore)の値と実機の値を直接比較でき、
/// 「まだ一度も更新していない古い端末」にも正しく通知できる。
///
/// 【設計】
/// - Firestoreの `app_config/settings` ドキュメント1件のみで、
///   下記の値をまとめて管理する。
///   - min_supported_build: 最低利用可能ビルド番号(強制ブロック用)
///   - latest_version / latest_build_number: 現在配布中の最新バージョン
///     (更新お知らせ用、ブロックはしない)
/// - アプリ起動時にこの値と、実機の実際のビルド番号(package_info_plus取得)を比較。
/// - 実機のビルド番号が min_supported_build 未満の場合、アプリ全体をブロックする
///   画面を表示し、日報の閲覧・入力を一切できないようにする。
/// - 実機のビルド番号が latest_build_number 未満の場合は、ブロックせずに
///   ホーム画面上部へ「新しいバージョンがあります」バナーを表示する。
/// - これらの設定値の変更は最高管理者のみが行える(system_architecture_screen.dart経由)。
///
/// 【安全策】
/// - ドキュメントが存在しない場合や読み込みに失敗した場合は「ブロックしない」
///   「通知しない」(fail-open)。誤ってこの機能自体でアプリが全社的に
///   使えなくなる/常に通知が出続ける事故を防ぐため。
/// - Web版はストア配布ではなくプレビュー用途のため、このチェック対象外とする
///   (常に最新のビルドがサーブされるため誤ブロック・誤通知の心配がない)。
class AppConfigService {
  static final AppConfigService instance = AppConfigService._internal();
  AppConfigService._internal();

  static const String _collection = 'app_config';
  static const String _docId = 'settings';

  DocumentReference<Map<String, dynamic>> get _doc =>
      FirebaseFirestore.instance.collection(_collection).doc(_docId);

  /// 実機(APK版)または「今実行中のコード」(Web版)のビルド番号を取得する。
  ///
  /// 【不具合修正・2026-09・Bug②対応】Web版では`package_info_plus`を
  /// 使わず、`build_info.dart`の`kCompiledBuildNumber`(コンパイル時に
  /// JSへ直接焼き込まれる定数)を返す。理由: `PackageInfo.fromPlatform()`の
  /// Web実装は実行時にHTTP経由で`version.json`を取得するだけの実装であり、
  /// 「サーバー上の最新値」を返してしまうため、タブが古いJSのまま動作して
  /// いても検知できない(ソース確認済みの既知の欠陥)。
  /// APK版は端末に実際にインストールされたビルド番号を正しく返すため、
  /// 従来通り`PackageInfo.fromPlatform()`を使用する。
  Future<int> getCurrentBuildNumber() async {
    if (kIsWeb) {
      return kCompiledBuildNumber;
    }
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  /// 現在のバージョン名(表示用、例: "1.1.6")を取得する。
  /// Web版は上記と同じ理由でコンパイル時定数を使用する。
  Future<String> getCurrentVersionName() async {
    if (kIsWeb) {
      return kCompiledVersionName;
    }
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// Firestoreから最新の設定値を取得する。
  /// ドキュメントが存在しない/読み込みに失敗した場合はnullを返す(fail-open)。
  ///
  /// 【v1.2.23で修正】Firestoreのデフォルト挙動では、オフラインキャッシュ
  /// (前回取得時の古い値)が先に返ってしまう場合がある。バージョン比較の
  /// 性質上、必ずサーバーの最新値を見る必要があるため、
  /// `GetOptions(source: Source.server)` を明示し、キャッシュ経由の
  /// 古い値で誤判定しないようにする。サーバーに到達できない場合は
  /// キャッシュへフォールバックする(完全な通信断でも極力fail-openを保つ)。
  Future<AppMinVersionConfig?> fetchConfig() async {
    try {
      DocumentSnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _doc.get(const GetOptions(source: Source.server));
      } catch (_) {
        // サーバー到達不可時のみキャッシュにフォールバック。
        snap = await _doc.get(const GetOptions(source: Source.cache));
      }
      if (!snap.exists) return null;
      final data = snap.data();
      if (data == null) return null;
      return AppMinVersionConfig.fromMap(data);
    } catch (_) {
      // 通信エラー・権限エラー等は「ブロックしない」方針(fail-open)。
      return null;
    }
  }

  /// 最高管理者が最低利用可能ビルド番号などを更新する。
  Future<void> updateConfig(AppMinVersionConfig config) async {
    await _doc.set(config.toMap(), SetOptions(merge: true));
  }

  /// 【更新お知らせ・v1.2.13で追加、v1.2.23でWeb版対応】実機(または
  /// ブラウザ)のビルド番号とFirestore側の `latest_build_number` を比較し、
  /// 「新しいバージョンが配布されている」かどうかを判定する。
  ///
  /// 【v1.2.23で修正】当初「Web版は常に最新のビルドが自動配信される」と
  /// いう前提でWeb版をチェック対象外にしていたが、これは誤りだった。
  /// Firebase Hostingへのデプロイ漏れや、ブラウザ側のキャッシュ/
  /// Service Workerにより、Web版でも実際には古いビルドが表示され続ける
  /// ケースがあることが判明した(2026-08 実際に発生)。
  /// そのため、Web版も同様にバージョン比較を行い、古い場合は
  /// バナー表示(Web版はページ再読み込みを促す)を行う。
  ///
  /// - `latest_build_number` が未設定(0)の場合や、通信・権限エラーが
  ///   発生した場合は「通知しない」(fail-open)。
  Future<UpdateAvailability> checkUpdateAvailability() async {
    try {
      final config = await fetchConfig();
      final currentBuild = await getCurrentBuildNumber();
      return evaluateUpdateAvailability(
        currentBuild: currentBuild,
        config: config,
      );
    } catch (_) {
      return UpdateAvailability.none;
    }
  }

  // ------------------------------------------------------------
  // 【月末チェック(日報記入率)機能】
  // 紙の作業報告書をOCR解析し、弊社受付Noを主キーとしてアプリ側の
  // 日報データと突合することで「未提出の日報」を検知する機能。
  // 全案件が対象だが、運用開始時の混乱を避けるため、最高管理者が
  // ON/OFFを切り替えられる段階導入方式とする(既定はOFF=fail-safe)。
  // ------------------------------------------------------------

  /// 月末チェック機能が有効かどうかを取得する。
  /// ドキュメント未設定・読み込み失敗時は false(無効)を返す(fail-safe)。
  Future<bool> fetchSubmissionCheckEnabled() async {
    try {
      final snap = await _doc.get();
      if (!snap.exists) return false;
      final data = snap.data();
      return (data?['submission_check_enabled'] as bool?) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 最高管理者が月末チェック機能のON/OFFを切り替える。
  Future<void> updateSubmissionCheckEnabled(bool enabled) async {
    await _doc.set({
      'submission_check_enabled': enabled,
      'submission_check_updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ------------------------------------------------------------
  // 【ベータ版配布(段階的リリース)・2026-10-06追加】
  //
  // 【目的】全社運用開始後、機能改善をリリースする際に「全社員へ一斉
  // 配布する前に、特定の数名(ベータテスター)だけに先行して新しい
  // ビルドを試してもらい、問題なければ全社配布に進む」という段階的
  // リリースを行うための仕組み。
  //
  // 【設計】既存の強制アップデートゲート/更新お知らせ(全社向け
  // latest_version/latest_build_number)とは完全に独立したフィールド
  // (beta_version/beta_build_number等)を同じ app_config/settings
  // ドキュメントに持たせる。全社向けの値を一切変更しないため、既存の
  // 正常動作している更新通知・強制ブロック機能には影響を与えない。
  //
  // 【安全策】beta_tester_uids に自分のuidが含まれていない社員には、
  // ベータ版の存在そのものが一切見えない(通知されない)。
  // ------------------------------------------------------------

  /// 最高管理者がベータ配布設定を更新する。
  Future<void> updateBetaConfig(AppMinVersionConfig config) async {
    await _doc.set({
      'beta_enabled': config.betaEnabled,
      'beta_version': config.betaVersion,
      'beta_build_number': config.betaBuildNumber,
      'beta_download_url': config.betaDownloadUrl,
      'beta_tester_uids': config.betaTesterUids,
      'beta_updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

/// 「サーバー側の最新ビルド番号」と「今動いている実機/ブラウザの
/// ビルド番号」を比較し、更新お知らせバナーを出すべきか判定する純粋関数。
///
/// 【テスト容易性のために意図的に切り出した・2026-10-06追加】
/// Firestore通信やプラットフォーム判定(kIsWeb等)を含まない、入力→出力が
/// 決定的な比較ロジックのみをここに集約する。これにより、
/// `test/app_config_service_test.dart` でFirebase初期化なしに
/// このロジックを回帰テストできる。
///
/// 【背景・2026-10-01に実際発生した事故】Web版ビルド時、サーバー側の
/// `latest_build_number`は正しく更新されていたのに、Web版の自己申告
/// ビルド番号(`build_info.dart`のコンパイル時定数)の更新を忘れたまま
/// デプロイしてしまい、「更新バナーをクリックしても表示が変わらない」
/// という不具合が発生した。この関数の単体テストでは、
/// 「サーバー値を更新したのにクライアント側の値を更新し忘れた」ような
/// パラメータの組み合わせを明示的にケースとして固定し、将来also同種の
/// 実装ミス(比較演算子の方向を間違える等)が入った場合に即座に
/// テストが失敗して検知できるようにする。
UpdateAvailability evaluateUpdateAvailability({
  required int currentBuild,
  required AppMinVersionConfig? config,
}) {
  if (config == null || config.latestBuildNumber <= 0) {
    return UpdateAvailability.none;
  }
  if (currentBuild >= config.latestBuildNumber) {
    return UpdateAvailability.none;
  }
  return UpdateAvailability(
    hasNewerVersion: true,
    latestVersion: config.latestVersion,
  );
}

/// 強制アップデートゲート(auth_gate.dart)の「アプリを全面ブロックすべきか」
/// を判定する純粋関数。[evaluateUpdateAvailability]と同じ理由
/// (テスト容易性・比較ロジック崩れの検知)で切り出している。
///
/// `min_supported_build`が未設定(0以下)の場合は常にブロックしない
/// (fail-open)。
bool shouldBlockForOutdatedBuild({
  required int currentBuild,
  required AppMinVersionConfig? config,
}) {
  if (config == null || config.minSupportedBuild <= 0) {
    return false;
  }
  return currentBuild < config.minSupportedBuild;
}

/// 【ベータ版配布・2026-10-06追加】現在ログイン中のユーザーが
/// ベータテスターに指定されているかどうかと、サーバー側の
/// ベータビルド番号を比較し、「ベータ版のお知らせバナーを表示すべきか」
/// を判定する純粋関数。
///
/// 【テスト容易性のために意図的に切り出した】[evaluateUpdateAvailability]
/// と同じ理由で、Firestore通信やFirebaseAuthの現在ユーザー取得を含まない
/// 決定的な比較ロジックのみをここに集約する。
///
/// - `beta_enabled` が false、または `beta_build_number` が未設定(0)の
///   場合は常に通知しない。
/// - 現在のuidが `beta_tester_uids` に含まれていない場合は通知しない
///   (ベータテスター以外には一切見えない)。
/// - 実機のビルド番号が `beta_build_number` 以上の場合は、すでに
///   そのベータビルドを使用中とみなし通知しない。
BetaAvailability evaluateBetaAvailability({
  required int currentBuild,
  required String? currentUid,
  required AppMinVersionConfig? config,
}) {
  if (config == null || !config.betaEnabled || config.betaBuildNumber <= 0) {
    return BetaAvailability.none;
  }
  if (currentUid == null || !config.betaTesterUids.contains(currentUid)) {
    return BetaAvailability.none;
  }
  if (currentBuild >= config.betaBuildNumber) {
    return BetaAvailability.none;
  }
  return BetaAvailability(
    hasBetaUpdate: true,
    betaVersion: config.betaVersion,
    betaDownloadUrl: config.betaDownloadUrl,
  );
}

/// 【ベータ版配布・2026-10-06追加】ベータ版お知らせの判定結果。
///
/// [hasBetaUpdate] が true の場合のみ、ベータテスターのホーム画面に
/// 「ベータ版が利用可能です」バナーを表示する。
class BetaAvailability {
  final bool hasBetaUpdate;
  final String betaVersion;
  final String betaDownloadUrl;

  const BetaAvailability({
    required this.hasBetaUpdate,
    required this.betaVersion,
    required this.betaDownloadUrl,
  });

  static const none = BetaAvailability(
    hasBetaUpdate: false,
    betaVersion: '',
    betaDownloadUrl: '',
  );
}

/// 「更新お知らせ(強制ではない)」の判定結果。
///
/// [hasNewerVersion] が true の場合のみ、ホーム画面に
/// 「新しいバージョンがあります」バナーを表示する。
class UpdateAvailability {
  final bool hasNewerVersion;
  final String latestVersion;

  const UpdateAvailability({
    required this.hasNewerVersion,
    required this.latestVersion,
  });

  static const none = UpdateAvailability(
    hasNewerVersion: false,
    latestVersion: '',
  );
}

/// 強制アップデートゲート及び更新お知らせの設定値。
class AppMinVersionConfig {
  /// これ未満のビルド番号のアプリはブロックされる(強制)。
  final int minSupportedBuild;

  /// ブロック画面に表示するお知らせ文(空の場合はデフォルト文言を使用)。
  final String message;

  /// 「新しいAPKをここから入手してください」という案内用URL(任意)。
  final String downloadUrl;

  /// 【更新お知らせ・v1.2.13で追加】現在配布中の最新バージョンの
  /// バージョン名(例: "1.2.13"、表示用)。空文字の場合は未設定扱い。
  final String latestVersion;

  /// 【更新お知らせ・v1.2.13で追加】現在配布中の最新バージョンの
  /// ビルド番号。実機のビルド番号がこれ未満の場合、ブロックせずに
  /// ホーム画面上部へ「新しいバージョンがあります」バナーを表示する。
  /// 0(未設定)の場合はこの機能を一切使用しない(fail-open)。
  final int latestBuildNumber;

  /// 【ベータ版配布・2026-10-06追加】ベータ配布機能そのもののON/OFF。
  /// false の場合、他のbeta_*フィールドの値に関わらず一切通知しない。
  final bool betaEnabled;

  /// ベータ版のバージョン名(表示用、例: "1.2.49-beta1")。
  final String betaVersion;

  /// ベータ版のビルド番号。ベータテスターの実機ビルド番号がこれ未満の
  /// 場合、ベータ版お知らせバナーを表示する。
  final int betaBuildNumber;

  /// ベータ版APKのダウンロードURL(任意、空の場合はデフォルトの
  /// 配布先を使用)。
  final String betaDownloadUrl;

  /// ベータテスターとして指定されたユーザーのuid一覧。
  /// ここに含まれるユーザーのみ、ベータ版お知らせバナーが表示される。
  final List<String> betaTesterUids;

  const AppMinVersionConfig({
    required this.minSupportedBuild,
    this.message = '',
    this.downloadUrl = '',
    this.latestVersion = '',
    this.latestBuildNumber = 0,
    this.betaEnabled = false,
    this.betaVersion = '',
    this.betaBuildNumber = 0,
    this.betaDownloadUrl = '',
    this.betaTesterUids = const [],
  });

  factory AppMinVersionConfig.fromMap(Map<String, dynamic> map) {
    return AppMinVersionConfig(
      minSupportedBuild: (map['min_supported_build'] as num?)?.toInt() ?? 0,
      message: (map['message'] as String?) ?? '',
      downloadUrl: (map['download_url'] as String?) ?? '',
      latestVersion: (map['latest_version'] as String?) ?? '',
      latestBuildNumber: (map['latest_build_number'] as num?)?.toInt() ?? 0,
      betaEnabled: (map['beta_enabled'] as bool?) ?? false,
      betaVersion: (map['beta_version'] as String?) ?? '',
      betaBuildNumber: (map['beta_build_number'] as num?)?.toInt() ?? 0,
      betaDownloadUrl: (map['beta_download_url'] as String?) ?? '',
      betaTesterUids:
          (map['beta_tester_uids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'min_supported_build': minSupportedBuild,
      'message': message,
      'download_url': downloadUrl,
      'latest_version': latestVersion,
      'latest_build_number': latestBuildNumber,
      'updated_at': FieldValue.serverTimestamp(),
    };
  }

  AppMinVersionConfig copyWith({
    int? minSupportedBuild,
    String? message,
    String? downloadUrl,
    String? latestVersion,
    int? latestBuildNumber,
    bool? betaEnabled,
    String? betaVersion,
    int? betaBuildNumber,
    String? betaDownloadUrl,
    List<String>? betaTesterUids,
  }) {
    return AppMinVersionConfig(
      minSupportedBuild: minSupportedBuild ?? this.minSupportedBuild,
      message: message ?? this.message,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      latestVersion: latestVersion ?? this.latestVersion,
      latestBuildNumber: latestBuildNumber ?? this.latestBuildNumber,
      betaEnabled: betaEnabled ?? this.betaEnabled,
      betaVersion: betaVersion ?? this.betaVersion,
      betaBuildNumber: betaBuildNumber ?? this.betaBuildNumber,
      betaDownloadUrl: betaDownloadUrl ?? this.betaDownloadUrl,
      betaTesterUids: betaTesterUids ?? this.betaTesterUids,
    );
  }
}
