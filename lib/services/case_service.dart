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
    // 【不具合修正・2026-08-31】
    // 日報を編集して伝票No/受付Noを後から入力・変更した場合、判定される
    // caseId(docId)が変わることがある。旧caseIdが既に存在し、かつ新しい
    // caseIdと異なる場合、旧案件からのリンク解除(unlinkReportFromCase)を
    // 行わないと、古い案件に古い集計値(参加者・合計作業時間・冷媒充填有無等)
    // が取り残されたまま残ってしまう(=「日報にはあるが案件に反映されない」
    // 不整合の主要因)。判定処理の最初に、まず旧caseIdを退避しておく。
    final previousCaseId = report.caseId.trim();

    late final String newCaseId;

    // 1. プロワン伝票No優先
    final slip = report.proWanRefNumber.trim();
    if (slip.isNotEmpty) {
      newCaseId = await _linkToConfirmedCase(
        report: report,
        keyType: 'prowan_slip',
        keyValue: slip,
      );
    } else {
      // 2. SE店舗の弊社受付No
      final receipt = report.storeSystemReportCopy.receiptNumber.trim();
      if (receipt.isNotEmpty) {
        newCaseId = await _linkToConfirmedCase(
          report: report,
          keyType: 'se_receipt',
          keyValue: receipt,
        );
      } else {
        // 3. 番号なし -> 曖昧グルーピングを試みる
        newCaseId = await _linkToSuggestedCase(report);
      }
    }

    // 旧caseIdが存在し、かつ新しい判定結果と異なる(=キー変更等により
    // 案件が切り替わった)場合、旧案件から自分を切り離す。
    if (previousCaseId.isNotEmpty && previousCaseId != newCaseId) {
      try {
        await unlinkReportFromCase(report.id, previousCaseId);
      } catch (_) {
        // 旧案件が既に削除済み等で失敗しても、新しい紐付け自体は
        // 完了しているためベストエフォートとして無視する。
      }
    }

    return newCaseId;
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
  ///
  /// 【不具合修正・2026-08-31】
  /// 従来は日報側の case_id を無条件に空文字へクリアしていたが、これだと
  /// 「新しい案件へ既に紐付け済みの日報」に対してこの関数を後始末目的で
  /// 呼び出した場合(syncCaseForReport() 内の旧案件クリーンアップ処理など)、
  /// せっかく設定した新しい case_id を誤って上書き消去してしまう危険がある。
  /// そのため、日報の現在の case_id が「これから切り離そうとしている
  /// caseId」と一致している場合のみクリアするようにする(=既に別の案件へ
  /// 付け替え済みなら、この日報の case_id には触れない)。
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

    final reportRef = _reportsCol.doc(reportId);
    final reportSnap = await reportRef.get();
    if (reportSnap.exists) {
      final currentCaseId = (reportSnap.data()?['case_id'] as String?) ?? '';
      // まだこの案件に紐づいたままの場合のみクリアする。
      // (既に別の案件へ付け替え済みなら、その正しい値を維持する)
      if (currentCaseId == caseId) {
        await reportRef.update({'case_id': ''});
      }
    }

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

  // ------------------------------------------------------------
  // 案件を手動でまとめる(管理画面用・2026-08追加)
  // ------------------------------------------------------------
  //
  // 【背景】案件一覧を「全件表示」にしたことで、実際は同じ案件なのに
  // 伝票No/受付Noの入力漏れ等により別々の案件として表示されてしまう
  // ケースが見えるようになった。これを管理者が手動で1つに統合できる
  // ようにするための機能。
  //
  // 【設計】
  // - まとめ先(targetCaseId)を1つ指定し、まとめ元(sourceCaseIds)に
  //   紐づく日報をすべてまとめ先へ付け替える。
  // - まとめ元の中に「確実」判定(伝票No/受付No一致)の案件が含まれ、
  //   まとめ先がまだ「推測」判定だった場合は、その確実な判定情報を
  //   まとめ先に引き継ぐ(より正確な情報を優先する)。
  // - 統合後、まとめ元の案件ドキュメントは削除する。
  // - 参加者・合計作業時間などは、加算方式による二重計上を避けるため
  //   recalculateCase() で紐づく日報から正確に再計算する。
  Future<void> mergeCases({
    required String targetCaseId,
    required List<String> sourceCaseIds,
  }) async {
    final otherIds = sourceCaseIds.where((id) => id != targetCaseId).toSet().toList();
    if (otherIds.isEmpty) return;

    final targetRef = _casesCol.doc(targetCaseId);
    final targetSnap = await targetRef.get();
    if (!targetSnap.exists) {
      throw Exception('まとめ先の案件が見つかりません');
    }
    final targetCase = WorkCase.fromMap(targetSnap.id, targetSnap.data()!);

    final allReportIds = <String>{...targetCase.linkedReportIds};

    for (final srcId in otherIds) {
      final srcSnap = await _casesCol.doc(srcId).get();
      if (!srcSnap.exists) continue;
      final srcCase = WorkCase.fromMap(srcSnap.id, srcSnap.data()!);
      allReportIds.addAll(srcCase.linkedReportIds);

      // まとめ先がまだ「推測」で、まとめ元が「確実」なら、確実な判定情報を引き継ぐ。
      if (!targetCase.isConfirmed && srcCase.isConfirmed) {
        targetCase.primaryKeyType = srcCase.primaryKeyType;
        targetCase.primaryKeyValue = srcCase.primaryKeyValue;
        targetCase.status = 'confirmed';
      }
    }

    // 日報側のcase_idをまとめ先へ付け替える(Firestoreのバッチ上限を考慮し分割)
    final reportIds = allReportIds.toList();
    const chunkSize = 400;
    for (var i = 0; i < reportIds.length; i += chunkSize) {
      final end = (i + chunkSize > reportIds.length) ? reportIds.length : i + chunkSize;
      final batch = _db.batch();
      for (final rid in reportIds.sublist(i, end)) {
        batch.update(_reportsCol.doc(rid), {'case_id': targetCaseId});
      }
      await batch.commit();
    }

    // まとめ先の案件情報(判定情報・紐づく日報一覧)を先に反映しておく
    targetCase.linkedReportIds = reportIds;
    await targetRef.set(targetCase.toMap());

    // まとめ元の案件ドキュメントを削除
    final deleteBatch = _db.batch();
    for (final srcId in otherIds) {
      deleteBatch.delete(_casesCol.doc(srcId));
    }
    await deleteBatch.commit();

    // 紐づく日報から正確に再計算(参加者・合計作業時間等の整合性を保証)
    await recalculateCase(targetCaseId);
  }

  // ------------------------------------------------------------
  // 未グルーピング日報の再判定(管理画面用・2026-08追加)
  // ------------------------------------------------------------
  //
  // 【背景】
  // 日報保存直後の自動グルーピング処理(syncCaseForReport)はベストエフォート
  // であり、保存時点でブラウザが古いキャッシュ版アプリを使っていた等の理由で
  // 実行されないまま日報が保存されるケースがあることが判明した(2026-08-26)。
  // このメソッドは、既存の全日報を対象に「案件への紐付けがまだ済んでいない
  // もの」だけを抽出し、現在のグルーピングロジックで再判定する。
  //
  // 【安全のための設計】
  // - 既に caseId が設定済みの日報には一切手を触れない(既存の正しい
  //   紐付けを壊さないことを最優先する)。
  // - 判定順は作成日時の昇順(古い日報から)とし、実際の保存時と同じ順序
  //   関係を再現する。
  // - 各日報ごとに syncCaseForReport を呼ぶだけであり、判定ロジック自体は
  //   通常の保存時と完全に同一(二重実装を避ける)。
  Future<CaseResyncResult> resyncUngroupedReports() async {
    final snap = await _reportsCol.get();
    final targets = <WorkReport>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      // 'case_id' フィールド自体が存在しない、または値がnull/空文字の
      // 日報のみを対象とする(=既にグルーピング済みのものは変更しない)。
      final raw = data['case_id'];
      final caseId = raw is String ? raw.trim() : '';
      if (caseId.isNotEmpty) continue;
      targets.add(WorkReport.fromMap(doc.id, data));
    }
    targets.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    var linkedCount = 0;
    var noMatchCount = 0;
    var errorCount = 0;
    final errors = <String>[];

    for (final report in targets) {
      try {
        final caseId = await syncCaseForReport(report);
        if (caseId.isNotEmpty) {
          linkedCount++;
        } else {
          noMatchCount++;
        }
      } catch (e) {
        errorCount++;
        errors.add('日報ID ${report.id}: $e');
      }
    }

    return CaseResyncResult(
      totalTargets: targets.length,
      linkedCount: linkedCount,
      noMatchCount: noMatchCount,
      errorCount: errorCount,
      errors: errors,
    );
  }

  // ------------------------------------------------------------
  // 既存案件の一括再計算(管理画面用・2026-08-31追加)
  // ------------------------------------------------------------
  //
  // 【背景】
  // resyncUngroupedReports() は「まだどの案件にも紐づいていない日報」
  // だけを対象とするため、「既に案件へ紐づいてはいるが、過去の不具合
  // (旧案件からの切り離し漏れ等)によって集計値(参加者・合計作業時間・
  // 冷媒充填有無・店舗名等)が古いまま/不正確になってしまっている案件」
  // は一切修復されない。
  //
  // このメソッドは、既存の cases コレクションを全件走査し、各案件を
  // recalculateCase() で「紐づく日報から正確に作り直す」ことで、
  // 過去に蓄積された不整合を一括で解消するための管理者向け機能。
  //
  // 【安全性】
  // recalculateCase() 自体は既に「紐づく日報一覧から都度作り直す」
  // 冪等な処理であるため、正常な案件に対して再実行しても値は変わらない
  // (=副作用のない安全な操作)。
  Future<CaseRecalculateAllResult> recalculateAllCases() async {
    final snap = await _casesCol.get();
    final caseIds = snap.docs.map((d) => d.id).toList();

    var successCount = 0;
    var deletedCount = 0; // 紐づく日報が既に存在しなかった等で削除された件数
    var errorCount = 0;
    final errors = <String>[];

    for (final caseId in caseIds) {
      try {
        final existedBefore = await _casesCol.doc(caseId).get();
        await recalculateCase(caseId);
        if (existedBefore.exists) {
          final existsAfter = await _casesCol.doc(caseId).get();
          if (!existsAfter.exists) {
            deletedCount++;
          } else {
            successCount++;
          }
        }
      } catch (e) {
        errorCount++;
        errors.add('案件ID $caseId: $e');
      }
    }

    return CaseRecalculateAllResult(
      totalTargets: caseIds.length,
      successCount: successCount,
      deletedCount: deletedCount,
      errorCount: errorCount,
      errors: errors,
    );
  }
}

