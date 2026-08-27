/// AI-OCR(Azure Document Intelligence)が抽出した日付テキストを
/// DateTimeへ変換する共通ユーティリティ。
///
/// 【背景・共通化の経緯・2026-08-28】
/// 元々は report_edit_screen.dart の _tryParseDate() にのみ実装されていたが、
/// 月末チェック機能(submission_check_screen.dart)でも同じ形式の
/// WorkStartDateをパースして日報のvisitDateと突合する必要が生じたため、
/// 共通ユーティリティとして切り出した。
///
/// プロワン用Azureカスタムモデル(prowan-report-v1)がWorkStartDateとして
/// 実際に返す値は、報告書上の印字表記そのままの"2026 08/26"
/// (年と月の間は半角スペース、月日間はスラッシュ)という形式である。
/// 年と月の間の区切りは空白・スラッシュ・ハイフンいずれも許容する。
library;

DateTime? tryParseScanDate(String text) {
  final cleaned = text
      .trim()
      .replaceAll('年', '/')
      .replaceAll('月', '/')
      .replaceAll('日', '');
  final match = RegExp(
    r'(\d{4})[\s/\-]+(\d{1,2})[/\-](\d{1,2})',
  ).firstMatch(cleaned);
  if (match == null) return null;
  try {
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  } catch (_) {
    return null;
  }
}

/// 2つの日付が「同じ日」かどうか(時刻は無視して年月日のみ比較)。
bool isSameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
