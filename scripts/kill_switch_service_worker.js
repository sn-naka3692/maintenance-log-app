// ============================================================
// 「キルスイッチ」Service Worker
// ============================================================
// 【背景・2026-08-26】Flutter Webは過去バージョンでService Worker
// (オフラインキャッシュ)を自動登録していた。--pwa-strategy=none に
// 切り替えても、それは「これから新しくアクセスする人」にしか効かず、
// 既にService Workerが登録済みの端末には一切効果がない。
//
// さらに、ブラウザの仕様上、新しいService Worker(空ファイル等)を
// 検出しても、標準では「既存の全タブが閉じられるまで」待機状態の
// ままになり、タブを閉じずに再読み込みするだけの一般的な使い方では
// 何日経っても切り替わらない、という致命的な穴があった。
//
// この「キルスイッチ」は、install時に self.skipWaiting() を呼んで
// 即座に有効化を強制し、activate時に自分自身を含む全キャッシュを
// 削除・登録解除し、開いている全タブを強制リロードする。
// これにより、ユーザーが何もしなくても(タブを閉じる必要すらなく)
// 次回のブラウザの自動更新チェック(通常24時間以内)で確実に
// 古いキャッシュ問題から復帰できる。
//
// 【注意】このファイルは build/web/flutter_service_worker.js を
// 上書きする形でデプロイされる(scripts/deploy_web_and_apk.sh 参照)。
// 恒久的に残しておいても、Service Worker自体が最終的に自分を
// 登録解除するため副作用はない。
// ============================================================

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      // 1) このオリジンの全キャッシュ(Cache Storage)を削除
      const keys = await caches.keys();
      await Promise.all(keys.map((key) => caches.delete(key)));

      // 2) 開いている全タブを即座に自分の管理下に置く
      await self.clients.claim();

      // 3) 自分自身(キルスイッチ)を登録解除する
      await self.registration.unregister();

      // 4) 開いている全タブへ強制リロードを指示する
      const clientList = await self.clients.matchAll({ type: 'window' });
      clientList.forEach((client) => {
        if (typeof client.navigate === 'function') {
          client.navigate(client.url);
        } else {
          client.postMessage({ type: 'FLUTTER_APP_FORCE_RELOAD' });
        }
      });
    })()
  );
});

// 何もキャッシュ・インターセプトせず、すべてのリクエストを
// そのまま通常のネットワーク取得に任せる。
self.addEventListener('fetch', () => {});
