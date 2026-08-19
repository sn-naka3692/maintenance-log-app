import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/work_report.dart';
import '../models/user.dart';
import '../data/employee_master_data.dart';

/// 日報・ユーザーデータの永続化を担当するサービス(Firestore)
///
/// 初回起動時、従業員マスタ(employee_master_data.dart、実在の従業員29名)が
/// まだ登録されていなければ自動投入する。既存のユーザーデータは維持する。
class ReportService {
  static const String currentUserKey = 'current_user_id';

  static final ReportService instance = ReportService._internal();
  ReportService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final _uuid = const Uuid();

  CollectionReference<Map<String, dynamic>> get _usersCol =>
      _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _reportsCol =>
      _db.collection('work_reports');

  List<AppUser> _usersCache = [];
  List<WorkReport> _reportsCache = [];

  Future<void> init() async {
    await _refreshUsersCache();
    await _seedEmployeeMasterIfNeeded();
    await _refreshReportsCache();
  }

  /// 従業員マスタ(実データ29名)がまだ登録されていない場合のみ自動投入する。
  /// 既存のユーザー(テストデータ等)は削除せず維持する(重複はidで防止)。
  Future<void> _seedEmployeeMasterIfNeeded() async {
    final existingIds = _usersCache.map((u) => u.id).toSet();
    final missing = initialEmployeeMasterData
        .where((u) => !existingIds.contains(u.id))
        .toList();
    if (missing.isEmpty) return;

    final batch = _db.batch();
    for (final u in missing) {
      final ref = _usersCol.doc(u.id);
      batch.set(ref, u.toMap());
    }
    await batch.commit();
    await _refreshUsersCache();
  }

  Future<void> _refreshUsersCache() async {
    final snap = await _usersCol.get();
    _usersCache = snap.docs
        .map((d) => AppUser.fromMap(d.id, d.data()))
        .toList();
  }

  Future<void> _refreshReportsCache() async {
    final snap = await _reportsCol.get();
    _reportsCache = snap.docs
        .map((d) => WorkReport.fromMap(d.id, d.data()))
        .toList();
    _reportsCache.sort((a, b) => b.visitDate.compareTo(a.visitDate));
  }

  // ------------ User ------------
  List<AppUser> getAllUsers() => _usersCache;

  Future<AppUser?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(currentUserKey);
    if (id == null) {
      return _usersCache.isNotEmpty ? _usersCache.first : null;
    }
    try {
      return _usersCache.firstWhere((u) => u.id == id);
    } catch (_) {
      return _usersCache.isNotEmpty ? _usersCache.first : null;
    }
  }

  Future<void> setCurrentUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(currentUserKey, userId);
  }

  Future<AppUser> addUser({
    required String name,
    required String employeeCode,
    required UserRole role,
    required String department,
  }) async {
    final id = _uuid.v4();
    final u = AppUser(
      id: id,
      name: name,
      employeeCode: employeeCode,
      role: role,
      department: department,
      createdAt: DateTime.now(),
    );
    await _usersCol.doc(id).set(u.toMap());
    await _refreshUsersCache();
    return u;
  }

  // ------------ Report ------------
  List<WorkReport> getAllReports() => _reportsCache;

  List<WorkReport> getReportsByAuthor(String authorId) {
    return _reportsCache.where((r) => r.authorId == authorId).toList();
  }

  WorkReport? getReportById(String id) {
    try {
      return _reportsCache.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<WorkReport> createReport(WorkReport report) async {
    await _reportsCol.doc(report.id).set(report.toMap());
    await _refreshReportsCache();
    return report;
  }

  Future<void> updateReport(WorkReport report) async {
    report.updatedAt = DateTime.now();
    await _reportsCol.doc(report.id).update(report.toMap());
    await _refreshReportsCache();
  }

  Future<void> deleteReport(String id) async {
    await _reportsCol.doc(id).delete();
    await _refreshReportsCache();
  }

  String newId() => _uuid.v4();

  Future<void> refreshAll() async {
    await _refreshUsersCache();
    await _refreshReportsCache();
  }

  // ------------ Search / Filter (in-memory, avoids Firestore composite index issues) ------------
  List<WorkReport> search({
    String? keyword,
    String? authorId,
    ResponseType? responseType,
    DateTime? from,
    DateTime? to,
    bool onlySuccess = false,
    bool onlyIssues = false,
  }) {
    var list = List<WorkReport>.from(_reportsCache);

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
