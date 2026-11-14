import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/app_notification_service.dart';
import '../../../services/auth_service.dart';
import '../../notifications/models/notification_models.dart';
import '../models/proxy_attendance_model.dart';
import 'proxy_attendance_repository.dart';

/// Production Supabase implementation of [ProxyAttendanceRepository].
class SupabaseProxyAttendanceRepositoryImpl implements ProxyAttendanceRepository {
  final SupabaseClient _supabase;
  final AuthService _authService;

  final StreamController<List<ProxyAttendanceSession>> _sessionsController =
      StreamController<List<ProxyAttendanceSession>>.broadcast();

  RealtimeChannel? _realtimeChannel;
  String? _subscribedEventId;
  String? _subscribedUserId;

  // In-memory cache for fast lookups
  List<ProxyAttendanceSession> _cachedSessions = [];

  // Stream for directly alerting host UI to pop up request dialog immediately
  final StreamController<ProxyAttendanceSession> _incomingRequestAlertController =
      StreamController<ProxyAttendanceSession>.broadcast();

  Stream<ProxyAttendanceSession> get incomingRequestAlerts =>
      _incomingRequestAlertController.stream;

  SupabaseProxyAttendanceRepositoryImpl({
    SupabaseClient? supabase,
    AuthService? authService,
  })  : _supabase = supabase ?? Supabase.instance.client,
        _authService = authService ?? AuthService();

  String? get _currentUserId => _authService.currentUserId;

  @override
  Stream<List<ProxyAttendanceSession>> observeSessions(String eventId) {
    _ensureRealtimeSubscription(eventId);
    _refreshSessions(eventId);
    return _sessionsController.stream;
  }

  void _ensureRealtimeSubscription(String eventId) {
    final userId = _currentUserId;
    if (userId == null) return;

    if (_subscribedEventId == eventId && _subscribedUserId == userId && _realtimeChannel != null) {
      return;
    }

    _realtimeChannel?.unsubscribe();
    _subscribedEventId = eventId;
    _subscribedUserId = userId;

    try {
      _realtimeChannel = _supabase
          .channel('public:proxy_attendance_sessions:$eventId:$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'proxy_attendance_sessions',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'event_id',
              value: eventId,
            ),
            callback: (payload) {
              debugPrint('ProxyAttendance Realtime event: ${payload.eventType}');
              final newRecord = payload.newRecord;
              if (newRecord.isNotEmpty) {
                final hostId = newRecord['host_user_id']?.toString();
                final status = newRecord['status']?.toString();

                // If current user is host and an incoming pending request arrived
                if (hostId == userId && status == 'pending' && payload.eventType == PostgresChangeEvent.insert) {
                  _handleIncomingRequestNotification(newRecord);
                }
              }
              _refreshSessions(eventId);
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('ProxyAttendance: Realtime subscription failed ($e)');
    }
  }

  Future<void> _handleIncomingRequestNotification(Map<String, dynamic> record) async {
    try {
      final reqUserId = record['requester_user_id']?.toString() ?? '';
      String requesterName = 'A friend';
      String? avatarUrl;

      // Fetch requester's profile details
      if (reqUserId.isNotEmpty) {
        final res = await _supabase
            .from('profiles')
            .select('full_name, avatar_url')
            .eq('id', reqUserId)
            .maybeSingle();
        if (res != null) {
          requesterName = res['full_name']?.toString() ?? 'A friend';
          avatarUrl = res['avatar_url']?.toString();
        }
      }

      final session = ProxyAttendanceSession.fromJson({
        ...record,
        'requester_name': requesterName,
        'requester_avatar_url': avatarUrl,
      });

      _incomingRequestAlertController.add(session);

      // Trigger high-priority native notification bar alert and in-app popup
      await AppNotificationService.instance.notify(
        title: 'Proxy Attendance Request',
        body: '$requesterName is low on battery and requested you to carry their event attendance.',
        category: NotificationCategory.safety,
        priority: NotificationPriority.urgent,
      );
    } catch (e) {
      debugPrint('ProxyAttendance: Failed to trigger incoming request alert ($e)');
    }
  }

  Future<List<ProxyAttendanceSession>> _refreshSessions(String eventId) async {
    final userId = _currentUserId;
    if (userId == null) {
      _cachedSessions = [];
      _sessionsController.add([]);
      return [];
    }

    try {
      final response = await _supabase
          .from('proxy_attendance_sessions')
          .select('''
            id,
            event_id,
            requester_user_id,
            host_user_id,
            status,
            created_at,
            accepted_at,
            revoked_at,
            revoked_by,
            requester:profiles!requester_user_id(id, full_name, avatar_url),
            host:profiles!host_user_id(id, full_name, avatar_url)
          ''')
          .eq('event_id', eventId)
          .or('requester_user_id.eq.$userId,host_user_id.eq.$userId')
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 8));

      final sessions = (response as List<dynamic>)
          .map((row) => ProxyAttendanceSession.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();

      _cachedSessions = sessions;
      _sessionsController.add(sessions);
      return sessions;
    } catch (e) {
      debugPrint('ProxyAttendance: _refreshSessions error: $e');
      _sessionsController.add(_cachedSessions);
      return _cachedSessions;
    }
  }

