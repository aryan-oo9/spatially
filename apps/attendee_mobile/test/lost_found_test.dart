import 'package:flutter_test/flutter_test.dart';
import 'package:attendee_mobile/features/safety/models/safety_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Lost & Found Unit Tests', () {
    test('LostFoundReport properties evaluate correctly', () {
      final report = LostFoundReport(
        id: 'test-1',
        eventId: 'c3f2d83f-60d4-427a-be3b-4351c02c526e',
        type: LostFoundType.found,
        category: LostFoundCategory.electronics,
        title: 'MacBook Charger',
        description: 'White USB-C 67W charger left on table',
        venueZoneId: 'zone-101',
        venueZoneName: 'Auditorium Hall',
        specificLocation: 'Row 4 Seat B',
        status: LostFoundStatus.submitted,
        createdAt: DateTime(2026, 11, 14, 10, 30),
        isCurrentUser: true,
      );

      expect(report.id, equals('test-1'));
      expect(report.type, equals(LostFoundType.found));
      expect(report.category, equals(LostFoundCategory.electronics));
      expect(report.title, equals('MacBook Charger'));
      expect(report.isCurrentUser, isTrue);
      expect(report.status, equals(LostFoundStatus.submitted));
    });

    test('LostFoundReport copyWith preserves or updates values correctly', () {
      final original = LostFoundReport(
        id: 'test-2',
        eventId: 'c3f2d83f-60d4-427a-be3b-4351c02c526e',
        type: LostFoundType.lost,
        category: LostFoundCategory.keys,
        title: 'Car Key Fob',
        description: 'Honda key with blue lanyard',
        venueZoneId: '712',
        venueZoneName: 'Foyer',
        status: LostFoundStatus.pendingSync,
        createdAt: DateTime(2026, 11, 14, 12, 0),
        isCurrentUser: false,
      );

      final updated = original.copyWith(
        id: 'synced-id-123',
        status: LostFoundStatus.resolved,
      );

      expect(updated.id, equals('synced-id-123'));
      expect(updated.status, equals(LostFoundStatus.resolved));
      expect(updated.title, equals('Car Key Fob'));
      expect(updated.type, equals(LostFoundType.lost));
    });

    test('Filtering reports by type and currentUser works properly', () {
      final list = [
        LostFoundReport(
          id: '1',
          eventId: 'e1',
          type: LostFoundType.lost,
          category: LostFoundCategory.bag,
          title: 'Backpack',
          description: '',
          venueZoneId: 'z1',
          venueZoneName: 'Lobby',
          status: LostFoundStatus.submitted,
          createdAt: DateTime.now(),
          isCurrentUser: true,
        ),
        LostFoundReport(
          id: '2',
          eventId: 'e1',
          type: LostFoundType.found,
          category: LostFoundCategory.phone,
          title: 'iPhone 15',
          description: '',
          venueZoneId: 'z2',
          venueZoneName: 'Stage',
          status: LostFoundStatus.submitted,
          createdAt: DateTime.now(),
          isCurrentUser: false,
        ),
        LostFoundReport(
          id: '3',
          eventId: 'e1',
          type: LostFoundType.found,
          category: LostFoundCategory.idCard,
          title: 'Campus ID',
          description: '',
          venueZoneId: 'z1',
          venueZoneName: 'Lobby',
          status: LostFoundStatus.submitted,
          createdAt: DateTime.now(),
          isCurrentUser: true,
        ),
      ];

      final lostOnly = list.where((r) => r.type == LostFoundType.lost).toList();
      expect(lostOnly.length, equals(1));
      expect(lostOnly.first.id, equals('1'));

      final foundOnly = list.where((r) => r.type == LostFoundType.found).toList();
      expect(foundOnly.length, equals(2));

      final myReports = list.where((r) => r.isCurrentUser).toList();
      expect(myReports.length, equals(2));
      expect(myReports.map((r) => r.id), containsAll(['1', '3']));
    });
  });
}
