import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/work_report.dart';
import '../models/user.dart';
import '../data/employee_master_data.dart';
import 'report_outbox_service.dart';

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
  final ReportOutboxService _outbox = ReportOutboxService.instance;

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

  /// 社員の役割を変更する(事故防止ガードは AppState 側で先に判定済みだが、
  /// サービス層でも最終防衛線として同じチェックを行う)。
  ///
  /// - 最高管理者(super_admin)のみが役割変更を実行できる。
  /// - 自分自身の役割は変更できない(誤操作による自己ロックアウト防止)。
  /// - 最高管理者が1人だけの場合、その人を降格させることはできない
  ///   (管理者が誰もいなくなる事故防止)。
  Future<void> updateUserRole({
    required String targetUserId,
    required UserRole newRole,
  }) async {
    final actor = getCurrentUser();
    if (actor == null || !actor.isSuperAdmin) {
      throw StateError('役割の変更は最高管理者のみ実行できます。');
    }
    if (actor.id == targetUserId) {
      throw StateError('自分自身の役割は変更できません。');
    }
    final target = _usersCache.firstWhere(
      (u) => u.id == targetUserId,
      orElse: () => throw StateError('対象の社員が見つかりません。'),
    );
    if (target.isSuperAdmin && newRole != UserRole.superAdmin) {
      final superAdminCount = _usersCache
          .where((u) => u.role == UserRole.superAdmin)
          .length;
      if (superAdminCount <= 1) {
        throw StateError('最後の最高管理者は降格できません。');
      }
    }
    await _usersCol.doc(targetUserId).update({
      'role': AppUser.roleToStr(newRole),
    });
    await _refreshUsersCache();
  }

  /// 社員を削除する(Firestore上のユーザードキュメントのみ削除。
  /// Firebase Authenticationアカウント自体はクライアントSDKからは削除できないため、
  /// 併せて手動でのアカウント無効化を管理者に案内する運用とする)。
  ///
  /// - 最高管理者(super_admin)のみが削除を実行できる。
  /// - 自分自身は削除できない。
  /// - 最後の最高管理者は削除できない。
  Future<void> deleteUser(String targetUserId) async {
    final actor = getCurrentUser();
    if (actor == null || !actor.isSuperAdmin) {
      throw StateError('社員の削除は最高管理者のみ実行できます。');
    }
    if (actor.id == targetUserId) {
      throw StateError('自分自身を削除することはできません。');
    }
    final target = _usersCache.firstWhere(
      (u) => u.id == targetUserId,
      orElse: () => throw StateError('対象の社員が見つかりません。'),
    );
    if (target.isSuperAdmin) {
      final superAdminCount = _usersCache
          .where((u) => u.role == UserRole.superAdmin)
          .length;
      if (superAdminCount <= 1) {
        throw StateError('最後の最高管理者は削除できません。');
      }
    }
    await _usersCol.doc(targetUserId).delete();
    await _refreshUsersCache();
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

  /// 【恒久対策・2026-09導入】日報保存の「必ず先にOutboxへ控えを残す」設計。
  ///
  /// 【背景】Firestoreのローカルキャッシュ(オフライン永続化)のみに
  /// 依存していた従来設計では、そのキャッシュ自体が何らかの理由
  /// (端末側のストレージ整理・アプリの異常終了等)で失われた場合、
  /// 「入力した本人には保存できたように見えるが、サーバーには一切
  /// 届かず、痕跡も残らない」という重大な事象が発生し得ることが、
  /// 実際の現場データ調査で確認された。
  ///
  /// このため、Firestoreへの書き込みを試みる前に必ずアプリ独自の
  /// 永続層(Hive、Outbox)へ控えを保存する。Firestore側のキャッシュが
  /// 消えても、Outbox側の控えから復元・再送信できるようにする
  /// (詳細は ReportOutboxService のドキュメント参照)。
  Future<WorkReport> createReport(WorkReport report) async {
    await _outbox.stash(report, isUpdate: false);
    try {
      await _reportsCol.doc(report.id).set(report.toMap());
      // ローカルキャッシュ確定だけでなく、実際にサーバーへ届いたことを
      // 確認できてから初めてOutboxの控えを消す(電波が無い場所では
      // ここでタイムアウトし、控えは残り続けるのが正しい挙動)。
      await _waitForServerConfirmationThenClear(report.id);
    } catch (e) {
      // Firestoreへの書き込み自体が例外を投げた場合も、Outboxの控えは
      // 消さずに残す(次回起動時・電波復帰時に自動再送信される)。
      if (kDebugMode) {
        debugPrint('日報の保存でエラーが発生(Outboxに控えを保持): $e');
      }
      rethrow;
    }
    await _refreshReportsCache();
    return report;
  }

  Future<void> updateReport(WorkReport report) async {
    report.updatedAt = DateTime.now();
    await _outbox.stash(report, isUpdate: true);
    try {
      await _reportsCol.doc(report.id).update(report.toMap());
      await _waitForServerConfirmationThenClear(report.id);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('日報の更新でエラーが発生(Outboxに控えを保持): $e');
      }
      rethrow;
    }
    await _refreshReportsCache();
  }

  /// Firestoreへの書き込みが実際にサーバーへ到達したこと
  /// (`waitForPendingWrites`)を確認できた場合のみOutboxの控えを消す。
  /// タイムアウトした場合は「まだ未確定」として控えを残したままにする
  /// (Outboxのバックグラウンド再送信・起動時再送信に任せる)。
  Future<void> _waitForServerConfirmationThenClear(String reportId) async {
    try {
      await _db.waitForPendingWrites().timeout(const Duration(seconds: 10));
      await _outbox.clear(reportId);
    } catch (_) {
      // タイムアウト・失敗時は控えを残す(意図的、何もしない)。
    }
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
    bool onlyRefrigerantFilling = false,
    bool onlyKnowledgeOverdue = false,
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
    if (onlyRefrigerantFilling) {
      list = list.where((r) => r.hasRefrigerantFilling).toList();
    }
    if (onlyKnowledgeOverdue) {
      list = list.where((r) => r.isKnowledgeOverdue).toList();
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
