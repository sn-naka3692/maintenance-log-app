import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../data/store_master_data.dart';
import '../models/store.dart';

/// 店舗マスタデータの永続化を担当するサービス(Firestore)
///
/// 初回起動時にコレクションが空であれば、SE修理データから抽出した
/// 初期店舗マスタ(74件)を自動投入する。
class StoreService {
  static final StoreService instance = StoreService._internal();
  StoreService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final _uuid = const Uuid();

  CollectionReference<Map<String, dynamic>> get _storesCol =>
      _db.collection('stores');

  List<Store> _cache = [];

  Future<void> init() async {
    await _refreshCache();
    if (_cache.isEmpty) {
      await _seedInitialData();
      await _refreshCache();
    }
  }

  Future<void> _seedInitialData() async {
    final batch = _db.batch();
    for (final store in initialStoreMasterData) {
      final ref = _storesCol.doc(store.id);
      batch.set(ref, store.toMap());
    }
    await batch.commit();
  }

  Future<void> _refreshCache() async {
    final snap = await _storesCol.get();
    _cache = snap.docs.map((d) => Store.fromMap(d.id, d.data())).toList();
    _cache.sort((a, b) => a.name.compareTo(b.name));
  }

  List<Store> getAll() => _cache;

  List<Store> search(String keyword) {
    if (keyword.trim().isEmpty) return _cache;
    final kw = keyword.trim().toLowerCase();
    return _cache
        .where(
          (s) =>
              s.name.toLowerCase().contains(kw) ||
              s.address.toLowerCase().contains(kw),
        )
        .toList();
  }

  Store? getById(String id) {
    try {
      return _cache.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<Store> addStore({
    required String name,
    String phone = '',
    String zipCode = '',
    String address = '',
    String keyLocation = '',
    String note = '',
  }) async {
    final id = _uuid.v4();
    final store = Store(
      id: id,
      name: name,
      phone: phone,
      zipCode: zipCode,
      address: address,
      keyLocation: keyLocation,
      note: note,
      isCustom: true,
      createdAt: DateTime.now(),
    );
    await _storesCol.doc(id).set(store.toMap());
    await _refreshCache();
    return store;
  }

  Future<void> updateStore(Store store) async {
    await _storesCol.doc(store.id).update(store.toMap());
    await _refreshCache();
  }

  Future<void> deleteStore(String id) async {
    await _storesCol.doc(id).delete();
    await _refreshCache();
  }

  Future<void> refreshAll() async {
    await _refreshCache();
  }
}
