import 'package:flutter/material.dart';
import '../../../design_system/spatially_colors.dart';
import '../../../design_system/spatially_radius.dart';
import '../../../design_system/spatially_typography.dart';
import '../data/proxy_attendance_repository.dart';
import '../models/proxy_attendance_model.dart';

/// Renders an active carrying badge on the Host's screen:
/// "👥 Carrying: [Name] (+1 Attendee)"
/// Tapping opens a management sheet allowing the host to tap "Release Proxy" at any time.
class ProxyCarryingBadge extends StatelessWidget {
  final List<ProxyAttendanceSession> activeSessions;
  final ProxyAttendanceRepository repository;
  final VoidCallback? onSessionRevoked;

  const ProxyCarryingBadge({
    super.key,
    required this.activeSessions,
    required this.repository,
    this.onSessionRevoked,
  });

  void _showManagementSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ProxyHostManagementSheet(
        activeSessions: activeSessions,
        repository: repository,
        onSessionRevoked: onSessionRevoked,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (activeSessions.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final totalCarried = activeSessions.length;
    final names = activeSessions.map((s) => s.requesterName).join(', ');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: SpatiallyColors.violet.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(SpatiallyRadius.md),
        border: Border.all(
          color: SpatiallyColors.violet.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showManagementSheet(context),
          borderRadius: BorderRadius.circular(SpatiallyRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: SpatiallyColors.violet.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.groups_rounded,
                    color: SpatiallyColors.violet,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Carrying Proxy Presence',
                            style: SpatiallyTypography.subheading(
                              color: isDark ? SpatiallyColors.darkTextPrimary : SpatiallyColors.lightTextPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: SpatiallyColors.violet,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '+$totalCarried',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Carrying: $names (Total Weight: ${1 + totalCarried})',
                        style: SpatiallyTypography.caption(
                          color: isDark ? SpatiallyColors.darkTextSecondary : SpatiallyColors.lightTextSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Manage',
                  style: SpatiallyTypography.button(color: SpatiallyColors.violet).copyWith(fontSize: 13),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: SpatiallyColors.violet,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProxyHostManagementSheet extends StatefulWidget {
  final List<ProxyAttendanceSession> activeSessions;
  final ProxyAttendanceRepository repository;
  final VoidCallback? onSessionRevoked;

  const _ProxyHostManagementSheet({
    required this.activeSessions,
    required this.repository,
    this.onSessionRevoked,
  });

  @override
  State<_ProxyHostManagementSheet> createState() => _ProxyHostManagementSheetState();
}

class _ProxyHostManagementSheetState extends State<_ProxyHostManagementSheet> {
  String? _revokingSessionId;

  Future<void> _releaseProxy(ProxyAttendanceSession session) async {
    setState(() {
      _revokingSessionId = session.id;
    });

    try {
      await widget.repository.revokeSession(sessionId: session.id);
      if (mounted) {
        widget.onSessionRevoked?.call();
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Released attendance delegation for ${session.requesterName}.'),
            backgroundColor: SpatiallyColors.darkSurface,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _revokingSessionId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not release proxy: $e'),
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

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(SpatiallyRadius.xl)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Active Proxy Delegations',
                style: SpatiallyTypography.subheading(color: textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                'You are currently carrying attendance for the following attendees. You can release delegation whenever you part ways.',
                style: SpatiallyTypography.caption(color: textSecondary),
              ),
              const SizedBox(height: 16),
              ...widget.activeSessions.map((session) {
                final isRevoking = _revokingSessionId == session.id;
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(SpatiallyRadius.md),
                    border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: SpatiallyColors.violet.withValues(alpha: 0.2),
                        child: Text(
                          session.requesterName.isNotEmpty ? session.requesterName[0].toUpperCase() : 'A',
                          style: SpatiallyTypography.subheading(color: SpatiallyColors.violet),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session.requesterName,
                              style: SpatiallyTypography.subheading(color: textPrimary),
                            ),
                            Text(
                              'Weight +1 • Active presence',
                              style: SpatiallyTypography.caption(color: SpatiallyColors.success),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton(
                        onPressed: isRevoking ? null : () => _releaseProxy(session),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: SpatiallyColors.error,
                          side: const BorderSide(color: SpatiallyColors.error),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(SpatiallyRadius.sm),
                          ),
                        ),
                        child: isRevoking
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: SpatiallyColors.error,
                                ),
                              )
                            : const Text('Release Proxy'),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
