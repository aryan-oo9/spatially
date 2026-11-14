import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/volunteer_assignment.dart';
import '../models/event_invitation.dart';
import '../repositories/volunteer_assignment_repository.dart';
import '../services/session_state.dart';

/// Shown after login (and battery check), before ZoneSelectionScreen.
/// Displays pending event invitations for the volunteer with Accept/Decline actions,
/// as well as active event assignments.
class EventPickerScreen extends StatefulWidget {
  final VolunteerAssignmentRepository? assignmentRepository;

  const EventPickerScreen({super.key, this.assignmentRepository});

  @override
  State<EventPickerScreen> createState() => _EventPickerScreenState();
}

class _EventPickerScreenState extends State<EventPickerScreen> {
  late final VolunteerAssignmentRepository _assignmentRepo;
  late Future<List<dynamic>> _dataFuture;
  final Set<String> _processingInvites = {};

  @override
  void initState() {
    super.initState();
    _assignmentRepo = widget.assignmentRepository ?? VolunteerAssignmentRepositoryImpl();
    _loadData();
  }

  void _loadData() {
    String? volunteerId = SessionState.instance.volunteerId;
    String? userEmail;
    try {
      volunteerId ??= Supabase.instance.client.auth.currentUser?.id;
      userEmail = Supabase.instance.client.auth.currentUser?.email;
    } catch (_) {}

    if (volunteerId != null) {
      _dataFuture = Future.wait([
        _assignmentRepo.getAssignments(volunteerId),
        _assignmentRepo.getPendingInvitations(volunteerId: volunteerId, email: userEmail),
      ]);
    } else {
      _dataFuture = Future.value([<VolunteerAssignment>[], <EventInvitation>[]]);
    }
  }

  void _reloadAssignments() {
    setState(() {
      _loadData();
    });
  }

  Future<void> _signOut() async {
    await SessionState.instance.clear();
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
  }

