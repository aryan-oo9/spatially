import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:attendee_mobile/features/wallet/data/wallet_service.dart';
import 'package:attendee_mobile/features/wallet/models/wallet_transaction.dart';
import 'package:attendee_mobile/features/explore/models/spatially_event.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SpatiallyEvent Ticket Price Parsing Tests', () {
    test('parses ticket_price from explicit field', () {
      final json = {
        'id': 'evt-1',
        'title': 'Tech Summit 2026',
        'ticket_price': 150,
      };
      final event = SpatiallyEvent.fromJson(json);
      expect(event.ticketPrice, 150);
      expect(event.isFree, false);
      expect(event.priceLabel, '150 PTS');
    });

    test('parses ticket_price from description tag fallback', () {
      final json = {
        'id': 'evt-2',
        'title': 'AI Hackathon',
        'description': 'Welcome to the hackathon! [TICKET_PRICE:250] Enjoy.',
      };
      final event = SpatiallyEvent.fromJson(json);
      expect(event.ticketPrice, 250);
      expect(event.isFree, false);
      expect(event.priceLabel, '250 PTS');
      expect(event.description.contains('[TICKET_PRICE'), false);
    });

    test('defaults to 0 for free event when omitted', () {
      final json = {
        'id': 'evt-3',
        'title': 'Open Community Meetup',
      };
      final event = SpatiallyEvent.fromJson(json);
      expect(event.ticketPrice, 0);
      expect(event.isFree, true);
      expect(event.priceLabel, 'Free Admission');
    });
  });

  group('WalletService Unit Tests', () {
    late WalletService walletService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      walletService = WalletService.instance;
      // Pre-seed some balance for tests
      await walletService.creditQuestPoints(
        points: 100,
        activityTitle: 'Initial Welcome Quest',
        activityId: 'initial-quest-seed',
      );
    });

    test('has valid balance after initial points credit', () {
      expect(walletService.balance >= 100, true);
      expect(walletService.transactions.isNotEmpty, true);
    });

    test('redeems valid coupon successfully', () async {
      final initialBalance = walletService.balance;
      final result = await walletService.redeemCoupon('SPATIAL50');

      expect(result['success'], true);
      expect(result['points'], 50);
      expect(walletService.balance, initialBalance + 50);

      // Verify transaction added
      final latest = walletService.transactions.first;
      expect(latest.type, WalletTransactionType.credit);
      expect(latest.category, WalletTransactionCategory.coupon);
      expect(latest.amount, 50);
    });

    test('rejects duplicate coupon redemption', () async {
      await walletService.redeemCoupon('WELCOME100');
      final secondTry = await walletService.redeemCoupon('WELCOME100');

      expect(secondTry['success'], false);
      expect((secondTry['message'] as String).contains('already been redeemed'), true);
    });

    test('rejects invalid coupon code', () async {
      final result = await walletService.redeemCoupon('INVALIDCODE999');

      expect(result['success'], false);
      expect((result['message'] as String).contains('Invalid'), true);
    });

    test('debits points for ticket purchase if balance is sufficient', () async {
      final startingBalance = walletService.balance;
      final success = await walletService.debitForTicket(
        eventName: 'Tech Summit 2026',
        eventId: 'evt-test-1',
        price: 50,
      );

      expect(success, true);
      expect(walletService.balance, startingBalance - 50);

      final latest = walletService.transactions.first;
      expect(latest.type, WalletTransactionType.debit);
      expect(latest.category, WalletTransactionCategory.ticketPurchase);
      expect(latest.amount, 50);
    });

    test('refuses debit if points balance is insufficient', () async {
      final startingBalance = walletService.balance;
      final success = await walletService.debitForTicket(
        eventName: 'VIP Gala',
        eventId: 'evt-vip',
        price: startingBalance + 10000,
      );

      expect(success, false);
      expect(walletService.balance, startingBalance);
    });

    test('credits quest points accurately', () async {
      final startingBalance = walletService.balance;
      await walletService.creditQuestPoints(
        activityTitle: 'Find Booth B-101',
        points: 40,
        activityId: 'activity-xyz-unique-123',
      );

      expect(walletService.balance, startingBalance + 40);
      final latest = walletService.transactions.first;
      expect(latest.type, WalletTransactionType.credit);
      expect(latest.category, WalletTransactionCategory.quest);
      expect(latest.amount, 40);
    });
  });
}
