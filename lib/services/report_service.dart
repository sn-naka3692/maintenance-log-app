import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:uuid/uuid.dart';
import '../models/work_report.dart';
import '../models/user.dart';
import '../data/employee_master_data.dart';

/// 日報・ユーザーデータの永続化を担当するサービス(Firestore)
///
/// 初回起動時、従業員マスタ(employee_master_data.dart、実在の従業員29名)が
/// まだ登録されていなければ自動投入する。既存のユーザーデータは維持する。
class ReportService {
  static final ReportService instance = ReportService._internal();
  ReportService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
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

  /// Firebase Authenticationでログイン中のユーザーに対応する
  /// Firestore上のユーザー情報を返す(UID = Firestoreドキュメントid で対応)。
  /// 未ログイン、またはFirestore側にユーザー情報が見つからない場合はnull。
  AppUser? getCurrentUser() {
    final fbUser = _auth.currentUser;
    if (fbUser == null) return null;
    try {
      return _usersCache.firstWhere((u) => u.id == fbUser.uid);
    } catch (_) {
      return null;
    }
  }

  bool get isSignedIn => _auth.currentUser != null;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  /// メールアドレス・パスワードでログインする。
  Future<AppUser?> signInWithEmail(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await _refreshUsersCache();
    return getCurrentUser();
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// パスワードを変更する(本人がログイン中に呼び出す)。
  /// 再認証が必要な場合(セッションが古い等)は re-login を促すため
  /// FirebaseAuthExceptionをそのままthrowする。
  Future<void> changePassword(String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'ログインしていません。',
      );
    }
    await user.updatePassword(newPassword);
  }

  /// パスワード再設定メールを送信する。
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  /// 社員を追加し、同時にFirebase Authenticationのログインアカウントも作成する。
  ///
  /// Firebase Authでユーザーを新規作成すると、クライアントSDKの仕様上
  /// 「作成した瞬間そのユーザーでログイン状態になる」ため、管理者自身が
  /// ログアウトされてしまう問題がある。これを避けるため、一時的な
  /// セカンダリのFirebaseAppインスタンス上でユーザー作成を行い、
  /// 管理者の現在のログインセッションには影響を与えないようにする。
  ///
  /// [initialPassword] は呼び出し元(画面)が生成した初期パスワード。
  /// 戻り値の [AppUser.id] はFirebase AuthのUIDと一致する(現行ユーザーと同じ設計)。
  Future<AppUser> addUser({
    required String name,
    required String employeeCode,
    required UserRole role,
    required String department,
    required String email,
    required String initialPassword,
    required String phone,
  }) async {
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty) {
      throw ArgumentError('メールアドレスは必須です');
    }
    if (phone.trim().isEmpty) {
      throw ArgumentError('電話番号は必須です');
    }

    // セカンダリアプリで新規ユーザーを作成(現在の管理者セッションを維持するため)
    final secondaryApp = await Firebase.initializeApp(
      name: 'secondaryAuth_${DateTime.now().microsecondsSinceEpoch}',
      options: Firebase.app().options,
    );
    String uid;
    try {
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      final cred = await secondaryAuth.createUserWithEmailAndPassword(
        email: trimmedEmail,
        password: initialPassword,
      );
      await cred.user?.updateDisplayName(name);
      uid = cred.user!.uid;
      await secondaryAuth.signOut();
    } finally {
      await secondaryApp.delete();
    }

    final u = AppUser(
      id: uid,
      name: name,
      employeeCode: employeeCode,
      role: role,
      department: department,
      createdAt: DateTime.now(),
      email: trimmedEmail,
      phone: phone,
    );
    await _usersCol.doc(uid).set(u.toMap());
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
    String? storeId,
    String? clientName,
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
    if (storeId != null && storeId.isNotEmpty) {
      list = list.where((r) => r.storeId == storeId).toList();
    }
    if (clientName != null && clientName.trim().isNotEmpty) {
      final cn = clientName.trim().toLowerCase();
      list = list
          .where((r) => r.clientName.toLowerCase().contains(cn))
          .toList();
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
