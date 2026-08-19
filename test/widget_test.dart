import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/work_report.dart';
import 'package:flutter_app/models/part_used.dart';
import 'package:flutter_app/models/store_system_report.dart';
import 'package:flutter_app/models/user.dart';

void main() {
  group('ResponseType', () {
    test('label returns correct Japanese text', () {
      expect(ResponseType.regularInspection.label, '定期点検');
      expect(ResponseType.breakdown.label, '故障対応');
      expect(ResponseType.repair.label, '修理');
    });

    test('value/fromValue round trip works', () {
      for (final type in ResponseType.values) {
        final restored = ResponseTypeLabel.fromValue(type.value);
        expect(restored, type);
      }
    });
  });

  group('WorkReport', () {
    test('toMap/fromMap round trip preserves data', () {
      final now = DateTime.now();
      final report = WorkReport(
        id: 'test-id',
        authorId: 'user-1',
        authorName: 'テスト太郎',
        coWorkerIds: const ['user-2', 'user-3'],
        clientName: 'テスト商店',
        visitDate: now,
        startTime: now,
        endTime: now.add(const Duration(hours: 1)),
        workContent: '定期点検を実施',
        equipmentModel: 'ABC-123',
        responseType: ResponseType.regularInspection,
        partsUsed: [PartUsed(name: 'フィルター', quantity: 1, note: '')],
        photoPaths: const [],
        notes: '特になし',
        successPoints: '早期発見できた',
        issuesPoints: '',
        tags: const ['冷蔵庫'],
        proWanRefNumber: 'PW-001',
        storeSystemReportCopy: StoreSystemReport(receiptNumber: 'R-001'),
        createdAt: now,
        updatedAt: now,
      );

      final map = report.toMap();
      final restored = WorkReport.fromMap(report.id, map);

      expect(restored.clientName, report.clientName);
      expect(restored.responseType, report.responseType);
      expect(restored.partsUsed.first.name, 'フィルター');
      expect(restored.tags, contains('冷蔵庫'));
      expect(restored.storeSystemReportCopy.receiptNumber, 'R-001');
      expect(restored.coWorkerIds, ['user-2', 'user-3']);
    });
  });

  group('AppUser', () {
    test('isAdmin reflects role correctly', () {
      final admin = AppUser(
        id: 'u1',
        name: '管理者',
        employeeCode: 'E001',
        role: UserRole.admin,
        department: '総務',
        createdAt: DateTime.now(),
      );
      final staff = AppUser(
        id: 'u2',
        name: 'スタッフ',
        employeeCode: 'E002',
        role: UserRole.staff,
        department: '現場',
        createdAt: DateTime.now(),
      );

      expect(admin.isAdmin, true);
      expect(staff.isAdmin, false);
    });
  });
}
