import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/wallet_transaction.dart';

/// Service managing the attendee's Points Wallet with bi-directional cloud sync.
/// 
/// Features:
/// - Balance calculation and real-time reactive notifications (via ChangeNotifier).
/// - Ledger of credit and debit transactions.
/// - Coupon code redemption with one-time verification.
/// - Seamless multi-device synchronization: Wallet state (balance, redeemed coupons,
///   transactions) is backed up in the attendee's Supabase account metadata and
///   persisted across Google OAuth, email/password logins, and device switches.
/// - Offline persistence via SharedPreferences, keyed per user account.
/// - Automatic reconciliation with Supabase gamified quest completions (`attendee_engagements`).
class WalletService extends ChangeNotifier {
  static final WalletService _instance = WalletService._internal();
  static WalletService get instance => _instance;

  WalletService._internal() {
    _setupAuthListener();
  }

  /// Registered coupon catalog: Code -> Points assigned
  static const Map<String, int> availableCoupons = {
    'WELCOME100': 100,
    'SPATIAL50': 50,
    'BONUS200': 200,
    'QUESTMASTER': 150,
    'VIP500': 500,
    'EARLYBIRD75': 75,
    'FESTIVAL250': 250,
    'COMMUNITY25': 25,
  };

  int _balance = 0;
  List<WalletTransaction> _transactions = [];
  Set<String> _redeemedCoupons = {};
  String? _currentUserId;
  bool _initialized = false;
  StreamSubscription<AuthState>? _authSub;

  int get balance => _balance;
  List<WalletTransaction> get transactions => List.unmodifiable(_transactions);
  Set<String> get redeemedCoupons => Set.unmodifiable(_redeemedCoupons);
  bool get isInitialized => _initialized;

  int get totalCredits => _transactions
      .where((tx) => tx.isCredit)
      .fold(0, (sum, tx) => sum + tx.amount);

  int get totalDebits => _transactions
      .where((tx) => tx.isDebit)
      .fold(0, (sum, tx) => sum + tx.amount);

  User? get _currentUser {
    try {
      return Supabase.instance.client.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  void _setupAuthListener() {
    if (_authSub != null) return;
    try {
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        final newUserId = data.session?.user.id ?? 'guest_device';
        if (newUserId != _currentUserId) {
          _currentUserId = newUserId;
          _initialized = false;
          init(forceRefresh: true);
        } else if (data.event == AuthChangeEvent.signedIn ||
            data.event == AuthChangeEvent.tokenRefreshed ||
            data.event == AuthChangeEvent.userUpdated) {
          syncFromSupabase();
        }
      });
    } catch (_) {
      // Supabase not yet initialized (e.g. in unit tests or before Supabase.initialize)
    }
  }

  /// Initializes the wallet for the currently active user session.
  Future<void> init({bool forceRefresh = false}) async {
    _setupAuthListener();
    final user = _currentUser;
    final userId = user?.id ?? 'guest_device';
    if (_initialized && _currentUserId == userId && !forceRefresh) {
      return;
    }
    _currentUserId = userId;
    await _loadFromLocal();
    _initialized = true;
    notifyListeners();

    // Reconcile with remote server in background
    await syncFromSupabase();
  }

  /// Refreshes wallet data and reconciles with remote server.
  Future<void> refresh() async {
    await _loadFromLocal();
    await syncFromSupabase();
    notifyListeners();
  }

  String get _storagePrefix => 'spatially_wallet_${_currentUserId ?? "default"}';

  Future<void> _loadFromLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _balance = prefs.getInt('${_storagePrefix}_balance') ?? 0;

      final rawTx = prefs.getString('${_storagePrefix}_transactions');
      if (rawTx != null && rawTx.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(rawTx);
        _transactions = decoded
            .map((item) => WalletTransaction.fromJson(Map<String, dynamic>.from(item)))
            .toList();
        _transactions.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      } else {
        _transactions = [];
      }