  Future<void> _handleAcceptInvitation(EventInvitation invitation) async {
    setState(() => _processingInvites.add(invitation.id));
    try {
      await _assignmentRepo.acceptInvitation(invitation);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Accepted invitation to "${invitation.eventName}"!'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
      _reloadAssignments();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to accept invitation: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processingInvites.remove(invitation.id));
      }
    }
  }

  Future<void> _handleDeclineInvitation(EventInvitation invitation) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline Invitation?'),
        content: Text('Are you sure you want to decline the invitation to "${invitation.eventName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Decline', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _processingInvites.add(invitation.id));
    try {
      await _assignmentRepo.declineInvitation(invitation.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invitation declined.')),
        );
      }
      _reloadAssignments();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to decline invitation: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processingInvites.remove(invitation.id));
      }
    }
  }

  Future<void> _selectEvent(VolunteerAssignment assignment) async {
    SessionState.instance.eventId = assignment.eventId;
    SessionState.instance.eventName = assignment.eventName;

    if (assignment.zoneId != null && assignment.zoneName != null) {
      await SessionState.instance.persistShift(
        newEventId: assignment.eventId,
        newZoneId: assignment.zoneId,
        newZoneName: assignment.zoneName!,
        newZoneCode: assignment.zoneCode,
        newEventName: assignment.eventName,
        isRoving: false,
        capacityLimit: assignment.capacityLimit,
      );
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/scan');
      }
    } else {
      await SessionState.instance.persistShift(
        newEventId: assignment.eventId,
        newZoneId: null,
        newZoneName: null,
        newZoneCode: null,
        newEventName: assignment.eventName,
        isRoving: true,
      );
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/zone_selection');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Spatially ',
                style: GoogleFonts.audiowide(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextSpan(
                text: 'for Volunteer',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh assignments and invitations',
            onPressed: _reloadAssignments,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: _signOut,
          ),
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wifi_off_rounded, size: 56, color: Colors.amber[700]),
                    const SizedBox(height: 16),
                    Text(
                      'Connection Issue',
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Unable to load your volunteer assignments. Please check your network connection and try again.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _reloadAssignments,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final assignments = (snapshot.data?[0] as List<VolunteerAssignment>?) ?? [];
          final invitations = (snapshot.data?[1] as List<EventInvitation>?) ?? [];

          if (assignments.isEmpty && invitations.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_busy_rounded, size: 56, color: Colors.blueGrey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      'No Active Assignments',
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No active assignments or pending invitations were found for your account.\nPlease contact your event coordinator to be assigned.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: _reloadAssignments,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Check for Updates'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            children: [
              // ─────────────────────────────────────────────
              // 1. PENDING INVITATIONS SECTION
              // ─────────────────────────────────────────────
              if (invitations.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 10.0, top: 2.0),
                  child: Row(
                    children: [
                      const Icon(Icons.mail_outline_rounded, size: 19, color: Colors.amber),
                      const SizedBox(width: 8),
                      Text(
                        'Pending Invitations (${invitations.length})',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
                ...invitations.map((inv) {
                  final isBusy = _processingInvites.contains(inv.id);
                  String formattedDate = 'Upcoming';
                  if (inv.eventDate != null) {
                    final d = inv.eventDate!;
                    formattedDate = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.amber.shade300, width: 1.5),
                    ),
                    color: Colors.amber.shade50.withValues(alpha: 0.4),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  inv.eventName,
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.amber.shade400),
                                ),
                                child: Text(
                                  'INVITE',
                                  style: TextStyle(
                                    color: Colors.amber.shade900,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.location_on_outlined, size: 14, color: Colors.grey.shade700),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${inv.venue} • $formattedDate',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                                ),
                              ),
                            ],
                          ),
                          if (inv.invitedBy.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Invited by Event Coordinator',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal.shade700,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                  onPressed: isBusy ? null : () => _handleAcceptInvitation(inv),
                                  icon: isBusy
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Icon(Icons.check_circle_outline, size: 18),
                                  label: Text(
                                    isBusy ? 'Accepting...' : 'Accept & Join',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red.shade700,
                                  side: BorderSide(color: Colors.red.shade300),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                                ),
                                onPressed: isBusy ? null : () => _handleDeclineInvitation(inv),
                                child: const Text('Decline', style: TextStyle(fontSize: 13)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 14),
              ],

              // ─────────────────────────────────────────────
              // 2. ACTIVE ASSIGNMENTS SECTION
              // ─────────────────────────────────────────────
              if (assignments.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 10.0, top: 4.0),
                  child: Row(
                    children: [
                      const Icon(Icons.event_available_rounded, size: 19, color: Colors.teal),
                      const SizedBox(width: 8),
                      Text(
                        'Active Event Assignments (${assignments.length})',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
                ...assignments.map((assignment) {
                  final eventName = assignment.eventName;
                  final venue = assignment.venue;
                  final status = assignment.eventStatus;

                  String formattedDate = 'Unknown Date';
                  if (assignment.eventDate != null) {
                    final parsed = assignment.eventDate!;
                    final month = parsed.month.toString().padLeft(2, '0');
                    final day = parsed.day.toString().padLeft(2, '0');
                    final hour = parsed.hour.toString().padLeft(2, '0');
                    final minute = parsed.minute.toString().padLeft(2, '0');
                    formattedDate = '${parsed.year}-$month-$day $hour:$minute';
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _selectEvent(assignment),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    eventName,
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: status == 'live' ? Colors.green.shade50 : Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: status == 'live' ? Colors.green.shade300 : Colors.blue.shade300,
                                    ),
                                  ),
                                  child: Text(
                                    status.toUpperCase(),
                                    style: TextStyle(
                                      color: status == 'live' ? Colors.green.shade800 : Colors.blue.shade800,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.location_on_outlined, size: 14, color: Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '$venue • $formattedDate',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: assignment.isRoving ? Colors.purple.shade50 : Colors.teal.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    assignment.isRoving ? Icons.directions_walk : Icons.pin_drop,
                                    size: 14,
                                    color: assignment.isRoving ? Colors.purple.shade700 : Colors.teal.shade700,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    assignment.isRoving
                                        ? 'Roving Assignment • All Event Zones'
                                        : 'Station: ${assignment.zoneName} (${assignment.zoneCode ?? "Zone"})',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: assignment.isRoving ? Colors.purple.shade800 : Colors.teal.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ],
          );
        },
      ),
    );
  }
}
