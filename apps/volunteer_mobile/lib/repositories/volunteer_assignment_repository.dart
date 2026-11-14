import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/volunteer_assignment.dart';
import '../models/event_zone.dart';
import '../models/event_invitation.dart';

abstract class VolunteerAssignmentRepository {
  /// Fetches the authoritative user role from public.profiles.
  Future<String?> getVolunteerRole(String userId);

  /// Fetches active assignments for the given volunteer, including joined event and zone.
  Future<List<VolunteerAssignment>> getAssignments(String volunteerId);

  /// Fetches pending invitations for the volunteer by ID or email.
  Future<List<EventInvitation>> getPendingInvitations({
    required String volunteerId,
    String? email,
  }) async => [];

  /// Accepts an event invitation and activates assignment.
  Future<void> acceptInvitation(EventInvitation invitation) async {}

  /// Declines an event invitation.
  Future<void> declineInvitation(String invitationId) async {}

  /// Fetches normalized zones for the specified event from public.event_zones.
  Future<List<EventZone>> getEventZones(String eventId);

  /// Validates whether the active session assignment is still valid on the server.
  Future<bool> isAssignmentValid({
    required String volunteerId,
    required String eventId,
    String? zoneId,
  });

  /// Assigns volunteer to an operational zone, persisting the shift to Supabase.
  Future<void> assignZone({
    required String eventId,
    required String volunteerId,
    required String zoneId,
    String? zoneName,
  });
}

class VolunteerAssignmentRepositoryImpl implements VolunteerAssignmentRepository {
  final SupabaseClient _supabase;

  VolunteerAssignmentRepositoryImpl({SupabaseClient? supabase})
      : _supabase = supabase ?? Supabase.instance.client;

