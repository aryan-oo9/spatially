import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/operational_incident.dart';
import '../models/lost_found_item.dart';
import '../services/observation_queue.dart';
import '../services/session_state.dart';

/// Thrown when an urgent incident cannot be transmitted due to being offline.
class UrgentOfflineException implements Exception {
  final String message;
  const UrgentOfflineException([
    this.message =
        'Urgent reports cannot be queued offline. For immediate medical, security, or safety issues, please notify event staff or organizers directly in person, or use the event emergency pathway.',
  ]);

  @override
  String toString() => message;
}

/// Thrown when an incident is already claimed by another volunteer.
class IncidentAlreadyAssignedException implements Exception {
  final String assignedToName;
  const IncidentAlreadyAssignedException(this.assignedToName);

  String get message => 'This incident is already assigned to $assignedToName.';

  @override
  String toString() => message;
}

class IncidentRepository {
  static final IncidentRepository instance = IncidentRepository._internal();
  factory IncidentRepository() => instance;
  IncidentRepository._internal();

  RealtimeChannel? _incidentsChannel;
  RealtimeChannel? _lostFoundChannel;
  final _uuid = const Uuid();

  /// Check connectivity status.
  Future<bool> _isOnline() async {
    final connectivityResults = await Connectivity().checkConnectivity();
    return connectivityResults.any((r) => r != ConnectivityResult.none);
  }

