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
      if (config == null || config.latestBuildNumber <= 0) {
        return UpdateAvailability.none;
      }
      final currentBuild = await getCurrentBuildNumber();
      if (currentBuild >= config.latestBuildNumber) {
        return UpdateAvailability.none;
      }
      return UpdateAvailability(
        hasNewerVersion: true,
        latestVersion: config.latestVersion,
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

  const AppMinVersionConfig({
    required this.minSupportedBuild,
    this.message = '',
    this.downloadUrl = '',
    this.latestVersion = '',
    this.latestBuildNumber = 0,
  });

  factory AppMinVersionConfig.fromMap(Map<String, dynamic> map) {
    return AppMinVersionConfig(
      minSupportedBuild: (map['min_supported_build'] as num?)?.toInt() ?? 0,
      message: (map['message'] as String?) ?? '',
      downloadUrl: (map['download_url'] as String?) ?? '',
      latestVersion: (map['latest_version'] as String?) ?? '',
      latestBuildNumber: (map['latest_build_number'] as num?)?.toInt() ?? 0,
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
  }) {
    return AppMinVersionConfig(
      minSupportedBuild: minSupportedBuild ?? this.minSupportedBuild,
      message: message ?? this.message,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      latestVersion: latestVersion ?? this.latestVersion,
      latestBuildNumber: latestBuildNumber ?? this.latestBuildNumber,
    );
  }
}