      final rawCoupons = prefs.getStringList('${_storagePrefix}_coupons');
      if (rawCoupons != null) {
        _redeemedCoupons = rawCoupons.toSet();
      } else {
        _redeemedCoupons = {};
      }
    } catch (e) {
      debugPrint('Error loading wallet from local storage: $e');
    }
  }

  Future<void> _saveToLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('${_storagePrefix}_balance', _balance);
      final encodedTx = jsonEncode(_transactions.map((tx) => tx.toJson()).toList());
      await prefs.setString('${_storagePrefix}_transactions', encodedTx);
      await prefs.setStringList('${_storagePrefix}_coupons', _redeemedCoupons.toList());
    } catch (e) {
      debugPrint('Error saving wallet to local storage: $e');
    }
  }

  /// Saves the current wallet state (balance, redeemed coupons, and transactions ledger)
  /// directly to the user's Supabase account metadata for cross-device synchronization.
  Future<void> _saveToCloud() async {
    final user = _currentUser;
    if (user == null) return;

    try {
      final client = Supabase.instance.client;
      final stateMap = {
        'balance': _balance,
        'redeemed_coupons': _redeemedCoupons.toList(),
        'transactions': _transactions.map((tx) => tx.toJson()).toList(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      await client.auth.updateUser(
        UserAttributes(
          data: {
            'wallet_state': stateMap,
          },
        ),
      );
    } catch (e) {
      debugPrint('Notice: Error saving wallet state to Supabase user metadata: $e');
    }
  }

  /// Syncs wallet data with Supabase:
  /// 1. Syncs with remote cloud wallet state stored in `auth.users.user_metadata`.
  /// 2. Syncs quest completion points from Supabase `attendee_engagements` table.
  /// 3. Reconciles local and remote ledgers, ensuring points and coupons match across devices.
  Future<void> syncFromSupabase() async {
    final user = _currentUser;
    if (user == null) return;
    final client = Supabase.instance.client;

    bool changed = false;

    // 1. Sync with Supabase Auth user metadata
    try {
      User? remoteUser;
      try {
        final res = await client.auth.getUser();
        remoteUser = res.user;
      } catch (_) {
        remoteUser = user;
      }

      final metadata = (remoteUser ?? user).userMetadata;
      final rawCloudState = metadata?['wallet_state'];

      if (rawCloudState is Map) {
        if (reconcileWithRemoteState(Map<String, dynamic>.from(rawCloudState))) {
          changed = true;
        }
      }
    } catch (e) {
      debugPrint('Notice: Supabase user metadata wallet sync error: $e');
    }

    // 2. Sync quest completion points from Supabase `attendee_engagements` table
    try {
      final res = await client
          .from('attendee_engagements')
          .select('id, event_id, reference_id, points_earned, verified_at, metadata')
          .eq('user_id', user.id)
          .eq('engagement_type', 'activity')
          .order('verified_at', ascending: true);

      for (final row in (res as List)) {
        final refId = row['reference_id']?.toString() ?? row['id']?.toString();
        final points = (row['points_earned'] as num?)?.toInt() ?? 0;
        if (points <= 0) continue;

        // Check if this quest completion is already recorded
        final exists = _transactions.any(
          (tx) => tx.category == WalletTransactionCategory.quest && tx.referenceId == refId,
        );

        if (!exists) {
          final title = (row['metadata'] as Map?)?['activity_title']?.toString() ??
              'Gamified Quest Checkpoint';
          final txDate = row['verified_at'] != null
              ? DateTime.tryParse(row['verified_at'].toString())?.toLocal() ?? DateTime.now()
              : DateTime.now();

          final tx = WalletTransaction(
            id: const Uuid().v4(),
            title: 'Quest Completed: $title',
            amount: points,
            type: WalletTransactionType.credit,
            category: WalletTransactionCategory.quest,
            timestamp: txDate,
            referenceId: refId,
          );

          _transactions.insert(0, tx);
          _balance += points;
          changed = true;
        }
      }
    } catch (e) {
      debugPrint('Notice: Supabase quest sync unavailable (offline or network): $e');
    }

    // Always push the combined, authoritative state to the cloud
    await _saveToCloud();

    if (changed) {
      _transactions.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      await _saveToLocal();
      notifyListeners();
    }
  }

  /// Merges remote cloud state with local state:
  /// - Takes union of redeemed coupons across devices.
  /// - Deduplicates and imports missing transactions.
  /// - Ensures all redeemed coupons have transactions in the ledger.
  /// - Reconciles balance to match highest observed or calculated ledger sum.
  bool reconcileWithRemoteState(Map<String, dynamic> rawCloudState) {
    bool changed = false;

    final cloudBalance = (rawCloudState['balance'] as num?)?.toInt() ?? 0;
    final rawCoupons = rawCloudState['redeemed_coupons'];
    final Set<String> cloudCoupons = rawCoupons is List
        ? rawCoupons.map((c) => c.toString()).toSet()
        : {};

    final rawTxList = rawCloudState['transactions'];
    final List<WalletTransaction> cloudTransactions = [];
    if (rawTxList is List) {
      for (final item in rawTxList) {
        if (item is Map) {
          try {
            cloudTransactions.add(WalletTransaction.fromJson(Map<String, dynamic>.from(item)));
          } catch (_) {}
        }
      }
    }

    // Merge coupons: union of local and cloud
    final prevCouponsCount = _redeemedCoupons.length;
    _redeemedCoupons = _redeemedCoupons.union(cloudCoupons);
    if (_redeemedCoupons.length != prevCouponsCount) {
      changed = true;
    }

    // Merge transactions: deduplicate by referenceId or id
    final existingRefIds = <String>{};
    final existingIds = <String>{};
    for (final tx in _transactions) {
      if (tx.referenceId != null && tx.referenceId!.isNotEmpty) {
        existingRefIds.add(tx.referenceId!);
      }
      existingIds.add(tx.id);
    }

    for (final ctx in cloudTransactions) {
      final hasRef = ctx.referenceId != null && ctx.referenceId!.isNotEmpty;
      final alreadyPresent = (hasRef && existingRefIds.contains(ctx.referenceId)) ||
          existingIds.contains(ctx.id);
      if (!alreadyPresent) {
        _transactions.add(ctx);
        if (hasRef) existingRefIds.add(ctx.referenceId!);
        existingIds.add(ctx.id);
        changed = true;
      }
    }

    // Ensure all redeemed coupons have a transaction recorded
    for (final couponCode in _redeemedCoupons) {
      final hasTx = _transactions.any(
        (tx) => tx.category == WalletTransactionCategory.coupon && tx.referenceId == couponCode,
      );
      if (!hasTx) {
        final points = availableCoupons[couponCode] ?? 100;
        final tx = WalletTransaction(
          id: const Uuid().v4(),
          title: 'Redeemed Coupon: $couponCode',
          amount: points,
          type: WalletTransactionType.credit,
          category: WalletTransactionCategory.coupon,
          timestamp: DateTime.now(),
          referenceId: couponCode,
        );
        _transactions.add(tx);
        changed = true;
      }
    }

    // Sort transactions descending by timestamp
    _transactions.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Reconcile balance
    final calculatedLedger = _transactions.fold<int>(
      0,
      (sum, tx) => sum + (tx.isCredit ? tx.amount : -tx.amount),
    );
    final highestBalance = [
      _balance,
      cloudBalance,
      calculatedLedger,
    ].reduce((curr, next) => curr > next ? curr : next);

    if (_balance != highestBalance) {
      _balance = highestBalance;
      changed = true;
    }

    return changed;
  }

  /// Checks whether the current user is active as a proxy requester (delegated) in an event.
  Future<bool> isUserProxyDelegated(String eventId) async {
    final user = _currentUser;
    if (user == null) return false;
    try {
      final res = await Supabase.instance.client
          .from('proxy_attendance_sessions')
          .select('id')
          .eq('event_id', eventId)
          .eq('requester_user_id', user.id)
          .eq('status', 'active')
          .maybeSingle();
      return res != null;
    } catch (_) {
      return false;
    }
  }

  /// Credits points earned immediately when a quest is verified in the app.
  /// Enforces ADR 0002: Gamified quest completion points are blocked while attendance is delegated to a proxy.
  Future<void> creditQuestPoints({
    required int points,
    required String activityTitle,
    required String activityId,
    String? eventId,
  }) async {
    if (points <= 0) return;

    if (eventId != null && await isUserProxyDelegated(eventId)) {
      debugPrint('WalletService: Quest points blocked because user attendance is currently delegated to a proxy');
      return;
    }

    // Check idempotency
    final exists = _transactions.any(
      (tx) => tx.category == WalletTransactionCategory.quest && tx.referenceId == activityId,
    );
    if (exists) return;

    final tx = WalletTransaction(
      id: const Uuid().v4(),
      title: 'Quest Completed: $activityTitle',
      amount: points,
      type: WalletTransactionType.credit,
      category: WalletTransactionCategory.quest,
      timestamp: DateTime.now(),
      referenceId: activityId,
    );

    _transactions.insert(0, tx);
    _balance += points;
    await _saveToLocal();
    await _saveToCloud();
    notifyListeners();
  }

  /// Redeems a promotional coupon code and credits its corresponding points.
  Future<Map<String, dynamic>> redeemCoupon(String inputCode) async {
    final code = inputCode.trim().toUpperCase();
    if (code.isEmpty) {
      return {
        'success': false,
        'message': 'Please enter a coupon code.',
      };
    }

    if (_redeemedCoupons.contains(code)) {
      return {
        'success': false,
        'message': 'This coupon code has already been redeemed.',
      };
    }

    final points = availableCoupons[code];
    if (points == null || points <= 0) {
      return {
        'success': false,
        'message': 'Invalid coupon code. Please check the spelling.',
      };
    }

    // Apply credit
    _balance += points;
    _redeemedCoupons.add(code);

    final tx = WalletTransaction(
      id: const Uuid().v4(),
      title: 'Redeemed Coupon: $code',
      amount: points,
      type: WalletTransactionType.credit,
      category: WalletTransactionCategory.coupon,
      timestamp: DateTime.now(),
      referenceId: code,
    );
    _transactions.insert(0, tx);

    await _saveToLocal();
    await _saveToCloud();
    notifyListeners();

    return {
      'success': true,
      'points': points,
      'message': '🎉 Successfully redeemed coupon! +$points PTS added to your wallet.',
    };
  }

  /// Debits points from the wallet for purchasing an event ticket.
  /// Returns `true` if payment succeeded, or `false` if balance was insufficient.
  Future<bool> debitForTicket({
    required int price,
    required String eventName,
    required String eventId,
  }) async {
    if (price <= 0) {
      return true; // Free ticket requires no debit
    }

    if (_balance < price) {
      return false; // Insufficient points
    }

    _balance -= price;
    final tx = WalletTransaction(
      id: const Uuid().v4(),
      title: 'Ticket Purchase: $eventName',
      amount: price,
      type: WalletTransactionType.debit,
      category: WalletTransactionCategory.ticketPurchase,
      timestamp: DateTime.now(),
      referenceId: eventId,
    );
    _transactions.insert(0, tx);

    await _saveToLocal();
    await _saveToCloud();
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