  /// Report an operational issue or request help.
  Future<OperationalIncident> reportIncident({
    required IncidentCategory category,
    required IncidentPriority priority,
    required String title,
    required String description,
    String? zoneId,
    String? venueZoneName,
    String? venuePoiId,
    String? specificLocation,
    String? imageUrl,
    bool linkOperationalMessage = false,
  }) async {
    final session = SessionState.instance;
    final eventId = session.eventId;
    final volunteerId = session.volunteerId;
    final volunteerName = session.volunteerName ?? 'Volunteer Staff';

    if (eventId == null || volunteerId == null) {
      throw StateError('Cannot report incident without active event and volunteer session.');
    }

    final isOnline = await _isOnline();

    // Urgent Offline Safety Principle: Refuse offline queueing for urgent incidents.
    if (!isOnline && priority == IncidentPriority.urgent) {
      throw const UrgentOfflineException();
    }

    // Offline Queueing for Normal / Important
    if (!isOnline) {
      final localId = 'local_${_uuid.v4()}';
      final row = {
        'local_id': localId,
        'event_id': eventId,
        'volunteer_id': volunteerId,
        'category': category.toDbString(),
        'priority': priority.toDbString(),
        'title': title,
        'description': description,
        'zone_id': zoneId,
        'venue_zone_name': venueZoneName,
        'venue_poi_id': venuePoiId,
        'specific_location': specificLocation,
        'image_url': imageUrl,
        'link_operational_message': linkOperationalMessage ? 1 : 0,
        'created_at': DateTime.now().toIso8601String(),
        'sync_status': 'pending',
      };

      await ObservationQueue().enqueuePendingIncident(row);

      return OperationalIncident(
        id: localId,
        eventId: eventId,
        reporterType: 'volunteer',
        reporterId: volunteerId,
        reporterName: volunteerName,
        category: category,
        priority: priority,
        status: IncidentStatus.open,
        title: title,
        description: description,
        zoneId: zoneId,
        venueZoneName: venueZoneName,
        venuePoiId: venuePoiId,
        specificLocation: specificLocation,
        imageUrl: imageUrl,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isOfflineQueued: true,
      );
    }

    // Online submission: Try RPC first, then fallback to direct resilient table insert
    final client = Supabase.instance.client;
    String? incidentId;
    String? linkedMsgId;

    try {
      final response = await client.rpc('report_operational_incident', params: {
        'p_event_id': eventId,
        'p_category': category.toDbString(),
        'p_priority': priority.toDbString(),
        'p_title': title,
        'p_description': description,
        'p_zone_id': zoneId,
        'p_venue_zone_name': venueZoneName,
        'p_venue_poi_id': venuePoiId,
        'p_specific_location': specificLocation,
        'p_image_url': imageUrl,
        'p_link_operational_message': linkOperationalMessage,
        'p_reporter_type': 'volunteer',
      });

      if (response is Map<String, dynamic> && response['success'] == true) {
        incidentId = response['incident_id'] as String?;
        linkedMsgId = response['linked_message_id'] as String?;
      }
    } catch (e) {
      debugPrint('report_operational_incident RPC failed, falling back to direct DB insert: $e');
    }

    if (incidentId == null) {
      // Direct resilient DB insert
      final insertPayload = <String, dynamic>{
        'event_id': eventId,
        'reporter_type': 'volunteer',
        'reporter_id': volunteerId,
        'reporter_name': volunteerName,
        'category': category.toDbString(),
        'priority': priority.toDbString(),
        'status': 'open',
        'title': title,
        'description': description,
      };
      if (zoneId != null) insertPayload['zone_id'] = zoneId;
      if (venuePoiId != null) insertPayload['venue_poi_id'] = venuePoiId;
      if (specificLocation != null) insertPayload['specific_location'] = specificLocation;
      if (imageUrl != null) insertPayload['image_url'] = imageUrl;

      final inserted = await client
          .from('operational_incidents')
          .insert(insertPayload)
          .select('id')
          .single();

      incidentId = inserted['id'] as String;

      // Also log audit record with action = 'created' (valid with check constraint!)
      try {
        await client.from('operational_incident_logs').insert({
          'incident_id': incidentId,
          'event_id': eventId,
          'actor_id': volunteerId,
          'actor_name': volunteerName,
          'action': 'created',
          'new_status': 'open',
          'notes': description,
        });
      } catch (logErr) {
        debugPrint('Failed to insert incident audit log: $logErr');
      }

      // If linkOperationalMessage is requested, create operational message
      if (linkOperationalMessage) {
        try {
          final msgPayload = <String, dynamic>{
            'event_id': eventId,
            'sender_id': volunteerId,
            'sender_role': 'volunteer',
            'sender_name': volunteerName,
            'target_type': zoneId != null ? 'zone' : 'broadcast',
            'message_type': 'incident_alert',
            'priority': priority.toDbString(),
            'body': '🚨 [INCIDENT] $title: $description',
            'requires_acknowledgment': priority == IncidentPriority.urgent,
          };
          if (zoneId != null) msgPayload['zone_id'] = zoneId;

          final msg = await client.from('operational_messages').insert(msgPayload).select('id').maybeSingle();

          if (msg != null) {
            linkedMsgId = msg['id'] as String?;
          }
        } catch (msgErr) {
          debugPrint('Failed to insert linked operational message: $msgErr');
        }
      }
    }

    return OperationalIncident(
      id: incidentId,
      eventId: eventId,
      reporterType: 'volunteer',
      reporterId: volunteerId,
      reporterName: volunteerName,
      category: category,
      priority: priority,
      status: IncidentStatus.open,
      title: title,
      description: description,
      zoneId: zoneId,
      venueZoneName: venueZoneName,
      venuePoiId: venuePoiId,
      specificLocation: specificLocation,
      imageUrl: imageUrl,
      linkedMessageId: linkedMsgId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isOfflineQueued: false,
    );
  }

