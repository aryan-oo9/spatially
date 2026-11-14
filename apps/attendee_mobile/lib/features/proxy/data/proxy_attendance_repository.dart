import 'dart:async';
import '../models/proxy_attendance_model.dart';

/// Abstract contract for managing reciprocal Proxy Attendance sessions.
abstract class ProxyAttendanceRepository {
  /// Stream of all active, pending, and recent proxy sessions involving the current user.
  Stream<List<ProxyAttendanceSession>> observeSessions(String eventId);

  /// Gets the currently active proxy session where the current user is the requester (their phone is carried by someone else).
  Future<ProxyAttendanceSession?> getActiveSessionForRequester(String eventId);

  /// Gets any pending proxy session sent by the current user awaiting host acceptance.
  Future<ProxyAttendanceSession?> getPendingSessionForRequester(String eventId);

  /// Gets all active proxy sessions where the current user is acting as the Host carrier.
  Future<List<ProxyAttendanceSession>> getActiveSessionsForHost(String eventId);

  /// Gets incoming pending proxy requests addressed to the current user as Host.
  Future<List<ProxyAttendanceSession>> getIncomingPendingRequests(String eventId);

  /// Fetches accepted friends who hold a checked-in ticket for this event and can serve as Host.
  Future<List<ProxyEligibleFriend>> getEligibleFriends(String eventId);

  /// Dispatches an asynchronous proxy attendance request from the current user to [hostUserId].
  Future<ProxyAttendanceSession> submitRequest({
    required String eventId,
    required String hostUserId,
  });

  /// Host responds to an incoming proxy attendance request ([accept] = true or false).
  Future<ProxyAttendanceSession> respondToRequest({
    required String sessionId,
    required bool accept,
  });

  /// Bilaterally revokes an active or pending proxy attendance session (can be called by Host or Requester).
  Future<ProxyAttendanceSession> revokeSession({
    required String sessionId,
  });

  /// Releases resources and unregisters Realtime subscriptions.
  void dispose();
}
