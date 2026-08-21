import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// アプリ全体の「最低利用可能バージョン(ビルド番号)」を管理するサービス。
///
/// 【目的】現場で古いバージョンのアプリ(古いAPK)が使われ続けることで、
/// 仕様変更(例: 作業者氏名の入力方式変更など)が反映されず、
/// 情報の回収に支障が出る事態を防ぐための「強制アップデートゲート」。
///
/// 【設計】
/// - Firestoreの `app_config/settings` ドキュメント1件のみで、
///   「最低利用可能ビルド番号(min_supported_build)」を管理する。
/// - アプリ起動時にこの値と、実機の実際のビルド番号(package_info_plus取得)を比較。
/// - 実機のビルド番号が min_supported_build 未満の場合、アプリ全体をブロックする
///   画面を表示し、日報の閲覧・入力を一切できないようにする。
/// - この設定値の変更は最高管理者のみが行える(system_architecture_screen.dart経由)。
///
/// 【安全策】
/// - ドキュメントが存在しない場合や読み込みに失敗した場合は「ブロックしない」
///   (fail-open)。誤ってこの機能自体でアプリが全社的に使えなくなる事故を防ぐため。
/// - Web版はストア配布ではなくプレビュー用途のため、このチェック対象外とする
///   (常に最新のビルドがサーブされるため誤ブロックの心配がない)。
class AppConfigService {
  static final AppConfigService instance = AppConfigService._internal();
  AppConfigService._internal();

  static const String _collection = 'app_config';
  static const String _docId = 'settings';

  DocumentReference<Map<String, dynamic>> get _doc =>
      FirebaseFirestore.instance.collection(_collection).doc(_docId);

  /// 実機のビルド番号を取得する(int変換に失敗した場合は0=最も古い扱い)。
  Future<int> getCurrentBuildNumber() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  /// 現在のバージョン名(表示用、例: "1.1.6")を取得する。
  Future<String> getCurrentVersionName() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// Firestoreから最新の設定値を取得する。
  /// ドキュメントが存在しない/読み込みに失敗した場合はnullを返す(fail-open)。
  Future<AppMinVersionConfig?> fetchConfig() async {
    try {
      final snap = await _doc.get();
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
}

/// 強制アップデートゲートの設定値。
class AppMinVersionConfig {
  /// これ未満のビルド番号のアプリはブロックされる。
  final int minSupportedBuild;

  /// ブロック画面に表示するお知らせ文(空の場合はデフォルト文言を使用)。
  final String message;

  /// 「新しいAPKをここから入手してください」という案内用URL(任意)。
  final String downloadUrl;

  const AppMinVersionConfig({
    required this.minSupportedBuild,
    this.message = '',
    this.downloadUrl = '',
  });

  factory AppMinVersionConfig.fromMap(Map<String, dynamic> map) {
    return AppMinVersionConfig(
      minSupportedBuild: (map['min_supported_build'] as num?)?.toInt() ?? 0,
      message: (map['message'] as String?) ?? '',
      downloadUrl: (map['download_url'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'min_supported_build': minSupportedBuild,
      'message': message,
      'download_url': downloadUrl,
      'updated_at': FieldValue.serverTimestamp(),
    };
  }

  AppMinVersionConfig copyWith({
    int? minSupportedBuild,
    String? message,
    String? downloadUrl,
  }) {
    return AppMinVersionConfig(
      minSupportedBuild: minSupportedBuild ?? this.minSupportedBuild,
      message: message ?? this.message,
      downloadUrl: downloadUrl ?? this.downloadUrl,
    );
  }
}
