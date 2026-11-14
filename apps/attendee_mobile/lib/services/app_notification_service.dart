import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../design_system/spatially_colors.dart';
import '../design_system/spatially_typography.dart';
import '../features/notifications/models/notification_models.dart';

/// Centralized notification service responsible for:
/// 1. Triggering native phone notifications in the Android notification bar tray.
/// 2. Displaying animated in-app popups / heads-up banners across any active screen.
class AppNotificationService {
  AppNotificationService._();
  static final AppNotificationService instance = AppNotificationService._();

  /// Global navigator key attached to [MaterialApp] in `app.dart`.
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;
  int _notificationCounter = 1000;

  OverlayEntry? _currentOverlayEntry;
  Timer? _dismissTimer;

  /// Android notification channel ID and properties.
  static const String _channelId = 'spatially_alerts';
  static const String _channelName = 'Spatially Event Alerts';
  static const String _channelDescription =
      'Real-time announcements, safety notices, crowd telemetry, and event updates';

  /// Initializes native notification channels and permissions.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
      );

      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint('Notification bar tapped: ${response.payload}');
          // If tapped, open notification center if possible
        },
      );

      // Create high-priority notification channel for Android heads-up display
      final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
        );
        // Request runtime permission for Android 13+
        await androidPlugin.requestNotificationsPermission();
      }

      _isInitialized = true;
      debugPrint('AppNotificationService: initialized successfully');
    } catch (e) {
      debugPrint('AppNotificationService: initialization error: $e');
    }
  }

  /// Dispatches a notification to BOTH the phone's notification bar AND an in-app popup.
  Future<void> notify({
    required String title,
    required String body,
    NotificationCategory category = NotificationCategory.event,
    NotificationPriority priority = NotificationPriority.normal,
    VoidCallback? onTap,
    NotificationAction? action,
  }) async {
    // 1. Trigger system notification in the phone notification bar
    await _showSystemNotification(
      title: title,
      body: body,
      category: category,
      priority: priority,
    );

    // 2. Trigger in-app popup / banner
    _showInAppPopup(
      title: title,
      body: body,
      category: category,
      priority: priority,
      onTap: onTap,
      action: action,
    );
  }

  /// Convenience helper to dispatch directly from a domain [NotificationItem].
  Future<void> showFromNotificationItem(
    NotificationItem item, {
    VoidCallback? onTap,
  }) async {
    await notify(
      title: item.title,
      body: item.body,
      category: item.category,
      priority: item.priority,
      action: item.action,
      onTap: onTap,
    );
  }

  /// Displays the notification in the Android system status bar / notification tray.
  Future<void> _showSystemNotification({
    required String title,
    required String body,
    required NotificationCategory category,
    required NotificationPriority priority,
  }) async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      final id = _notificationCounter++;
      final isUrgent = priority == NotificationPriority.urgent || priority == NotificationPriority.high;

      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: isUrgent ? Importance.max : Importance.high,
        priority: isUrgent ? Priority.max : Priority.high,
        ticker: 'Spatially Alert',
        icon: '@mipmap/ic_launcher',
        enableVibration: true,
        playSound: true,
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
          summaryText: category.label,
        ),
      );

      final darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        subtitle: category.label,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      await _localNotifications.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: category.name,
      );
    } catch (e) {
      debugPrint('AppNotificationService: system notification failed: $e');
    }
  }

  /// Injects an animated floating heads-up banner at the top of the Flutter view.
  void _showInAppPopup({
    required String title,
    required String body,
    required NotificationCategory category,
    required NotificationPriority priority,
    VoidCallback? onTap,
    NotificationAction? action,
  }) {
    final overlayState = navigatorKey.currentState?.overlay;
    if (overlayState == null) {
      debugPrint('AppNotificationService: overlayState is null, cannot show in-app banner');
      return;
    }

    // Dismiss existing banner cleanly if still active
    _dismissTimer?.cancel();
    _currentOverlayEntry?.remove();
    _currentOverlayEntry = null;

    late OverlayEntry entry;
    final isUrgent = priority == NotificationPriority.urgent || priority == NotificationPriority.high;
    final duration = isUrgent ? const Duration(seconds: 7) : const Duration(seconds: 4, milliseconds: 500);

    entry = OverlayEntry(
      builder: (context) => _InAppNotificationPopupWidget(
        title: title,
        body: body,
        category: category,
        priority: priority,
        action: action,
        onTap: () {
          entry.remove();
          if (_currentOverlayEntry == entry) _currentOverlayEntry = null;
          _dismissTimer?.cancel();
          if (onTap != null) {
            onTap();
          }
        },
        onDismiss: () {
          entry.remove();
          if (_currentOverlayEntry == entry) _currentOverlayEntry = null;
          _dismissTimer?.cancel();
        },
      ),
    );

    _currentOverlayEntry = entry;
    overlayState.insert(entry);

    _dismissTimer = Timer(duration, () {
      if (_currentOverlayEntry == entry) {
        entry.remove();
        _currentOverlayEntry = null;
      }
    });
  }
}

