import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:attendee_mobile/features/wallet/data/wallet_service.dart';
import 'package:attendee_mobile/features/wallet/models/wallet_transaction.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('WalletService Unit Tests', () {
    test('Initializes with empty or zero state', () async {
      final wallet = WalletService.instance;
      await wallet.init(forceRefresh: true);

      expect(wallet.isInitialized, isTrue);
      expect(wallet.balance, equals(0));
      expect(wallet.transactions, isEmpty);
      expect(wallet.redeemedCoupons, isEmpty);
    });

    test('Redeems a valid coupon code, updates balance, and records transaction', () async {
      final wallet = WalletService.instance;
      await wallet.init(forceRefresh: true);

      final res = await wallet.redeemCoupon('WELCOME100');
      expect(res['success'], isTrue);
      expect(res['points'], equals(100));
      expect(wallet.balance, equals(100));
      expect(wallet.redeemedCoupons.contains('WELCOME100'), isTrue);
      expect(wallet.transactions.length, equals(1));
      expect(wallet.transactions.first.amount, equals(100));
      expect(wallet.transactions.first.type, equals(WalletTransactionType.credit));
      expect(wallet.transactions.first.category, equals(WalletTransactionCategory.coupon));
    });

    test('Rejects duplicate coupon redemption', () async {
      final wallet = WalletService.instance;
      await wallet.init(forceRefresh: true);

      final firstRes = await wallet.redeemCoupon('SPATIAL50');
      expect(firstRes['success'], isTrue);

      final secondRes = await wallet.redeemCoupon('SPATIAL50');
      expect(secondRes['success'], isFalse);
      expect(secondRes['message'], contains('already been redeemed'));
    });

    test('Debits points correctly for ticket purchase', () async {
      final wallet = WalletService.instance;
      await wallet.init(forceRefresh: true);

      await wallet.redeemCoupon('BONUS200'); // +200 PTS
      final initialBalance = wallet.balance;

      final debited = await wallet.debitForTicket(
        price: 50,
        eventName: 'Exclusive Concert',
        eventId: 'event-xyz',
      );

      expect(debited, isTrue);
      expect(wallet.balance, equals(initialBalance - 50));
      expect(wallet.totalDebits, equals(50));
      expect(wallet.transactions.first.isDebit, isTrue);
    });

    test('Rejects ticket debit if points balance is insufficient', () async {
      final wallet = WalletService.instance;
      await wallet.init(forceRefresh: true);

      final debited = await wallet.debitForTicket(
        price: 9999,
        eventName: 'VIP Gala',
        eventId: 'event-vip',
      );

      expect(debited, isFalse);
    });

    test('WalletTransaction JSON roundtrip parses reference_id and referenceId', () {
      final json1 = {
        'id': 'tx-1',
        'title': 'Test Credit',
        'amount': 150,
        'type': 'credit',
        'category': 'coupon',
        'timestamp': DateTime.now().toIso8601String(),
        'reference_id': 'TEST_REF',
      };
      final tx1 = WalletTransaction.fromJson(json1);
      expect(tx1.referenceId, equals('TEST_REF'));

      final json2 = {
        'id': 'tx-2',
        'title': 'Test Credit 2',
        'amount': 250,
        'type': 'credit',
        'category': 'quest',
        'timestamp': DateTime.now().toIso8601String(),
        'referenceId': 'QUEST_CAMEL',
      };
      final tx2 = WalletTransaction.fromJson(json2);
      expect(tx2.referenceId, equals('QUEST_CAMEL'));
    });

    test('reconcileWithRemoteState imports 400 points and all coupons onto a fresh device', () async {
      final wallet = WalletService.instance;
      await wallet.init(forceRefresh: true);
      expect(wallet.balance, equals(0));
      expect(wallet.redeemedCoupons, isEmpty);

      // Simulate remote cloud payload created from Phone 1
      final remoteCloudState = {
        'balance': 400,
        'redeemed_coupons': ['WELCOME100', 'BONUS200', 'SPATIAL50', 'QUESTMASTER'],
        'transactions': [
          {
            'id': 'tx-remote-1',
            'title': 'Redeemed Coupon: WELCOME100',
            'amount': 100,
            'type': 'credit',
            'category': 'coupon',
            'timestamp': DateTime.now().toIso8601String(),
            'reference_id': 'WELCOME100',
          },
          {
            'id': 'tx-remote-2',
            'title': 'Redeemed Coupon: BONUS200',
            'amount': 200,
            'type': 'credit',
            'category': 'coupon',
            'timestamp': DateTime.now().toIso8601String(),
            'reference_id': 'BONUS200',
          },
          {
            'id': 'tx-remote-3',
            'title': 'Redeemed Coupon: SPATIAL50',
            'amount': 50,
            'type': 'credit',
            'category': 'coupon',
            'timestamp': DateTime.now().toIso8601String(),
            'reference_id': 'SPATIAL50',
          },
          {
            'id': 'tx-remote-4',
            'title': 'Redeemed Coupon: QUESTMASTER',
            'amount': 150,
            'type': 'credit',
            'category': 'coupon',
            'timestamp': DateTime.now().toIso8601String(),
            'reference_id': 'QUESTMASTER',
          },
          {
            'id': 'tx-remote-5',
            'title': 'Ticket Purchase: Tech Summit',
            'amount': 100,
            'type': 'debit',
            'category': 'ticketPurchase',
            'timestamp': DateTime.now().toIso8601String(),
            'reference_id': 'ticket-abc',
          },
        ],
      };

      final changed = wallet.reconcileWithRemoteState(remoteCloudState);
      expect(changed, isTrue);
      expect(wallet.balance, equals(400));
      expect(wallet.redeemedCoupons.length, equals(4));
      expect(wallet.redeemedCoupons.contains('WELCOME100'), isTrue);
      expect(wallet.redeemedCoupons.contains('BONUS200'), isTrue);
      expect(wallet.redeemedCoupons.contains('SPATIAL50'), isTrue);
      expect(wallet.redeemedCoupons.contains('QUESTMASTER'), isTrue);
      expect(wallet.transactions.length, equals(5));

      // Attempting to redeem already used coupon is rejected
      final secondTry = await wallet.redeemCoupon('WELCOME100');
      expect(secondTry['success'], isFalse);
      expect(secondTry['message'], contains('already been redeemed'));
    });

    test('reconcileWithRemoteState unions multi-device actions without duplicates', () async {
      final wallet = WalletService.instance;
      await wallet.init(forceRefresh: true);

      // Local device already redeemed COMMUNITY25
      await wallet.redeemCoupon('COMMUNITY25'); // +25 PTS
      expect(wallet.balance, equals(25));
      expect(wallet.redeemedCoupons, contains('COMMUNITY25'));

      // Remote cloud state from another device that redeemed FESTIVAL250
      final remoteCloudState = {
        'balance': 250,
        'redeemed_coupons': ['FESTIVAL250'],
        'transactions': [
          {
            'id': 'tx-remote-festival',
            'title': 'Redeemed Coupon: FESTIVAL250',
            'amount': 250,
            'type': 'credit',
            'category': 'coupon',
            'timestamp': DateTime.now().toIso8601String(),
            'reference_id': 'FESTIVAL250',
          },
        ],
      };

      wallet.reconcileWithRemoteState(remoteCloudState);

      // Union of both coupons
      expect(wallet.redeemedCoupons.contains('COMMUNITY25'), isTrue);
      expect(wallet.redeemedCoupons.contains('FESTIVAL250'), isTrue);
      expect(wallet.balance, equals(275)); // 25 + 250
      expect(wallet.transactions.length, equals(2));
    });
  });
}
