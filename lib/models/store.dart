/// 店舗マスタ(訪問先の店舗・拠点情報)
class Store {
  String id;
  String name; // 店舗名
  String phone; // 電話番号
  String zipCode; // 郵便番号
  String address; // 住所
  String keyLocation; // 鍵・動力盤の設置場所
  String note; // 備考
  bool isCustom; // アプリ内でユーザーが追加した店舗かどうか
  DateTime? createdAt;

  Store({
    required this.id,
    required this.name,
    this.phone = '',
    this.zipCode = '',
    this.address = '',
    this.keyLocation = '',
    this.note = '',
    this.isCustom = false,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phone': phone,
      'zip_code': zipCode,
      'address': address,
      'key_location': keyLocation,
      'note': note,
      'is_custom': isCustom,
      'created_at': createdAt ?? DateTime.now(),
    };
  }

  factory Store.fromMap(String id, Map<String, dynamic> map) {
    return Store(
      id: id,
      name: map['name'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      zipCode: map['zip_code'] as String? ?? '',
      address: map['address'] as String? ?? '',
      keyLocation: map['key_location'] as String? ?? '',
      note: map['note'] as String? ?? '',
      isCustom: map['is_custom'] as bool? ?? false,
      createdAt: _parseDate(map['created_at']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    try {
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }
}
