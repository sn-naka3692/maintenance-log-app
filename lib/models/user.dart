/// ユーザーの役割
///
/// 管理者権限は「一般管理者」「最高管理者」の2階層に分離している。
/// - staff: 一般作業員。日報の作成・自分の日報の編集のみ。
/// - admin: 一般管理者。管理ダッシュボード閲覧、一般作業員の追加は可能だが、
///          他人への管理者権限の付与/剥奪、社員の削除は不可(誤操作・権限乱用の事故防止)。
/// - superAdmin: 最高管理者(社長など)。社員の役割変更・削除など、全ての管理操作が可能。
enum UserRole {
  staff, // 一般作業員
  admin, // 一般管理者
  superAdmin, // 最高管理者
}

class AppUser {
  String id;
  String name;
  String employeeCode; // 社員番号
  UserRole role;
  String department; // 所属(例: 冷凍機部門、空調部門)
  DateTime createdAt;
  String email; // ログイン用メールアドレス
  String phone; // 電話番号

  AppUser({
    required this.id,
    required this.name,
    required this.employeeCode,
    required this.role,
    required this.department,
    required this.createdAt,
    this.email = '',
    this.phone = '',
  });

  /// 一般管理者・最高管理者のどちらでも true (管理ダッシュボード等の閲覧権限判定用)
  bool get isAdmin => role == UserRole.admin || role == UserRole.superAdmin;

  /// 最高管理者のみ true (役割変更・社員削除など、事故防止のため制限された操作の権限判定用)
  bool get isSuperAdmin => role == UserRole.superAdmin;

  static String roleToStr(UserRole r) {
    switch (r) {
      case UserRole.superAdmin:
        return 'super_admin';
      case UserRole.admin:
        return 'admin';
      case UserRole.staff:
        return 'staff';
    }
  }

  static UserRole roleFromStr(String? s) {
    switch (s) {
      case 'super_admin':
        return UserRole.superAdmin;
      case 'admin':
        return UserRole.admin;
      default:
        return UserRole.staff;
    }
  }

  /// 画面表示用の役割ラベル(日本語)
  static String roleLabel(UserRole? r) {
    switch (r) {
      case UserRole.superAdmin:
        return '最高管理者';
      case UserRole.admin:
        return '一般管理者';
      case UserRole.staff:
      case null:
        return '一般作業員';
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'employee_code': employeeCode,
      'role': roleToStr(role),
      'department': department,
      'created_at': createdAt,
      'email': email,
      'phone': phone,
    };
  }

  factory AppUser.fromMap(String id, Map<String, dynamic> map) {
    return AppUser(
      id: id,
      name: map['name'] as String? ?? '',
      employeeCode: map['employee_code'] as String? ?? '',
      role: roleFromStr(map['role'] as String?),
      department: map['department'] as String? ?? '',
      createdAt: _parseDate(map['created_at']),
      email: map['email'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
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
