import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attendee_mobile/design_system/components/spatially_crowd_indicator.dart';
import 'package:attendee_mobile/features/home/widgets/home_current_zone_card.dart';
import 'package:attendee_mobile/features/home/widgets/home_mini_map.dart';
import 'package:attendee_mobile/features/map/data/attendee_location_repository.dart';
import 'package:attendee_mobile/features/map/models/attendee_location_models.dart';
import 'package:attendee_mobile/features/map/models/venue_map_models.dart';
import 'package:attendee_mobile/features/map/widgets/map_zone_sheet.dart';

class MockAttendeeLocationRepository implements AttendeeLocationRepository {
  final StreamController<AttendeeLocationState> _controller =
      StreamController<AttendeeLocationState>.broadcast();

  AttendeeLocationState currentState;

  MockAttendeeLocationRepository({AttendeeLocationState? initialState})
      : currentState = initialState ?? AttendeeLocationState.unknown();

  @override
  Stream<AttendeeLocationState> watchLocation(String eventId) {
    Future.microtask(() => _controller.add(currentState));
    return _controller.stream;
  }

  @override
  Future<AttendeeLocationState> getLocation(String eventId) async => currentState;

  void emit(AttendeeLocationState state) {
    currentState = state;
    _controller.add(state);
  }

  @override
  Future<void> setManualZone(
    String eventId,
    String zoneId, {
    String? zoneName,
    String? zoneCode,
    String? levelId,
    String? levelName,
    int? floorLevel,
  }) async {
    currentState = AttendeeLocationState(
      status: AttendeeLocationStatus.manual,
      zoneId: zoneId,
      zoneCode: zoneCode ?? 'Z-$zoneId',
      zoneName: zoneName ?? 'Manual Zone $zoneId',
      levelId: levelId,
      levelName: levelName ?? 'Floor 1',
      floorLevel: floorLevel ?? 1,
      lastSeen: DateTime.now(),
    );
    _controller.add(currentState);
  }

  @override
  Future<void> clearManualZone(String eventId) async {
    currentState = AttendeeLocationState.unknown();
    _controller.add(currentState);
  }

