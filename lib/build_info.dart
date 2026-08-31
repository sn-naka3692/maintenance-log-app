/// 【不具合修正・2026-09・Bug②対応】現在コンパイルされているコード自身の
/// ビルド番号を示す定数。
///
/// 【背景】従来、Web版のバージョンチェック(`AppConfigService`)は
/// `package_info_plus`の`PackageInfo.fromPlatform()`を使っていたが、
/// このパッケージのWeb実装は「実行中のJSコードのバージョン」ではなく、
/// 呼び出された瞬間にHTTP経由で`version.json`を新たに取得して返す
/// 実装になっている(package_info_plus 8.1.3のソース確認済み)。
///
/// そのため、ブラウザのタブが古いJS(`main.dart.js`)をService Worker
/// キャッシュから読み込んで動作していても、`PackageInfo.fromPlatform()`は
/// 「サーバー上の最新のversion.json」を返してしまい、「今動いている
/// コード自体が古い」ことを検知できないという致命的な欠陥があった。
/// これが佐藤さんの案件反映漏れ(Bug②)を含む、Web版での古いコード
/// 実行が長期間検知されなかった根本原因である。
///
/// 【対策】この定数はソースコードに直接埋め込まれ、コンパイル時に
/// `main.dart.js`へ焼き込まれる。実行中のタブがどれだけ古いJSを
/// 使っていても、この値は「そのJSがビルドされた時点のビルド番号」を
/// 正しく返す。
///
/// 【運用ルール】バージョンを上げるたびに、pubspec.yamlの`version:`と
/// 同じビルド番号(`+`より後の数字)をここにも必ず反映すること。
/// changelog_data.dartの更新と合わせてセットで更新する習慣とする。
const int kCompiledBuildNumber = 45;

/// 表示用バージョン名(pubspec.yamlの`version:`の`+`より前の部分と一致させる)。
const String kCompiledVersionName = '1.2.36';
