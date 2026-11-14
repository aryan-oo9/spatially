import 'package:flutter/material.dart';
import '../../../design_system/design_system.dart';
import '../../map/models/attendee_location_models.dart';

/// Contextual, real-time "Current Location" card for registered attendees on the Home screen.
///
/// Communicates indoor spatial presence honestly:
/// - [AttendeeLocationStatus.detected]: Green/Cyan active indicator, room name, floor, crowd status.
/// - [AttendeeLocationStatus.stale]: Subdued indicator, relative time since last sighting.
/// - [AttendeeLocationStatus.manual]: Indication of manual pin with ability to clear.
/// - [AttendeeLocationStatus.locating]: Pulse animation searching for beacons.
/// - [AttendeeLocationStatus.unknown]: Prompt to enable Bluetooth or manually select zone.
class HomeCurrentZoneCard extends StatelessWidget {
  final AttendeeLocationState locationState;
  final VoidCallback? onViewOnMap;
  final VoidCallback? onChangeZone;

  const HomeCurrentZoneCard({
    super.key,
    required this.locationState,
    this.onViewOnMap,
    this.onChangeZone,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? SpatiallyColors.darkSurface : SpatiallyColors.lightSurface;
    final border =
        isDark ? SpatiallyColors.darkBorderSubdued : SpatiallyColors.lightBorderSubdued;
    final textPrimary =
        isDark ? SpatiallyColors.darkTextPrimary : SpatiallyColors.lightTextPrimary;
    final textSecondary =
        isDark ? SpatiallyColors.darkTextSecondary : SpatiallyColors.lightTextSecondary;

    final hasLocation = locationState.hasLocation;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: SpatiallyRadius.borderMd,
        border: Border.all(
          color: hasLocation
              ? SpatiallyColors.spatialCyan.withValues(alpha: 0.35)
              : border,
        ),
        boxShadow: SpatiallyShadows.cardShadow(isDark: isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Header Row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                // Glowing Pin / Radar Icon
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: hasLocation
                        ? SpatiallyColors.spatialCyan.withValues(alpha: 0.14)
                        : (isDark ? const Color(0xFF222230) : const Color(0xFFF1F5F9)),
                    borderRadius: SpatiallyRadius.borderXs,
                  ),
                  child: Icon(
                    hasLocation ? Icons.my_location_rounded : Icons.location_searching_rounded,
                    size: 17,
                    color: hasLocation
                        ? SpatiallyColors.spatialCyan
                        : textSecondary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CURRENT LOCATION',
                        style: SpatiallyTypography.caption(
                          color: hasLocation ? SpatiallyColors.spatialCyan : textSecondary,
                        ).copyWith(letterSpacing: 0.8, fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasLocation
                            ? (locationState.zoneName ?? 'Event Zone')
                            : (locationState.status == AttendeeLocationStatus.locating
                                ? 'Locating your zone…'
                                : 'Zone Not Detected'),
                        style: SpatiallyTypography.subheading(
                          color: textPrimary,
                        ).copyWith(fontSize: 15, fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Floor level badge or status pill
                if (hasLocation && locationState.levelName != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF232336) : const Color(0xFFF1F5F9),
                      borderRadius: SpatiallyRadius.borderXs,
                      border: Border.all(color: border),
                    ),
                    child: Text(
                      locationState.levelName!,
                      style: SpatiallyTypography.badge(color: textPrimary).copyWith(fontSize: 10.5),
                    ),
                  ),
                ] else ...[
                  _buildStatusPill(isDark),
                ],
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Middle Row: Crowd state & telemetry freshness
          if (hasLocation) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  // Crowd level pill
                  SpatiallyCrowdIndicator(
                    level: locationState.crowdLevel,
                    compact: true,
                  ),
                  if (locationState.activeHeadcount != null && locationState.activeHeadcount! > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      '· ${locationState.activeHeadcount} people',
                      style: SpatiallyTypography.secondary(color: textSecondary).copyWith(fontSize: 11.5),
                    ),
                  ],
                  const Spacer(),

                  // Telemetry source / relative freshness
                  Icon(
                    locationState.isManual ? Icons.edit_location_alt_rounded : Icons.sensors_rounded,
                    size: 13,
                    color: locationState.isStale ? SpatiallyColors.warning : textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    locationState.relativeFreshness,
                    style: SpatiallyTypography.secondary(
                      color: locationState.isStale ? SpatiallyColors.warning : textSecondary,
                    ).copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Spatial beacons are scanning for your phone nearby. You can also pick your zone manually.',
                style: SpatiallyTypography.secondary(color: textSecondary).copyWith(fontSize: 12),
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Divider
          Divider(height: 1, color: border),

          // Bottom Action Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Change Zone action
                TextButton.icon(
                  onPressed: onChangeZone,
                  icon: Icon(
                    locationState.isManual ? Icons.refresh_rounded : Icons.swap_horiz_rounded,
                    size: 16,
                    color: textSecondary,
                  ),
                  label: Text(
                    locationState.isManual ? 'Reset Auto-Detect' : 'Select Zone',
                    style: SpatiallyTypography.caption(color: textSecondary).copyWith(fontWeight: FontWeight.w600),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),

                // View on Map action
                TextButton.icon(
                  onPressed: onViewOnMap,
                  icon: const Icon(
                    Icons.map_outlined,
                    size: 16,
                    color: SpatiallyColors.violet,
                  ),
                  label: Text(
                    'View on Map',
                    style: SpatiallyTypography.caption(color: SpatiallyColors.violet).copyWith(fontWeight: FontWeight.w600),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill(bool isDark) {
    String label;
    Color color;

    switch (locationState.status) {
      case AttendeeLocationStatus.detected:
        label = 'LIVE';
        color = SpatiallyColors.spatialCyan;
        break;
      case AttendeeLocationStatus.manual:
        label = 'PINNED';
        color = SpatiallyColors.violet;
        break;
      case AttendeeLocationStatus.stale:
        label = 'STALE';
        color = SpatiallyColors.warning;
        break;
      case AttendeeLocationStatus.locating:
        label = 'SCANNING';
        color = SpatiallyColors.spatialCyan;
        break;
      case AttendeeLocationStatus.unknown:
        label = 'STANDBY';
        color = isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: SpatiallyRadius.borderXs,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: color,
        ),
      ),
    );
  }
}