  @override
  void dispose() {
    _controller.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AttendeeLocationState Model Tests', () {
    test('State properties and getters evaluate correctly for detected zone', () {
      final now = DateTime.now();
      final state = AttendeeLocationState(
        status: AttendeeLocationStatus.detected,
        zoneId: 'zone-101',
        zoneCode: '101',
        zoneName: 'Robotics Arena',
        levelId: 'lvl-1',
        levelName: 'Level 1',
        floorLevel: 1,
        activeHeadcount: 42,
        crowdLevel: SpatiallyCrowdLevel.low,
        lastSeen: now.subtract(const Duration(seconds: 25)),
      );

      expect(state.hasLocation, isTrue);
      expect(state.isAutoDetected, isTrue);
      expect(state.isManual, isFalse);
      expect(state.isStale, isFalse);
      expect(state.relativeFreshness, equals('Just now'));
    });

    test('Stale detection state evaluates correctly', () {
      final state = AttendeeLocationState(
        status: AttendeeLocationStatus.stale,
        zoneId: 'zone-101',
        zoneName: 'Main Stage',
        lastSeen: DateTime.now().subtract(const Duration(minutes: 4)),
      );

      expect(state.hasLocation, isTrue);
      expect(state.isAutoDetected, isTrue);
      expect(state.isStale, isTrue);
      expect(state.relativeFreshness, equals('4m ago'));
    });

    test('Manual pin state evaluates correctly', () {
      final state = AttendeeLocationState(
        status: AttendeeLocationStatus.manual,
        zoneId: 'zone-202',
        zoneName: 'Workshop Hall',
      );

      expect(state.hasLocation, isTrue);
      expect(state.isAutoDetected, isFalse);
      expect(state.isManual, isTrue);
      expect(state.relativeFreshness, equals('Manually selected'));
    });

    test('JSON serialization round-trip preserves state', () {
      final original = AttendeeLocationState(
        status: AttendeeLocationStatus.detected,
        zoneId: 'z-uuid-777',
        zoneCode: 'A1',
        zoneName: 'Keynote Hall',
        levelId: 'lvl-0',
        levelName: 'Ground Floor',
        floorLevel: 0,
        activeHeadcount: 150,
        crowdLevel: SpatiallyCrowdLevel.busy,
        lastSeen: DateTime.utc(2026, 11, 14, 12, 0, 0),
        rssi: -65,
      );

      final json = original.toJson();
      final revived = AttendeeLocationState.fromJson(json);

      expect(revived.status, equals(original.status));
      expect(revived.zoneId, equals(original.zoneId));
      expect(revived.zoneName, equals(original.zoneName));
      expect(revived.activeHeadcount, equals(original.activeHeadcount));
      expect(revived.crowdLevel, equals(original.crowdLevel));
      expect(revived.rssi, equals(-65));
    });
  });

  group('HomeCurrentZoneCard Widget Tests', () {
    testWidgets('renders active detected zone, level, and crowd indicator', (tester) async {
      final state = AttendeeLocationState(
        status: AttendeeLocationStatus.detected,
        zoneId: 'zone-1',
        zoneCode: 'Z1',
        zoneName: 'Robotics Arena',
        levelName: 'Level 1',
        floorLevel: 1,
        activeHeadcount: 55,
        crowdLevel: SpatiallyCrowdLevel.moderate,
        lastSeen: DateTime.now().subtract(const Duration(seconds: 40)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeCurrentZoneCard(
              locationState: state,
            ),
          ),
        ),
      );

      expect(find.text('CURRENT LOCATION'), findsOneWidget);
      expect(find.text('Robotics Arena'), findsOneWidget);
      expect(find.text('Level 1'), findsOneWidget);
      expect(find.text('· 55 people'), findsOneWidget);
      expect(find.text('Moderate Crowd'), findsOneWidget);
      expect(find.text('40s ago'), findsOneWidget);
      expect(find.text('View on Map'), findsOneWidget);
    });

    testWidgets('renders locating state when scanning', (tester) async {
      final state = AttendeeLocationState.locating();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeCurrentZoneCard(
              locationState: state,
            ),
          ),
        ),
      );

      expect(find.text('Locating your zone…'), findsOneWidget);
      expect(find.text('SCANNING'), findsOneWidget);
    });

    testWidgets('triggers callbacks for View on Map and Select Zone', (tester) async {
      bool mapTapped = false;
      bool changeTapped = false;

      final state = AttendeeLocationState(
        status: AttendeeLocationStatus.detected,
        zoneId: 'z-1',
        zoneName: 'Design Lab',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeCurrentZoneCard(
              locationState: state,
              onViewOnMap: () => mapTapped = true,
              onChangeZone: () => changeTapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('View on Map'));
      expect(mapTapped, isTrue);

      await tester.tap(find.text('Select Zone'));
      expect(changeTapped, isTrue);
    });
  });

  group('HomeMiniMap Active Zone Integration Tests', () {
    testWidgets('renders "You\'re in <Zone>" badge when activeZone is provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HomeMiniMap(
              activeZone: 'Robotics Arena',
            ),
          ),
        ),
      );

      expect(find.text('Robotics Arena'), findsOneWidget);
      expect(find.text("You're in Robotics Arena"), findsOneWidget);
    });
  });

  group('MapZoneSheet Location Pinning Tests', () {
    testWidgets('renders "Set as my location" button and triggers callback', (tester) async {
      bool setLocationCalled = false;

      const zone = MapZone(
        id: 'zone-abc',
        roomNumber: '101',
        name: 'Main Auditorium',
        purpose: 'Keynote sessions',
        bounds: MapBounds(left: 0.1, top: 0.1, width: 0.3, height: 0.3),
        entrancePoint: MapPoint(0.2, 0.2),
        crowdLevel: SpatiallyCrowdLevel.low,
        crowdFreshness: SpatialCrowdFreshness.live,
        capacity: 200,
        poiIds: [],
        operatingCapacity: 200,
        warningThreshold: 150,
        criticalThreshold: 180,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapZoneSheet(
              zone: zone,
              allPois: const [],
              isCurrentZone: false,
              onSetCurrentZone: () => setLocationCalled = true,
              onNavigate: () {},
              onClose: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.pin_drop_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.pin_drop_outlined));
      expect(setLocationCalled, isTrue);
    });
  });
}

