import '../models/attendee_location_models.dart';

/// Contract for registered attendee indoor spatial localization and telemetry loopback.
abstract class AttendeeLocationRepository {
  /// Stream of location updates for the given active event.
  Stream<AttendeeLocationState> watchLocation(String eventId);

  /// Synchronously or on-demand resolves the current location for the given event.
  Future<AttendeeLocationState> getLocation(String eventId);

  /// Manually pins the attendee to a specific event zone (user override or QR scan).
  Future<void> setManualZone(
    String eventId,
    String zoneId, {
    String? zoneName,
    String? zoneCode,
    String? levelId,
    String? levelName,
    int? floorLevel,
  });

  /// Clears any manual pin, reverting back to automatic telemetry resolution.
  Future<void> clearManualZone(String eventId);

  /// Releases stream subscriptions and background timers.
  void dispose();
}