  @override
  Future<String?> getVolunteerRole(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .maybeSingle();

      if (response != null && response['role'] != null) {
        return response['role'] as String;
      }
      return null;
    } catch (e) {
      print('VolunteerAssignmentRepository ERROR fetching role: $e');
      return null;
    }
  }

  @override
  Future<List<VolunteerAssignment>> getAssignments(String volunteerId) async {
    try {
      final response = await _supabase
          .from('volunteer_assignments')
          .select('*, events(*), event_zones(*)')
          .eq('volunteer_id', volunteerId)
          .eq('status', 'active');

      final list = (response as List<dynamic>)
          .map((item) => VolunteerAssignment.fromSupabase(item as Map<String, dynamic>))
          .toList();

      return list;
    } catch (e) {
      print('VolunteerAssignmentRepository ERROR fetching assignments: $e');
      rethrow;
    }
  }

  @override
  Future<List<EventInvitation>> getPendingInvitations({
    required String volunteerId,
    String? email,
  }) async {
    try {
      var query = _supabase
          .from('event_invitations')
          .select('*, events(*)');

      if (email != null && email.isNotEmpty) {
        query = query.or('volunteer_id.eq.$volunteerId,volunteer_email.eq.$email');
      } else {
        query = query.eq('volunteer_id', volunteerId);
      }

      final response = await query
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      final list = (response as List<dynamic>)
          .map((item) => EventInvitation.fromSupabase(item as Map<String, dynamic>))
          .toList();

      return list;
    } catch (e) {
      print('VolunteerAssignmentRepository ERROR fetching invitations: $e');
      return [];
    }
  }

  @override
  Future<void> acceptInvitation(EventInvitation invitation) async {
    try {
      final token = _supabase.auth.currentSession?.accessToken;
      bool apiHandled = false;

      // Try calling FastAPI backend endpoints to ensure assignment is created with service key
      if (token != null) {
        final candidateHosts = [
          'http://127.0.0.1:8000',
          'http://10.0.2.2:8000',
          'http://192.168.1.5:8000',
        ];

        for (final host in candidateHosts) {
          try {
            final client = HttpClient();
            client.connectionTimeout = const Duration(milliseconds: 1500);
            final req = await client.postUrl(
              Uri.parse('$host/api/volunteers/invitations/${invitation.id}/accept'),
            );
            req.headers.set('Authorization', 'Bearer $token');
            req.headers.set('Content-Type', 'application/json');
            final res = await req.close();
            if (res.statusCode == 200) {
              apiHandled = true;
              client.close();
              break;
            }
            client.close();
          } catch (_) {
            // Try next host
          }
        }
      }

      // If backend was not reached, update directly via Supabase client
      if (!apiHandled) {
        await _supabase
            .from('event_invitations')
            .update({'status': 'accepted'})
            .eq('id', invitation.id);

        try {
          await _supabase.from('volunteer_assignments').insert({
            'volunteer_id': invitation.volunteerId ?? _supabase.auth.currentUser?.id,
            'event_id': invitation.eventId,
            'status': 'active',
            'role': 'crowd_monitor',
          });
        } catch (e) {
          print('VolunteerAssignmentRepository note: direct assignment insert: $e');
        }
      }
    } catch (e) {
      print('VolunteerAssignmentRepository ERROR accepting invitation: $e');
      rethrow;
    }
  }

  @override
  Future<void> declineInvitation(String invitationId) async {
    try {
      await _supabase
          .from('event_invitations')
          .update({'status': 'declined'})
          .eq('id', invitationId);

      final token = _supabase.auth.currentSession?.accessToken;
      if (token != null) {
        final candidateHosts = [
          'http://127.0.0.1:8000',
          'http://10.0.2.2:8000',
          'http://192.168.1.5:8000',
        ];
        for (final host in candidateHosts) {
          try {
            final client = HttpClient();
            client.connectionTimeout = const Duration(milliseconds: 1200);
            final req = await client.postUrl(
              Uri.parse('$host/api/volunteers/invitations/$invitationId/decline'),
            );
            req.headers.set('Authorization', 'Bearer $token');
            final res = await req.close();
            client.close();
            if (res.statusCode == 200) break;
          } catch (_) {}
        }
      }
    } catch (e) {
      print('VolunteerAssignmentRepository ERROR declining invitation: $e');
      rethrow;
    }
  }

  @override
  Future<List<EventZone>> getEventZones(String eventId) async {
    try {
      // 1. Primary: query normalized event_zones
      final response = await _supabase
          .from('event_zones')
          .select('*')
          .eq('event_id', eventId)
          .order('code', ascending: true);

      final zones = (response as List<dynamic>)
          .map((item) => EventZone.fromSupabase(item as Map<String, dynamic>))
          .toList();

      if (zones.isNotEmpty) {
        return zones;
      }

      // 2. Safe fallback: if normalized event_zones has not yet been seeded for
      // an older event, read the legacy events.zones TEXT[] array
      final eventResponse = await _supabase
          .from('events')
          .select('zones')
          .eq('id', eventId)
          .maybeSingle();

      if (eventResponse != null && eventResponse['zones'] is List) {
        final legacyZones = (eventResponse['zones'] as List).map((z) {
          final str = z.toString();
          return EventZone(
            id: str,
            eventId: eventId,
            name: str,
            code: str,
          );
        }).toList();
        return legacyZones;
      }

      return [];
    } catch (e) {
      print('VolunteerAssignmentRepository ERROR fetching event zones: $e');
      return [];
    }
  }

  @override
  Future<bool> isAssignmentValid({
    required String volunteerId,
    required String eventId,
    String? zoneId,
  }) async {
    try {
      var query = _supabase
          .from('volunteer_assignments')
          .select('id')
          .eq('volunteer_id', volunteerId)
          .eq('event_id', eventId)
          .eq('status', 'active');

      if (zoneId != null && zoneId.isNotEmpty) {
        final isUuid = RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(zoneId);
        if (isUuid) {
          query = query.or('zone_id.eq.$zoneId,zone_id.is.null');
        }
      }

      final result = await query.maybeSingle();
      return result != null;
    } catch (e) {
      print('VolunteerAssignmentRepository ERROR verifying assignment: $e');
      return false;
    }
  }

  @override
  Future<void> assignZone({
    required String eventId,
    required String volunteerId,
    required String zoneId,
    String? zoneName,
  }) async {
    try {
      // 1. Get existing assignment
      final assignmentRes = await _supabase
          .from('volunteer_assignments')
          .select('id')
          .eq('volunteer_id', volunteerId)
          .eq('event_id', eventId)
          .maybeSingle();

      String? assignmentId = assignmentRes != null ? assignmentRes['id'] as String? : null;
      if (assignmentId == null) {
        try {
          final newAssign = await _supabase
              .from('volunteer_assignments')
              .insert({
                'event_id': eventId,
                'volunteer_id': volunteerId,
                'status': 'active',
                'role': 'crowd_monitor',
                'zone_id': zoneId,
              })
              .select('id')
              .single();
          assignmentId = newAssign['id'] as String?;
        } catch (e) {
          print('VolunteerAssignmentRepository note: assignment insert fallback $e');
        }
      } else {
        try {
          await _supabase
              .from('volunteer_assignments')
              .update({'zone_id': zoneId})
              .eq('id', assignmentId);
        } catch (e) {
          print('VolunteerAssignmentRepository note: assignment update fallback $e');
        }
      }

      // 2. Update or insert active shift in volunteer_shifts
      final existingShifts = await _supabase
          .from('volunteer_shifts')
          .select('id')
          .eq('volunteer_id', volunteerId)
          .eq('event_id', eventId)
          .inFilter('status', ['scheduled', 'active', 'on_break']);

      final nowUtc = DateTime.now().toUtc();
      if ((existingShifts as List).isNotEmpty) {
        final shiftId = existingShifts[0]['id'];
        await _supabase
            .from('volunteer_shifts')
            .update({
              'zone_id': zoneId,
              'status': 'active',
              'actual_start': nowUtc.toIso8601String(),
              'updated_at': nowUtc.toIso8601String(),
            })
            .eq('id', shiftId);
      } else if (assignmentId != null) {
        await _supabase
            .from('volunteer_shifts')
            .insert({
              'event_id': eventId,
              'volunteer_id': volunteerId,
              'assignment_id': assignmentId,
              'zone_id': zoneId,
              'shift_name': 'Operational Shift',
              'scheduled_start': nowUtc.toIso8601String(),
              'scheduled_end': nowUtc.add(const Duration(hours: 8)).toIso8601String(),
              'actual_start': nowUtc.toIso8601String(),
              'status': 'active',
              'break_state': 'none',
            });
      }
    } catch (e) {
      print('VolunteerAssignmentRepository ERROR assigning zone: $e');
      rethrow;
    }
  }
}
