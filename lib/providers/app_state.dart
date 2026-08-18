import 'package:flutter/material.dart';
import '../models/user.dart';
import '../models/work_report.dart';
import '../services/report_service.dart';

class AppState extends ChangeNotifier {
  final ReportService _service = ReportService.instance;

  AppUser? _currentUser;
  AppUser? get currentUser => _currentUser;

  List<AppUser> _users = [];
  List<AppUser> get users => _users;

  List<WorkReport> _reports = [];
  List<WorkReport> get reports => _reports;

  Future<void> init() async {
    _users = _service.getAllUsers();
    _currentUser = _service.getCurrentUser();
    refreshReports();
  }

  void refreshReports() {
    _reports = _service.getAllReports();
    notifyListeners();
  }

  List<WorkReport> get myReports {
    if (_currentUser == null) return [];
    return _reports.where((r) => r.authorId == _currentUser!.id).toList();
  }

  bool get isAdmin => _currentUser?.isAdmin ?? false;

  Future<void> switchUser(String userId) async {
    await _service.setCurrentUser(userId);
    _currentUser = _users.firstWhere((u) => u.id == userId);
    refreshReports();
  }

  Future<void> addReport(WorkReport report) async {
    await _service.createReport(report);
    refreshReports();
  }

  Future<void> updateReport(WorkReport report) async {
    await _service.updateReport(report);
    refreshReports();
  }

  Future<void> deleteReport(String id) async {
    await _service.deleteReport(id);
    refreshReports();
  }

  Future<AppUser> addUser({
    required String name,
    required String employeeCode,
    required UserRole role,
    required String department,
  }) async {
    final u = await _service.addUser(
      name: name,
      employeeCode: employeeCode,
      role: role,
      department: department,
    );
    _users = _service.getAllUsers();
    notifyListeners();
    return u;
  }

  List<WorkReport> search({
    String? keyword,
    String? authorId,
    ResponseType? responseType,
    DateTime? from,
    DateTime? to,
    bool onlySuccess = false,
    bool onlyIssues = false,
  }) {
    return _service.search(
      keyword: keyword,
      authorId: authorId,
      responseType: responseType,
      from: from,
      to: to,
      onlySuccess: onlySuccess,
      onlyIssues: onlyIssues,
    );
  }

  Map<String, int> countByResponseType(List<WorkReport> reports) =>
      _service.countByResponseType(reports);

  Map<String, int> countByAuthor(List<WorkReport> reports) =>
      _service.countByAuthor(reports);

  String newId() => _service.newId();
}
