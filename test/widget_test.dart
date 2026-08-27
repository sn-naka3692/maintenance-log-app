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
        lastEditedByAdminId: 'admin-1',
        lastEditedByAdminName: '管理者花子',
        lastEditedByAdminAt: now,
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
      expect(restored.lastEditedByAdminId, 'admin-1');
      expect(restored.lastEditedByAdminName, '管理者花子');
      expect(restored.lastEditedByAdminAt, isNotNull);
    });

    test(
      '代筆編集記録(lastEditedByAdmin*)が未設定でもnullのまま復元される',
      () {
        final now = DateTime.now();
        final report = WorkReport(
          id: 'test-id-2',
          authorId: 'user-1',
          authorName: 'テスト太郎',
          clientName: 'テスト商店',
          visitDate: now,
          startTime: now,
          endTime: now.add(const Duration(hours: 1)),
          workContent: '定期点検を実施',
          createdAt: now,
          updatedAt: now,
        );

        final restored = WorkReport.fromMap(report.id, report.toMap());

        expect(restored.lastEditedByAdminId, isNull);
        expect(restored.lastEditedByAdminName, isNull);
        expect(restored.lastEditedByAdminAt, isNull);
      },
    );
  });

  group('WorkReport.hasRefrigerantFilling', () {
    WorkReport buildReport({
      StoreSystemReport? storeSystemReportCopy,
      String nonSeRefrigerantType = '',
      String nonSeRefrigerantAmountKg = '',
    }) {
      final now = DateTime.now();
      return WorkReport(
        id: 'r',
        authorId: 'u',
        authorName: 'テスト',
        clientName: '顧客',
        visitDate: now,
        startTime: now,
        endTime: now,
        workContent: '',
        storeSystemReportCopy: storeSystemReportCopy,
        nonSeRefrigerantType: nonSeRefrigerantType,
        nonSeRefrigerantAmountKg: nonSeRefrigerantAmountKg,
        createdAt: now,
        updatedAt: now,
      );
    }

    test('false when both SE and non-SE fields are empty', () {
      expect(buildReport().hasRefrigerantFilling, false);
    });

    test('false when non-SE fields are "なし"/"0" (not-filled convention)', () {
      final r = buildReport(
        nonSeRefrigerantType: 'なし',
        nonSeRefrigerantAmountKg: '0',
      );
      expect(r.hasRefrigerantFilling, false);
    });

    test('true when non-SE fields indicate actual filling', () {
      final r = buildReport(
        nonSeRefrigerantType: 'R410A',
        nonSeRefrigerantAmountKg: '1.2',
      );
      expect(r.hasRefrigerantFilling, true);
    });

    test('true when SE store refrigerant fields are filled', () {
      final r = buildReport(
        storeSystemReportCopy: StoreSystemReport(
          refrigerantType: 'R32',
          refrigerantAmount: '0.8',
        ),
      );
      expect(r.hasRefrigerantFilling, true);
    });

    test('false when SE store refrigerant fields are empty', () {
      final r = buildReport(
        storeSystemReportCopy: StoreSystemReport(receiptNumber: 'R-1'),
      );
      expect(r.hasRefrigerantFilling, false);
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
