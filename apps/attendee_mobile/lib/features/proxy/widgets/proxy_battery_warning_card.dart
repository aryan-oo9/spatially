import 'package:flutter/material.dart';
import '../../../design_system/spatially_colors.dart';
import '../../../design_system/spatially_radius.dart';
import '../../../design_system/spatially_typography.dart';

/// Prominent low-battery warning card rendered proactively on the Attendee Home Screen
/// when device battery drops to <= 15%.
class ProxyBatteryWarningCard extends StatelessWidget {
  final int batteryLevel;
  final VoidCallback onDelegatePressed;
  final VoidCallback? onDismiss;

  const ProxyBatteryWarningCard({
    super.key,
    required this.batteryLevel,
    required this.onDelegatePressed,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textPrimary = isDark ? SpatiallyColors.darkTextPrimary : SpatiallyColors.lightTextPrimary;
    final textSecondary = isDark ? SpatiallyColors.darkTextSecondary : SpatiallyColors.lightTextSecondary;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A1B14) : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(SpatiallyRadius.md),
        border: Border.all(
          color: SpatiallyColors.warning.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: SpatiallyColors.warning.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.battery_alert_rounded,
                  color: SpatiallyColors.warning,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Low Battery Warning ($batteryLevel%)',
                      style: SpatiallyTypography.subheading(color: textPrimary).copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Phone may power off soon',
                      style: SpatiallyTypography.caption(color: SpatiallyColors.warning),
                    ),
                  ],
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: textSecondary,
                  onPressed: onDismiss,
                  tooltip: 'Dismiss alert',
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Don\'t lose your event presence! Delegate your attendance to a friend at this event so you remain checked in while your phone is off.',
            style: SpatiallyTypography.body(color: textSecondary).copyWith(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onDelegatePressed,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text('Delegate Attendance'),
              style: ElevatedButton.styleFrom(
                backgroundColor: SpatiallyColors.warning,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(SpatiallyRadius.sm),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
