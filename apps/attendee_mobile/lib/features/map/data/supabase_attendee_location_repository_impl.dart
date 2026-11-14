import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../design_system/components/spatially_crowd_indicator.dart';
import '../../../services/attendee_identity.dart';
import '../../../services/ephemeral_id.dart';
import '../../../services/offline_service.dart';
import '../models/attendee_location_models.dart';
import '../models/venue_map_models.dart';
import 'attendee_location_repository.dart';

/// Production Supabase-backed implementation of [AttendeeLocationRepository].
///
/// Features:
/// - Resolves registered attendee's active event zone via volunteer proximity telemetry loopback.
/// - Matches deterministic 6-byte rotating ephemeral IDs (current and previous 5-minute epoch).
/// - Automatically transitions between [detected], [stale], and [unknown] states based on time.
/// - Supports persistent manual zone pinning / QR check-in stored in [SharedPreferences].
/// - Enriches resolved zone with floor level details and crowd telemetry.
class SupabaseAttendeeLocationRepositoryImpl implements AttendeeLocationRepository {
  final SupabaseClient _supabase;
  final OfflineService _offlineService;

  static const String _kManualZonePrefix = 'attendee_manual_zone_';

  final StreamController<AttendeeLocationState> _controller =
      StreamController<AttendeeLocationState>.broadcast();

  Timer? _refreshTimer;
  String? _activeEventId;
  AttendeeLocationState _lastState = AttendeeLocationState.unknown();

  // In-memory zone metadata cache to avoid repetitive joins
  final Map<String, Map<String, dynamic>> _zoneCache = {};

  SupabaseAttendeeLocationRepositoryImpl({
    SupabaseClient? supabase,
    OfflineService? offlineService,
  })  : _supabase = supabase ?? Supabase.instance.client,
        _offlineService = offlineService ?? OfflineService();

  @override
  Stream<AttendeeLocationState> watchLocation(String eventId) {
    if (_activeEventId != eventId) {
      _activeEventId = eventId;
      _startPeriodicRefresh(eventId);
    }
    // Eagerly resolve in background
    getLocation(eventId).then((state) {
      if (!_controller.isClosed) {
        _controller.add(state);
      }
    }).catchError((_) {});

    return _controller.stream;
  }

