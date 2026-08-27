import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/prowan_job_cache.dart';
import '../utils/fuzzy_match.dart';

/// プロワンCSVキャッシュ(`prowan_job_cache` コレクション)への
/// 読み取り専用アクセスを担当するサービス。
///
/// 【設計方針(前セッションで確定・本セッションで実装)】
/// 「CSVキャッシュ + 伝票No一点読み取り」のハイブリッド方式における、
/// 現場でのスキャン時の照合ロジックを担当する。
///
/// 二段階マッチングの「①スキャン時OCR読み取り」に対応:
///   1. 完全一致: ドキュメントIDで直接取得(伝票Noが正確に読み取れた場合)
///   2. 曖昧一致: 完全一致しない場合、キャッシュ全体から
///      レーベンシュタイン距離ベースで近い伝票Noを検索
///   3. 手入力フォールバック: 曖昧一致でも見つからない場合はnullを返し、
///      呼び出し元(UI)が手入力を促す
///
/// 【キャッシュ更新について】
/// このコレクション自体の更新(日次CSV取込)は事務所側で
/// csv_cache_backend/import_prowan_csv.py (Firebase Admin SDK) が担当する。
/// Flutterアプリからは書き込みを行わない(読み取り専用)。
class ProwanJobCacheService {
  static final ProwanJobCacheService instance =
      ProwanJobCacheService._internal();
  ProwanJobCacheService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _cacheCol =>
      _db.collection('prowan_job_cache');

  // 曖昧一致検索用に、伝票No一覧をメモリキャッシュする。
  // (件数が数百件程度想定のため全件メモリ保持で問題ない。
  //  Firestoreの複合インデックス要件を避けるため、単純な .get() のみ使用)
  List<String> _allJobNumbersCache = [];
  DateTime? _jobNumbersCacheLoadedAt;

  /// 伝票Noで完全一致検索する(ドキュメントID直接取得、最速)。
  /// 見つからない場合はnullを返す。
  Future<ProwanJobCache?> findByExactJobNumber(String jobNumber) async {
    final trimmed = jobNumber.trim();
    if (trimmed.isEmpty) return null;
    final snap = await _cacheCol.doc(trimmed).get();
    if (!snap.exists) return null;
    return ProwanJobCache.fromMap(snap.id, snap.data()!);
  }

  /// 全伝票No一覧を取得する(曖昧一致検索の候補集合として使う)。
  /// 直近取得済みならキャッシュを再利用する(5分以内は再取得しない)。
  Future<List<String>> _loadAllJobNumbers({bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _jobNumbersCacheLoadedAt != null &&
        now.difference(_jobNumbersCacheLoadedAt!) < const Duration(minutes: 5) &&
        _allJobNumbersCache.isNotEmpty) {
      return _allJobNumbersCache;
    }
    // ドキュメントIDのみ必要なので、フィールド全体は取得コストがかかるが
    // Firestoreクライアントの制約上ドキュメント自体を取得する必要がある。
    // 件数が数百件規模のため実用上問題ない。
    final snap = await _cacheCol.get();
    _allJobNumbersCache = snap.docs.map((d) => d.id).toList();
    _jobNumbersCacheLoadedAt = now;
    return _allJobNumbersCache;
  }

