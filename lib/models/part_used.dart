/// 日報内で使用した部品情報
///
/// 【機能追加・2026-08-28】部品図番(partNumber)を追加。
/// SDRS(サンデン・リテールシステム)から毎月末頃に届く請求明細書
/// (Excel)には「使用部品名」「使用個数」に加えて部品を一意に特定できる
/// 情報が含まれる。現場入力時点でも図番まで分かる場合は入力しておくと、
/// 月次で届く請求明細データとの突合精度(名称表記ゆれの吸収)が上がる。
/// 図番が分からない場合は空欄のままでよい(必須項目ではない)。
class PartUsed {
  String name; // 部品名
  int quantity; // 数量
  String? partNumber; // 部品図番(型番・品番。任意入力)
  String? note; // 補足(仕入先など)

  PartUsed({
    required this.name,
    required this.quantity,
    this.partNumber,
    this.note,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'quantity': quantity,
      'part_number': partNumber,
      'note': note,
    };
  }

  factory PartUsed.fromMap(Map<String, dynamic> map) {
    return PartUsed(
      name: map['name'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      partNumber: map['part_number'] as String?,
      note: map['note'] as String?,
    );
  }
}
