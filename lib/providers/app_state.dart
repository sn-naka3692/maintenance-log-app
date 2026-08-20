import 'package:flutter/material.dart';
import '../models/store.dart';
import '../models/user.dart';
import '../models/work_report.dart';
import '../services/report_service.dart';
import '../services/store_service.dart';

class AppState extends ChangeNotifier {
  final ReportService _service = ReportService.instance;
  final StoreService _storeService = StoreService.instance;

  AppUser? _currentUser;
  AppUser? get currentUser => _currentUser;

  List<AppUser> _users = [];
  List<AppUser> get users => _users;

  List<WorkReport> _reports = [];
  List<WorkReport> get reports => _reports;

  List<Store> _stores = [];
  List<Store> get stores => _stores;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _service.init();
      await _storeService.init();
      _users = _service.getAllUsers();
      _currentUser = _service.getCurrentUser();
      _reports = _service.getAllReports();
      _stores = _storeService.getAll();
      _error = null;
    } catch (e) {
      _error = 'データの読み込みに失敗しました: $e';
    }
    _isLoading = false;
    notifyListeners();
  }

  bool get isSignedIn => _service.isSignedIn;

  /// メールアドレス・パスワードでログインする。失敗時は例外をthrowする。
  Future<void> signIn(String email, String password) async {
    await _service.signInWithEmail(email, password);
    _users = _service.getAllUsers();
    _currentUser = _service.getCurrentUser();
    if (_currentUser != null) {
      _reports = _service.getAllReports();
      _stores = _storeService.getAll();
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    await _service.signOut();
    _currentUser = null;
    notifyListeners();
  }

  Future<void> refreshReports() async {
    await _service.refreshAll();
    _reports = _service.getAllReports();
    _users = _service.getAllUsers();
    notifyListeners();
  }

  // ------------ Store ------------
  List<Store> searchStores(String keyword) => _storeService.search(keyword);

  Store? getStoreById(String id) => _storeService.getById(id);

  Future<Store> addStore({
    required String name,
    String phone = '',
    String zipCode = '',
    String address = '',
    String keyLocation = '',
    String note = '',
    bool isSE = false,
  }) async {
    final s = await _storeService.addStore(
      name: name,
      phone: phone,
      zipCode: zipCode,
      address: address,
      keyLocation: keyLocation,
      note: note,
      isSE: isSE,
    );
    _stores = _storeService.getAll();
    notifyListeners();
    return s;
  }

  Future<void> updateStore(Store store) async {
    await _storeService.updateStore(store);
    _stores = _storeService.getAll();
    notifyListeners();
  }

  Future<void> deleteStore(String id) async {
    await _storeService.deleteStore(id);
    _stores = _storeService.getAll();
    notifyListeners();
  }

  List<WorkReport> get myReports {
    if (_currentUser == null) return [];
    return _reports.where((r) => r.authorId == _currentUser!.id).toList();
  }

  bool get isAdmin => _currentUser?.isAdmin ?? false;

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
    required String email,
    required String initialPassword,
    required String phone,
  }) async {
    final u = await _service.addUser(
      name: name,
      employeeCode: employeeCode,
      role: role,
      department: department,
      email: email,
      initialPassword: initialPassword,
      phone: phone,
    );
    _users = _service.getAllUsers();
    notifyListeners();
    return u;
  }

  Future<void> changePassword(String newPassword) => _service.changePassword(newPassword);

  Future<void> sendPasswordResetEmail(String email) =>
      _service.sendPasswordResetEmail(email);

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
