import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/case.dart';
import '../models/store.dart';
import '../models/user.dart';
import '../models/work_report.dart';
import '../services/case_service.dart';
import '../services/case_sync_failure_service.dart';
import '../services/pending_sync_service.dart';
import '../services/report_service.dart';
import '../services/store_service.dart';

class AppState extends ChangeNotifier {
  final ReportService _service = ReportService.instance;
  final StoreService _storeService = StoreService.instance;
  final CaseService _caseService = CaseService.instance;
  final CaseSyncFailureService _caseSyncFailureService =
      CaseSyncFailureService.instance;
  final PendingSyncService _pendingSyncService = PendingSyncService.instance;

  // 【不具合対応・2026-08-31】自分の日報のうち、まだサーバーへの送信が
  // 完了していない(電波不良等で端末内に留まっている)件数。
  // 0件なら正常。ホーム画面の警告バナー表示に使う。
  StreamSubscription<int>? _pendingSyncSub;
  int _pendingSyncCount = 0;
  int get pendingSyncCount => _pendingSyncCount;

  void _watchPendingSync(String authorId) {
    _pendingSyncSub?.cancel();
    _pendingSyncCount = 0;
    _pendingSyncSub = _pendingSyncService
        .watchPendingCount(authorId)
        .listen((count) {
          if (_pendingSyncCount != count) {
            _pendingSyncCount = count;
            notifyListeners();
          }
        });
  }

  @override
  void dispose() {
    _pendingSyncSub?.cancel();
    super.dispose();
  }

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
      if (_currentUser != null) {
        _watchPendingSync(_currentUser!.id);
      }
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
      _watchPendingSync(_currentUser!.id);
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    await _pendingSyncSub?.cancel();
    _pendingSyncSub = null;
    _pendingSyncCount = 0;
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

  /// 最高管理者かどうか(役割変更・社員削除など、事故防止のため
  /// 制限された操作を実行できるのは最高管理者のみ)
  bool get isSuperAdmin => _currentUser?.isSuperAdmin ?? false;

  Future<void> addReport(WorkReport report) async {
    await _service.createReport(report);
    await _syncCaseSilently(report);
    // case_id がFirestore上で更新されている可能性があるため再取得する
    await _service.refreshAll();
    _reports = _service.getAllReports();
    notifyListeners();
  }

  Future<void> updateReport(WorkReport report) async {
    await _service.updateReport(report);
    await _syncCaseSilently(report);
    await _service.refreshAll();
    _reports = _service.getAllReports();
    notifyListeners();
  }