  /// Fetch incidents for the active event.
  Future<List<OperationalIncident>> fetchIncidents({bool forceRefresh = false}) async {
    final session = SessionState.instance;
    final eventId = session.eventId;
    final volunteerId = session.volunteerId;

    if (eventId == null || volunteerId == null) {
      return [];
    }

    final isOnline = await _isOnline();

    if (isOnline) {
      try {
        final client = Supabase.instance.client;
        final res = await client
            .from('v_operational_incidents')
            .select()
            .eq('event_id', eventId)
            .order('created_at', ascending: false);

        final rawList = List<Map<String, dynamic>>.from(res as List);
        await ObservationQueue().cacheIncidents(eventId, volunteerId, rawList);

        final parsed = rawList.map((j) => OperationalIncident.fromJson(j)).toList();

        // Also merge any pending local offline incidents that haven't flushed yet
        final pending = await ObservationQueue().getPendingIncidents(
          volunteerId: volunteerId,
          eventId: eventId,
        );

        final pendingIncidents = pending.map((p) => OperationalIncident(
          id: p['local_id'] as String,
          eventId: eventId,
          reporterType: 'volunteer',
          reporterId: volunteerId,
          reporterName: session.volunteerName ?? 'Volunteer Staff',
          category: IncidentCategory.fromString(p['category'] as String),
          priority: IncidentPriority.fromString(p['priority'] as String),
          status: IncidentStatus.open,
          title: p['title'] as String,
          description: p['description'] as String,
          zoneId: p['zone_id'] as String?,
          venueZoneName: p['venue_zone_name'] as String?,
          venuePoiId: p['venue_poi_id'] as String?,
          specificLocation: p['specific_location'] as String?,
          imageUrl: p['image_url'] as String?,
          createdAt: DateTime.tryParse(p['created_at'] as String) ?? DateTime.now(),
          updatedAt: DateTime.tryParse(p['created_at'] as String) ?? DateTime.now(),
          isOfflineQueued: true,
        )).toList();

        return [...pendingIncidents, ...parsed];
      } catch (e) {
        print('IncidentRepository: Error fetching online incidents, falling back to cache: $e');
      }
    }

    // Fallback: Read from SQLite cache
    final cached = await ObservationQueue().getCachedIncidents(eventId, volunteerId);
    final parsedCached = cached.map((j) => OperationalIncident.fromJson(j)).toList();

    final pending = await ObservationQueue().getPendingIncidents(
      volunteerId: volunteerId,
      eventId: eventId,
    );

    final pendingIncidents = pending.map((p) => OperationalIncident(
      id: p['local_id'] as String,
      eventId: eventId,
      reporterType: 'volunteer',
      reporterId: volunteerId,
      reporterName: session.volunteerName ?? 'Volunteer Staff',
      category: IncidentCategory.fromString(p['category'] as String),
      priority: IncidentPriority.fromString(p['priority'] as String),
      status: IncidentStatus.open,
      title: p['title'] as String,
      description: p['description'] as String,
      zoneId: p['zone_id'] as String?,
      venueZoneName: p['venue_zone_name'] as String?,
      venuePoiId: p['venue_poi_id'] as String?,
      specificLocation: p['specific_location'] as String?,
      imageUrl: p['image_url'] as String?,
      createdAt: DateTime.tryParse(p['created_at'] as String) ?? DateTime.now(),
      updatedAt: DateTime.tryParse(p['created_at'] as String) ?? DateTime.now(),
      isOfflineQueued: true,
    )).toList();

    return [...pendingIncidents, ...parsedCached];
  }

  /// Atomically assign an incident to self or another volunteer.
  Future<void> assignIncident(String incidentId, {String? targetVolunteerId}) async {
    final session = SessionState.instance;
    final assigneeId = targetVolunteerId ?? session.volunteerId;

    if (assigneeId == null) {
      throw StateError('Cannot assign incident without authenticated volunteer ID.');
    }

    final client = Supabase.instance.client;
    final res = await client.rpc('assign_operational_incident', params: {
      'p_incident_id': incidentId,
      'p_assigned_to_id': assigneeId,
    });

    if (res is Map<String, dynamic>) {
      if (res['success'] == true) {
        return;
      }
      if (res['error'] == 'ALREADY_ASSIGNED') {
        final name = res['assigned_to_name']?.toString() ?? 'another volunteer';
        throw IncidentAlreadyAssignedException(name);
      }
      throw Exception(res['error'] ?? 'Assignment failed');
    }
  }

  /// Acknowledge an incident.
  Future<void> acknowledgeIncident(String incidentId) async {
    final client = Supabase.instance.client;
    final res = await client.rpc('acknowledge_operational_incident', params: {
      'p_incident_id': incidentId,
    });

    if (res is Map<String, dynamic> && res['success'] == true) {
      return;
    }
    throw Exception('Failed to acknowledge incident: $res');
  }

  /// Update incident status (e.g. in_progress, resolved, closed, cancelled).
  Future<void> updateStatus(
    String incidentId,
    IncidentStatus newStatus, {
    String? resolutionNotes,
    String? staffNotes,
  }) async {
    final client = Supabase.instance.client;
    final res = await client.rpc('update_incident_status', params: {
      'p_incident_id': incidentId,
      'p_new_status': newStatus.toDbString(),
      'p_resolution_notes': resolutionNotes,
      'p_staff_notes': staffNotes,
    });

    if (res is Map<String, dynamic> && res['success'] == true) {
      return;
    }
    throw Exception('Failed to update incident status: $res');
  }