  @override
  Future<ProxyAttendanceSession?> getActiveSessionForRequester(String eventId) async {
    final userId = _currentUserId;
    if (userId == null) return null;

    final cached = _cachedSessions.where(
      (s) => s.eventId == eventId && s.requesterUserId == userId && s.isActive,
    );
    if (cached.isNotEmpty) return cached.first;

    final sessions = await _refreshSessions(eventId);
    final matches = sessions.where(
      (s) => s.eventId == eventId && s.requesterUserId == userId && s.isActive,
    );
    return matches.isNotEmpty ? matches.first : null;
  }

  @override
  Future<ProxyAttendanceSession?> getPendingSessionForRequester(String eventId) async {
    final userId = _currentUserId;
    if (userId == null) return null;

    final cached = _cachedSessions.where(
      (s) => s.eventId == eventId && s.requesterUserId == userId && s.isPending,
    );
    if (cached.isNotEmpty) return cached.first;

    final sessions = await _refreshSessions(eventId);
    final matches = sessions.where(
      (s) => s.eventId == eventId && s.requesterUserId == userId && s.isPending,
    );
    return matches.isNotEmpty ? matches.first : null;
  }

  @override
  Future<List<ProxyAttendanceSession>> getActiveSessionsForHost(String eventId) async {
    final userId = _currentUserId;
    if (userId == null) return [];

    final sessions = await _refreshSessions(eventId);
    return sessions
        .where((s) => s.eventId == eventId && s.hostUserId == userId && s.isActive)
        .toList();
  }

  @override
  Future<List<ProxyAttendanceSession>> getIncomingPendingRequests(String eventId) async {
    final userId = _currentUserId;
    if (userId == null) return [];

    final sessions = await _refreshSessions(eventId);
    return sessions
        .where((s) => s.eventId == eventId && s.hostUserId == userId && s.isPending)
        .toList();
  }