  /// 完全一致 -> 曖昧一致 の順で伝票Noを検索する。
  ///
  /// [scannedStoreName] はAI-OCRが同時に読み取った店名(あれば)。
  /// 【不具合修正・2026-08-27】曖昧一致候補が伝票No的には近くても、
  /// 実際には全く無関係な別店舗の案件であるケースが本番で発生したため、
  /// 店名が読み取れている場合は候補の店名との類似度もあわせてチェックし、
  /// 明らかに違う店舗の案件は候補から除外する。
  ///
  /// [scannedWorkStartDate] はAI-OCRが同時に読み取った「作業開始日」
  /// (あれば)。【2026-08-27追加: 関連案件対応】1つの伝票Noに複数の
  /// 作業日程が存在する場合、この値を使って [ProwanJobCache.schedules]
  /// から該当する日程を選び出し、結果の [ProwanJobCacheMatchResult.matchedSchedule]
  /// に設定する。日程が1件のみ、またはこの値が空欄・解析不能な場合は
  /// nullのままとなる(呼び出し元はトップレベルの値をそのまま使えばよい)。
  ///
  /// 戻り値: 見つかった場合は [ProwanJobCacheMatchResult](一致した伝票No・距離・
  /// キャッシュ内容・該当日程を含む)、見つからなければnull(呼び出し元は手入力へ
  /// フォールバックすること)。
  Future<ProwanJobCacheMatchResult?> findByScannedJobNumber(
    String scannedNumber, {
    String? scannedStoreName,
    String? scannedWorkStartDate,
  }) async {
    final trimmed = scannedNumber.trim();
    if (trimmed.isEmpty) return null;

    // 1. 完全一致
    final exact = await findByExactJobNumber(trimmed);
    if (exact != null) {
      return ProwanJobCacheMatchResult(
        cache: exact,
        matchedJobNumber: exact.jobManagementNumber,
        distance: 0,
        isExactMatch: true,
        matchedSchedule: exact.findScheduleByScannedWorkStartDate(
          scannedWorkStartDate ?? '',
        ),
      );
    }

    // 2. 曖昧一致(OCR誤読を1〜2文字許容)
    final allNumbers = await _loadAllJobNumbers();
    final rawCandidates = findFuzzyJobNumberMatches(trimmed, allNumbers);
    if (rawCandidates.isEmpty) return null;

    // 各候補の実データを取得し、店名が明らかに異なるものは除外する。
    final resolvedCandidates = <_ResolvedCandidate>[];
    for (final c in rawCandidates) {
      final cache = await findByExactJobNumber(c.candidate);
      if (cache == null) continue;
      final compatible = isStoreNameCompatible(
        scannedStoreName: scannedStoreName ?? '',
        candidateStoreName: cache.storeName,
      );
      if (!compatible) continue; // 店名が明確に異なる→無関係な案件として除外
      resolvedCandidates.add(_ResolvedCandidate(cache, c.distance));
    }

    if (resolvedCandidates.isEmpty) {
      // 番号だけは近いが店名が全く違う案件しかなかった場合。
      // 「無関係な案件を誤って提案する」よりは、手入力フォールバックへ
      // 倒す方が安全という社内方針に基づく。
      return null;
    }

    final best = resolvedCandidates.first;
    return ProwanJobCacheMatchResult(
      cache: best.cache,
      matchedJobNumber: best.cache.jobManagementNumber,
      distance: best.distance,
      isExactMatch: false,
      // 複数候補がある場合、UI側で選択肢として提示できるようにする
      alternativeCandidates: resolvedCandidates.length > 1
          ? resolvedCandidates
                .sublist(1)
                .map((c) => c.cache.jobManagementNumber)
                .toList()
          : [],
      matchedSchedule: best.cache.findScheduleByScannedWorkStartDate(
        scannedWorkStartDate ?? '',
      ),
    );
  }

  // ------------------------------------------------------------

  /// キャッシュ内の全件数を取得する(管理画面での状態表示用)。
  Future<int> countAll() async {
    final agg = await _cacheCol.count().get();
    return agg.count ?? 0;
  }

  /// 最終更新日時(取込日時)を取得する(管理画面での状態表示用)。
  /// 全件のうち最新の updated_at を1件だけ取得する。
  Future<DateTime?> getLastImportedAt() async {
    final snap = await _cacheCol
        .orderBy('updated_at', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final data = snap.docs.first.data();
    final value = data['updated_at'];
    if (value == null) return null;
    try {
      return (value as Timestamp).toDate();
    } catch (_) {
      return null;
    }
  }
}

/// 伝票No照合の結果(完全一致 or 曖昧一致)。
class ProwanJobCacheMatchResult {
  final ProwanJobCache cache;
  final String matchedJobNumber; // 実際にマッチしたキャッシュ側の伝票No
  final int distance; // レーベンシュタイン距離(0=完全一致)
  final bool isExactMatch;
  final List<String> alternativeCandidates; // 曖昧一致時、他にも候補があれば

  /// 【2026-08-27追加: 関連案件対応】伝票No一致後、OCRで読み取った
  /// 「作業開始日」を使って [cache.schedules] から選び出された日程。
  /// - [cache.schedules] が0/1件、または作業開始日が読み取れなかった/
  ///   解析できなかった場合は null(呼び出し元はトップレベルの値をそのまま使う)。
  /// - nullでない場合、呼び出し元はこの日程の
  ///   [ProwanScheduleEntry.toWorkReportFieldValues()] を優先的に使うことで、
  ///   関連案件の中から該当する1日程分の内容だけを反映できる。
  final ProwanScheduleEntry? matchedSchedule;

  const ProwanJobCacheMatchResult({
    required this.cache,
    required this.matchedJobNumber,
    required this.distance,
    required this.isExactMatch,
    this.alternativeCandidates = const [],
    this.matchedSchedule,
  });

  /// UI表示用: 「曖昧一致のため確認が必要」かどうか
  bool get needsConfirmation => !isExactMatch;

  /// UI表示用: 伝票No内に複数日程(関連案件)が存在するかどうか。
  bool get hasMultipleSchedules => cache.schedules.length > 1;

  /// UI表示用: 複数日程が存在するが、作業開始日から日程を1件に
  /// 絞り込めなかった(=OCRが作業開始日を読み取れなかった、または
  /// 表記が解析できなかった)状態かどうか。
  bool get scheduleAmbiguous => hasMultipleSchedules && matchedSchedule == null;
}

/// findByScannedJobNumber()内部でのみ使う、店名フィルタ通過後の
/// 曖昧一致候補(キャッシュ実データ+距離)の一時保持用。
class _ResolvedCandidate {
  final ProwanJobCache cache;
  final int distance;
  const _ResolvedCandidate(this.cache, this.distance);
}
