// GENERATED CODE - MANUALLY MAINTAINED HIVE ADAPTER
part of 'work_report.dart';

class WorkReportAdapter extends TypeAdapter<WorkReport> {
  @override
  final int typeId = 2;

  @override
  WorkReport read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return WorkReport(
      id: fields[0] as String,
      authorId: fields[1] as String,
      authorName: fields[2] as String,
      clientName: fields[3] as String,
      visitDate: fields[4] as DateTime,
      startTime: fields[5] as DateTime,
      endTime: fields[6] as DateTime,
      workContent: fields[7] as String,
      equipmentModel: fields[8] as String? ?? '',
      responseTypeIndex: fields[9] as int? ?? 0,
      partsUsed: (fields[10] as List?)?.cast<PartUsed>() ?? [],
      photoPaths: (fields[11] as List?)?.cast<String>() ?? [],
      notes: fields[12] as String? ?? '',
      successPoints: fields[13] as String? ?? '',
      issuesPoints: fields[14] as String? ?? '',
      tags: (fields[15] as List?)?.cast<String>() ?? [],
      proWanRefNumber: fields[16] as String? ?? '',
      storeSystemReportCopy: fields[17] as String? ?? '',
      createdAt: fields[18] as DateTime,
      updatedAt: fields[19] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, WorkReport obj) {
    writer
      ..writeByte(20)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.authorId)
      ..writeByte(2)
      ..write(obj.authorName)
      ..writeByte(3)
      ..write(obj.clientName)
      ..writeByte(4)
      ..write(obj.visitDate)
      ..writeByte(5)
      ..write(obj.startTime)
      ..writeByte(6)
      ..write(obj.endTime)
      ..writeByte(7)
      ..write(obj.workContent)
      ..writeByte(8)
      ..write(obj.equipmentModel)
      ..writeByte(9)
      ..write(obj.responseTypeIndex)
      ..writeByte(10)
      ..write(obj.partsUsed)
      ..writeByte(11)
      ..write(obj.photoPaths)
      ..writeByte(12)
      ..write(obj.notes)
      ..writeByte(13)
      ..write(obj.successPoints)
      ..writeByte(14)
      ..write(obj.issuesPoints)
      ..writeByte(15)
      ..write(obj.tags)
      ..writeByte(16)
      ..write(obj.proWanRefNumber)
      ..writeByte(17)
      ..write(obj.storeSystemReportCopy)
      ..writeByte(18)
      ..write(obj.createdAt)
      ..writeByte(19)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkReportAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