  @override
  Future<List<ProxyEligibleFriend>> getEligibleFriends(String eventId) async {
    final userId = _currentUserId;
    if (userId == null) return [];

    try {
      // 1. Fetch accepted connections
      final connRes = await _supabase
          .from('attendee_connections')
          .select('''
            id,
            requester_id,
            addressee_id,
            status,
            requester:profiles!requester_id(id, full_name, headline, avatar_url),
            addressee:profiles!addressee_id(id, full_name, headline, avatar_url)
          ''')
          .eq('event_id', eventId)
          .eq('status', 'accepted')
          .or('requester_id.eq.$userId,addressee_id.eq.$userId');

      final eligible = <ProxyEligibleFriend>[];
      final friendIds = <String>[];
      final profileMaps = <String, Map<String, dynamic>>{};

      for (final row in connRes as List<dynamic>) {
        final r = Map<String, dynamic>.from(row as Map);
        final isOutbound = r['requester_id']?.toString() == userId;
        final peerProfile = isOutbound ? r['addressee'] : r['requester'];
        if (peerProfile == null || peerProfile is! Map) continue;

        final fId = peerProfile['id']?.toString() ?? '';
        if (fId.isNotEmpty && fId != userId) {
          friendIds.add(fId);
          profileMaps[fId] = Map<String, dynamic>.from(peerProfile);
        }
      }

      if (friendIds.isEmpty) return [];

      // 2. Filter for friends who hold an active checked_in ticket for eventId
      final ticketsRes = await _supabase
          .from('tickets')
          .select('user_id, status')
          .eq('event_id', eventId)
          .inFilter('user_id', friendIds)
          .eq('status', 'checked_in');

      final checkedInFriendIds = (ticketsRes as List<dynamic>)
          .map((t) => t['user_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      // 3. Check active carried proxies for each friend to verify capacity (max 2)
      final activeProxiesRes = await _supabase
          .from('proxy_attendance_sessions')
          .select('host_user_id')
          .eq('event_id', eventId)
          .eq('status', 'active')
          .inFilter('host_user_id', checkedInFriendIds.toList());

      final proxyCountMap = <String, int>{};
      for (final p in activeProxiesRes as List<dynamic>) {
        final hId = p['host_user_id']?.toString();
        if (hId != null) {
          proxyCountMap[hId] = (proxyCountMap[hId] ?? 0) + 1;
        }
      }

      for (final fId in checkedInFriendIds) {
        final p = profileMaps[fId];
        if (p == null) continue;

        final fullName = p['full_name']?.toString() ?? 'Attendee';
        final initials = fullName.isNotEmpty
            ? fullName.split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join()
            : 'A';

        eligible.add(ProxyEligibleFriend(
          userId: fId,
          fullName: fullName,
          headline: p['headline']?.toString(),
          avatarUrl: p['avatar_url']?.toString(),
          avatarInitials: initials,
          isCheckedIn: true,
          activeCarriedCount: proxyCountMap[fId] ?? 0,
        ));
      }

      // Sort by available capacity first
      eligible.sort((a, b) => b.canAcceptMore ? 1 : -1);
      return eligible;
    } catch (e) {
      debugPrint('ProxyAttendance: getEligibleFriends error: $e');
      return [];
    }
  }

  @override
  Future<ProxyAttendanceSession> submitRequest({
    required String eventId,
    required String hostUserId,
  }) async {
    final userId = _currentUserId;
    if (userId == null) {
      throw Exception('User is not authenticated');
    }

    try {
      // Attempt RPC first
      final rpcRes = await _supabase.rpc('request_proxy_attendance', params: {
        'p_event_id': eventId,
        'p_host_user_id': hostUserId,
      }).timeout(const Duration(seconds: 8));

      final created = ProxyAttendanceSession.fromJson(Map<String, dynamic>.from(rpcRes as Map));
      await _refreshSessions(eventId);
      return created;
    } catch (rpcErr) {
      debugPrint('ProxyAttendance: RPC request_proxy_attendance failed ($rpcErr), attempting direct insert');
      // Direct table fallback
      final insertRes = await _supabase.from('proxy_attendance_sessions').insert({
        'event_id': eventId,
        'requester_user_id': userId,
        'host_user_id': hostUserId,
        'status': 'pending',
      }).select('''
        id, event_id, requester_user_id, host_user_id, status, created_at, accepted_at, revoked_at, revoked_by
      ''').single();

      final created = ProxyAttendanceSession.fromJson(Map<String, dynamic>.from(insertRes));
      await _refreshSessions(eventId);
      return created;
    }
  }

  @override
  Future<ProxyAttendanceSession> respondToRequest({
    required String sessionId,
    required bool accept,
  }) async {
    final userId = _currentUserId;
    if (userId == null) {
      throw Exception('User is not authenticated');
    }

    try {
      // Attempt RPC first
      final rpcRes = await _supabase.rpc('respond_to_proxy_request', params: {
        'p_session_id': sessionId,
        'p_accept': accept,
      }).timeout(const Duration(seconds: 8));

      final updated = ProxyAttendanceSession.fromJson(Map<String, dynamic>.from(rpcRes as Map));
      if (_subscribedEventId != null) {
        await _refreshSessions(_subscribedEventId!);
      }
      return updated;
    } catch (rpcErr) {
      debugPrint('ProxyAttendance: RPC respond_to_proxy_request failed ($rpcErr), attempting direct update');
      final updateData = accept
          ? {
              'status': 'active',
              'accepted_at': DateTime.now().toUtc().toIso8601String(),
            }
          : {
              'status': 'declined',
              'revoked_at': DateTime.now().toUtc().toIso8601String(),
              'revoked_by': userId,
            };

      final updateRes = await _supabase
          .from('proxy_attendance_sessions')
          .update(updateData)
          .eq('id', sessionId)
          .select('''
            id, event_id, requester_user_id, host_user_id, status, created_at, accepted_at, revoked_at, revoked_by
          ''')
          .single();

      final updated = ProxyAttendanceSession.fromJson(Map<String, dynamic>.from(updateRes));
      if (_subscribedEventId != null) {
        await _refreshSessions(_subscribedEventId!);
      }
      return updated;
    }
  }

  @override
  Future<ProxyAttendanceSession> revokeSession({
    required String sessionId,
  }) async {
    final userId = _currentUserId;
    if (userId == null) {
      throw Exception('User is not authenticated');
    }

    try {
      // Attempt RPC first
      final rpcRes = await _supabase.rpc('revoke_proxy_attendance', params: {
        'p_session_id': sessionId,
      }).timeout(const Duration(seconds: 8));

      final updated = ProxyAttendanceSession.fromJson(Map<String, dynamic>.from(rpcRes as Map));
      if (_subscribedEventId != null) {
        await _refreshSessions(_subscribedEventId!);
      }
      return updated;
    } catch (rpcErr) {
      debugPrint('ProxyAttendance: RPC revoke_proxy_attendance failed ($rpcErr), attempting direct update');
      final updateRes = await _supabase
          .from('proxy_attendance_sessions')
          .update({
            'status': 'revoked',
            'revoked_at': DateTime.now().toUtc().toIso8601String(),
            'revoked_by': userId,
          })
          .eq('id', sessionId)
          .select('''
            id, event_id, requester_user_id, host_user_id, status, created_at, accepted_at, revoked_at, revoked_by
          ''')
          .single();

      final updated = ProxyAttendanceSession.fromJson(Map<String, dynamic>.from(updateRes));
      if (_subscribedEventId != null) {
        await _refreshSessions(_subscribedEventId!);
      }
      return updated;
    }
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _sessionsController.close();
    _incomingRequestAlertController.close();
  }
}
