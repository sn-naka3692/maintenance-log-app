/// ユーザーの役割
enum UserRole {
  staff, // 一般作業員
  admin, // 管理者
}

class AppUser {
  String id;
  String name;
  String employeeCode; // 社員番号
  UserRole role;
  String department; // 所属(例: 冷凍機部門、空調部門)
  DateTime createdAt;

  AppUser({
    required this.id,
    required this.name,
    required this.employeeCode,
    required this.role,
    required this.department,
    required this.createdAt,
  });

  bool get isAdmin => role == UserRole.admin;

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'employee_code': employeeCode,
      'role': role == UserRole.admin ? 'admin' : 'staff',
      'department': department,
      'created_at': createdAt,
    };
  }

  factory AppUser.fromMap(String id, Map<String, dynamic> map) {
    return AppUser(
      id: id,
      name: map['name'] as String? ?? '',
      employeeCode: map['employee_code'] as String? ?? '',
      role: (map['role'] as String? ?? 'staff') == 'admin'
          ? UserRole.admin
          : UserRole.staff,
      department: map['department'] as String? ?? '',
      createdAt: _parseDate(map['created_at']),
    );
  }

  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    try {
      // Firestore Timestamp has toDate()
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {
      return DateTime.now();
    }
  }
}
