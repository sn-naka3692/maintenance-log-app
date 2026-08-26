import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/case.dart';
import '../models/work_report.dart';
import '../utils/fuzzy_match.dart';

/// 「案件」自動グルーピングを担当するサービス。
///
/// 【設計方針(2026-08導入・ユーザー要望に基づく)】
/// 日報機能はあくまで「1人1回の対応記録」を書くための機能であり、
/// 複数人で同じ現場対応をした場合でも、それぞれが個別に日報を書く運用は
/// 変えない(現場の入力負担を増やさないことを最優先とする=A案)。
///
/// その代わり、日報の保存(作成・更新)のたびに、このサービスが裏側で
/// 自動的に「同じ案件と思われる日報」を判定し、`cases` コレクションへの
/// 集約を行う。従業員からは一切見えない/操作不要の処理。
///
/// 【グルーピング判定の優先順位】
///   1. プロワン伝票No(proWanRefNumber)が完全一致 -> confirmed
///   2. SE店舗の弊社受付No(storeSystemReportCopy.receiptNumber)が完全一致
///      -> confirmed
///   3. 番号が無い場合、同じ店舗 + 訪問日が近い(前後3日以内)+ 作業内容の
///      類似度が高い(0.5以上)既存日報があれば、それと同じ案件の可能性が
///      高いとみなし suggested としてグルーピングする
///      (誤結合のリスクがあるため、管理画面から手動で分離できるようにする)
class CaseService {
  static final CaseService instance = CaseService._internal();
  CaseService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _casesCol =>
      _db.collection('cases');
  CollectionReference<Map<String, dynamic>> get _reportsCol =>
      _db.collection('work_reports');

  // 曖昧グルーピング(status=='provisional'系)の判定に使う類似度しきい値
  static const double _similarityThreshold = 0.5;
  // 「訪問日が近い」とみなす日数
  static const int _nearDays = 3;

  /// 日報1件を保存した直後に呼び出す。
  /// 該当日報がどの案件に属するかを判定し、cases コレクションへ反映する。
  /// 戻り値: 紐付けられた caseId(判定できなかった場合は空文字)
  ///
  /// この処理はベストエフォートとする。万一エラーが発生しても、
  /// 日報自体の保存(呼び出し元で既に完了している)には影響を与えない
  /// よう、呼び出し元で try-catch することを推奨する。
  Future<String> syncCaseForReport(WorkReport report) async {
    // 1. プロワン伝票No優先
    final slip = report.proWanRefNumber.trim();
    if (slip.isNotEmpty) {
      return _linkToConfirmedCase(
        report: report,
        keyType: 'prowan_slip',
        keyValue: slip,
      );
    }

    // 2. SE店舗の弊社受付No
    final receipt = report.storeSystemReportCopy.receiptNumber.trim();
    if (receipt.isNotEmpty) {
      return _linkToConfirmedCase(
        report: report,
        keyType: 'se_receipt',
        keyValue: receipt,
      );
    }

    // 3. 番号なし -> 曖昧グルーピングを試みる
    return _linkToSuggestedCase(report);
  }

  /// 伝票No/受付Noをドキュメントキーとして正規化する
  /// (Firestoreドキュメントパスに使えない文字を避けるため簡易サニタイズ)
  String _sanitizeKey(String raw) {
    return raw.trim().replaceAll(RegExp(r'[/\\.#$\[\]]'), '_');
  }

  Future<String> _linkToConfirmedCase({
    required WorkReport report,
    required String keyType,
    required String keyValue,
  }) async {
    final docId = '${keyType}_${_sanitizeKey(keyValue)}';
    final ref = _casesCol.doc(docId);

    // 【二重カウント防止】同じ日報が既にこの案件に紐づいている場合
    // (=日報を編集して再保存したケース)、_applyReportToCaseを再度呼ぶと
    // 参加者・合計作業時間が加算され続けてしまう。そのため、既に紐づき
    // 済みかどうかを判定し、既存であれば案件全体をrecalculateCase()で
    // 正確に作り直す(=日報側の内容変更、例えば作業時間の修正等も
    // 正しく反映される)。
    bool alreadyLinked = false;
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      WorkCase caseObj;
      if (snap.exists) {
        caseObj = WorkCase.fromMap(snap.id, snap.data()!);
      } else {
        caseObj = WorkCase(
          id: docId,
          primaryKeyType: keyType,
          primaryKeyValue: keyValue,
          status: 'confirmed',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
      }
      alreadyLinked = caseObj.linkedReportIds.contains(report.id);
      if (!alreadyLinked) {
        _applyReportToCase(caseObj, report);
      }
      caseObj.status = 'confirmed';
      tx.set(ref, caseObj.toMap(), SetOptions(merge: false));
    });

