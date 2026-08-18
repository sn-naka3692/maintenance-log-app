/// 日報内で使用した部品情報
class PartUsed {
  String name; // 部品名
  int quantity; // 数量
  String? note; // 補足(型番・仕入先など)

  PartUsed({required this.name, required this.quantity, this.note});

  Map<String, dynamic> toMap() {
    return {'name': name, 'quantity': quantity, 'note': note};
  }

  factory PartUsed.fromMap(Map<String, dynamic> map) {
    return PartUsed(
      name: map['name'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      note: map['note'] as String?,
    );
  }
}
