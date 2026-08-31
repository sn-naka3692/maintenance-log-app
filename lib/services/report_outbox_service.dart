import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';
import '../models/work_report.dart';

/// 【恒久対策・2026-09導入】日報の「送信控え(Outbox)」サービス。
///
/// 【背景・2026-09発覚の重大事象】
/// Firestoreはオフライン永続化がデフォルト有効であり、`set()`/`update()`の
/// `await`は「端末のローカルキャッシュへの書き込みが確定した時点」で
/// 完了扱いになる。これまでは、この「ローカルキャッシュ(SQLite)」こそが
/// 送信待ちデータの唯一の保管場所だった。しかし現場調査で、電波の弱い
/// 環境で入力された日報のうち、Firestoreのローカルキャッシュに一度も
/// サーバー到達しないまま実際に消失した事例が複数件確認された
/// (原因は特定できていないが、OSによるアプリデータの自動整理・端末の
/// ストレージ不足・アプリの異常終了等、Firestore内部キャッシュだけに
/// 依存する設計であれば構造的に起こり得る)。
///
/// 【この設計の目的】
/// Firestoreの内部キャッシュを一切信用せず、アプリ自身が管理する
/// 独立した永続層(Hive)に「サーバー到達が確認できるまで絶対に消さない」
/// 日報の控えを必ず保存する。これにより、Firestore側のキャッシュが
/// どのような理由で失われても、Hive側の控えから復元・再送信できる。
///
/// 【運用フロー】
/// 1. 日報保存の瞬間、まずこのOutboxにレコードを書き込む(必ず先に行う)。
/// 2. その後Firestoreへの書き込みを試みる。
/// 3. Firestoreへの書き込みが「サーバー確定(hasPendingWrites=false)」に
///    なったことを確認できてから、Outboxのレコードを削除する。
/// 4. アプリ起動時・電波復帰時に、Outboxに残っている(=まだサーバー確定
///    していない)レコードを自動的に再送信する。
class ReportOutboxService {
  static final ReportOutboxService instance = ReportOutboxService._internal();
  ReportOutboxService._internal();

  static const String _boxName = 'report_outbox_v1';
  Box<Map>? _box;

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// main()から起動直後に呼び出す。Hiveの初期化自体は main 側で
  /// Hive.initFlutter() 済みであることを前提とする。
  Future<void> init() async {
    _box ??= await Hive.openBox<Map>(_boxName);
  }

  Box<Map> get _requireBox {
    final b = _box;
    if (b == null) {
      throw StateError('ReportOutboxService.init() が呼ばれていません');
    }
    return b;
  }

  /// 日報をOutboxに控えとして保存する(Firestoreへの書き込みより必ず先に行う)。
  /// [isUpdate] は既存日報の更新か、新規作成かを記録する(再送信時の分岐用)。
  Future<void> stash(WorkReport report, {required bool isUpdate}) async {
    await init();
    final map = report.toMap();
    // Firestoreの Timestamp/FieldValue はそのままHiveへ保存できないため、
    // DateTimeはミリ秒int、その他はプリミティブ値のみに変換して保存する。
    final safe = _toSafeMap(map);
    await _requireBox.put(report.id, {
      'is_update': isUpdate,
      'saved_at': DateTime.now().millisecondsSinceEpoch,
      'data': safe,
    });
  }

  /// サーバーへの到達が確認できたら、Outboxから控えを削除する。
  Future<void> clear(String reportId) async {
    await init();
    await _requireBox.delete(reportId);
  }

  /// 現在Outboxに残っている(=サーバー到達が未確認の)件数。
  int get pendingCount {
    final b = _box;
    if (b == null) return 0;
    return b.length;
  }

  Stream<int> watchPendingCount() {
    return _watchController.stream;
  }

  final StreamController<int> _watchController =
      StreamController<int>.broadcast();

  void _notifyCountChanged() {
    if (!_watchController.isClosed) {
      _watchController.add(pendingCount);
    }
  }

  /// アプリ起動時・電波復帰時に呼び出す。Outboxに残っている全レコードを
  /// Firestoreへ再送信し、サーバー到達が確認できたものだけOutboxから
  /// 削除する。1件ずつ独立して処理するため、一部が失敗しても他の
  /// レコードの再送信は継続する。
  ///
  /// 戻り値: 再送信に成功した件数。
  Future<int> flushPending() async {
    await init();
    final keys = _requireBox.keys.toList();
    if (keys.isEmpty) return 0;

    int successCount = 0;
    for (final key in keys) {
      final entry = _requireBox.get(key);
      if (entry == null) continue;
      try {
        final data = Map<String, dynamic>.from(entry['data'] as Map);
        final restored = _fromSafeMap(data);
        final reportId = key.toString();

        // Firestore上に既に存在するか確認する。既に存在する場合は
        // (=以前の書き込みが実は成功していた場合)上書きではなく、
        // 内容が壊れないよう set(merge: true) にはせず、そのまま同じ
        // 内容で set することでベき等性を保つ(同じ日報IDへの再送信は
        // 常に安全)。
        await _db
            .collection('work_reports')
            .doc(reportId)
            .set(restored)
            .timeout(const Duration(seconds: 20));

        // サーバー確定を待つ(ローカルキャッシュ確定だけでなく、実際に
        // サーバーへ届いたことまで確認してからOutboxを消す)。
        await _db.waitForPendingWrites().timeout(const Duration(seconds: 15));

        await _requireBox.delete(key);
        successCount++;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Outbox再送信に失敗(次回再試行): $key -> $e');
        }
        // 失敗しても削除しない。次回起動時・電波復帰時に再度試みる。
      }
    }
    _notifyCountChanged();
    return successCount;
  }

  /// Firestore用のMapから、Hiveに安全に保存できるMapへ変換する。
  /// DateTime -> ミリ秒int、FieldValue(SERVER_TIMESTAMP等)は使用していない
  /// 前提(WorkReport.toMap()はDateTimeのみを使用)。
  Map<String, dynamic> _toSafeMap(Map<String, dynamic> map) {
    final result = <String, dynamic>{};
    map.forEach((key, value) {
      result[key] = _toSafeValue(value);
    });
    return result;
  }

  dynamic _toSafeValue(dynamic value) {
    if (value is DateTime) {
      return {'__dt__': value.millisecondsSinceEpoch};
    }
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _toSafeValue(v)));
    }
    if (value is List) {
      return value.map(_toSafeValue).toList();
    }
    return value;
  }

  Map<String, dynamic> _fromSafeMap(Map<String, dynamic> map) {
    final result = <String, dynamic>{};
    map.forEach((key, value) {
      result[key] = _fromSafeValue(value);
    });
    return result;
  }

  dynamic _fromSafeValue(dynamic value) {
    if (value is Map) {
      if (value.length == 1 && value.containsKey('__dt__')) {
        final ms = value['__dt__'];
        return DateTime.fromMillisecondsSinceEpoch(ms as int);
      }
      return value.map((k, v) => MapEntry(k.toString(), _fromSafeValue(v)));
    }
    if (value is List) {
      return value.map(_fromSafeValue).toList();
    }
    return value;
  }
}
