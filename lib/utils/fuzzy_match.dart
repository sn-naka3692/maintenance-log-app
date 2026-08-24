/// 曖昧一致(レーベンシュタイン距離ベース)ロジック。
///
/// (Python版 /home/user/csv_cache_backend/fuzzy_match.py からの移植。
///  ロジックは完全に同一に保つこと)
///
/// 【想定用途】
/// スキャン時、OCRで読み取った伝票No(job_management_number)が
/// prowan_job_cache に完全一致しない場合、1〜2文字程度のOCR誤読を
/// 許容して再検索するために使う(例: "0"⇔"O"、"1"⇔"I" 等の誤読)。
library;

/// 2つの文字列間のレーベンシュタイン距離を計算する。
int levenshteinDistance(String a, String b) {
  if (a == b) return 0;
  final la = a.length;
  final lb = b.length;
  if (la == 0) return lb;
  if (lb == 0) return la;

  var prev = List<int>.generate(lb + 1, (j) => j);
  for (var i = 1; i <= la; i++) {
    final curr = List<int>.filled(lb + 1, 0);
    curr[0] = i;
    for (var j = 1; j <= lb; j++) {
      final costSub = prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      final costDel = prev[j] + 1;
      final costIns = curr[j - 1] + 1;
      curr[j] = [costSub, costDel, costIns].reduce((x, y) => x < y ? x : y);
    }
    prev = curr;
  }
  return prev[lb];
}

/// 伝票No照合における許容距離を、文字列長に応じて決める。
///
/// 短すぎる文字列で距離を大きく許容すると誤爆(全く別の伝票と一致してしまう)が
/// 増えるため、長さに応じて段階的に許容範囲を広げる(Python版と同一のロジック)。
int maxDistanceFor(int keyLength) {
  if (keyLength <= 4) return 0; // 短すぎる場合は完全一致のみ
  if (keyLength <= 8) return 1;
  return 2; // 通常の伝票No(例: "A2026030285" は11文字)は距離2まで許容
}

/// 0.0(完全不一致)〜1.0(完全一致)の類似度スコアを返す。
double similarityRatio(String a, String b) {
  final maxLen = a.length > b.length ? a.length : b.length;
  if (maxLen == 0) return 1.0;
  final dist = levenshteinDistance(a, b);
  final ratio = 1.0 - dist / maxLen;
  return ratio < 0.0 ? 0.0 : ratio;
}

/// 曖昧一致候補(伝票No, 距離)
class FuzzyMatchCandidate {
  final String candidate;
  final int distance;
  const FuzzyMatchCandidate(this.candidate, this.distance);
}

/// OCRで読み取った伝票Noに対し、キャッシュ内の伝票No群から曖昧一致候補を
/// 距離の近い順に返す。許容距離を超えるものは除外する。
List<FuzzyMatchCandidate> findFuzzyJobNumberMatches(
  String scannedNumber,
  List<String> candidateNumbers, {
  int maxResults = 3,
}) {
  final trimmed = scannedNumber.trim();
  if (trimmed.isEmpty) return [];

  final threshold = maxDistanceFor(trimmed.length);
  final scored = <FuzzyMatchCandidate>[];
  for (final rawCand in candidateNumbers) {
    final cand = rawCand.trim();
    if (cand.isEmpty) continue;
    final dist = levenshteinDistance(trimmed, cand);
    if (dist <= threshold) {
      scored.add(FuzzyMatchCandidate(cand, dist));
    }
  }
  scored.sort((x, y) => x.distance.compareTo(y.distance));
  if (scored.length > maxResults) {
    return scored.sublist(0, maxResults);
  }
  return scored;
}
