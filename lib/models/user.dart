import 'package:hive/hive.dart';

part 'user.g.dart';

/// ユーザーの役割
enum UserRole {
  staff, // 一般作業員
  admin, // 管理者
}

@HiveType(typeId: 0)
class AppUser extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String employeeCode; // 社員番号

  @HiveField(3)
  int roleIndex; // UserRole index

  @HiveField(4)
  String department; // 所属(例: 冷凍機部門、空調部門)

  @HiveField(5)
  DateTime createdAt;

  AppUser({
    required this.id,
    required this.name,
    required this.employeeCode,
    required this.roleIndex,
    required this.department,
    required this.createdAt,
  });

  UserRole get role => UserRole.values[roleIndex];

  bool get isAdmin => role == UserRole.admin;
}
