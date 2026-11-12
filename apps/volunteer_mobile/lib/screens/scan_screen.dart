import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:app_settings/app_settings.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/operational_message.dart' hide OperationalPriority;
import '../services/ble_scanner_service.dart';
import '../services/session_state.dart';
import '../services/observation_queue.dart';
import '../services/telemetry_service.dart';
import '../repositories/volunteer_assignment_repository.dart';
import '../repositories/operational_communication_repository.dart';
import '../main.dart';
import 'qr_scanner_screen.dart';
import 'communications_center_screen.dart';
import 'report_issue_dialog.dart';
import 'incidents_list_screen.dart';
import 'lost_found_operations_screen.dart';
import '../repositories/team_shift_repository.dart';
import '../models/volunteer_shift.dart';
import 'shift_overview_screen.dart';
import 'team_overview_screen.dart';
import 'supervisor_tasks_screen.dart';
import '../models/operational_awareness_item.dart';
import '../services/event_awareness_service.dart';
import 'event_awareness_feed_screen.dart';
import 'incident_detail_screen.dart';
import 'operational_health_screen.dart';

class CrowdDensityInfo {
  final String label;
  final Color color;
  final Color bgColor;
  final double ratio;

  const CrowdDensityInfo({
    required this.label,
    required this.color,
    required this.bgColor,
    required this.ratio,
  });
}

class ScanScreen extends StatefulWidget {
  final VolunteerAssignmentRepository? assignmentRepository;
  final OperationalCommunicationRepository? commsRepository;

