import 'package:uuid/uuid.dart';

enum WalletTransactionType {
  credit,
  debit,
}

enum WalletTransactionCategory {
  quest,
  coupon,
  ticketPurchase,
  adjustment,
}

/// Represents an authoritative points transaction (credit or debit) in the attendee's wallet.
class WalletTransaction {
  final String id;
  final String title;
  final int amount; // positive integer, e.g. 100
  final WalletTransactionType type;
  final WalletTransactionCategory category;
  final DateTime timestamp;
  final String? referenceId;
  final Map<String, dynamic>? metadata;

  const WalletTransaction({
    required this.id,
    required this.title,
    required this.amount,
    required this.type,
    required this.category,
    required this.timestamp,
    this.referenceId,
    this.metadata,
  });

  bool get isCredit => type == WalletTransactionType.credit;
  bool get isDebit => type == WalletTransactionType.debit;

  factory WalletTransaction.fromJson(Map<String, dynamic> json) {
    return WalletTransaction(
      id: json['id']?.toString() ?? const Uuid().v4(),
      title: json['title']?.toString() ?? 'Points Transaction',
      amount: (json['amount'] as num?)?.toInt().abs() ?? 0,
      type: json['type'] == 'debit'
          ? WalletTransactionType.debit
          : WalletTransactionType.credit,
      category: _parseCategory(json['category']?.toString()),
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString())?.toLocal() ?? DateTime.now()
          : DateTime.now(),
      referenceId: json['reference_id']?.toString() ?? json['referenceId']?.toString(),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'amount': amount,
      'type': isCredit ? 'credit' : 'debit',
      'category': category.name,
      'timestamp': timestamp.toIso8601String(),
      'reference_id': referenceId,
      'metadata': metadata,
    };
  }

  static WalletTransactionCategory _parseCategory(String? cat) {
    switch (cat) {
      case 'quest':
        return WalletTransactionCategory.quest;
      case 'coupon':
        return WalletTransactionCategory.coupon;
      case 'ticketPurchase':
      case 'ticket_purchase':
        return WalletTransactionCategory.ticketPurchase;
      default:
        return WalletTransactionCategory.adjustment;
    }
  }
}

