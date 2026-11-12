import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/wallet_transaction.dart';

/// Service managing the attendee's Points Wallet.
/// 
/// Features:
/// - Balance calculation and real-time reactive notifications (via ChangeNotifier).
/// - Ledger of credit and debit transactions.
/// - Coupon code redemption with one-time verification.
/// - Offline persistence via SharedPreferences, keyed per user account.
/// - Automatic reconciliation with Supabase gamified quest completions (`attendee_engagements`).
class WalletService extends ChangeNotifier {
  static final WalletService _instance = WalletService._internal();
  static WalletService get instance => _instance;

  WalletService._internal();

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

  /// Initializes the wallet for the currently active user session.
  Future<void> init() async {
    final user = Supabase.instance.client.auth.currentUser;
    final userId = user?.id ?? 'guest_device';
    if (_initialized && _currentUserId == userId) {
      return;
    }
    _currentUserId = userId;
    await _loadFromLocal();
    await syncFromSupabase();
    _initialized = true;
    notifyListeners();
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

  /// Syncs quest completion points from Supabase `attendee_engagements` table.
  /// Any quest points earned that are not yet in the wallet transactions ledger
  /// are automatically credited.
  Future<void> syncFromSupabase() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final res = await Supabase.instance.client
          .from('attendee_engagements')
          .select('id, event_id, reference_id, points_earned, verified_at, metadata')
          .eq('user_id', user.id)
          .eq('engagement_type', 'activity')
          .order('verified_at', ascending: true);

      bool changed = false;
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

      if (changed) {
        _transactions.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        await _saveToLocal();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Notice: Supabase quest sync unavailable (offline or network): $e');
    }
  }

  /// Credits points earned immediately when a quest is verified in the app.
  Future<void> creditQuestPoints({
    required int points,
    required String activityTitle,
    required String activityId,
  }) async {
    if (points <= 0) return;

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
    notifyListeners();
    return true;
  }
}