    if (report.caseId != docId) {
      await _reportsCol.doc(report.id).update({'case_id': docId});
    }
    if (alreadyLinked) {
      // 日報の内容(作業時間・氏名等)が更新された可能性があるため、
      // 紐づく全日報から正確に再計算する。
      await recalculateCase(docId);
    }
    return docId;
  }

  /// 番号なしの日報を、既存の類似日報と照合してグルーピングする。
  Future<String> _linkToSuggestedCase(WorkReport report) async {
    if (report.storeId == null || report.storeId!.isEmpty) {
      return '';
    }

    // 同じ店舗の既存日報(自分自身は除く)を対象に類似度を評価する。
    final candidatesSnap = await _reportsCol
        .where('store_id', isEqualTo: report.storeId)
        .get();

    WorkReport? bestMatch;
    double bestScore = 0;

    for (final doc in candidatesSnap.docs) {
      if (doc.id == report.id) continue;
      final candidate = WorkReport.fromMap(doc.id, doc.data());
      // 【重要】候補側が確実キー(伝票No/受付No)を持つ既存日報も比較対象に
      // 含める。これは「同じ現場対応で、片方だけ伝票Noを入力し、もう片方は
      // 空欄のまま保存した」というケース(=複数人対応時に典型的に起こる)
      // を確実な案件へ正しく合流させるために必要な挙動。
      // (このメソッド自体は常に「番号なしの日報」に対してのみ呼ばれるため、
      // candidate側がconfirmedキーを持っていても、report自身が誤って
      // confirmedルートを上書きされることはない)
      final dayDiff = report.visitDate
          .difference(candidate.visitDate)
          .inDays
          .abs();
      if (dayDiff > _nearDays) continue;

      final score = similarityRatio(
        _normalizeForCompare(report.workContent),
        _normalizeForCompare(candidate.workContent),
      );
      if (score > bestScore) {
        bestScore = score;
        bestMatch = candidate;
      }
    }

    if (bestMatch == null || bestScore < _similarityThreshold) {
      return '';
    }

    // 既にbestMatch側が案件に紐づいていればそこに合流、
    // なければ新規のprovisional案件を作る。
    final existingCaseId = bestMatch.caseId.trim();
    final ref = existingCaseId.isNotEmpty
        ? _casesCol.doc(existingCaseId)
        : _casesCol.doc();
    final caseId = ref.id;
    // bestMatchが既存の案件に紐づいている場合、bestMatch自身は既に
    // その案件のlinkedReportIds/participants/totalWorkHoursに反映済み
    // のはずなので、ここで再度applyすると二重カウントになる。
    // 新規案件を作る場合(bestMatchが未グルーピングだった場合)のみ、
    // bestMatchも合わせてapplyする。
    final needsApplyBestMatch = existingCaseId.isEmpty;
    bool reportAlreadyLinked = false;

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      WorkCase caseObj;
      if (snap.exists) {
        caseObj = WorkCase.fromMap(snap.id, snap.data()!);
      } else {
        caseObj = WorkCase(
          id: ref.id,
          primaryKeyType: 'provisional',
          primaryKeyValue: '',
          status: 'suggested',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
      }
      if (needsApplyBestMatch) {
        _applyReportToCase(caseObj, bestMatch!);
      }
      reportAlreadyLinked = caseObj.linkedReportIds.contains(report.id);
      if (!reportAlreadyLinked) {
        _applyReportToCase(caseObj, report);
      }
      tx.set(ref, caseObj.toMap(), SetOptions(merge: false));
    });

    // 両方の日報にcaseIdをセットする
    final batch = _db.batch();
    if (report.caseId != caseId) {
      batch.update(_reportsCol.doc(report.id), {'case_id': caseId});
    }
    if (bestMatch.caseId != caseId) {
      batch.update(_reportsCol.doc(bestMatch.id), {'case_id': caseId});
    }
    await batch.commit();

    // reportが既に案件に紐づいていた(=編集して再保存した)場合、
    // 内容変更(作業時間等)を正確に反映するため再計算する。
    if (reportAlreadyLinked) {
      await recalculateCase(caseId);
    }

    return caseId;
  }

  String _normalizeForCompare(String s) {
    return s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  }

  void _applyReportToCase(WorkCase caseObj, WorkReport report) {
    if (!caseObj.linkedReportIds.contains(report.id)) {
      caseObj.linkedReportIds.add(report.id);
    }
    caseObj.storeId = report.storeId;
    if (report.clientName.isNotEmpty) {
      caseObj.storeName = report.clientName;
    }

    // 参加者集計
    final idx = caseObj.participants.indexWhere(
      (p) => p.authorId == report.authorId,
    );
    if (idx >= 0) {
      final existing = caseObj.participants[idx];
      // 同一人物の同一日報を二重カウントしないよう、
      // 常に「この日報のauthor一覧に基づき再集計」ではなく単純加算とする
      // (呼び出しは日報1件の保存につき1回のみのため実務上問題ない)。
      caseObj.participants[idx] = CaseParticipant(
        authorId: existing.authorId,
        authorName: report.authorName,
        reportCount: existing.reportCount,
      );
    } else {
      caseObj.participants.add(
        CaseParticipant(authorId: report.authorId, authorName: report.authorName),
      );
    }

    // 合計作業時間(重複カウント防止のため、都度全紐付け日報から再計算するのが
    // 理想だが、呼び出し頻度を抑えるためここでは加算方式とする点に留意。
    // より厳密にしたい場合は recalculateTotals() を使う。
    final hours = report.workDuration.inMinutes / 60.0;
    caseObj.totalWorkHours += hours;

    if (caseObj.firstVisitDate == null ||
        report.visitDate.isBefore(caseObj.firstVisitDate!)) {
      caseObj.firstVisitDate = report.visitDate;
    }
    if (caseObj.lastVisitDate == null ||
        report.visitDate.isAfter(caseObj.lastVisitDate!)) {
      caseObj.lastVisitDate = report.visitDate;
    }
    // 紐づく日報のいずれか1件でも冷媒充填を行っていれば案件全体として true。
    if (report.hasRefrigerantFilling) {
      caseObj.hasRefrigerantFilling = true;
    }
    caseObj.updatedAt = DateTime.now();
  }

  /// 案件1件を、紐づく日報一覧から正確に再計算する
  /// (手動分離・移行スクリプト等、加算方式では不整合が起きうる場面で使う)。
  Future<void> recalculateCase(String caseId) async {
    final ref = _casesCol.doc(caseId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final caseObj = WorkCase.fromMap(snap.id, snap.data()!);

    if (caseObj.linkedReportIds.isEmpty) {
      await ref.delete();
      return;
    }

    final reports = <WorkReport>[];
    for (final rid in caseObj.linkedReportIds) {
      final rSnap = await _reportsCol.doc(rid).get();
      if (rSnap.exists) {
        reports.add(WorkReport.fromMap(rSnap.id, rSnap.data()!));
      }
    }

    if (reports.isEmpty) {
      await ref.delete();
      return;
    }

    final rebuilt = WorkCase(
      id: caseObj.id,
      primaryKeyType: caseObj.primaryKeyType,
      primaryKeyValue: caseObj.primaryKeyValue,
      status: caseObj.status,
      createdAt: caseObj.createdAt,
      updatedAt: DateTime.now(),
    );
    for (final r in reports) {
      _applyReportToCase(rebuilt, r);
    }
    await ref.set(rebuilt.toMap());
  }

  /// 誤結合を管理画面から手動で解除する(1件の日報を案件から切り離す)。
  /// 切り離した日報は再度単独案件(または未グルーピング)として扱われる。
  Future<void> unlinkReportFromCase(String reportId, String caseId) async {
    final caseRef = _casesCol.doc(caseId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(caseRef);
      if (!snap.exists) return;
      final caseObj = WorkCase.fromMap(snap.id, snap.data()!);
      caseObj.linkedReportIds.remove(reportId);
      if (caseObj.linkedReportIds.isEmpty) {
        tx.delete(caseRef);
      } else {
        tx.update(caseRef, {
          'linked_report_ids': caseObj.linkedReportIds,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
    });
    await _reportsCol.doc(reportId).update({'case_id': ''});
    if (caseId.isNotEmpty) {
      await recalculateCase(caseId);
    }
  }

  Future<List<WorkCase>> getAllCases() async {
    final snap = await _casesCol.get();
    final list = snap.docs
        .map((d) => WorkCase.fromMap(d.id, d.data()))
        .toList();
    list.sort(
      (a, b) => (b.lastVisitDate ?? b.updatedAt).compareTo(
        a.lastVisitDate ?? a.updatedAt,
      ),
    );
    return list;
  }

  Future<WorkCase?> getCaseById(String caseId) async {
    if (caseId.isEmpty) return null;
    final snap = await _casesCol.doc(caseId).get();
    if (!snap.exists) return null;
    return WorkCase.fromMap(snap.id, snap.data()!);
  }
}
