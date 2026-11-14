import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attendee_mobile/features/proxy/models/proxy_attendance_model.dart';
import 'package:attendee_mobile/features/proxy/data/proxy_attendance_repository.dart';
import 'package:attendee_mobile/features/proxy/widgets/proxy_battery_warning_card.dart';
import 'package:attendee_mobile/features/proxy/widgets/proxy_carrying_badge.dart';
import 'package:attendee_mobile/features/proxy/widgets/proxy_host_request_dialog.dart';
import 'package:attendee_mobile/features/proxy/widgets/proxy_reclaim_banner.dart';

class MockProxyAttendanceRepository implements ProxyAttendanceRepository {
  final List<ProxyAttendanceSession> sessions = [];
  final List<ProxyEligibleFriend> eligibleFriends = [];
  bool submitCalled = false;
  bool respondCalled = false;
  bool revokeCalled = false;
  bool lastResponseAccept = false;

  @override
  Stream<List<ProxyAttendanceSession>> observeSessions(String eventId) {
    return Stream.value(sessions);
  }

  @override
  Future<ProxyAttendanceSession?> getActiveSessionForRequester(String eventId) async {
    final matches = sessions.where((s) => s.isActive && s.eventId == eventId);
    return matches.isNotEmpty ? matches.first : null;
  }

  @override
  Future<ProxyAttendanceSession?> getPendingSessionForRequester(String eventId) async {
    final matches = sessions.where((s) => s.isPending && s.eventId == eventId);
    return matches.isNotEmpty ? matches.first : null;
  }

  @override
  Future<List<ProxyAttendanceSession>> getActiveSessionsForHost(String eventId) async {
    return sessions.where((s) => s.isActive && s.eventId == eventId).toList();
  }

  @override
  Future<List<ProxyAttendanceSession>> getIncomingPendingRequests(String eventId) async {
    return sessions.where((s) => s.isPending && s.eventId == eventId).toList();
  }

  @override
  Future<List<ProxyEligibleFriend>> getEligibleFriends(String eventId) async {
    return eligibleFriends;
  }

  @override
  Future<ProxyAttendanceSession> submitRequest({
    required String eventId,
    required String hostUserId,
  }) async {
    submitCalled = true;
    final newSession = ProxyAttendanceSession(
      id: 'mock-session-1',
      eventId: eventId,
      requesterUserId: 'mock-user-1',
      hostUserId: hostUserId,
      status: ProxyStatus.pending,
      createdAt: DateTime.now().toUtc(),
    );
    sessions.add(newSession);
    return newSession;
  }

  @override
  Future<ProxyAttendanceSession> respondToRequest({
    required String sessionId,
    required bool accept,
  }) async {
    respondCalled = true;
    lastResponseAccept = accept;
    final idx = sessions.indexWhere((s) => s.id == sessionId);
    final current = idx >= 0
        ? sessions[idx]
        : ProxyAttendanceSession(
            id: sessionId,
            eventId: 'event-1',
            requesterUserId: 'req-1',
            hostUserId: 'host-1',
            status: ProxyStatus.pending,
            createdAt: DateTime.now().toUtc(),
          );
    final updated = current.copyWith(
      status: accept ? ProxyStatus.active : ProxyStatus.declined,
      acceptedAt: accept ? DateTime.now().toUtc() : null,
      revokedAt: !accept ? DateTime.now().toUtc() : null,
    );
    if (idx >= 0) sessions[idx] = updated;
    return updated;
  }

  @override
  Future<ProxyAttendanceSession> revokeSession({
    required String sessionId,
  }) async {
    revokeCalled = true;
    final idx = sessions.indexWhere((s) => s.id == sessionId);
    final current = idx >= 0
        ? sessions[idx]
        : ProxyAttendanceSession(
            id: sessionId,
            eventId: 'event-1',
            requesterUserId: 'req-1',
            hostUserId: 'host-1',
            status: ProxyStatus.active,
            createdAt: DateTime.now().toUtc(),
          );
    final updated = current.copyWith(
      status: ProxyStatus.revoked,
      revokedAt: DateTime.now().toUtc(),
    );
    if (idx >= 0) sessions[idx] = updated;
    return updated;
  }

  @override
  void dispose() {}
}

