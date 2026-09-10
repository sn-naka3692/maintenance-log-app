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
///
/// 【不具合対応・2026-09-10】3回目モデル再学習後のregression_test.py
/// 実測(全36件中11件の失敗を分析)で、WorkStartDateの推論結果には
/// 以下2パターンの「日付以外の文字列混入」が一定確率で発生することが
/// 判明した:
///   (a) 時刻混入: "2026 08/26 08:30"(作業開始時刻が後ろに続く)
///   (b) 複数日付混入: "2026 08/18 2026 08/27 21:00"
///       (訪問日印字欄が複数行ある報告書で、最終行=最新日程の座標を
///       返すべきところ、モデルが前の行も含めて広く座標を取ってしまう)
/// 実測11件のうち9件がこのパターンで、いずれも「テキスト中に出現する
/// 日付候補のうち最後(一番後ろ)のものが正解」という共通性があった
/// (regression報告書 20260910_084955_standalone.json で検証済み)。
/// 従来は先頭候補(firstMatch)を採用していたため、(b)のようなケースで
/// 誤った(古い)日付を自動反映してしまうリスクがあった。
/// AIモデル側の追加学習で座標予測自体を完全に直すよりも、テキスト側で
/// 「最後の日付候補を採用する」後処理を行う方が即効性・確実性が高いと
/// 判断し、firstMatch から「マッチ全件のうち最後の1件」を採用する方式に
/// 変更した(全36件のground truthで再検証し、既存の一致ケースを壊さない
/// ことを確認済み:firstMatch方式33/36 -> lastMatch方式34/36)。
/// なお、座標予測自体が全く別の日付を指してしまう残り2件(regression
/// report上のprowan_page31/32)は、テキスト後処理では原理的に対応できない
/// ため、次回のモデル再学習(教師データ拡充)で対応する。
library;

DateTime? tryParseScanDate(String text) {
  final cleaned = text
      .trim()
      .replaceAll('年', '/')
      .replaceAll('月', '/')
      .replaceAll('日', '');
  final matches = RegExp(
    r'(\d{4})[\s/\-]+(\d{1,2})[/\-](\d{1,2})',
  ).allMatches(cleaned).toList();
  if (matches.isEmpty) return null;
  final match = matches.last;
  try {
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime(year, month, day);
    // 【不具合防止・2026-08-28】DartのDateTimeコンストラクタは、
    // 2/30のような実在しない日付を例外を出さずに3/2へ自動繰り上げ
    // (ロールオーバー)してしまう。OCRの誤読で実在しない日付が来た場合に
    // 静かに別の日付として扱われると、月末チェックの日付一致判定
    // (isSameCalendarDay)が意図しない挙動になるため、生成結果の
    // year/month/dayが入力値と完全一致するか検証し、ズレていれば
    // 「パース失敗」として null を返す。
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    return parsed;
  } catch (_) {
    return null;
  }
}

/// 2つの日付が「同じ日」かどうか(時刻は無視して年月日のみ比較)。
bool isSameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
