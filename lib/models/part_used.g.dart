// GENERATED CODE - MANUALLY MAINTAINED HIVE ADAPTER
part of 'part_used.dart';

class PartUsedAdapter extends TypeAdapter<PartUsed> {
  @override
  final int typeId = 1;

  @override
  PartUsed read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PartUsed(
      name: fields[0] as String,
      quantity: fields[1] as int,
      note: fields[2] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, PartUsed obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.quantity)
      ..writeByte(2)
      ..write(obj.note);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PartUsedAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
