/// 冷媒種類マスタ(管理者が「その他」入力から正式追加した冷媒種類)。
///
/// 【設計方針・2026-09追加】RefrigerantTypeOptions(work_report.dart内の
/// 静的リスト)は事務側提供データを反映した固定リストだが、現場で今後
/// リストに無い新しい冷媒が使われる可能性があるため、「その他」を選ぶと
/// 自由入力できる逃げ道を用意していた。ユーザーからの追加要望
/// (「追加できるルートがあると便利」)を受け、管理者がダッシュボードから
/// 新しい冷媒種類を正式にマスタへ昇格登録できる仕組みを追加する
/// (ユーザー承認: 「管理者側でのマスタ昇格ルートでOK」)。
///
/// 【想定運用】現場が「その他」で入力した冷媒名の頻度が増えてきたら、
/// 管理者がこのマスタへ追加する。追加後は全端末のドロップダウンに
/// 即座に反映される(静的リスト+このコレクションの内容をマージして表示)。
class RefrigerantTypeEntry {
  String id;
  String name; // 冷媒名(例: "R290")
  String addedByName; // 追加した管理者の氏名(表示用・監査用)
  DateTime createdAt;

  RefrigerantTypeEntry({
    required this.id,
    required this.name,
    this.addedByName = '',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {'name': name, 'added_by_name': addedByName, 'created_at': createdAt};
  }

  factory RefrigerantTypeEntry.fromMap(String id, Map<String, dynamic> map) {
    return RefrigerantTypeEntry(
      id: id,
      name: map['name'] as String? ?? '',
      addedByName: map['added_by_name'] as String? ?? '',
      createdAt: _parseDate(map['created_at']),
    );
  }

  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    try {
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {
      return DateTime.now();
    }
  }
}
