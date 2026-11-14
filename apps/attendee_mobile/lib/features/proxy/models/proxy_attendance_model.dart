import 'package:flutter/foundation.dart';

/// Lifecycle statuses for a proxy attendance session according to ADR 0002.
enum ProxyStatus {
  pending,
  active,
  revoked,
  declined,
  expired;

  static ProxyStatus fromString(String? val) {
    switch (val?.toLowerCase()) {
      case 'active':
        return ProxyStatus.active;
      case 'revoked':
        return ProxyStatus.revoked;
      case 'declined':
        return ProxyStatus.declined;
      case 'expired':
        return ProxyStatus.expired;
      case 'pending':
      default:
        return ProxyStatus.pending;
    }
  }

  String get label {
    switch (this) {
      case ProxyStatus.pending:
        return 'Pending Acceptance';
      case ProxyStatus.active:
        return 'Active';
      case ProxyStatus.revoked:
        return 'Revoked';
      case ProxyStatus.declined:
        return 'Declined';
      case ProxyStatus.expired:
        return 'Expired';
    }
  }
}

/// Represents an authoritative proxy attendance delegation session between two attendees.
@immutable
class ProxyAttendanceSession {
  final String id;
  final String eventId;
  final String requesterUserId;
  final String hostUserId;
  final ProxyStatus status;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? revokedAt;
  final String? revokedBy;

  // Joined presentation data
  final String requesterName;
  final String? requesterAvatarUrl;
  final String hostName;
  final String? hostAvatarUrl;

  const ProxyAttendanceSession({
    required this.id,
    required this.eventId,
    required this.requesterUserId,
    required this.hostUserId,
    required this.status,
    required this.createdAt,
    this.acceptedAt,
    this.revokedAt,
    this.revokedBy,
    this.requesterName = 'Attendee',
    this.requesterAvatarUrl,
    this.hostName = 'Friend',
    this.hostAvatarUrl,
  });

  bool get isPending => status == ProxyStatus.pending;
  bool get isActive => status == ProxyStatus.active;
  bool get isRevoked => status == ProxyStatus.revoked;
  bool get isDeclined => status == ProxyStatus.declined;
  bool get isExpired => status == ProxyStatus.expired;

  factory ProxyAttendanceSession.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic d) {
      if (d == null) return DateTime.now().toUtc();
      if (d is DateTime) return d;
      return DateTime.tryParse(d.toString())?.toUtc() ?? DateTime.now().toUtc();
    }

    // Handle nested requester/host profiles if joined
    final reqProfile = json['requester'] is Map ? Map<String, dynamic>.from(json['requester'] as Map) : null;
    final hostProfile = json['host'] is Map ? Map<String, dynamic>.from(json['host'] as Map) : null;

    return ProxyAttendanceSession(
      id: json['id']?.toString() ?? '',
      eventId: json['event_id']?.toString() ?? '',
      requesterUserId: json['requester_user_id']?.toString() ?? '',
      hostUserId: json['host_user_id']?.toString() ?? '',
      status: ProxyStatus.fromString(json['status']?.toString()),
      createdAt: parseDate(json['created_at']),
      acceptedAt: json['accepted_at'] != null ? parseDate(json['accepted_at']) : null,
      revokedAt: json['revoked_at'] != null ? parseDate(json['revoked_at']) : null,
      revokedBy: json['revoked_by']?.toString(),
      requesterName: reqProfile?['full_name']?.toString() ??
          json['requester_name']?.toString() ??
          'Attendee',
      requesterAvatarUrl: reqProfile?['avatar_url']?.toString() ?? json['requester_avatar_url']?.toString(),
      hostName: hostProfile?['full_name']?.toString() ??
          json['host_name']?.toString() ??
          'Friend',
      hostAvatarUrl: hostProfile?['avatar_url']?.toString() ?? json['host_avatar_url']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'event_id': eventId,
      'requester_user_id': requesterUserId,
      'host_user_id': hostUserId,
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
      'accepted_at': acceptedAt?.toIso8601String(),
      'revoked_at': revokedAt?.toIso8601String(),
      'revoked_by': revokedBy,
    };
  }

  ProxyAttendanceSession copyWith({
    String? id,
    String? eventId,
    String? requesterUserId,
    String? hostUserId,
    ProxyStatus? status,
    DateTime? createdAt,
    DateTime? acceptedAt,
    DateTime? revokedAt,
    String? revokedBy,
    String? requesterName,
    String? requesterAvatarUrl,
    String? hostName,
    String? hostAvatarUrl,
  }) {
    return ProxyAttendanceSession(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      requesterUserId: requesterUserId ?? this.requesterUserId,
      hostUserId: hostUserId ?? this.hostUserId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      revokedAt: revokedAt ?? this.revokedAt,
      revokedBy: revokedBy ?? this.revokedBy,
      requesterName: requesterName ?? this.requesterName,
      requesterAvatarUrl: requesterAvatarUrl ?? this.requesterAvatarUrl,
      hostName: hostName ?? this.hostName,
      hostAvatarUrl: hostAvatarUrl ?? this.hostAvatarUrl,
    );
  }
}

/// Represents an accepted connection who holds a checked-in ticket for the same event
/// and is eligible to be chosen as a Proxy Host.
@immutable
class ProxyEligibleFriend {
  final String userId;
  final String fullName;
  final String? headline;
  final String? avatarUrl;
  final String avatarInitials;
  final bool isCheckedIn;
  final int activeCarriedCount;

  const ProxyEligibleFriend({
    required this.userId,
    required this.fullName,
    this.headline,
    this.avatarUrl,
    required this.avatarInitials,
    required this.isCheckedIn,
    required this.activeCarriedCount,
  });

  /// Host capacity is capped at 2 active proxies (carried weight <= 3).
  bool get canAcceptMore => activeCarriedCount < 2;
}
