/// APK版アプリの「更新」ボタン用サービス(ダウンロード完了後、
/// インストーラーを自動的に起動するところまでを担当)。
///
/// 【不具合修正・2026-08】従来は「ダウンロード→通知から手動でファイルを
/// 開いてインストール」という2段階の手間があった。これを、アプリ内で
/// 直接バイナリをダウンロードして進捗を表示し、完了後に
/// android.intent.action.VIEWでインストーラーを自動起動するところまで
/// 一気通貫で行うことでシームレスな更新体験に改善する。
///
/// dart.library.io が使えるかどうか(=ネイティブ/Androidかどうか)で
/// 実装を自動的に切り替える(conditional export)。Web版ではこのボタン
/// 自体を表示しない設計のため、Web版の実装は「未対応」を返すだけの
/// スタブでよい。
library;

export 'apk_installer_service_stub.dart'
    if (dart.library.io) 'apk_installer_service_io.dart';