void main() {
  group('Proxy Attendance Model & Capacity Tests', () {
    test('ProxyStatus enum maps correctly', () {
      expect(ProxyStatus.fromString('pending'), ProxyStatus.pending);
      expect(ProxyStatus.fromString('active'), ProxyStatus.active);
      expect(ProxyStatus.fromString('revoked'), ProxyStatus.revoked);
      expect(ProxyStatus.fromString('declined'), ProxyStatus.declined);
      expect(ProxyStatus.fromString('expired'), ProxyStatus.expired);
      expect(ProxyStatus.fromString('UNKNOWN'), ProxyStatus.pending);
    });

    test('Host capacity cap enforces maximum of 2 active proxies', () {
      const friendAvailable = ProxyEligibleFriend(
        userId: 'f1',
        fullName: 'Alice Walker',
        avatarInitials: 'AW',
        isCheckedIn: true,
        activeCarriedCount: 1,
      );
      expect(friendAvailable.canAcceptMore, isTrue);

      const friendAtCapacity = ProxyEligibleFriend(
        userId: 'f2',
        fullName: 'Bob Martin',
        avatarInitials: 'BM',
        isCheckedIn: true,
        activeCarriedCount: 2,
      );
      expect(friendAtCapacity.canAcceptMore, isFalse);
    });
  });

  group('Proxy Attendance Widget Tests', () {
    testWidgets('ProxyBatteryWarningCard renders low battery percentage and triggers delegation',
        (tester) async {
      bool delegateTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProxyBatteryWarningCard(
              batteryLevel: 12,
              onDelegatePressed: () {
                delegateTapped = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('Low Battery Warning (12%)'), findsOneWidget);
      expect(find.text('Delegate Attendance'), findsOneWidget);

      await tester.tap(find.text('Delegate Attendance'));
      await tester.pump();
      expect(delegateTapped, isTrue);
    });

    testWidgets('ProxyHostRequestDialog renders requester details and processes acceptance',
        (tester) async {
      final repo = MockProxyAttendanceRepository();
      final session = ProxyAttendanceSession(
        id: 'session-xyz',
        eventId: 'event-100',
        requesterUserId: 'user-req-1',
        hostUserId: 'user-host-1',
        requesterName: 'Charlie Brown',
        status: ProxyStatus.pending,
        createdAt: DateTime.now().toUtc(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProxyHostRequestDialog(
              session: session,
              repository: repo,
            ),
          ),
        ),
      );

      expect(find.text('Proxy Attendance Request'), findsOneWidget);
      expect(find.textContaining('Charlie Brown\'s phone battery is discharging'), findsOneWidget);
      expect(find.text('Accept Delegation'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);

      await tester.tap(find.text('Accept Delegation'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(repo.respondCalled, isTrue);
      expect(repo.lastResponseAccept, isTrue);
    });

    testWidgets('ProxyCarryingBadge displays carried proxies count and allows release',
        (tester) async {
      final repo = MockProxyAttendanceRepository();
      final session = ProxyAttendanceSession(
        id: 'sess-1',
        eventId: 'event-1',
        requesterUserId: 'user-a',
        hostUserId: 'user-b',
        requesterName: 'Diana Prince',
        status: ProxyStatus.active,
        createdAt: DateTime.now().toUtc(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProxyCarryingBadge(
              activeSessions: [session],
              repository: repo,
            ),
          ),
        ),
      );

      expect(find.text('Carrying Proxy Presence'), findsOneWidget);
      expect(find.text('+1'), findsOneWidget);
      expect(find.textContaining('Diana Prince'), findsOneWidget);

      // Open management sheet
      await tester.tap(find.text('Manage'));
      await tester.pumpAndSettle();

      expect(find.text('Active Proxy Delegations'), findsOneWidget);
      expect(find.text('Release Proxy'), findsOneWidget);

      await tester.tap(find.text('Release Proxy'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(repo.revokeCalled, isTrue);
    });

    testWidgets('ProxyReclaimBanner displays host name and reclaims attendance',
        (tester) async {
      final repo = MockProxyAttendanceRepository();
      final session = ProxyAttendanceSession(
        id: 'sess-2',
        eventId: 'event-1',
        requesterUserId: 'user-me',
        hostUserId: 'user-host',
        hostName: 'Clark Kent',
        status: ProxyStatus.active,
        createdAt: DateTime.now().toUtc(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProxyReclaimBanner(
              activeSession: session,
              repository: repo,
            ),
          ),
        ),
      );

      expect(find.text('Attendance Delegated'), findsOneWidget);
      expect(find.text('Carried by Clark Kent'), findsOneWidget);
      expect(find.text('Reclaim My Attendance'), findsOneWidget);

      await tester.tap(find.text('Reclaim My Attendance'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(repo.revokeCalled, isTrue);
    });
  });
}
