import 'package:flutter/material.dart';
import '../../../design_system/spatially_colors.dart';
import '../../../design_system/spatially_radius.dart';
import '../../../design_system/spatially_typography.dart';
import '../data/proxy_attendance_repository.dart';
import '../models/proxy_attendance_model.dart';

/// Rendered on the Home Screen when the attendee's presence is delegated to a host.
/// Allows the attendee to immediately reclaim their independent attendance once their phone is powered back on.
class ProxyReclaimBanner extends StatefulWidget {
  final ProxyAttendanceSession activeSession;
  final ProxyAttendanceRepository repository;
  final VoidCallback? onReclaimed;

  const ProxyReclaimBanner({
    super.key,
    required this.activeSession,
    required this.repository,
    this.onReclaimed,
  });

  @override
  State<ProxyReclaimBanner> createState() => _ProxyReclaimBannerState();
}

class _ProxyReclaimBannerState extends State<ProxyReclaimBanner> {
  bool _reclaiming = false;

  Future<void> _reclaimAttendance() async {
    setState(() {
      _reclaiming = true;
    });

    try {
      await widget.repository.revokeSession(sessionId: widget.activeSession.id);
      if (mounted) {
        widget.onReclaimed?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Attendance reclaimed! Your phone is now actively recording your presence.'),
            backgroundColor: SpatiallyColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _reclaiming = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not reclaim attendance: $e'),
            backgroundColor: SpatiallyColors.error,
          ),
        );
      }
    }
  }

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
        color: SpatiallyColors.warning.withValues(alpha: 0.12),
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
                  Icons.battery_charging_full_rounded,
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
                      'Attendance Delegated',
                      style: SpatiallyTypography.subheading(color: textPrimary).copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Carried by ${widget.activeSession.hostName}',
                      style: SpatiallyTypography.caption(color: textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Your event presence is currently being maintained by your friend. Now that your phone is powered back on, tap below to reclaim your active attendance.',
            style: SpatiallyTypography.body(color: textSecondary).copyWith(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _reclaiming ? null : _reclaimAttendance,
              icon: _reclaiming
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.restore_rounded, size: 18),
              label: const Text('Reclaim My Attendance'),
              style: ElevatedButton.styleFrom(
                backgroundColor: SpatiallyColors.violet,
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
