import 'package:flutter/material.dart';
import '../../../design_system/spatially_colors.dart';
import '../../../design_system/spatially_radius.dart';
import '../../../design_system/spatially_typography.dart';
import '../data/proxy_attendance_repository.dart';
import '../models/proxy_attendance_model.dart';

/// Modal bottom sheet allowing a low-battery attendee to delegate their attendance
/// to an accepted, checked-in friend at the same event.
class ProxyRequestBottomSheet extends StatefulWidget {
  final String eventId;
  final String eventName;
  final ProxyAttendanceRepository repository;
  final VoidCallback? onRequestSubmitted;

  const ProxyRequestBottomSheet({
    super.key,
    required this.eventId,
    required this.eventName,
    required this.repository,
    this.onRequestSubmitted,
  });

  static Future<void> show({
    required BuildContext context,
    required String eventId,
    required String eventName,
    required ProxyAttendanceRepository repository,
    VoidCallback? onRequestSubmitted,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ProxyRequestBottomSheet(
        eventId: eventId,
        eventName: eventName,
        repository: repository,
        onRequestSubmitted: onRequestSubmitted,
      ),
    );
  }

  @override
  State<ProxyRequestBottomSheet> createState() => _ProxyRequestBottomSheetState();
}

class _ProxyRequestBottomSheetState extends State<ProxyRequestBottomSheet> {
  bool _loading = true;
  String? _error;
  List<ProxyEligibleFriend> _friends = [];
  String? _submittingHostId;
  ProxyAttendanceSession? _pendingSession;

  @override
  void initState() {
    super.initState();
    _loadEligibleFriends();
  }

  Future<void> _loadEligibleFriends() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final existingPending = await widget.repository.getPendingSessionForRequester(widget.eventId);
      if (existingPending != null) {
        if (mounted) {
          setState(() {
            _pendingSession = existingPending;
            _loading = false;
          });
        }
        return;
      }

      final friends = await widget.repository.getEligibleFriends(widget.eventId);
      if (mounted) {
        setState(() {
          _friends = friends;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load eligible friends ($e)';
          _loading = false;
        });
      }
    }
  }

  Future<void> _submitProxyRequest(ProxyEligibleFriend friend) async {
    setState(() {
      _submittingHostId = friend.userId;
    });

    try {
      final session = await widget.repository.submitRequest(
        eventId: widget.eventId,
        hostUserId: friend.userId,
      );

      if (mounted) {
        setState(() {
          _pendingSession = session.copyWith(hostName: friend.fullName);
          _submittingHostId = null;
        });
        widget.onRequestSubmitted?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submittingHostId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not send proxy request: $e'),
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
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(SpatiallyRadius.xl)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag Handle
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

              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: SpatiallyColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(SpatiallyRadius.sm),
                    ),
                    child: const Icon(
                      Icons.battery_alert_rounded,
                      color: SpatiallyColors.warning,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Delegate Attendance',
                          style: SpatiallyTypography.subheading(color: textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Ensure your presence is counted if your battery dies',
                          style: SpatiallyTypography.caption(color: textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Body content
              if (_pendingSession != null)
                _buildPendingState(textPrimary, textSecondary, isDark)
              else if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: CircularProgressIndicator(color: SpatiallyColors.violet),
                  ),
                )
              else if (_error != null)
                _buildErrorState(textPrimary, textSecondary)
              else if (_friends.isEmpty)
                _buildEmptyFriendsState(textPrimary, textSecondary)
              else
                _buildFriendList(textPrimary, textSecondary, isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingState(Color textPrimary, Color textSecondary, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SpatiallyColors.violet.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(SpatiallyRadius.md),
        border: Border.all(color: SpatiallyColors.violet.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.hourglass_top_rounded,
            color: SpatiallyColors.violet,
            size: 40,
          ),
          const SizedBox(height: 12),
          Text(
            'Proxy Request Sent!',
            style: SpatiallyTypography.subheading(color: textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            'Awaiting acceptance from ${_pendingSession!.hostName}.\nOnce accepted, your friend will represent your presence with a carried weight of 2.',
            textAlign: TextAlign.center,
            style: SpatiallyTypography.body(color: textSecondary).copyWith(height: 1.4),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(SpatiallyRadius.md),
                ),
              ),
              child: Text(
                'Close',
                style: SpatiallyTypography.button(color: textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendList(Color textPrimary, Color textSecondary, bool isDark) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SELECT A CHECKED-IN FRIEND',
            style: SpatiallyTypography.badge(color: textSecondary).copyWith(letterSpacing: 0.8),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: _friends.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final friend = _friends[index];
                final isSubmitting = _submittingHostId == friend.userId;
                final canAccept = friend.canAcceptMore;

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(SpatiallyRadius.md),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: SpatiallyColors.violet.withValues(alpha: 0.2),
                        child: Text(
                          friend.avatarInitials,
                          style: SpatiallyTypography.subheading(color: SpatiallyColors.violet),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              friend.fullName,
                              style: SpatiallyTypography.subheading(color: textPrimary),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: SpatiallyColors.success,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  canAccept
                                      ? (friend.activeCarriedCount == 0 ? 'Checked-In' : 'Carrying 1/2')
                                      : 'Max Capacity (2/2)',
                                  style: SpatiallyTypography.caption(
                                    color: canAccept ? SpatiallyColors.success : SpatiallyColors.warning,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: (!canAccept || isSubmitting) ? null : () => _submitProxyRequest(friend),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SpatiallyColors.violet,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(SpatiallyRadius.sm),
                          ),
                        ),
                        child: isSubmitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Delegate'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyFriendsState(Color textPrimary, Color textSecondary) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Center(
        child: Column(
          children: [
            const Icon(
              Icons.people_outline_rounded,
              size: 48,
              color: SpatiallyColors.darkTextTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              'No Eligible Friends Found',
              style: SpatiallyTypography.subheading(color: textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              'To delegate attendance, connect with a friend at this event who has also checked in.',
              textAlign: TextAlign.center,
              style: SpatiallyTypography.caption(color: textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(Color textPrimary, Color textSecondary) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: SpatiallyColors.error, size: 40),
            const SizedBox(height: 8),
            Text(_error ?? 'Unknown error', style: SpatiallyTypography.body(color: textSecondary)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _loadEligibleFriends,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
