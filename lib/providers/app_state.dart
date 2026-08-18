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

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _service.init();
      _users = _service.getAllUsers();
      _currentUser = await _service.getCurrentUser();
      _reports = _service.getAllReports();
      _error = null;
    } catch (e) {
      _error = 'データの読み込みに失敗しました: $e';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> refreshReports() async {
    await _service.refreshAll();
    _reports = _service.getAllReports();
    _users = _service.getAllUsers();
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
    notifyListeners();
  }

  Future<void> addReport(WorkReport report) async {
    await _service.createReport(report);
    _reports = _service.getAllReports();
    notifyListeners();
  }

  Future<void> updateReport(WorkReport report) async {
    await _service.updateReport(report);
    _reports = _service.getAllReports();
    notifyListeners();
  }

  Future<void> deleteReport(String id) async {
    await _service.deleteReport(id);
    _reports = _service.getAllReports();
    notifyListeners();
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
