import 'package:flutter/material.dart';
import '../../../design_system/spatially_colors.dart';
import '../../../design_system/spatially_radius.dart';
import '../../../design_system/spatially_typography.dart';
import '../data/proxy_attendance_repository.dart';
import '../models/proxy_attendance_model.dart';

/// Modal dialog / bottom sheet displayed to a Host when an incoming proxy attendance request is received.
class ProxyHostRequestDialog extends StatefulWidget {
  final ProxyAttendanceSession session;
  final ProxyAttendanceRepository repository;
  final VoidCallback? onHandled;

  const ProxyHostRequestDialog({
    super.key,
    required this.session,
    required this.repository,
    this.onHandled,
  });

  static Future<bool?> show({
    required BuildContext context,
    required ProxyAttendanceSession session,
    required ProxyAttendanceRepository repository,
    VoidCallback? onHandled,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ProxyHostRequestDialog(
        session: session,
        repository: repository,
        onHandled: onHandled,
      ),
    );
  }

  @override
  State<ProxyHostRequestDialog> createState() => _ProxyHostRequestDialogState();
}

class _ProxyHostRequestDialogState extends State<ProxyHostRequestDialog> {
  bool _submitting = false;

  Future<void> _respond(bool accept) async {
    setState(() {
      _submitting = true;
    });

    try {
      await widget.repository.respondToRequest(
        sessionId: widget.session.id,
        accept: accept,
      );

      if (mounted) {
        widget.onHandled?.call();
        Navigator.of(context).pop(accept);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accept
                  ? 'Accepted! You are now carrying attendance for ${widget.session.requesterName}.'
                  : 'Declined proxy attendance request.',
            ),
            backgroundColor: accept ? SpatiallyColors.success : SpatiallyColors.darkSurface,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to process response: $e'),
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
    final surface = isDark ? SpatiallyColors.darkSurface : SpatiallyColors.lightSurface;
    final textPrimary = isDark ? SpatiallyColors.darkTextPrimary : SpatiallyColors.lightTextPrimary;
    final textSecondary = isDark ? SpatiallyColors.darkTextSecondary : SpatiallyColors.lightTextSecondary;

    final requesterName = widget.session.requesterName;
    final initials = requesterName.isNotEmpty
        ? requesterName.split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join()
        : 'A';

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(SpatiallyRadius.xl)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Requester Avatar with Proxy Badge
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: SpatiallyColors.violet.withValues(alpha: 0.2),
                    child: Text(
                      initials,
                      style: SpatiallyTypography.sectionHeading(color: SpatiallyColors.violet),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: SpatiallyColors.warning,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.battery_alert_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              Text(
                'Proxy Attendance Request',
                style: SpatiallyTypography.subheading(color: textPrimary),
              ),

              const SizedBox(height: 8),

              Text(
                '$requesterName\'s phone battery is discharging. They requested you to carry their event presence so their check-in remains active.',
                textAlign: TextAlign.center,
                style: SpatiallyTypography.body(color: textSecondary).copyWith(height: 1.4),
              ),

              const SizedBox(height: 16),

              // Information card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: SpatiallyColors.violet.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(SpatiallyRadius.md),
                  border: Border.all(
                    color: SpatiallyColors.violet.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.people_alt_rounded,
                      color: SpatiallyColors.violet,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Presence Multiplier (+1)',
                            style: SpatiallyTypography.subheading(color: textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Your device will count as 2 attendees in crowd telemetry while together.',
                            style: SpatiallyTypography.caption(color: textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting ? null : () => _respond(false),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(SpatiallyRadius.md),
                        ),
                      ),
                      child: Text(
                        'Decline',
                        style: SpatiallyTypography.button(color: textSecondary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : () => _respond(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SpatiallyColors.violet,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(SpatiallyRadius.md),
                        ),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Accept Delegation'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
