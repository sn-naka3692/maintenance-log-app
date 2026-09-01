import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/refrigerant_type_entry.dart';

/// 冷媒種類マスタ(管理者昇格分)の永続化を担当するサービス(Firestore)。
///
/// 【設計方針・2026-09追加】StoreService(店舗マスタ)と同じ「初回全件取得
/// →ローカルキャッシュ」パターンを踏襲する。事務側提供の固定リスト
/// (RefrigerantTypeOptions.all)とは別に、このコレクションに管理者が
/// 追加した冷媒種類を保持し、ドロップダウン表示時にマージして使う。
/// 種類が急激に増える想定ではないため、初期シードデータは不要(空でOK)。
class RefrigerantTypeService {
  static final RefrigerantTypeService instance =
      RefrigerantTypeService._internal();
  RefrigerantTypeService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final _uuid = const Uuid();

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('refrigerant_types');

  List<RefrigerantTypeEntry> _cache = [];

  Future<void> init() async {
    await _refreshCache();
  }

  Future<void> _refreshCache() async {
    final snap = await _col.get();
    _cache = snap.docs
        .map((d) => RefrigerantTypeEntry.fromMap(d.id, d.data()))
        .toList();
    _cache.sort((a, b) => a.name.compareTo(b.name));
  }

  List<RefrigerantTypeEntry> getAll() => _cache;

  /// 表示用の冷媒名一覧のみ(マージ用)。
  List<String> get names => _cache.map((e) => e.name).toList();

  /// 新しい冷媒種類をマスタへ追加する(管理者操作)。
  /// 既に同名(前後空白除去・大文字小文字区別なし)が存在する場合は
  /// 重複追加を避けるため何もせず既存分を返す。
  Future<RefrigerantTypeEntry> addType({
    required String name,
    required String addedByName,
  }) async {
    final trimmed = name.trim();
    final existing = _cache
        .where((e) => e.name.toLowerCase() == trimmed.toLowerCase())
        .toList();
    if (existing.isNotEmpty) {
      return existing.first;
    }
    final id = _uuid.v4();
    final entry = RefrigerantTypeEntry(
      id: id,
      name: trimmed,
      addedByName: addedByName,
      createdAt: DateTime.now(),
    );
    await _col.doc(id).set(entry.toMap());
    await _refreshCache();
    return entry;
  }

  Future<void> deleteType(String id) async {
    await _col.doc(id).delete();
    await _refreshCache();
  }

  Future<void> refreshAll() async {
    await _refreshCache();
  }
}
