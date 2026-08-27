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

/// 【不具合修正・2026-08-27】
/// 伝票No同士の距離だけで曖昧一致を判定すると、番号が近いだけの
/// 「全く無関係な別案件」(例: 同時期に連番で採番された別店舗の案件)を
/// 誤って候補提示してしまう不具合が本番で発見された。
/// (実例: スキャン「R2026080980」(ラッキー栗山店)に対し、
///  「R2026080982」(ラッキー星置駅前)を提案してしまっていた)
///
/// AI-OCRはスキャン時に伝票Noと同時に店名も読み取っているため、
/// 店名の一致度も加味することで、無関係な案件を除外する。
/// 店名情報がどちらか一方でも空の場合は、判定材料がないため
/// 従来通り番号の距離のみで判定する(除外しない)。
///
/// 【類似度比率ではなく距離ベースを採用した理由】
/// チェーン店名(例:「ラッキー」「東光ストア」)が共通する別店舗同士は、
/// 類似度比率(0〜1)で見ると共通接頭辞の影響で意外と高い値
/// (例:「ラッキー栗山店」vs「ラッキー星置駅前」で0.50)になってしまい、
/// 閾値調整が難しい。一方、生のレーベンシュタイン距離で見ると、
/// 同一店舗(表記ゆれのみ)は距離0〜1に収まるのに対し、別店舗は
/// 実データ上ほぼ確実に距離2以上になるため、閾値を明確に設定できる。
bool isStoreNameCompatible({
  required String scannedStoreName,
  required String candidateStoreName,
}) {
  final a = _normalizeStoreName(scannedStoreName);
  final b = _normalizeStoreName(candidateStoreName);
  if (a.isEmpty || b.isEmpty) return true; // 判定材料なし→除外しない
  if (a == b) return true;
  // 表記ゆれ(全角半角スペース・OCR誤読1文字程度)は許容するが、
  // それを超える違いは別店舗とみなして除外する。
  return levenshteinDistance(a, b) <= 1;
}

/// 店名比較用の正規化(前後・内部の全角/半角スペース除去)。
String _normalizeStoreName(String s) {
  return s.trim().replaceAll(RegExp(r'[\s\u3000]'), '');
}