  /// 日報保存後、案件への自動グルーピングを行う。
  ///
  /// 【重要】これはあくまで「後から便利に検索・集計できるようにする」
  /// 付随機能であり、日報の保存自体(従業員にとっての本来の目的)を
  /// 妨げてはならない。そのため失敗しても例外は表に投げず、
  /// ベストエフォートで処理を続ける。
  ///
  /// 【不具合修正・2026-08-31】
  /// 以前は失敗時にデバッグモードでの `debugPrint` のみで記録しており、
  /// 本番環境では失敗が発生していても管理者から一切見えなかった
  /// (=「日報にはある情報が案件に反映されない」不整合に気づく手段が
  /// なかった)。CaseSyncFailureServiceを使って失敗をFirestoreへ記録し、
  /// 案件一覧画面の管理者向けバッジ・一覧から気づけるようにする。
  /// 成功した場合は、過去に記録が残っていれば消去する。
  Future<void> _syncCaseSilently(WorkReport report) async {
    try {
      final caseId = await _caseService.syncCaseForReport(report);
      if (caseId.isNotEmpty && report.caseId != caseId) {
        report.caseId = caseId;
      }
      // 成功したので、過去にこの日報の失敗記録が残っていればクリアする。
      await _caseSyncFailureService.clearFailure(report.id);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('案件グルーピング処理に失敗しました(日報自体は保存済み): $e');
      }
      final summary =
          '${report.clientName.isNotEmpty ? report.clientName : "(店舗不明)"}'
          ' ・ ${report.authorName} ・ '
          '${report.visitDate.year}/${report.visitDate.month}/${report.visitDate.day}';
      await _caseSyncFailureService.recordFailure(
        reportId: report.id,
        reportSummary: summary,
        errorMessage: e.toString(),
      );
    }
  }

  /// 【管理者用】現在記録されている「案件への自動反映に失敗した日報」の
  /// 一覧を取得する。
  Future<List<CaseSyncFailure>> getCaseSyncFailures() =>
      _caseSyncFailureService.getAllFailures();

  /// 【管理者用】未解決の同期失敗件数のみを取得する(バッジ表示用)。
  Future<int> countCaseSyncFailures() =>
      _caseSyncFailureService.countFailures();

  /// 【管理者用】同期失敗した日報1件について、現在の判定ロジックで
  /// 再同期を試みる。成功すれば失敗記録は自動的に消える。
  Future<bool> retryCaseSync(String reportId) async {
    final report = _service.getReportById(reportId);
    if (report == null) {
      // 日報自体が既に削除されている場合は、記録だけ消してあげる。
      await _caseSyncFailureService.clearFailure(reportId);
      return false;
    }
    try {
      final caseId = await _caseService.syncCaseForReport(report);
      if (caseId.isNotEmpty && report.caseId != caseId) {
        report.caseId = caseId;
        await _service.updateReport(report);
      }
      await _caseSyncFailureService.clearFailure(reportId);
      await refreshReports();
      return true;
    } catch (e) {
      final summary =
          '${report.clientName.isNotEmpty ? report.clientName : "(店舗不明)"}'
          ' ・ ${report.authorName} ・ '
          '${report.visitDate.year}/${report.visitDate.month}/${report.visitDate.day}';
      await _caseSyncFailureService.recordFailure(
        reportId: report.id,
        reportSummary: summary,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }

  /// 【管理者用】同期失敗記録を「解決済み」として手動で消す
  /// (例: 日報自体が意図的に未グルーピングのままで問題ないと判断した場合)。
  Future<void> dismissCaseSyncFailure(String reportId) =>
      _caseSyncFailureService.clearFailure(reportId);

  Future<void> deleteReport(String id) async {
    // 削除前に案件からの切り離しを試みる(失敗しても日報削除は継続する)
    try {
      final report = _service.getReportById(id);
      if (report != null && report.caseId.isNotEmpty) {
        await _caseService.unlinkReportFromCase(id, report.caseId);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('案件からの切り離し処理に失敗しました(日報削除は継続します): $e');
      }
    }
    await _service.deleteReport(id);
    _reports = _service.getAllReports();
    notifyListeners();
  }

  /// 案件一覧を取得する(検索画面の「案件」タブ用)。
  Future<List<WorkCase>> getAllCases() => _caseService.getAllCases();

  /// 案件を1件取得する(案件詳細画面用)。
  Future<WorkCase?> getCaseById(String caseId) =>
      _caseService.getCaseById(caseId);

  /// 指定した案件に紐づく日報一覧を取得する(新しい順)。
  List<WorkReport> getReportsForCase(WorkCase c) {
    final list = _reports.where((r) => c.linkedReportIds.contains(r.id)).toList();
    list.sort((a, b) => b.visitDate.compareTo(a.visitDate));
    return list;
  }

  /// 指定した日報と同じ案件に属する他の日報一覧を取得する(自分自身は除く)。
  List<WorkReport> getRelatedReports(WorkReport report) {
    if (report.caseId.isEmpty) return [];
    final list = _reports
        .where((r) => r.id != report.id && r.caseId == report.caseId)
        .toList();
    list.sort((a, b) => b.visitDate.compareTo(a.visitDate));
    return list;
  }

  /// 誤って自動グルーピングされた日報を案件から手動で切り離す(管理画面用)。
  Future<void> unlinkReportFromCase(String reportId, String caseId) async {
    await _caseService.unlinkReportFromCase(reportId, caseId);
    await _service.refreshAll();
    _reports = _service.getAllReports();
    notifyListeners();
  }

  /// 未グルーピングの日報を一括で再判定する(管理者用)。
  ///
  /// 【想定シナリオ】ブラウザのキャッシュが古いままだった等の理由で、
  /// 日報保存時の自動グルーピングが実行されなかった日報が後から
  /// 見つかった場合に、管理者がこの操作で一括リカバリできるようにする。
  /// 既に案件へ紐付いている日報には影響しない(安全設計)。
  Future<CaseResyncResult> resyncUngroupedCases() async {
    final result = await _caseService.resyncUngroupedReports();
    await _service.refreshAll();
    _reports = _service.getAllReports();
    notifyListeners();
    return result;
  }

  /// 既存の全案件を、紐づく日報から正確に再計算する(管理者用)。
  ///
  /// 【想定シナリオ】過去の不具合(旧案件からの切り離し漏れ等)によって
  /// 案件側の集計値(参加者・合計作業時間・冷媒充填有無・店舗名等)が
  /// 実際の日報内容と食い違ってしまっている場合に、管理者がこの操作で
  /// 一括修復できるようにする。既に案件に紐づいている日報の内容から
  /// 案件を丸ごと作り直すだけなので、正常な案件に対して実行しても
  /// 結果は変わらない(安全設計)。
  Future<CaseRecalculateAllResult> recalculateAllCases() async {
    final result = await _caseService.recalculateAllCases();
    await _service.refreshAll();
    _reports = _service.getAllReports();
    notifyListeners();
    return result;
  }

  /// 複数の案件を1つにまとめる(管理者用・案件一覧のまとめ機能)。
  ///
  /// [targetCaseId] に [sourceCaseIds] の内容(紐づく日報)を統合する。
  /// まとめ元の案件ドキュメントは削除される。
  Future<void> mergeCases({
    required String targetCaseId,
    required List<String> sourceCaseIds,
  }) async {
    await _caseService.mergeCases(
      targetCaseId: targetCaseId,
      sourceCaseIds: sourceCaseIds,
    );
    await _service.refreshAll();
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

  /// 社員の役割を変更する。事故防止のガード(自己変更禁止・最後の最高管理者の
  /// 降格禁止・最高管理者以外は実行不可)は ReportService 側で最終チェックされる。
  Future<void> updateUserRole({
    required String targetUserId,
    required UserRole newRole,
  }) async {
    await _service.updateUserRole(targetUserId: targetUserId, newRole: newRole);
    _users = _service.getAllUsers();
    notifyListeners();
  }

  /// 社員を削除する。事故防止のガード(自己削除禁止・最後の最高管理者の
  /// 削除禁止・最高管理者以外は実行不可)は ReportService 側で最終チェックされる。
  Future<void> deleteUser(String targetUserId) async {
    await _service.deleteUser(targetUserId);
    _users = _service.getAllUsers();
    notifyListeners();
  }

  Future<void> changePassword(String newPassword) =>
      _service.changePassword(newPassword);

  Future<void> sendPasswordResetEmail(String email) =>
      _service.sendPasswordResetEmail(email);

  List<WorkReport> search({
    String? keyword,
    String? authorId,
    String? storeId,
    String? clientName,
    ResponseType? responseType,
    DateTime? from,
    DateTime? to,
    bool onlySuccess = false,
    bool onlyIssues = false,
    bool onlyRefrigerantFilling = false,
  }) {
    return _service.search(
      keyword: keyword,
      authorId: authorId,
      storeId: storeId,
      clientName: clientName,
      responseType: responseType,
      from: from,
      to: to,
      onlySuccess: onlySuccess,
      onlyIssues: onlyIssues,
      onlyRefrigerantFilling: onlyRefrigerantFilling,
    );
  }

  Map<String, int> countByResponseType(List<WorkReport> reports) =>
      _service.countByResponseType(reports);

  Map<String, int> countByAuthor(List<WorkReport> reports) =>
      _service.countByAuthor(reports);

  String newId() => _service.newId();
}
