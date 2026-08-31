import 'package:cloud_firestore/cloud_firestore.dart';

/// 【不具合対応・2026-08-31】
/// 「本人には保存できたように見えるが、実際はまだサーバーに届いていない」
/// 問題への対応。
///
/// 背景: FirestoreはAndroid/iOSでオフライン永続化がデフォルト有効であり、
/// `set()`/`update()` の `await` は「端末のローカルキャッシュへの書き込みが
/// 確定した時点」で完了扱いになる。電波状況が悪い現場(設備室・バックヤード等)
/// では、保存操作自体は成功したように見えても、実際のサーバーへの送信は
/// 保留(pending)のままアプリを閉じてしまい、送信されないまま止まることがある。
/// 管理者側はサーバー上のデータしか見えないため、この状態には気づけない。
///
/// このサービスは、ログイン中ユーザー自身が作成した日報のうち、まだサーバーに
/// 届いていない(=端末発信のローカル書き込みが未確定)件数を検知し、本人が
/// 気づけるようにする。
///
/// 【重要な制約】`hasPendingWrites` はその端末自身のローカル書き込みキューの
/// 状態であり、他人の端末の未送信状況を検知することはできない
/// (Firestoreの設計上、管理者が「Aさんの端末に未送信データがある」ことを
/// 遠隔から直接知る手段は存在しない)。そのため、この機能は「本人が自分の
/// 未送信状態に気づける」ことを目的とし、各ユーザーの端末上で有効に働く。
class PendingSyncService {
  static final PendingSyncService instance = PendingSyncService._internal();
  PendingSyncService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// 指定した authorId(=ログイン中ユーザー自身のuid)の日報のうち、
  /// サーバーへの送信が完了していない(pending)件数をリアルタイムに流す。
  ///
  /// `includeMetadataChanges: true` を指定することで、書き込みが
  /// ローカル確定→サーバー確定に変わった瞬間の変化も検知できる。
  Stream<int> watchPendingCount(String authorId) {
    if (authorId.isEmpty) {
      return Stream.value(0);
    }
    return _db
        .collection('work_reports')
        .where('author_id', isEqualTo: authorId)
        .snapshots(includeMetadataChanges: true)
        .map((snap) {
          // fromCache かつ hasPendingWrites は「サーバーが一度も確認していない、
          // この端末発の書き込み」を指す。サーバーから正常に読み込めた
          // ドキュメント(他人の書き込みも含む正常な最新データ)は
          // hasPendingWrites が false になるため誤検知しない。
          return snap.docs
              .where((d) => d.metadata.hasPendingWrites)
              .length;
        });
  }
}
