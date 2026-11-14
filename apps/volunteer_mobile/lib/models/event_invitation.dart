/// Model representing an invitation sent by an organizer to a volunteer.
class EventInvitation {
  final String id;
  final String eventId;
  final String eventName;
  final String venue;
  final DateTime? eventDate;
  final String eventStatus;
  final String volunteerEmail;
  final String? volunteerId;
  final String status; // 'pending' | 'accepted' | 'declined'
  final String invitedBy;
  final DateTime createdAt;

  const EventInvitation({
    required this.id,
    required this.eventId,
    required this.eventName,
    required this.venue,
    this.eventDate,
    required this.eventStatus,
    required this.volunteerEmail,
    this.volunteerId,
    required this.status,
    required this.invitedBy,
    required this.createdAt,
  });

  factory EventInvitation.fromSupabase(Map<String, dynamic> json) {
    final eventMap = json['events'] as Map<String, dynamic>?;

    DateTime? parseDate(dynamic val) {
      if (val == null) return null;
      return DateTime.tryParse(val.toString())?.toLocal();
    }

    return EventInvitation(
      id: json['id'] as String? ?? '',
      eventId: json['event_id'] as String? ?? '',
      eventName: eventMap?['name'] as String? ?? 'Unnamed Event',
      venue: eventMap?['venue'] as String? ?? 'TBA',
      eventDate: parseDate(eventMap?['event_start_time'] ?? eventMap?['event_date']),
      eventStatus: eventMap?['status'] as String? ?? 'upcoming',
      volunteerEmail: json['volunteer_email'] as String? ?? '',
      volunteerId: json['volunteer_id'] as String?,
      status: json['status'] as String? ?? 'pending',
      invitedBy: json['invited_by'] as String? ?? '',
      createdAt: parseDate(json['created_at']) ?? DateTime.now(),
    );
  }
}

