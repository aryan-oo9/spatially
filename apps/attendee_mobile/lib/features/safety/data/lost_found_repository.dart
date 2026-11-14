import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/attendee_identity.dart';
import '../../../services/offline_service.dart';
import '../models/safety_models.dart';

/// Abstract contract for event-scoped Lost & Found operations.
abstract class LostFoundRepository {
  Stream<List<LostFoundReport>> getReportsStream(String eventId);
  Future<List<LostFoundReport>> getReports(String eventId, {LostFoundType? type, bool onlyMyReports = false});
  Future<LostFoundReport> submitReport({
    required String eventId,
    required LostFoundType type,
    required LostFoundCategory category,
    required String title,
    required String description,
    required String venueZoneId,
    required String venueZoneName,
    String? specificLocation,
    String? imagePlaceholderName,
  });
  Future<void> updateReportStatus(String reportId, LostFoundStatus status);
  Future<void> syncPendingReports();
}

/// Exception thrown when the digital Lost & Found service/table is not available.
class LostFoundUnavailableException implements Exception {
  final String message;
  const LostFoundUnavailableException([
    this.message = 'Lost & Found digital logging service is currently unavailable for this event. Please report or claim items in person at the Central Help Desk (Room 712 Foyer).',
  ]);

  @override
  String toString() => message;
}

/// Production repository with Supabase persistence, stream reactivity, offline drafting, and outbox sync.
class LostFoundRepositoryImpl implements LostFoundRepository {
  static final LostFoundRepositoryImpl _instance = LostFoundRepositoryImpl._internal();
  factory LostFoundRepositoryImpl() => _instance;

  final SupabaseClient _supabase;
  final Map<String, List<LostFoundReport>> _eventReports = {};
  final List<Map<String, dynamic>> _offlineOutbox = [];
  final StreamController<List<LostFoundReport>> _controller = StreamController<List<LostFoundReport>>.broadcast();
  final Map<String, Future<List<LostFoundReport>>> _inFlightFetches = {};
  final Map<String, RealtimeChannel> _channels = {};

  LostFoundRepositoryImpl._internal({SupabaseClient? supabase})
      : _supabase = supabase ?? Supabase.instance.client {
    OfflineService().isOnlineNotifier.addListener(_onConnectivityChanged);
  }

  void _onConnectivityChanged() {
    if (OfflineService().isOnline) {
      syncPendingReports();
    }
  }

  /// Ensures we always query Supabase with a valid event UUID rather than a placeholder string.
  Future<String> _resolveValidEventId(String rawEventId) async {
    final trimmed = rawEventId.trim();
    final isUuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(trimmed);
    if (isUuid) return trimmed;

    // If eventId is 'demo_event' or empty or invalid UUID, find actual event UUID
    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        final tickets = await _supabase
            .from('tickets')
            .select('event_id')
            .eq('user_id', user.id)
            .order('purchased_at', ascending: false)
            .limit(1);
        if ((tickets as List).isNotEmpty && tickets.first['event_id'] != null) {
          return tickets.first['event_id'].toString();
        }
      }

      // Check for live event
      final liveRes = await _supabase
          .from('events')
          .select('id')
          .eq('status', 'live')
          .limit(1);
      if ((liveRes as List).isNotEmpty && liveRes.first['id'] != null) {
        return liveRes.first['id'].toString();
      }

