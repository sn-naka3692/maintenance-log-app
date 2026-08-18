import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/work_report.dart';
import '../models/part_used.dart';
import '../models/user.dart';

/// 日報・ユーザーデータの永続化を担当するサービス
class ReportService {
  static const String reportBoxName = 'work_reports';
  static const String userBoxName = 'app_users';
  static const String currentUserKey = 'current_user_id';
  static const String settingsBoxName = 'app_settings';

  static final ReportService instance = ReportService._internal();
  ReportService._internal();

  late Box<WorkReport> _reportBox;
  late Box<AppUser> _userBox;
  late Box _settingsBox;
  final _uuid = const Uuid();

  Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(AppUserAdapter());
    Hive.registerAdapter(PartUsedAdapter());
    Hive.registerAdapter(WorkReportAdapter());

    _reportBox = await Hive.openBox<WorkReport>(reportBoxName);
    _userBox = await Hive.openBox<AppUser>(userBoxName);
    _settingsBox = await Hive.openBox(settingsBoxName);

    await _seedInitialData();
  }

  Future<void> _seedInitialData() async {
    if (_userBox.isEmpty) {
      final admin = AppUser(
        id: _uuid.v4(),
        name: '管理者(店長)',
        employeeCode: 'A001',
        roleIndex: UserRole.admin.index,
        department: '本社管理部',
        createdAt: DateTime.now(),
      );
      final staffNames = [
        ['佐藤 太郎', 'S001', '冷凍機部門'],
        ['鈴木 一郎', 'S002', '空調部門'],
        ['高橋 次郎', 'S003', '冷凍機部門'],
      ];
      await _userBox.put(admin.id, admin);
      for (final s in staffNames) {
        final u = AppUser(
          id: _uuid.v4(),
          name: s[0],
          employeeCode: s[1],
          roleIndex: UserRole.staff.index,
          department: s[2],
          createdAt: DateTime.now(),
        );
        await _userBox.put(u.id, u);
      }
      await _settingsBox.put(currentUserKey, admin.id);
    }
  }

  // ------------ User ------------
  List<AppUser> getAllUsers() => _userBox.values.toList();

  AppUser? getCurrentUser() {
    final id = _settingsBox.get(currentUserKey);
    if (id == null) return null;
    try {
      return _userBox.values.firstWhere((u) => u.id == id);
    } catch (_) {
      return _userBox.values.isNotEmpty ? _userBox.values.first : null;
    }
  }

  Future<void> setCurrentUser(String userId) async {
    await _settingsBox.put(currentUserKey, userId);
  }

  Future<AppUser> addUser({
    required String name,
    required String employeeCode,
    required UserRole role,
    required String department,
  }) async {
    final u = AppUser(
      id: _uuid.v4(),
      name: name,
      employeeCode: employeeCode,
      roleIndex: role.index,
      department: department,
      createdAt: DateTime.now(),
    );
    await _userBox.put(u.id, u);
    return u;
  }

  // ------------ Report ------------
  List<WorkReport> getAllReports() {
    final list = _reportBox.values.toList();
    list.sort((a, b) => b.visitDate.compareTo(a.visitDate));
    return list;
  }

  List<WorkReport> getReportsByAuthor(String authorId) {
    return getAllReports().where((r) => r.authorId == authorId).toList();
  }

  WorkReport? getReportById(String id) {
    try {
      return _reportBox.values.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<WorkReport> createReport(WorkReport report) async {
    await _reportBox.put(report.id, report);
    return report;
  }

  Future<void> updateReport(WorkReport report) async {
    report.updatedAt = DateTime.now();
    await _reportBox.put(report.id, report);
  }

  Future<void> deleteReport(String id) async {
    await _reportBox.delete(id);
  }

  String newId() => _uuid.v4();

  // ------------ Search / Filter ------------
  List<WorkReport> search({
    String? keyword,
    String? authorId,
    ResponseType? responseType,
    DateTime? from,
    DateTime? to,
    bool onlySuccess = false,
    bool onlyIssues = false,
  }) {
    var list = getAllReports();

    if (authorId != null && authorId.isNotEmpty) {
      list = list.where((r) => r.authorId == authorId).toList();
    }
    if (responseType != null) {
      list = list.where((r) => r.responseType == responseType).toList();
    }
    if (from != null) {
      list = list
          .where(
            (r) => !r.visitDate.isBefore(
              DateTime(from.year, from.month, from.day),
            ),
          )
          .toList();
    }
    if (to != null) {
      final toEnd = DateTime(to.year, to.month, to.day, 23, 59, 59);
      list = list.where((r) => !r.visitDate.isAfter(toEnd)).toList();
    }
    if (onlySuccess) {
      list = list.where((r) => r.hasSuccess).toList();
    }
    if (onlyIssues) {
      list = list.where((r) => r.hasIssues).toList();
    }
    if (keyword != null && keyword.trim().isNotEmpty) {
      final kw = keyword.trim().toLowerCase();
      list = list.where((r) {
        return r.clientName.toLowerCase().contains(kw) ||
            r.workContent.toLowerCase().contains(kw) ||
            r.equipmentModel.toLowerCase().contains(kw) ||
            r.authorName.toLowerCase().contains(kw) ||
            r.notes.toLowerCase().contains(kw) ||
            r.successPoints.toLowerCase().contains(kw) ||
            r.issuesPoints.toLowerCase().contains(kw) ||
            r.tags.any((t) => t.toLowerCase().contains(kw));
      }).toList();
    }
    return list;
  }

  // ------------ Stats ------------
  Map<String, int> countByResponseType(List<WorkReport> reports) {
    final map = <String, int>{};
    for (final r in reports) {
      final label = r.responseType.label;
      map[label] = (map[label] ?? 0) + 1;
    }
    return map;
  }

  Map<String, int> countByAuthor(List<WorkReport> reports) {
    final map = <String, int>{};
    for (final r in reports) {
      map[r.authorName] = (map[r.authorName] ?? 0) + 1;
    }
    return map;
  }
}