/// [CaseService.recalculateAllCases] の実行結果。
class CaseRecalculateAllResult {
  final int totalTargets; // 対象だった案件数
  final int successCount; // 正常に再計算できた件数
  final int deletedCount; // 紐づく日報が消滅していた等で削除された件数
  final int errorCount; // 処理中にエラーが発生した件数
  final List<String> errors; // エラー内容

  const CaseRecalculateAllResult({
    required this.totalTargets,
    required this.successCount,
    required this.deletedCount,
    required this.errorCount,
    required this.errors,
  });

  bool get hasTargets => totalTargets > 0;
  bool get hasErrors => errorCount > 0;
}

/// [CaseService.resyncUngroupedReports] の実行結果。
class CaseResyncResult {
  final int totalTargets; // 再判定対象だった日報数
  final int linkedCount; // 新たに案件へ紐付けられた件数
  final int noMatchCount; // 判定した結果、該当する案件がなかった件数(=正常)
  final int errorCount; // 処理中にエラーが発生した件数
  final List<String> errors; // エラー内容(先頭数件程度を想定)

  const CaseResyncResult({
    required this.totalTargets,
    required this.linkedCount,
    required this.noMatchCount,
    required this.errorCount,
    required this.errors,
  });

  bool get hasTargets => totalTargets > 0;
  bool get hasErrors => errorCount > 0;
}