  /// Upload photo evidence to 'incident-evidence' bucket.
  Future<String> uploadEvidence(File file) async {
    final session = SessionState.instance;
    final eventId = session.eventId;

    if (eventId == null) {
      throw StateError('Cannot upload evidence without active event.');
    }

    final length = await file.length();
    if (length > 5 * 1024 * 1024) {
      throw Exception('Photo evidence exceeds maximum allowed size (5MB).');
    }

    final ext = file.path.split('.').last.toLowerCase();
    if (!['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
      throw Exception('Unsupported file format. Please upload JPG, PNG, or WebP images.');
    }

    final client = Supabase.instance.client;
    final fileName = '${_uuid.v4()}.$ext';
    final storagePath = 'event/$eventId/incidents/$fileName';

    await client.storage.from('incident-evidence').upload(
      storagePath,
      file,
      fileOptions: FileOptions(
        contentType: 'image/$ext',
        upsert: true,
      ),
    );

    return client.storage.from('incident-evidence').getPublicUrl(storagePath);
  }

  /// Fetch Lost & Found reports.
  Future<List<LostFoundItem>> fetchLostFoundReports({bool forceRefresh = false}) async {
    final session = SessionState.instance;
    final eventId = session.eventId;
    final volunteerId = session.volunteerId;

    if (eventId == null || volunteerId == null) {
      return [];
    }

    final isOnline = await _isOnline();

    if (isOnline) {
      try {
        final client = Supabase.instance.client;
        final res = await client
            .from('lost_found_reports')
            .select()
            .eq('event_id', eventId)
            .order('created_at', ascending: false);

        final rawList = List<Map<String, dynamic>>.from(res as List);
        await ObservationQueue().cacheLostFoundReports(eventId, volunteerId, rawList);

        return rawList.map((j) => LostFoundItem.fromJson(j)).toList();
      } catch (e) {
        print('IncidentRepository: Error fetching lost & found online: $e');
      }
    }

    final cached = await ObservationQueue().getCachedLostFoundReports(eventId, volunteerId);
    return cached.map((j) => LostFoundItem.fromJson(j)).toList();
  }

  /// Update Lost & Found item status.
  Future<void> updateLostFoundStatus(
    String reportId,
    String newStatus, {
    String? pickupInstructions,
  }) async {
    final client = Supabase.instance.client;
    String dbStatus = newStatus.toLowerCase();
    if (dbStatus == 'open') dbStatus = 'submitted';
    if (dbStatus == 'returned' || dbStatus == 'expired' || dbStatus == 'closed') dbStatus = 'resolved';

    final res = await client.rpc('update_lost_found_status', params: {
      'p_report_id': reportId,
      'p_new_status': dbStatus,
      'p_pickup_instructions': pickupInstructions,
    });

    if (res is Map<String, dynamic> && res['success'] == true) {
      return;
    }
    throw Exception('Failed to update lost & found report status: $res');
  }

  /// Subscribe to Realtime Postgres changes for operational incidents and lost & found.
  void subscribeRealtime({
    required void Function() onDataChanged,
  }) {
    final session = SessionState.instance;
    final eventId = session.eventId;
    if (eventId == null) return;

    unsubscribeRealtime();

    final client = Supabase.instance.client;

    _incidentsChannel = client
        .channel('public:operational_incidents:event:$eventId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'operational_incidents',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'event_id',
            value: eventId,
          ),
          callback: (payload) {
            print('IncidentRepository: Realtime incident update received: ${payload.eventType}');
            onDataChanged();
          },
        )
        .subscribe();

    _lostFoundChannel = client
        .channel('public:lost_found_reports:event:$eventId')
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
            print('IncidentRepository: Realtime lost & found update received: ${payload.eventType}');
            onDataChanged();
          },
        )
        .subscribe();
  }

  /// Clean up realtime subscriptions.
  void unsubscribeRealtime() {
    if (_incidentsChannel != null) {
      Supabase.instance.client.removeChannel(_incidentsChannel!);
      _incidentsChannel = null;
    }
    if (_lostFoundChannel != null) {
      Supabase.instance.client.removeChannel(_lostFoundChannel!);
      _lostFoundChannel = null;
    }
  }
}