  void _startPeriodicRefresh(String eventId) {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      try {
        final state = await getLocation(eventId);
        if (!_controller.isClosed) {
          _controller.add(state);
        }
      } catch (e) {
        debugPrint('SupabaseAttendeeLocationRepositoryImpl: periodic refresh error: $e');
      }
    });
  }

  @override
  Future<AttendeeLocationState> getLocation(String eventId) async {
    // 1. Check for manual override stored locally
    final manualState = await _getManualZone(eventId);
    if (manualState != null) {
      _lastState = manualState;
      return manualState;
    }

    // 2. If offline, keep previous location or return unknown
    if (!_offlineService.isOnline) {
      if (_lastState.hasLocation) {
        return _lastState.copyWith(status: AttendeeLocationStatus.stale);
      }
      return AttendeeLocationState.unknown();
    }

    final deviceId = AttendeeIdentity.deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      return AttendeeLocationState.unknown();
    }

    try {
      // 3. Compute current and previous 5-minute ephemeral IDs
      final currentBytes = EphemeralId.compute(deviceId);
      final currentHex = currentBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      final prevWindow = EphemeralId.currentWindowStart().subtract(const Duration(minutes: 5));
      final prevInput = '$deviceId${prevWindow.millisecondsSinceEpoch}';
      final prevDigest = sha256.convert(utf8.encode(prevInput));
      final prevHex = prevDigest.bytes.take(6).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      final fiveMinutesAgo = DateTime.now().toUtc().subtract(const Duration(minutes: 5)).toIso8601String();

      // 4. Query sightings in Supabase observations table
      final response = await _supabase
          .from('observations')
          .select('zone, zone_id, observed_at, rssi')
          .eq('event_id', eventId)
          .inFilter('ephemeral_id', [currentHex, prevHex])
          .gte('observed_at', fiveMinutesAgo)
          .order('observed_at', ascending: false)
          .limit(5)
          .timeout(const Duration(seconds: 4));

      final observations = response as List;
      if (observations.isEmpty) {
        if (_lastState.hasLocation && _lastState.isAutoDetected) {
          // If previous sighting is between 3 and 5 minutes old, mark stale
          final diff = _lastState.lastSeen != null
              ? DateTime.now().difference(_lastState.lastSeen!)
              : const Duration(minutes: 10);
          if (diff.inMinutes < 5) {
            _lastState = _lastState.copyWith(status: AttendeeLocationStatus.stale);
            return _lastState;
          }
        }
        _lastState = AttendeeLocationState.unknown();
        return _lastState;
      }

      // Pick top observation with non-empty zone_id or zone text
      final topObs = observations.firstWhere(
        (obs) => (obs['zone_id'] != null && obs['zone_id'].toString().isNotEmpty) ||
                 (obs['zone'] != null && obs['zone'].toString().isNotEmpty),
        orElse: () => null,
      );

      if (topObs == null) {
        _lastState = AttendeeLocationState.unknown();
        return _lastState;
      }

      var zoneId = topObs['zone_id']?.toString();
      final zoneText = topObs['zone']?.toString();

      // If zone_id is null, resolve from zone text/code
      if ((zoneId == null || zoneId.isEmpty) && zoneText != null && zoneText.isNotEmpty) {
        try {
          final matchedZone = await _supabase
              .from('event_zones')
              .select('id')
              .eq('event_id', eventId)
              .or('code.ilike.$zoneText,name.ilike.$zoneText')
              .limit(1)
              .maybeSingle();
          if (matchedZone != null && matchedZone['id'] != null) {
            zoneId = matchedZone['id'].toString();
          }
        } catch (_) {}
      }

      final observedAt = DateTime.tryParse(topObs['observed_at']?.toString() ?? '') ?? DateTime.now();
      final rssi = (topObs['rssi'] as num?)?.toInt();

      final age = DateTime.now().toUtc().difference(observedAt.toUtc());
      final status = age.inMinutes >= 3
          ? AttendeeLocationStatus.stale
          : AttendeeLocationStatus.detected;

      // 5. Lookup Zone and Level Metadata
      final zoneMeta = zoneId != null && zoneId.isNotEmpty
          ? await _resolveZoneMetadata(eventId, zoneId)
          : <String, dynamic>{'name': zoneText ?? 'Event Venue'};

      _lastState = AttendeeLocationState(
        status: status,
        zoneId: zoneId,
        zoneCode: zoneMeta['code']?.toString() ?? zoneText,
        zoneName: zoneMeta['name']?.toString() ?? zoneText ?? 'Zone',
        levelId: zoneMeta['level_id']?.toString(),
        levelName: zoneMeta['level_name']?.toString(),
        floorLevel: (zoneMeta['floor_level'] as num?)?.toInt(),
        activeHeadcount: (zoneMeta['active_headcount'] as num?)?.toInt(),
        crowdLevel: zoneMeta['crowd_level'] as SpatiallyCrowdLevel? ?? SpatiallyCrowdLevel.low,
        lastSeen: observedAt,
        rssi: rssi,
      );

      return _lastState;
    } catch (e) {
      debugPrint('SupabaseAttendeeLocationRepositoryImpl: error resolving location: $e');
      if (_lastState.hasLocation) {
        return _lastState.copyWith(status: AttendeeLocationStatus.stale);
      }
      return AttendeeLocationState.unknown();
    }
  }

  Future<Map<String, dynamic>> _resolveZoneMetadata(String eventId, String zoneId) async {
    if (_zoneCache.containsKey(zoneId)) {
      final cached = _zoneCache[zoneId]!;
      // Refresh live crowd count
      final crowd = await _fetchZoneCrowd(eventId, cached['code']?.toString());
      cached['active_headcount'] = crowd['active_count'];
      cached['crowd_level'] = crowd['crowd_level'];
      return cached;
    }

    try {
      // Query event_zones joined with venue_levels
      final row = await _supabase
          .from('event_zones')
          .select('id, name, code, level_id, operating_capacity, venue_levels(id, name, level_index)')
          .eq('id', zoneId)
          .maybeSingle()
          .timeout(const Duration(seconds: 4));

      if (row != null) {
        final Map<String, dynamic> meta = {
          'id': row['id']?.toString(),
          'name': row['name']?.toString(),
          'code': row['code']?.toString(),
          'level_id': row['level_id']?.toString(),
          'operating_capacity': (row['operating_capacity'] as num?)?.toInt() ?? 100,
        };

        if (row['venue_levels'] is Map) {
          final vl = row['venue_levels'] as Map;
          meta['level_name'] = vl['name']?.toString();
          meta['floor_level'] = (vl['level_index'] as num?)?.toInt();
        }

        final crowd = await _fetchZoneCrowd(eventId, meta['code']?.toString());
        meta['active_headcount'] = crowd['active_count'];
        meta['crowd_level'] = crowd['crowd_level'];

        _zoneCache[zoneId] = meta;
        return meta;
      }
    } catch (e) {
      debugPrint('SupabaseAttendeeLocationRepositoryImpl: zone metadata error: $e');
    }

    return {
      'id': zoneId,
      'name': 'Zone $zoneId',
      'code': zoneId,
      'crowd_level': SpatiallyCrowdLevel.low,
    };
  }

  Future<Map<String, dynamic>> _fetchZoneCrowd(String eventId, String? zoneCode) async {
    if (zoneCode == null || zoneCode.isEmpty) {
      return {'active_count': 0, 'crowd_level': SpatiallyCrowdLevel.low};
    }

    try {
      final row = await _supabase
          .from('volunteer_counts')
          .select('headcount')
          .eq('event_id', eventId)
          .eq('zone', zoneCode)
          .order('recorded_at', ascending: false)
          .limit(1)
          .maybeSingle()
          .timeout(const Duration(seconds: 3));

      if (row != null) {
        final count = (row['headcount'] as num?)?.toInt() ?? 0;
        final level = SpatialCrowdState.levelFromCount(count);
        return {'active_count': count, 'crowd_level': level};
      }
    } catch (_) {}

    return {'active_count': 0, 'crowd_level': SpatiallyCrowdLevel.low};
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
    final prefs = await SharedPreferences.getInstance();
    final key = '$_kManualZonePrefix$eventId';

    // If metadata wasn't passed, try resolving from cache
    final meta = _zoneCache[zoneId] ?? {};
    final resolvedName = zoneName ?? meta['name']?.toString() ?? 'Zone $zoneId';
    final resolvedCode = zoneCode ?? meta['code']?.toString();
    final resolvedLevelId = levelId ?? meta['level_id']?.toString();
    final resolvedLevelName = levelName ?? meta['level_name']?.toString();
    final resolvedFloorLevel = floorLevel ?? (meta['floor_level'] as num?)?.toInt();

    final state = AttendeeLocationState(
      status: AttendeeLocationStatus.manual,
      zoneId: zoneId,
      zoneCode: resolvedCode,
      zoneName: resolvedName,
      levelId: resolvedLevelId,
      levelName: resolvedLevelName,
      floorLevel: resolvedFloorLevel,
      lastSeen: DateTime.now(),
    );

    await prefs.setString(key, jsonEncode(state.toJson()));
    _lastState = state;
    if (!_controller.isClosed) {
      _controller.add(state);
    }
  }

  @override
  Future<void> clearManualZone(String eventId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_kManualZonePrefix$eventId';
    await prefs.remove(key);

    _lastState = AttendeeLocationState.locating();
    if (!_controller.isClosed) {
      _controller.add(_lastState);
    }
    // Immediately re-fetch automatic location
    final newState = await getLocation(eventId);
    if (!_controller.isClosed) {
      _controller.add(newState);
    }
  }

  Future<AttendeeLocationState?> _getManualZone(String eventId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_kManualZonePrefix$eventId';
      final jsonStr = prefs.getString(key);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map<String, dynamic>) {
          return AttendeeLocationState.fromJson(decoded);
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _controller.close();
  }
}

