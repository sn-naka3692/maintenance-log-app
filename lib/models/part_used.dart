import 'package:hive/hive.dart';

part 'part_used.g.dart';

/// 日報内で使用した部品情報
@HiveType(typeId: 1)
class PartUsed extends HiveObject {
  @HiveField(0)
  String name; // 部品名

  @HiveField(1)
  int quantity; // 数量

  @HiveField(2)
  String? note; // 補足(型番・仕入先など)

  PartUsed({required this.name, required this.quantity, this.note});
}