      // Check for upcoming event
      final upcomingRes = await _supabase
          .from('events')
          .select('id')
          .order('event_start_time', ascending: true)
          .limit(1);
      if ((upcomingRes as List).isNotEmpty && upcomingRes.first['id'] != null) {
        return upcomingRes.first['id'].toString();
      }
    } catch (e) {
      debugPrint('Notice resolving fallback event ID for Lost & Found: $e');
    }

    return trimmed;
  }

  void _subscribeRealtime(String eventId) {
    if (_channels.containsKey(eventId)) return;

    try {
      final channel = _supabase.channel('attendee-lost-found-$eventId');
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'lost_found_reports',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'event_id',
              value: eventId,
            ),
            callback: (payload) {
              debugPrint('LostFoundRepository: Realtime sync trigger (${payload.eventType})');
              _fetchRemoteReports(eventId, notifyStream: true).catchError((_) => <LostFoundReport>[]);
            },
          )
          .subscribe();
      _channels[eventId] = channel;
    } catch (e) {
      debugPrint('Notice: Realtime subscription on lost_found_reports unavailable: $e');
    }
  }

  Future<List<LostFoundReport>> _fetchRemoteReports(String rawEventId, {bool notifyStream = true}) async {
    final eventId = await _resolveValidEventId(rawEventId);
    _subscribeRealtime(eventId);

    if (_inFlightFetches.containsKey(eventId)) {
      return await _inFlightFetches[eventId]!;
    }

    final future = _doFetchRemoteReports(eventId, rawEventId, notifyStream: notifyStream);
    _inFlightFetches[eventId] = future;
    try {
      return await future;
    } finally {
      _inFlightFetches.remove(eventId);
    }
  }

  Future<List<LostFoundReport>> _doFetchRemoteReports(
    String eventId,
    String rawEventId, {
    bool notifyStream = true,
  }) async {
    try {
      final isUuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(eventId);

      var query = _supabase
          .from('lost_found_reports')
          .select('*, event_zones(name)');

      if (isUuid) {
        query = query.eq('event_id', eventId);
      }

      final response = await query
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 5));

      final myDeviceId = AttendeeIdentity.deviceId;
      final myUserId = _supabase.auth.currentUser?.id;

      final remoteReports = (response as List<dynamic>).map((row) {
        final r = Map<String, dynamic>.from(row as Map);
        final reportType = (r['report_type']?.toString().toLowerCase() == 'found')
            ? LostFoundType.found
            : LostFoundType.lost;

        final catStr = r['category']?.toString().toLowerCase();
        final cat = LostFoundCategory.values.firstWhere(
          (c) => c.name.toLowerCase() == catStr,
          orElse: () => LostFoundCategory.other,
        );

        final statusStr = r['status']?.toString().toLowerCase();
        final status = LostFoundStatus.values.firstWhere(
          (s) => s.name.toLowerCase() == statusStr,
          orElse: () => LostFoundStatus.submitted,
        );

        final isMine = (myDeviceId != null && r['reporter_device_id'] == myDeviceId) ||
            (myUserId != null && r['reporter_user_id'] == myUserId);

        final eventZoneMap = r['event_zones'] is Map ? (r['event_zones'] as Map) : null;
        final zoneName = eventZoneMap?['name']?.toString() ??
            r['specific_location']?.toString() ??
            'Venue Zone';

        return LostFoundReport(
          id: r['id']?.toString() ?? '',
          eventId: r['event_id']?.toString() ?? eventId,
          type: reportType,
          category: cat,
          title: r['title']?.toString() ?? 'Report',
          description: r['description']?.toString() ?? '',
          venueZoneId: r['zone_id']?.toString() ?? '712',
          venueZoneName: zoneName,
          specificLocation: r['specific_location']?.toString(),
          imagePlaceholderName: r['image_url']?.toString(),
          status: status,
          createdAt: DateTime.tryParse(r['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
          isCurrentUser: isMine,
          pickupInstructions: r['pickup_instructions']?.toString(),
        );
      }).toList();

      final existingLocal = _eventReports[eventId] ?? [];
      final pendingDrafts = existingLocal.where((r) => r.status == LostFoundStatus.pendingSync).toList();

      final merged = [...pendingDrafts, ...remoteReports];
      _eventReports[eventId] = merged;
      if (rawEventId != eventId) {
        _eventReports[rawEventId] = merged;
      }

      if (notifyStream) {
        _controller.add(List.unmodifiable(merged));
      }
      return merged;
    } catch (e) {
      debugPrint('LostFoundRepository: Remote fetch encountered error: $e');
      final existingLocal = _eventReports[eventId] ?? _eventReports[rawEventId] ?? [];
      if (existingLocal.isNotEmpty) {
        return existingLocal;
      }
      _controller.addError(const LostFoundUnavailableException());
      throw const LostFoundUnavailableException();
    }
  }

  @override
  Stream<List<LostFoundReport>> getReportsStream(String eventId) {
    _fetchRemoteReports(eventId, notifyStream: true).catchError((_) => <LostFoundReport>[]);
    return _controller.stream;
  }

  @override
  Future<List<LostFoundReport>> getReports(
    String eventId, {
    LostFoundType? type,
    bool onlyMyReports = false,
  }) async {
    final all = await _fetchRemoteReports(eventId, notifyStream: false);

    var list = all;
    if (type != null) {
      list = list.where((r) => r.type == type).toList();
    }
    if (onlyMyReports) {
      list = list.where((r) => r.isCurrentUser).toList();
    }
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(list);
  }

  @override
  Future<LostFoundReport> submitReport({
    required String eventId,
    required LostFoundType type,
    required LostFoundCategory category,
    required String title,
    required String description,
    required String venueZoneId,
    required String venueZoneName,
    String? specificLocation,
    String? imagePlaceholderName,
  }) async {
    final effectiveEventId = await _resolveValidEventId(eventId);
    final isOnline = OfflineService().isOnline;
    final myDeviceId = AttendeeIdentity.deviceId ?? 'guest_device';
    final myUserId = _supabase.auth.currentUser?.id;

    final String instructions = type == LostFoundType.found
        ? 'Item handed to on-site volunteer or kept safe by reporter.'
        : 'Central Help Desk notified. Staff will cross-reference incoming found property.';

    if (isOnline) {
      try {
        final isUuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(venueZoneId);
        final payload = {
          'event_id': effectiveEventId,
          'reporter_device_id': myDeviceId,
          'reporter_user_id': myUserId,
          'report_type': type.name,
          'category': category.name,
          'title': title,
          'description': description,
          'zone_id': isUuid ? venueZoneId : null,
          'specific_location': specificLocation ?? venueZoneName,
          'image_url': imagePlaceholderName,
          'status': 'submitted',
          'pickup_instructions': instructions,
        };

        final inserted = await _supabase
            .from('lost_found_reports')
            .insert(payload)
            .select()
            .single()
            .timeout(const Duration(seconds: 4));

        final newReport = LostFoundReport(
          id: inserted['id']?.toString() ?? 'lf_${DateTime.now().millisecondsSinceEpoch}',
          eventId: effectiveEventId,
          type: type,
          category: category,
          title: title,
          description: description,
          venueZoneId: venueZoneId,
          venueZoneName: venueZoneName,
          specificLocation: specificLocation,
          imagePlaceholderName: imagePlaceholderName,
          status: LostFoundStatus.submitted,
          createdAt: DateTime.tryParse(inserted['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
          isCurrentUser: true,
          pickupInstructions: instructions,
        );

        final list = _eventReports[effectiveEventId] ?? [];
        list.insert(0, newReport);
        _eventReports[effectiveEventId] = list;
        if (eventId != effectiveEventId) {
          _eventReports[eventId] = list;
        }
        _controller.add(List.unmodifiable(list));
        return newReport;
      } catch (e) {
        debugPrint('LostFoundRepository: Supabase insert failed: $e');
        // Fallback to offline queue if Supabase insert timed out or failed
      }
    }

    // Offline or network error: Save locally as pendingSync
    final offlineReport = LostFoundReport(
      id: 'lf_pending_${DateTime.now().millisecondsSinceEpoch}',
      eventId: effectiveEventId,
      type: type,
      category: category,
      title: title,
      description: description,
      venueZoneId: venueZoneId,
      venueZoneName: venueZoneName,
      specificLocation: specificLocation,
      imagePlaceholderName: imagePlaceholderName,
      status: LostFoundStatus.pendingSync,
      createdAt: DateTime.now(),
      isCurrentUser: true,
      pickupInstructions: 'Draft saved locally offline. Will be submitted once connectivity is restored.',
    );

    final isUuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(venueZoneId);
    _offlineOutbox.add({
      'report': offlineReport,
      'payload': {
        'event_id': effectiveEventId,
        'reporter_device_id': myDeviceId,
        'reporter_user_id': myUserId,
        'report_type': type.name,
        'category': category.name,
        'title': title,
        'description': description,
        'zone_id': isUuid ? venueZoneId : null,
        'specific_location': specificLocation ?? venueZoneName,
        'image_url': imagePlaceholderName,
        'status': 'submitted',
        'pickup_instructions': instructions,
      }
    });

    final list = _eventReports[effectiveEventId] ?? [];
    list.insert(0, offlineReport);
    _eventReports[effectiveEventId] = list;
    if (eventId != effectiveEventId) {
      _eventReports[eventId] = list;
    }
    _controller.add(List.unmodifiable(list));

    return offlineReport;
  }

  @override
  Future<void> updateReportStatus(String reportId, LostFoundStatus status) async {
    for (final eventId in _eventReports.keys) {
      final list = _eventReports[eventId]!;
      final idx = list.indexWhere((r) => r.id == reportId);
      if (idx != -1) {
        list[idx] = list[idx].copyWith(status: status);
        _controller.add(List.unmodifiable(list));
        break;
      }
    }
  }

  @override
  Future<void> syncPendingReports() async {
    if (_offlineOutbox.isEmpty) return;

    final itemsToSync = List<Map<String, dynamic>>.from(_offlineOutbox);
    for (final item in itemsToSync) {
      try {
        final payload = item['payload'] as Map<String, dynamic>;
        final localReport = item['report'] as LostFoundReport;

        final inserted = await _supabase
            .from('lost_found_reports')
            .insert(payload)
            .select()
            .single()
            .timeout(const Duration(seconds: 4));

        _offlineOutbox.remove(item);

        final eventId = localReport.eventId;
        if (_eventReports.containsKey(eventId)) {
          final list = _eventReports[eventId]!;
          final idx = list.indexWhere((r) => r.id == localReport.id);
          if (idx != -1) {
            list[idx] = localReport.copyWith(
              id: inserted['id']?.toString() ?? localReport.id,
              status: LostFoundStatus.submitted,
              pickupInstructions: localReport.type == LostFoundType.found
                  ? 'Item handed to on-site volunteer or kept safe by reporter.'
                  : 'Central Help Desk notified. Staff will cross-reference incoming found property.',
            );
            _controller.add(List.unmodifiable(list));
          }
        }
      } catch (_) {
        // Leave item in outbox for subsequent retry
      }
    }
  }
}
