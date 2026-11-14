import 'package:flutter/foundation.dart';
import '../../../design_system/components/spatially_crowd_indicator.dart';

/// The detection status of the registered attendee's physical location.
enum AttendeeLocationStatus {
  /// Actively resolving or awaiting telemetry from nearby scanners.
  locating,

  /// High-confidence automatic sighting from volunteer proximity telemetry (< 3 minutes old).
  detected,

  /// Automatic sighting is between 3 and 5 minutes old; location may be stale.
  stale,

  /// Pinned manually by the attendee or via entrance QR code scan.
  manual,

  /// No telemetry sightings within 5 minutes and no manual pin set.
  unknown,
}

/// Real-time indoor location and contextual presence state for a registered attendee.
@immutable
class AttendeeLocationState {
  final AttendeeLocationStatus status;
  final String? zoneId;
  final String? zoneCode;
  final String? zoneName;
  final String? levelId;
  final String? levelName;
  final int? floorLevel;
  final int? activeHeadcount;
  final SpatiallyCrowdLevel crowdLevel;
  final DateTime? lastSeen;
  final int? rssi;
  final String? errorMessage;

  const AttendeeLocationState({
    required this.status,
    this.zoneId,
    this.zoneCode,
    this.zoneName,
    this.levelId,
    this.levelName,
    this.floorLevel,
    this.activeHeadcount,
    this.crowdLevel = SpatiallyCrowdLevel.low,
    this.lastSeen,
    this.rssi,
    this.errorMessage,
  });

  /// Initial or unlocalized state.
  factory AttendeeLocationState.unknown() => const AttendeeLocationState(
        status: AttendeeLocationStatus.unknown,
      );

  /// Active locating state.
  factory AttendeeLocationState.locating({String? previousZoneName}) =>
      AttendeeLocationState(
        status: AttendeeLocationStatus.locating,
        zoneName: previousZoneName,
      );

  bool get hasLocation =>
      zoneId != null &&
      zoneId!.isNotEmpty &&
      (status == AttendeeLocationStatus.detected ||
          status == AttendeeLocationStatus.stale ||
          status == AttendeeLocationStatus.manual);

  bool get isAutoDetected =>
      status == AttendeeLocationStatus.detected ||
      status == AttendeeLocationStatus.stale;

  bool get isStale => status == AttendeeLocationStatus.stale;
  bool get isManual => status == AttendeeLocationStatus.manual;

  /// Human-readable relative freshness string (e.g., "Just now", "45s ago", "2m ago").
  String get relativeFreshness {
    if (status == AttendeeLocationStatus.manual) {
      return 'Manually selected';
    }
    if (lastSeen == null) {
      return 'Unknown';
    }
    final diff = DateTime.now().difference(lastSeen!);
    if (diff.inSeconds < 30) {
      return 'Just now';
    } else if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s ago';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else {
      return '${diff.inHours}h ago';
    }
  }

  AttendeeLocationState copyWith({
    AttendeeLocationStatus? status,
    String? zoneId,
    String? zoneCode,
    String? zoneName,
    String? levelId,
    String? levelName,
    int? floorLevel,
    int? activeHeadcount,
    SpatiallyCrowdLevel? crowdLevel,
    DateTime? lastSeen,
    int? rssi,
    String? errorMessage,
  }) {
    return AttendeeLocationState(
      status: status ?? this.status,
      zoneId: zoneId ?? this.zoneId,
      zoneCode: zoneCode ?? this.zoneCode,
      zoneName: zoneName ?? this.zoneName,
      levelId: levelId ?? this.levelId,
      levelName: levelName ?? this.levelName,
      floorLevel: floorLevel ?? this.floorLevel,
      activeHeadcount: activeHeadcount ?? this.activeHeadcount,
      crowdLevel: crowdLevel ?? this.crowdLevel,
      lastSeen: lastSeen ?? this.lastSeen,
      rssi: rssi ?? this.rssi,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  Map<String, dynamic> toJson() => {
        'status': status.name,
        'zone_id': zoneId,
        'zone_code': zoneCode,
        'zone_name': zoneName,
        'level_id': levelId,
        'level_name': levelName,
        'floor_level': floorLevel,
        'active_headcount': activeHeadcount,
        'crowd_level': crowdLevel.name,
        'last_seen': lastSeen?.toIso8601String(),
        'rssi': rssi,
        'error_message': errorMessage,
      };

  factory AttendeeLocationState.fromJson(Map<String, dynamic> json) {
    return AttendeeLocationState(
      status: AttendeeLocationStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => AttendeeLocationStatus.unknown,
      ),
      zoneId: json['zone_id']?.toString(),
      zoneCode: json['zone_code']?.toString(),
      zoneName: json['zone_name']?.toString(),
      levelId: json['level_id']?.toString(),
      levelName: json['level_name']?.toString(),
      floorLevel: (json['floor_level'] as num?)?.toInt(),
      activeHeadcount: (json['active_headcount'] as num?)?.toInt(),
      crowdLevel: SpatiallyCrowdLevel.values.firstWhere(
        (e) => e.name == json['crowd_level'],
        orElse: () => SpatiallyCrowdLevel.low,
      ),
      lastSeen: json['last_seen'] != null
          ? DateTime.tryParse(json['last_seen'].toString())
          : null,
      rssi: (json['rssi'] as num?)?.toInt(),
      errorMessage: json['error_message']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttendeeLocationState &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          zoneId == other.zoneId &&
          zoneCode == other.zoneCode &&
          levelId == other.levelId &&
          crowdLevel == other.crowdLevel &&
          lastSeen == other.lastSeen;

  @override
  int get hashCode =>
      status.hashCode ^
      zoneId.hashCode ^
      zoneCode.hashCode ^
      levelId.hashCode ^
      crowdLevel.hashCode ^
      lastSeen.hashCode;
}

