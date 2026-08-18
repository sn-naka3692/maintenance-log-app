import 'package:hive/hive.dart';
import 'part_used.dart';

part 'work_report.g.dart';

/// 対応区分
enum ResponseType {
  regularInspection, // 定期点検
  breakdown, // 故障対応
  repair, // 修理
  installation, // 新設・設置
  other, // その他
}

extension ResponseTypeLabel on ResponseType {
  String get label {
    switch (this) {
      case ResponseType.regularInspection:
        return '定期点検';
      case ResponseType.breakdown:
        return '故障対応';
      case ResponseType.repair:
        return '修理';
      case ResponseType.installation:
        return '新設・設置';
      case ResponseType.other:
        return 'その他';
    }
  }
}

@HiveType(typeId: 2)
class WorkReport extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String authorId;

  @HiveField(2)
  String authorName;

  @HiveField(3)
  String clientName; // 訪問先(顧客名)

  @HiveField(4)
  DateTime visitDate; // 訪問日

  @HiveField(5)
  DateTime startTime; // 作業開始時刻

  @HiveField(6)
  DateTime endTime; // 作業終了時刻

  @HiveField(7)
  String workContent; // 作業内容

  @HiveField(8)
  String equipmentModel; // 機器型番(プロワン参照用)

  @HiveField(9)
  int responseTypeIndex; // 対応区分

  @HiveField(10)
  List<PartUsed> partsUsed; // 使用部品

  @HiveField(11)
  List<String> photoPaths; // 写真パス(ローカル)

  @HiveField(12)
  String notes; // 備考

  @HiveField(13)
  String successPoints; // うまくいったこと(ナレッジ共有)

  @HiveField(14)
  String issuesPoints; // 課題・失敗・改善点(ナレッジ共有)

  @HiveField(15)
  List<String> tags; // タグ(症状/機種/対応区分など自由入力)

  @HiveField(16)
  String proWanRefNumber; // プロワン管理番号(参照用・将来API連携)

  @HiveField(17)
  String storeSystemReportCopy; // コンビニ側システム入力内容の控え(社内保存用)

  @HiveField(18)
  DateTime createdAt;

  @HiveField(19)
  DateTime updatedAt;

  WorkReport({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.clientName,
    required this.visitDate,
    required this.startTime,
    required this.endTime,
    required this.workContent,
    this.equipmentModel = '',
    this.responseTypeIndex = 0,
    List<PartUsed>? partsUsed,
    List<String>? photoPaths,
    this.notes = '',
    this.successPoints = '',
    this.issuesPoints = '',
    List<String>? tags,
    this.proWanRefNumber = '',
    this.storeSystemReportCopy = '',
    required this.createdAt,
    required this.updatedAt,
  }) : partsUsed = partsUsed ?? [],
       photoPaths = photoPaths ?? [],
       tags = tags ?? [];

  ResponseType get responseType => ResponseType.values[responseTypeIndex];

  Duration get workDuration => endTime.difference(startTime);

  bool get hasIssues => issuesPoints.trim().isNotEmpty;
  bool get hasSuccess => successPoints.trim().isNotEmpty;
}
