import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../design_system/design_system.dart';
import '../../../utils/date_formatter.dart';
import '../data/wallet_service.dart';
import '../models/wallet_transaction.dart';

/// Spatially Attendee — Points Wallet Screen.
/// 
/// Allows attendees to:
/// 1. View their live points balance.
/// 2. View lifetime credited and debited points.
/// 3. Redeem promotional coupon codes with instant wallet credit.
/// 4. Inspect full history of credits and debits (quests, coupons, tickets).
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final WalletService _walletService = WalletService.instance;
  final TextEditingController _couponController = TextEditingController();

  String _filter = 'All'; // 'All' | 'Credits' | 'Debits'
  bool _isSubmittingCoupon = false;
  String? _couponMessage;
  bool _couponSuccess = false;

  @override
  void initState() {
    super.initState();
    _walletService.init();
    _walletService.addListener(_onWalletChanged);
  }

  @override
  void dispose() {
    _walletService.removeListener(_onWalletChanged);
    _couponController.dispose();
    super.dispose();
  }

  void _onWalletChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _handleRedeemCoupon() async {
    final code = _couponController.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _isSubmittingCoupon = true;
      _couponMessage = null;
    });

    final res = await _walletService.redeemCoupon(code);

    if (mounted) {
      setState(() {
        _isSubmittingCoupon = false;
        _couponSuccess = res['success'] == true;
        _couponMessage = res['message']?.toString();
      });

      if (_couponSuccess) {
        _couponController.clear();
      }
    }
  }

  List<WalletTransaction> get _filteredTransactions {
    final list = _walletService.transactions;
    if (_filter == 'Credits') {
      return list.where((t) => t.isCredit).toList();
    } else if (_filter == 'Debits') {
      return list.where((t) => t.isDebit).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textPrimary =
        isDark ? SpatiallyColors.darkTextPrimary : SpatiallyColors.lightTextPrimary;
    final textSecondary =
        isDark ? SpatiallyColors.darkTextSecondary : SpatiallyColors.lightTextSecondary;

    return Scaffold(
      appBar: const SpatiallyAppBar(
        title: 'Points Wallet',
        automaticallyImplyLeading: true,
      ),
      body: RefreshIndicator(
        onRefresh: () => _walletService.refresh(),
        color: SpatiallyColors.violet,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: SpatiallySpacing.screenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Balance Hero Card
              _buildBalanceHero(isDark: isDark, textPrimary: textPrimary, textSecondary: textSecondary),

              SpatiallySpacing.gapVerticalLg,

              // 2. Coupon Redemption Card
              _buildCouponRedemptionCard(
                isDark: isDark,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
              ),

              SpatiallySpacing.gapVerticalXl,

              // 3. Transactions Ledger Section Header & Filter Tabs
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Points History',
                    style: SpatiallyTypography.sectionHeading(color: textPrimary),
                  ),
                  _buildFilterPills(isDark: isDark, textPrimary: textPrimary, textSecondary: textSecondary),
                ],
              ),

              SpatiallySpacing.gapVerticalMd,

              // 4. Transaction List
              _buildTransactionsList(isDark: isDark, textPrimary: textPrimary, textSecondary: textSecondary),

              SpatiallySpacing.gapVerticalXxl,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBalanceHero({
    required bool isDark,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0xFF1E1430),
                  const Color(0xFF14141E),
                ]
              : [
                  const Color(0xFFF3EEFF),
                  const Color(0xFFEDE8FC),
                ],
        ),
        borderRadius: SpatiallyRadius.borderLg,
        border: Border.all(
          color: SpatiallyColors.violet.withValues(alpha: isDark ? 0.4 : 0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: SpatiallyColors.violet.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: SpatiallyColors.violet.withValues(alpha: 0.15),
                      borderRadius: SpatiallyRadius.borderSm,
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: SpatiallyColors.violet,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Available Balance',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: SpatiallyColors.violet.withValues(alpha: 0.2),
                  borderRadius: SpatiallyRadius.borderFull,
                ),
                child: Text(
                  'Spatially Economy',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: SpatiallyColors.violet,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${_walletService.balance}',
                style: GoogleFonts.inter(
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                  color: textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'PTS',
                style: GoogleFonts.audiowide(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: SpatiallyColors.violet,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Use your points to purchase event admission tickets and unlock perks.',
            style: SpatiallyTypography.caption(color: textSecondary),
          ),
          const SizedBox(height: 18),
          const Divider(height: 1, thickness: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.arrow_downward_rounded, color: SpatiallyColors.success, size: 16),
                    const SizedBox(width: 6),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Earned', style: SpatiallyTypography.caption(color: textSecondary)),
                        Text(
                          '+${_walletService.totalCredits} PTS',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: SpatiallyColors.success,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 28, color: textSecondary.withValues(alpha: 0.2)),
              const SizedBox(width: 16),
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.arrow_upward_rounded, color: SpatiallyColors.error, size: 16),
                    const SizedBox(width: 6),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Spent', style: SpatiallyTypography.caption(color: textSecondary)),
                        Text(
                          '-${_walletService.totalDebits} PTS',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: SpatiallyColors.error,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCouponRedemptionCard({
    required bool isDark,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return SpatiallyCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_offer_outlined, color: SpatiallyColors.spatialCyan, size: 20),
              const SizedBox(width: 8),
              Text(
                'Redeem Promo Coupon',
                style: SpatiallyTypography.subheading(color: textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Have a voucher or promotional code? Enter it below to claim instant bonus points.',
            style: SpatiallyTypography.secondary(color: textSecondary),
          ),
          const SizedBox(height: 16),

          // Input field and button
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _couponController,
                  textCapitalization: TextCapitalization.characters,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                    color: textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g. WELCOME100',
                    hintStyle: GoogleFonts.inter(
                      color: textSecondary.withValues(alpha: 0.6),
                      letterSpacing: 0.5,
                    ),
                    filled: true,
                    fillColor: isDark
                        ? SpatiallyColors.darkSurfaceElevated
                        : SpatiallyColors.lightSurfaceElevated,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: SpatiallyRadius.borderSm,
                      borderSide: BorderSide(
                        color: isDark
                            ? SpatiallyColors.darkBorderSubdued
                            : SpatiallyColors.lightBorderSubdued,
                      ),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: SpatiallyRadius.borderSm,
                      borderSide: BorderSide(color: SpatiallyColors.violet, width: 1.5),
                    ),
                    prefixIcon: const Icon(Icons.confirmation_number_outlined, size: 20),
                  ),
                  onSubmitted: (_) => _handleRedeemCoupon(),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _isSubmittingCoupon ? null : _handleRedeemCoupon,
                style: ElevatedButton.styleFrom(
                  backgroundColor: SpatiallyColors.violet,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  shape: const RoundedRectangleBorder(borderRadius: SpatiallyRadius.borderSm),
                ),
                child: _isSubmittingCoupon
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Redeem',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ],
          ),

          if (_couponMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _couponSuccess
                    ? SpatiallyColors.success.withValues(alpha: 0.12)
                    : SpatiallyColors.error.withValues(alpha: 0.12),
                borderRadius: SpatiallyRadius.borderSm,
                border: Border.all(
                  color: _couponSuccess
                      ? SpatiallyColors.success.withValues(alpha: 0.3)
                      : SpatiallyColors.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _couponSuccess ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                    size: 18,
                    color: _couponSuccess ? SpatiallyColors.success : SpatiallyColors.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _couponMessage!,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _couponSuccess ? SpatiallyColors.success : SpatiallyColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),
          // Suggested coupons pills
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Try codes:',
                style: GoogleFonts.inter(fontSize: 12, color: textSecondary, fontWeight: FontWeight.w500),
              ),
              ...['WELCOME100', 'BONUS200', 'SPATIAL50', 'QUESTMASTER'].map((code) {
                final isUsed = _walletService.redeemedCoupons.contains(code);
                return InkWell(
                  onTap: isUsed
                      ? null
                      : () {
                          _couponController.text = code;
                          _handleRedeemCoupon();
                        },
                  borderRadius: SpatiallyRadius.borderFull,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isUsed
                          ? textSecondary.withValues(alpha: 0.1)
                          : SpatiallyColors.violet.withValues(alpha: 0.1),
                      borderRadius: SpatiallyRadius.borderFull,
                      border: Border.all(
                        color: isUsed
                            ? textSecondary.withValues(alpha: 0.2)
                            : SpatiallyColors.violet.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          code,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isUsed ? textSecondary : SpatiallyColors.violet,
                            decoration: isUsed ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        if (isUsed) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.check, size: 12, color: SpatiallyColors.success),
                        ],
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPills({
    required bool isDark,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: ['All', 'Credits', 'Debits'].map((filterOption) {
        final isSelected = _filter == filterOption;
        return Padding(
          padding: const EdgeInsets.only(left: 6),
          child: InkWell(
            onTap: () => setState(() => _filter = filterOption),
            borderRadius: SpatiallyRadius.borderFull,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? SpatiallyColors.violet
                    : (isDark ? SpatiallyColors.darkSurface : SpatiallyColors.lightSurface),
                borderRadius: SpatiallyRadius.borderFull,
                border: Border.all(
                  color: isSelected
                      ? SpatiallyColors.violet
                      : (isDark ? SpatiallyColors.darkBorderSubdued : SpatiallyColors.lightBorderSubdued),
                ),
              ),
              child: Text(
                filterOption,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : textSecondary,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTransactionsList({
    required bool isDark,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    final list = _filteredTransactions;

    if (list.isEmpty) {
      return SpatiallyCard(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.history_toggle_off_rounded, size: 40, color: textSecondary.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(
                'No Transactions Yet',
                style: SpatiallyTypography.subheading(color: textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                'Complete gamified event quests or redeem promo coupons to earn points.',
                style: SpatiallyTypography.secondary(color: textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: list.length,
      separatorBuilder: (context, index) => SpatiallySpacing.gapVerticalSm,
      itemBuilder: (context, index) {
        final tx = list[index];
        final isCredit = tx.isCredit;
        final dateStr = SpatiallyDateFormatter.formatDateTime(tx.timestamp.toIso8601String(), includeYear: true);

        IconData catIcon;
        Color catColor;
        switch (tx.category) {
          case WalletTransactionCategory.quest:
            catIcon = Icons.military_tech_rounded;
            catColor = SpatiallyColors.spatialCyan;
            break;
          case WalletTransactionCategory.coupon:
            catIcon = Icons.local_offer_rounded;
            catColor = SpatiallyColors.violet;
            break;
          case WalletTransactionCategory.ticketPurchase:
            catIcon = Icons.confirmation_number_rounded;
            catColor = SpatiallyColors.warning;
            break;
          default:
            catIcon = Icons.swap_horiz_rounded;
            catColor = textSecondary;
        }

        return SpatiallyCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (isCredit ? SpatiallyColors.success : SpatiallyColors.error)
                      .withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                  color: isCredit ? SpatiallyColors.success : SpatiallyColors.error,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tx.title,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(catIcon, size: 12, color: catColor),
                        const SizedBox(width: 4),
                        Text(
                          dateStr,
                          style: SpatiallyTypography.caption(color: textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (isCredit ? SpatiallyColors.success : SpatiallyColors.error)
                      .withValues(alpha: 0.12),
                  borderRadius: SpatiallyRadius.borderFull,
                ),
                child: Text(
                  '${isCredit ? "+" : "-"}${tx.amount} PTS',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isCredit ? SpatiallyColors.success : SpatiallyColors.error,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
