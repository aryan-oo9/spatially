/// Typed domain model representing an event in the Spatially platform.
/// 
/// Maps directly to the Supabase `events` table with safe fallbacks and
/// helper predicates.
class SpatiallyEvent {
  final String id;
  final String name;
  final String? venueId;
  final String venue;
  final DateTime eventDate;
  final String timezone;
  final String status; // 'live' | 'upcoming' | 'ended'
  final List<String> zones;
  final String description;
  final int capacity;
  final String organizerName;
  final String locationAddress;
  final String? startTime;
  final String? endTime;

  const SpatiallyEvent({
    required this.id,
    required this.name,
    this.venueId,
    this.venue = 'TBA',
    required this.eventDate,
    this.timezone = 'UTC',
    this.status = 'upcoming',
    this.zones = const [],
    this.description = '',
    this.capacity = 0,
    this.organizerName = '',
    this.locationAddress = '',
    this.startTime,
    this.endTime,
  });

  /// Creates a [SpatiallyEvent] from a Supabase row map.
  factory SpatiallyEvent.fromJson(Map<String, dynamic> json) {
    // Parse event date (supporting schema v2.1 event_start_time and legacy event_date)
    DateTime parsedDate;
    final rawDate = json['event_start_time'] ?? json['event_date'] ?? json['start_time'];
    if (rawDate is String) {
      parsedDate = DateTime.tryParse(rawDate)?.toLocal() ?? DateTime.now();
    } else if (rawDate is DateTime) {
      parsedDate = rawDate.toLocal();
    } else {
      parsedDate = DateTime.now();
    }

    // Parse zones array
    List<String> parsedZones = [];
    final rawZones = json['zones'];
    if (rawZones is List) {
      parsedZones = rawZones.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    }

    // Parse capacity
    int parsedCapacity = 0;
    final rawCapacity = json['capacity'];
    if (rawCapacity is int) {
      parsedCapacity = rawCapacity;
    } else if (rawCapacity is String) {
      parsedCapacity = int.tryParse(rawCapacity) ?? 0;
    }

    final venueObj = json['venues'] as Map<String, dynamic>?;
    final venueNameFromObj = venueObj?['name']?.toString();
    final rawVenueStr = json['venue']?.toString();
    final venueName = (venueNameFromObj != null && venueNameFromObj.isNotEmpty)
        ? venueNameFromObj
        : ((rawVenueStr != null && rawVenueStr.isNotEmpty && rawVenueStr != 'TBA')
            ? rawVenueStr
            : 'TBA');
    final locationAddress = venueObj?['address']?.toString() ?? json['location_address']?.toString() ?? '';
    final venueId = json['venue_id']?.toString() ?? venueObj?['id']?.toString();
    final timezone = json['timezone']?.toString() ?? venueObj?['timezone']?.toString() ?? 'UTC';

    return SpatiallyEvent(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unnamed Event',
      venueId: venueId,
      venue: venueName,
      eventDate: parsedDate,
      timezone: timezone,
      status: (json['status']?.toString() ?? 'upcoming').toLowerCase(),
      zones: parsedZones,
      description: json['description']?.toString() ?? '',
      capacity: parsedCapacity,
      organizerName: json['organizer_name']?.toString() ?? '',
      locationAddress: locationAddress,
      startTime: json['event_start_time']?.toString() ?? json['start_time']?.toString(),
      endTime: json['event_end_time']?.toString() ?? json['end_time']?.toString(),
    );
  }

  /// Exports the event to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'venue_id': venueId,
      'venue': venue,
      'event_date': eventDate.toIso8601String(),
      'timezone': timezone,
      'status': status,
      'zones': zones,
      'description': description,
      'capacity': capacity,
      'organizer_name': organizerName,
      'location_address': locationAddress,
      'start_time': startTime,
      'end_time': endTime,
      'event_start_time': startTime,
      'event_end_time': endTime,
      'venues': {
        'id': venueId,
        'name': venue,
        'address': locationAddress,
        'timezone': timezone,
      },
    };
  }

  /// Whether the event is currently active / live.
  bool get isLive => status == 'live';

  /// Whether the event is upcoming.
  bool get isUpcoming => status == 'upcoming';

  /// Whether the event has concluded.
  bool get isEnded => status == 'ended';

  /// Returns location summary prioritizing locationAddress then venue.
  String get fullLocation {
    if (locationAddress.isNotEmpty && locationAddress != venue) {
      return '$venue, $locationAddress';
    }
    return venue;
  }
}