  const ScanScreen({
    super.key,
    this.assignmentRepository,
    this.commsRepository,
  });

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver {
  late final VolunteerAssignmentRepository _assignmentRepo;
  final BleScannerService _scanner = BleScannerService();

  StreamSubscription<void>? _countSub;
  StreamSubscription<BluetoothAdapterState>? _btStateSub;
  StreamSubscription<QueueSyncInfo>? _queueSyncSub;
  Timer? _relativeTimeTimer;

  bool _isScanning = false;
  bool _isProcessing = false;
  bool _showBluetoothBlock = false;
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  QueueSyncInfo? _queueSyncInfo;

  // Realtime subscription for urgent coordinator/safety broadcasts
  RealtimeChannel? _notificationChannel;
  String? _activeUrgentAlert;
  String? _activeUrgentMessageId;
  int _pendingTicketCount = 0;

  // Operational Communications (Block 2.5A)
  late final OperationalCommunicationRepository _commsRepo;
  StreamSubscription<OperationalMessage>? _commsMessageSub;
  StreamSubscription<int>? _commsUnreadSub;
  int _unreadCommsCount = 0;

  // Operational Team & Shift (Block 2.5C)
  VolunteerShift? _currentShift;
  int _pendingTaskCount = 0;

  @override
  void initState() {
    super.initState();
    _assignmentRepo = widget.assignmentRepository ?? VolunteerAssignmentRepositoryImpl();
    _commsRepo = widget.commsRepository ?? OperationalCommunicationRepositoryImpl();
    WidgetsBinding.instance.addObserver(this);
    _initForegroundTask();
    _initRealtimeNotifications();
    _initCommsListeners();
    _loadPendingTickets();
    _loadQueueSyncInfo();
    _loadShiftAndTasks();

    final activeEventId = SessionState.instance.eventId;
    if (activeEventId != null) {
      EventAwarenessService.instance.initialize(
        eventId: activeEventId,
        volunteerId: SessionState.instance.volunteerId,
      );
    }

    _btStateSub = FlutterBluePlus.adapterState.listen((state) {
      if (mounted) {
        setState(() {
          _adapterState = state;
        });
      }
      if (state == BluetoothAdapterState.off && _isScanning) {
        EventAwarenessService.instance.recordSystemAlert(
          key: 'bluetooth_off',
          title: 'Bluetooth Disabled',
          message: 'Crowd scanner paused. Enable Bluetooth to resume sensing.',
          priority: OperationalPriority.important,
        );
      }
      if (state == BluetoothAdapterState.on && _showBluetoothBlock) {
        setState(() {
          _showBluetoothBlock = false;
        });
        _toggleScan(); // auto-proceed
      }
    });

    _queueSyncSub = ObservationQueue().syncStatusStream.listen((info) {
      if (mounted) {
        setState(() {
          _queueSyncInfo = info;
          _pendingTicketCount = info.pendingTickets;
        });
      }
    });

    // Refresh relative timestamps (e.g. "synced 4s ago") every 4 seconds
    _relativeTimeTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadQueueSyncInfo() async {
    try {
      final info = await ObservationQueue().getSyncInfo(
        volunteerId: SessionState.instance.volunteerId,
      );
      if (mounted) {
        setState(() {
          _queueSyncInfo = info;
          _pendingTicketCount = info.pendingTickets;
        });
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _revalidateAssignmentOnResume();
      _loadQueueSyncInfo();
    }
  }

  Future<void> _revalidateAssignmentOnResume() async {
    final vId = SessionState.instance.volunteerId;
    final eId = SessionState.instance.eventId;
    final zId = SessionState.instance.zoneId;

    if (vId == null || eId == null) return;

    final isValid = await _assignmentRepo.isAssignmentValid(
      volunteerId: vId,
      eventId: eId,
      zoneId: zId,
    );

    if (!isValid && mounted) {
      await _handleRevokedAssignment('Assignment revoked or expired while in background.');
    }
  }

  Future<void> _handleRevokedAssignment(String reason) async {
    if (_isScanning) {
      await _scanner.stopScan();
      await _countSub?.cancel();
      _countSub = null;
      await FlutterForegroundTask.stopService();
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }

    await _notificationChannel?.unsubscribe();
    _notificationChannel = null;

    EventAwarenessService.instance.clearSession();
    SessionState.instance.eventId = null;
    SessionState.instance.zoneId = null;
    SessionState.instance.zoneName = null;
    SessionState.instance.zoneCode = null;
    await SessionState.instance.clearPersistence();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(reason),
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 5),
        ),
      );
      Navigator.of(context).pushNamedAndRemoveUntil('/event_picker', (route) => false);
    }
  }

  void _initRealtimeNotifications() {
    final eventId = SessionState.instance.eventId;
    if (eventId == null) return;

    try {
      _notificationChannel = Supabase.instance.client
          .channel('volunteer_alerts_$eventId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'event_notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'event_id',
              value: eventId,
            ),
            callback: (payload) {
              final record = payload.newRecord;
              final category = record['category'] as String?;
              final title = record['title'] as String? ?? 'Urgent Broadcast';
              final body = record['body'] as String? ?? '';
              final isActive = record['is_active'] as bool? ?? true;

              if (isActive && (category == 'urgent' || category == 'safety')) {
                if (mounted) {
                  setState(() {
                    _activeUrgentAlert = '$title: $body';
                  });
                }
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('ScanScreen: Error subscribing to Realtime notifications: $e');
    }
  }

  void _initCommsListeners() {
    final eventId = SessionState.instance.eventId;
    if (eventId == null) return;

    _commsRepo.subscribeRealtime(eventId);

    _commsUnreadSub = _commsRepo.unreadCountStream.listen((count) {
      if (mounted) setState(() => _unreadCommsCount = count);
    });

    _commsMessageSub = _commsRepo.messageStream.listen((msg) {
      if (mounted && msg.eventId == eventId) {
        if (msg.isUrgent && msg.senderId != SessionState.instance.volunteerId) {
          setState(() {
            _activeUrgentAlert = '🚨 [URGENT] ${msg.senderName} (${msg.senderRole}): ${msg.body}';
            _activeUrgentMessageId = msg.id;
          });
        }
      }
    });

    _refreshCommsUnreadCount();
  }

  Future<void> _refreshCommsUnreadCount() async {
    final eventId = SessionState.instance.eventId;
    if (eventId == null) return;
    try {
      final messages = await _commsRepo.getMessages(eventId: eventId, limit: 100);
      final unread = messages.where((m) => !m.isRead && m.senderId != SessionState.instance.volunteerId).length;
      if (mounted) setState(() => _unreadCommsCount = unread);
    } catch (_) {}
  }

  Future<void> _openCommunicationsCenter() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CommunicationsCenterScreen(repository: _commsRepo),
      ),
    );
    _refreshCommsUnreadCount();
  }

  Future<void> _loadPendingTickets() async {
    try {
      final count = await ObservationQueue().getPendingTicketCheckInCount(
        volunteerId: SessionState.instance.volunteerId,
      );
      if (mounted) {
        setState(() {
          _pendingTicketCount = count;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadShiftAndTasks() async {
    final eventId = SessionState.instance.eventId;
    final volunteerId = SessionState.instance.volunteerId;
    if (eventId == null) return;

    try {
      final shift = await TeamShiftRepository.instance.fetchActiveShift(eventId: eventId);
      final tasks = await TeamShiftRepository.instance.fetchTasks(
        eventId: eventId,
        assignedToId: volunteerId,
      );
      final activeTasks = tasks.where((t) => !t.isCompleted).length;

      if (mounted) {
        setState(() {
          _currentShift = shift;
          _pendingTaskCount = activeTasks;
        });

        if (shift != null) {
          SessionState.instance.activeShiftId = shift.id;
          SessionState.instance.activeShiftName = shift.shiftName;
          SessionState.instance.shiftStatus = shift.status.toDbString();
          SessionState.instance.teamId = shift.teamId;
          SessionState.instance.teamName = shift.teamName;
          SessionState.instance.supervisorName = shift.supervisorName;
        }
      }
    } catch (_) {}
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'spatially_ble_scan',
        channelName: 'Spatially BLE Scanning',
        channelDescription: 'Keeps BLE scanning active in the background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _relativeTimeTimer?.cancel();
    _queueSyncSub?.cancel();
    _btStateSub?.cancel();
    _countSub?.cancel();
    _notificationChannel?.unsubscribe();
    _commsMessageSub?.cancel();
    _commsUnreadSub?.cancel();
    _scanner.dispose();
    FlutterForegroundTask.stopService();
    super.dispose();
  }

  Future<void> _toggleScan() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      if (_isScanning) {
        await _scanner.stopScan();
        await _countSub?.cancel();
        _countSub = null;
        await FlutterForegroundTask.stopService();
        setState(() {
          _isScanning = false;
        });
      } else {
        // Pre-scan lifecycle gate: verify active assignment on server
        final vId = SessionState.instance.volunteerId;
        final eId = SessionState.instance.eventId;
        final zId = SessionState.instance.zoneId;

        if (vId != null && eId != null) {
          final isValid = await _assignmentRepo.isAssignmentValid(
            volunteerId: vId,
            eventId: eId,
            zoneId: zId,
          );
          if (!isValid) {
            await _handleRevokedAssignment('Your assignment has expired or was revoked by coordinator.');
            return;
          }
        }

        final isBluetoothOn = await _scanner.isBluetoothOn();
        if (!isBluetoothOn && mounted) {
          setState(() {
            _showBluetoothBlock = true;
          });
          return;
        }

        final statuses = await _scanner.requestPermissions();
        final notificationStatus = await Permission.notification.request();
        final allGranted = statuses.values.every(
          (status) => status == PermissionStatus.granted,
        );

        if (notificationStatus != PermissionStatus.granted) {
          debugPrint('WARNING: Notification permission denied. Foreground service may not run.');
        }

        bool isIgnoring = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
        if (!isIgnoring) {
          await FlutterForegroundTask.requestIgnoreBatteryOptimization();
        }

        if (!allGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('BLE scanning requires Location and Bluetooth permissions.'),
              ),
            );
          }
          return;
        }

        setState(() {
          _isScanning = true;
        });

        _countSub = _scanner.stateStream.listen((_) {
          setState(() {});
        });

        await _scanner.startScan();
        await FlutterForegroundTask.startService(
          notificationTitle: 'Spatially',
          notificationText: 'Scanning active for ${SessionState.instance.zoneName ?? "station"}',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _manualSync() async {
    setState(() {
      _isProcessing = true;
    });
    try {
      await ObservationQueue().flushAllNow();
      await _loadQueueSyncInfo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync completed.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync attempted. Unsent records remain in offline queue.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    if (_isScanning) {
      await _scanner.stopScan();
      await _countSub?.cancel();
      _countSub = null;
      await FlutterForegroundTask.stopService();
    }
    await _notificationChannel?.unsubscribe();
    await _commsRepo.unsubscribeRealtime();
    await _commsRepo.clearAccountCache();
    await _commsMessageSub?.cancel();
    await _commsUnreadSub?.cancel();
    EventAwarenessService.instance.clearSession();
    await SessionState.instance.clear();
    await Supabase.instance.client.auth.signOut();

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil<void>(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (Route<dynamic> route) => false,
      );
    }
  }

  Future<void> _openScanner() async {
    final status = await Permission.camera.request();
    if (status == PermissionStatus.granted) {
      if (mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const QrScannerScreen()),
        );
        _loadPendingTickets();
        _loadQueueSyncInfo();
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission is required to scan tickets.')),
        );
      }
    }
  }

  CrowdDensityInfo? _calculateDensity(int detectedCount, int? capacity) {
    if (capacity == null || capacity <= 0) return null;
    final ratio = detectedCount / capacity;

    if (ratio < 0.40) {
      return CrowdDensityInfo(
        label: 'Low Crowd',
        color: Colors.green.shade700,
        bgColor: Colors.green.shade50,
        ratio: ratio,
      );
    } else if (ratio < 0.80) {
      return CrowdDensityInfo(
        label: 'Moderate Crowd',
        color: Colors.amber.shade800,
        bgColor: Colors.amber.shade50,
        ratio: ratio,
      );
    } else if (ratio < 0.90) {
      return CrowdDensityInfo(
        label: 'Busy',
        color: Colors.orange.shade800,
        bgColor: Colors.orange.shade50,
        ratio: ratio,
      );
    } else {
      return CrowdDensityInfo(
        label: 'Near Capacity',
        color: Colors.red.shade700,
        bgColor: Colors.red.shade50,
        ratio: ratio,
      );
    }
  }

  String _formatRelativeTime(DateTime? dateTime) {
    if (dateTime == null) return 'Never';
    final diff = DateTime.now().difference(dateTime);
    if (diff.inSeconds < 10) return 'just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    if (_showBluetoothBlock) {
      return PopScope(
        canPop: false,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Bluetooth Required'),
            automaticallyImplyLeading: false,
          ),
          body: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.bluetooth_disabled, size: 80, color: Colors.redAccent),
                const SizedBox(height: 24),
                const Text(
                  'Bluetooth is off',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Spatially requires Bluetooth to scan for attendee beacons. Please turn it on to continue.',
                  style: TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                ElevatedButton(
                  onPressed: () => AppSettings.openAppSettings(type: AppSettingsType.bluetooth),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Open Bluetooth Settings', style: TextStyle(fontSize: 18)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final eventName = SessionState.instance.eventName ?? 'Assigned Event';
    final zoneName = SessionState.instance.zoneName ?? SessionState.instance.zone ?? 'General Zone';
    final zoneCode = SessionState.instance.zoneCode ?? 'Zone';
    final isRoving = SessionState.instance.isRoving;
    final capacity = SessionState.instance.capacityLimit;

    final detectedCount = _scanner.activeSpatiallyDevicesCount;
    final densityInfo = _calculateDensity(detectedCount, capacity);

    final isSyncing = _queueSyncInfo?.isSyncing ?? false;
    final totalPending = _queueSyncInfo?.totalPending ?? 0;
    final lastSync = _queueSyncInfo?.lastSyncedAt ?? TelemetryService().lastCountSyncAt;

    return Scaffold(
      appBar: AppBar(
        title: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Spatially ',
                style: GoogleFonts.audiowide(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextSpan(
                text: 'Volunteer',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: _unreadCommsCount > 0
                ? Badge(
                    label: Text('$_unreadCommsCount'),
                    child: const Icon(Icons.forum_outlined),
                  )
                : const Icon(Icons.forum_outlined),
            tooltip: 'Communications Center',
            onPressed: _openCommunicationsCenter,
          ),
          IconButton(
            icon: totalPending > 0
                ? Badge(
                    label: Text('$totalPending'),
                    child: const Icon(Icons.sync),
                  )
                : const Icon(Icons.sync),
            tooltip: 'Sync queued items',
            onPressed: _isProcessing ? null : _manualSync,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: _signOut,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Urgent Alert Banner
            if (_activeUrgentAlert != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                color: Colors.red.shade800,
                child: Row(
                  children: [
                    const Icon(Icons.warning_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _activeUrgentAlert!,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                      ),
                    ),
                    if (_activeUrgentMessageId != null) ...[
                      TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.red.shade900,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                        onPressed: () {
                          _commsRepo.acknowledgeMessage(_activeUrgentMessageId!);
                          setState(() {
                            _activeUrgentAlert = null;
                            _activeUrgentMessageId = null;
                          });
                        },
                        child: const Text('ACKNOWLEDGE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 4),
                    ],
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 16),
                      onPressed: () => setState(() => _activeUrgentAlert = null),
                    ),
                  ],
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // CARD 1: OPERATIONAL IDENTITY (EVENT & ZONE)
                  _buildIdentityCard(eventName, zoneName, zoneCode, isRoving, capacity),

                  const SizedBox(height: 12),

                  // CARD 2: MERGED INCIDENTS, EVENT AWARENESS & OPERATIONAL WORKFLOWS
                  _buildMergedOperationalHubCard(),

                  const SizedBox(height: 12),

                  // CARD 3: CROWD PRESENTATION, TICKETING & SCANNER CONTROLS
                  _buildCrowdAndScannerCard(
                    detectedCount: detectedCount,
                    densityInfo: densityInfo,
                    capacity: capacity,
                    isSyncing: isSyncing,
                    totalPending: totalPending,
                    lastSync: lastSync,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Component Cards
  // ---------------------------------------------------------------------------

  Widget _buildIdentityCard(
    String eventName,
    String zoneName,
    String zoneCode,
    bool isRoving,
    int? capacity,
  ) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event, size: 16, color: Colors.blue.shade700),
                const SizedBox(width: 6),
                Text(
                  'CURRENT EVENT',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                    color: Colors.blue.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              eventName,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ZONE / STATION',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        zoneName,
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.indigo.shade200),
                  ),
                  child: Text(
                    zoneCode.toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.indigo.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isRoving ? Colors.purple.shade50 : Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isRoving ? Icons.directions_walk : Icons.pin_drop,
                          size: 13,
                          color: isRoving ? Colors.purple.shade800 : Colors.teal.shade800,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            isRoving ? 'Roving Assignment (All Event Zones)' : 'Fixed Station Shift',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isRoving ? Colors.purple.shade900 : Colors.teal.shade900,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (capacity != null && capacity > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    'Cap: $capacity',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
            if (_currentShift != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: _currentShift!.isOnBreak
                      ? Colors.amber.shade50
                      : (_currentShift!.isActive ? const Color(0xFFECFDF5) : Colors.blue.shade50),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _currentShift!.isOnBreak
                        ? Colors.amber.shade300
                        : (_currentShift!.isActive ? const Color(0xFFA7F3D0) : Colors.blue.shade200),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _currentShift!.isOnBreak
                          ? Icons.coffee
                          : (_currentShift!.isActive ? Icons.check_circle_outline : Icons.schedule),
                      size: 16,
                      color: _currentShift!.isOnBreak
                          ? Colors.amber.shade900
                          : (_currentShift!.isActive ? const Color(0xFF065F46) : Colors.blue.shade900),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Shift: ${_currentShift!.shiftName} • ${_currentShift!.status.label.toUpperCase()}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _currentShift!.isOnBreak
                              ? Colors.amber.shade900
                              : (_currentShift!.isActive ? const Color(0xFF065F46) : Colors.blue.shade900),
                        ),
                      ),
                    ),
                    Text(
                      _currentShift!.teamName ?? 'Team',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Merged Operational Hub & Event Awareness
  // ---------------------------------------------------------------------------

  Widget _buildMergedOperationalHubCard() {
    return StreamBuilder<OperationalAwarenessSummary>(
      stream: EventAwarenessService.instance.summaryStream,
      initialData: EventAwarenessService.instance.summary,
      builder: (context, snapshot) {
        final summary = snapshot.data ?? const OperationalAwarenessSummary();
        final attentionItems = EventAwarenessService.instance.attentionRequiredItems;
        final hasActiveIncidents = summary.activeIncidentsCount > 0;

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with Awareness Links
                Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 16, color: Colors.indigo.shade800),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'AWARENESS & WORKFLOWS',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color: Colors.indigo.shade900,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const OperationalHealthScreen()),
                      ),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.insights, size: 12, color: Colors.indigo.shade700),
                            const SizedBox(width: 3),
                            Text(
                              'Health',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const EventAwarenessFeedScreen()),
                      ),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.radar, size: 12, color: Colors.indigo.shade700),
                            const SizedBox(width: 3),
                            Text(
                              'Live Feed',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                // Attention Required alert block or Active Incident prompt
                if (attentionItems.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildAttentionAlertBox(attentionItems.first, attentionItems.length),
                ] else if (hasActiveIncidents) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red.shade800),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${summary.activeIncidentsCount} active incident${summary.activeIncidentsCount == 1 ? '' : 's'} reported in this event',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade900,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const IncidentsListScreen()),
                          ),
                          child: Text(
                            'VIEW',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // 4-Pillar Operational Action Matrix
                Row(
                  children: [
                    // 1. Report Issue
                    _buildQuickActionBtn(
                      icon: Icons.add_alert_outlined,
                      label: 'Report Issue',
                      color: Colors.orange.shade800,
                      bgColor: Colors.orange.shade50,
                      borderColor: Colors.orange.shade200,
                      onTap: () => ReportIssueDialog.show(context),
                    ),
                    const SizedBox(width: 8),

                    // 2. Need Help
                    _buildQuickActionBtn(
                      icon: Icons.handshake_outlined,
                      label: 'Need Help',
                      color: Colors.red.shade800,
                      bgColor: Colors.red.shade50,
                      borderColor: Colors.red.shade200,
                      onTap: () => ReportIssueDialog.show(context, isNeedHelpMode: true),
                    ),
                    const SizedBox(width: 8),

                    // 3. Incidents & Assistance
                    _buildQuickActionBtn(
                      icon: Icons.assignment_outlined,
                      label: hasActiveIncidents
                          ? 'Incidents (${summary.activeIncidentsCount})'
                          : 'Incidents',
                      color: Colors.indigo.shade800,
                      bgColor: Colors.indigo.shade50,
                      borderColor: Colors.indigo.shade200,
                      badgeCount: summary.activeIncidentsCount > 0 ? summary.activeIncidentsCount : null,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const IncidentsListScreen()),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // 4. Lost & Found
                    _buildQuickActionBtn(
                      icon: Icons.inventory_2_outlined,
                      label: 'Lost & Found',
                      color: Colors.teal.shade800,
                      bgColor: Colors.teal.shade50,
                      borderColor: Colors.teal.shade200,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LostFoundOperationsScreen()),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 10),

                // Floor Operations: Shift, Team & Floor Tasks
                Row(
                  children: [
                    Expanded(
                      child: _buildFloorBarItem(
                        icon: Icons.access_time_outlined,
                        title: _currentShift?.isOnBreak == true
                            ? 'On Break'
                            : (_currentShift?.isActive == true ? 'Active Shift' : 'Shift Ops'),
                        subtitle: _currentShift?.shiftName ?? 'No Shift',
                        color: _currentShift?.isOnBreak == true
                            ? Colors.amber.shade900
                            : (_currentShift?.isActive == true ? const Color(0xFF065F46) : Colors.blue.shade900),
                        bgColor: _currentShift?.isOnBreak == true
                            ? Colors.amber.shade50
                            : (_currentShift?.isActive == true ? const Color(0xFFECFDF5) : Colors.blue.shade50),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const ShiftOverviewScreen()),
                        ).then((_) => _loadShiftAndTasks()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildFloorBarItem(
                        icon: Icons.groups_outlined,
                        title: 'Team & Relief',
                        subtitle: summary.coverageNeededCount > 0
                            ? '${summary.coverageNeededCount} open relief'
                            : (_currentShift?.teamName ?? 'Team Nominal'),
                        color: Colors.purple.shade900,
                        bgColor: Colors.purple.shade50,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const TeamOverviewScreen()),
                        ).then((_) => _loadShiftAndTasks()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildFloorBarItem(
                        icon: Icons.task_alt,
                        title: 'Floor Tasks',
                        subtitle: _pendingTaskCount > 0 ? '$_pendingTaskCount pending' : 'All Clear',
                        color: Colors.cyan.shade900,
                        bgColor: Colors.cyan.shade50,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const SupervisorTasksScreen()),
                        ).then((_) => _loadShiftAndTasks()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAttentionAlertBox(OperationalAwarenessItem item, int totalCount) {
    final isUrgent = item.priority == OperationalPriority.urgent;
    final color = isUrgent ? Colors.red.shade800 : Colors.amber.shade900;
    final bgColor = isUrgent ? Colors.red.shade50 : Colors.amber.shade50;
    final borderColor = isUrgent ? Colors.red.shade300 : Colors.amber.shade300;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isUrgent ? Icons.error_outline : Icons.warning_amber_rounded,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'ATTENTION REQUIRED ($totalCount)',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (item.zoneName != null) ...[
                const SizedBox(width: 4),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      item.zoneName!,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item.title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            item.message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: color),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  EventAwarenessService.instance.acknowledgeAttention(item.id);
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('ACKNOWLEDGE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  EventAwarenessService.instance.markAttentionSeen(item.id);
                  _navigateToAwarenessItem(item);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('ACT NOW', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required Color borderColor,
    required VoidCallback onTap,
    int? badgeCount,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, color: color, size: 22),
                  if (badgeCount != null && badgeCount > 0)
                    Positioned(
                      right: -8,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.red.shade700,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloorBarItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 3),
            Text(
              title,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              subtitle,
              style: TextStyle(fontSize: 9, color: color.withAlpha(200)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Card 3: Unified Crowd Sensing & BLE Scanner Controls
  // ---------------------------------------------------------------------------

  Widget _buildCrowdAndScannerCard({
    required int detectedCount,
    required CrowdDensityInfo? densityInfo,
    required int? capacity,
    required bool isSyncing,
    required int totalPending,
    required DateTime? lastSync,
  }) {
    String stateLabel;
    Color stateColor;
    Color stateBg;
    IconData stateIcon;

    if (_isProcessing) {
      stateLabel = 'Updating Scanner...';
      stateColor = Colors.blue.shade800;
      stateBg = Colors.blue.shade50;
      stateIcon = Icons.hourglass_top_rounded;
    } else if (_isScanning) {
      stateLabel = '● SCANNING ACTIVE';
      stateColor = Colors.green.shade800;
      stateBg = Colors.green.shade50;
      stateIcon = Icons.radar;
    } else if (_adapterState != BluetoothAdapterState.on && _adapterState != BluetoothAdapterState.unknown) {
      stateLabel = '▲ BLUETOOTH OFF';
      stateColor = Colors.red.shade800;
      stateBg = Colors.red.shade50;
      stateIcon = Icons.bluetooth_disabled;
    } else {
      stateLabel = '○ READY TO SCAN';
      stateColor = Colors.blueGrey.shade800;
      stateBg = Colors.blueGrey.shade50;
      stateIcon = Icons.play_arrow_rounded;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status row + Sync Interval
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: stateBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: stateColor.withAlpha(80)),
                  ),
                  child: Row(
                    children: [
                      Icon(stateIcon, size: 14, color: stateColor),
                      const SizedBox(width: 6),
                      Text(
                        stateLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: stateColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    const Text('Sync rate: ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    DropdownButton<int>(
                      value: SessionState.instance.syncRateSeconds,
                      isDense: true,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 10, child: Text('10s', style: TextStyle(fontSize: 11))),
                        DropdownMenuItem(value: 30, child: Text('30s', style: TextStyle(fontSize: 11))),
                        DropdownMenuItem(value: 60, child: Text('60s', style: TextStyle(fontSize: 11))),
                      ],
                      onChanged: (int? newValue) {
                        if (newValue != null) {
                          setState(() {
                            SessionState.instance.syncRateSeconds = newValue;
                          });
                          _scanner.updateTelemetryInterval();
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Attendee detection metrics
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DETECTED ATTENDEES',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '$detectedCount',
                            style: GoogleFonts.poppins(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo.shade900,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'devices nearby',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (densityInfo != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: densityInfo.bgColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: densityInfo.color.withAlpha(80)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          densityInfo.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: densityInfo.color,
                          ),
                        ),
                        Text(
                          '${(densityInfo.ratio * 100).toInt()}% capacity',
                          style: TextStyle(fontSize: 10, color: densityInfo.color),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            if (densityInfo != null) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: densityInfo.ratio.clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(densityInfo.color),
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Mini stats
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMiniStat('Unique Seen', '${_scanner.totalUniqueSpatiallySeenCount}'),
                  Container(width: 1, height: 20, color: Colors.grey.shade300),
                  _buildMiniStat('Ambient BLE', '${_scanner.activeDevicesCount}'),
                  Container(width: 1, height: 20, color: Colors.grey.shade300),
                  _buildMiniStat('Raw Signals', '${_scanner.rawObservationsCount}'),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Actions: Start BLE Scanner & Scan Attendee Pass
            Row(
              children: [
                Expanded(
                  flex: 5,
                  child: SizedBox(
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _toggleScan,
                      icon: Icon(
                        _isScanning ? Icons.stop_rounded : Icons.sensors_rounded,
                        size: 20,
                      ),
                      label: Text(
                        _isScanning ? 'Stop BLE' : 'Start BLE',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isScanning ? Colors.red.shade700 : Colors.indigo.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 5,
                  child: SizedBox(
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: _openScanner,
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Scan Pass', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          if (_pendingTicketCount > 0) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade700,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$_pendingTicketCount',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // Compact Sync Footer
            Row(
              children: [
                Icon(
                  isSyncing
                      ? Icons.sync
                      : (totalPending > 0 ? Icons.cloud_queue_rounded : Icons.cloud_done_rounded),
                  size: 16,
                  color: isSyncing
                      ? Colors.blue.shade700
                      : (totalPending > 0 ? Colors.orange.shade800 : Colors.green.shade700),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isSyncing
                        ? 'Uploading queued records to server...'
                        : (totalPending > 0
                            ? '$totalPending pending sync (${_queueSyncInfo?.pendingTickets ?? 0} offline passes)'
                            : 'Online • Synced ${_formatRelativeTime(lastSync)}'),
                    style: TextStyle(
                      fontSize: 11,
                      color: totalPending > 0 ? Colors.orange.shade900 : Colors.grey.shade700,
                      fontWeight: totalPending > 0 ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                InkWell(
                  onTap: _isProcessing ? null : _manualSync,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      'Sync Now',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
      ],
    );
  }

  void _navigateToAwarenessItem(OperationalAwarenessItem item) {
    final route = item.actionRoute;
    if (route == null) return;

    switch (route) {
      case 'incident_detail':
        final incidentId = item.actionPayload?['incidentId'] as String?;
        if (incidentId != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => IncidentDetailScreen(incidentId: incidentId),
            ),
          );
        }
        break;
      case 'supervisor_tasks':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SupervisorTasksScreen()),
        );
        break;
      case 'shift_overview':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ShiftOverviewScreen()),
        );
        break;
      case 'team_overview':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TeamOverviewScreen()),
        );
        break;
      case 'communications':
        _openCommunicationsCenter();
        break;
      case 'scanner':
        break;
    }
  }
}
