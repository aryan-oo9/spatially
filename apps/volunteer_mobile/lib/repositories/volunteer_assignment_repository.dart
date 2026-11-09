import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/volunteer_assignment.dart';
import '../models/event_zone.dart';

abstract class VolunteerAssignmentRepository {
  /// Fetches the authoritative user role from public.profiles.
  Future<String?> getVolunteerRole(String userId);

  /// Fetches active assignments for the given volunteer, including joined event and zone.
  Future<List<VolunteerAssignment>> getAssignments(String volunteerId);

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
