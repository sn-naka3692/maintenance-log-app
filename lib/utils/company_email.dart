/// 【社員メール誤字チェック・v1.2.63】社員メールアドレスの入力ミスを防ぐ。
/// 許可ドメインは @sapporo-nakano.com。よくある綴りミス(例: sappporo)は
/// 編集距離2以内なら自動補正し、それでもダメな場合は null を返して呼び出し元に
/// エラー表示させる。
const String kCompanyEmailDomain = 'sapporo-nakano.com';

int _lev(String a, String b) {
  final m = a.length, n = b.length;
  final dp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
  for (var i = 0; i <= m; i++) {
    dp[i][0] = i;
  }
  for (var j = 0; j <= n; j++) {
    dp[0][j] = j;
  }
  for (var i = 1; i <= m; i++) {
    for (var j = 1; j <= n; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var v = dp[i - 1][j] + 1;
      if (dp[i][j - 1] + 1 < v) v = dp[i][j - 1] + 1;
      if (dp[i - 1][j - 1] + cost < v) v = dp[i - 1][j - 1] + cost;
      dp[i][j] = v;
    }
  }
  return dp[m][n];
}

/// 整形済みメールアドレスを返す。形式不正・ドメイン不備なら null。
String? normalizeCompanyEmail(String raw) {
  final email = raw.trim().toLowerCase();
  final at = email.indexOf('@');
  if (at <= 0 || email.contains(' ') || email.indexOf('@', at + 1) >= 0) {
    return null;
  }
  final local = email.substring(0, at);
  final domain = email.substring(at + 1);
  if (domain == kCompanyEmailDomain) return email;
  if (_lev(domain, kCompanyEmailDomain) <= 2) {
    return '$local@$kCompanyEmailDomain';
  }
  return null;
}