/// Animated heads-up notification card that slides down from top of the screen.
class _InAppNotificationPopupWidget extends StatefulWidget {
  final String title;
  final String body;
  final NotificationCategory category;
  final NotificationPriority priority;
  final NotificationAction? action;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _InAppNotificationPopupWidget({
    required this.title,
    required this.body,
    required this.category,
    required this.priority,
    this.action,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_InAppNotificationPopupWidget> createState() => _InAppNotificationPopupWidgetState();
}

class _InAppNotificationPopupWidgetState extends State<_InAppNotificationPopupWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<Offset> _offsetAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, -1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeIn),
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _dismissAnimated() {
    _animController.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final catColor = widget.category.color;
    final isUrgent = widget.priority == NotificationPriority.urgent;

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: SlideTransition(
            position: _offsetAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: GestureDetector(
                onVerticalDragUpdate: (details) {
                  if (details.primaryDelta != null && details.primaryDelta! < -4) {
                    _dismissAnimated();
                  }
                },
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 480),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E2A) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isUrgent
                            ? SpatiallyColors.error
                            : catColor.withValues(alpha: isDark ? 0.45 : 0.35),
                        width: isUrgent ? 1.8 : 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (isUrgent ? SpatiallyColors.error : Colors.black)
                              .withValues(alpha: isDark ? 0.35 : 0.15),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: widget.onTap,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Category Icon Container
                            Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                color: catColor.withValues(alpha: isDark ? 0.22 : 0.14),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                widget.category.icon,
                                color: catColor,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Content Details
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Top row: Category badge + Just now indicator
                                  Row(
                                    children: [
                                      Text(
                                        widget.category.label.toUpperCase(),
                                        style: SpatiallyTypography.caption(color: catColor).copyWith(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 10,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      if (isUrgent) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: SpatiallyColors.error,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'URGENT',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                      const Spacer(),
                                      Text(
                                        'Just now',
                                        style: TextStyle(
                                          color: isDark ? Colors.white38 : Colors.black38,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),

                                  // Notification Title
                                  Text(
                                    widget.title,
                                    style: TextStyle(
                                      color: isDark ? Colors.white : SpatiallyColors.lightTextPrimary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),

                                  // Notification Body
                                  Text(
                                    widget.body,
                                    style: TextStyle(
                                      color: isDark ? SpatiallyColors.darkTextSecondary : SpatiallyColors.lightTextSecondary,
                                      fontSize: 12.5,
                                      height: 1.3,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),

                                  // Optional Action Chip
                                  if (widget.action != null && widget.action!.type != NotificationActionType.none) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Text(
                                          '${widget.action!.displayLabel} →',
                                          style: TextStyle(
                                            color: SpatiallyColors.spatialCyan,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),

                            // Close / Dismiss Button
                            GestureDetector(
                              onTap: _dismissAnimated,
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
