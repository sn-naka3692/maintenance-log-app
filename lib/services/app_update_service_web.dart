// Web専用実装。package:webはWebターゲットのみでビルドされるため、
// このファイル自体がAndroidビルド時にコンパイルされることはない
// (app_update_service.dartのconditional importで切り替わる)。
import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool get isWebPlatform => true;

/// Web版アプリを「最新の状態」に更新する。
///
/// 【背景・不具合対応】Web版はFirebase Hostingへ新しいコードを
/// デプロイしても、ブラウザ側がFlutterのService Worker
/// (flutter_service_worker.js)経由でファイルをキャッシュしているため、
/// ユーザーが手動でアプリを終了して開き直すか、ブラウザのキャッシュを
/// クリアしない限り古いバージョンが表示され続けてしまう。
/// 「Web版で更新の案内が出ない・何をすればいいか分からない」という
/// 問い合わせへの対応として、このボタン一つで確実に最新版へ更新できる
/// ようにする。
///
/// 処理内容:
/// 1. Service Worker経由のキャッシュをすべて明示的に削除する
/// 2. 登録済みのService Worker自体も解除する(古いバージョンの
///    Service Workerが居座り続けるのを防ぐため)
/// 3. キャッシュを回避する形でページを強制リロードする
Future<void> reloadForLatestVersion() async {
  try {
    // 1. Cache Storage APIで保持されているキャッシュを全削除
    final cacheStorage = web.window.caches;
    final keysPromise = cacheStorage.keys();
    final keys = await keysPromise.toDart;
    for (final key in keys.toDart) {
      await cacheStorage.delete(key.toDart).toDart;
    }
  } catch (_) {
    // Cache Storage未対応環境でも致命的ではないため握りつぶす
  }

  try {
    // 2. 登録済みのService Workerを解除
    final registrations = await web.window.navigator.serviceWorker
        .getRegistrations()
        .toDart;
    for (final reg in registrations.toDart) {
      await reg.unregister().toDart;
    }
  } catch (_) {
    // Service Worker未対応環境でも致命的ではないため握りつぶす
  }

  // 3. キャッシュを回避してページを再読み込み
  web.window.location.reload();
}
