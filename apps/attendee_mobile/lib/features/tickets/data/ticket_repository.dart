import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/auth_service.dart';
import '../../../services/offline_service.dart';
import '../../explore/data/event_cache_manager.dart';

/// Abstract contract for attendee ticket operations.
///
/// Strictly separates:
/// - GUEST DATA: tickets where `attendee_id = deviceId AND user_id IS NULL`.
/// - AUTHENTICATED USER DATA: tickets where `user_id = auth.uid()`.
abstract class TicketRepository {
  Future<List<Map<String, dynamic>>> getMyTickets();
  Future<ClaimTicketsResult> claimGuestTickets();
  Future<Map<String, dynamic>?> getGuestTicketByCode(String ticketCode);
}

/// Production implementation backed by Supabase with offline caching.
class TicketRepositoryImpl implements TicketRepository {
  final SupabaseClient _supabase;
  final EventCacheManager _cacheManager;
  final OfflineService _offlineService;

  TicketRepositoryImpl({
    SupabaseClient? supabase,
    EventCacheManager? cacheManager,
    OfflineService? offlineService,
  })  : _supabase = supabase ?? Supabase.instance.client,
        _cacheManager = cacheManager ?? EventCacheManager(),
        _offlineService = offlineService ?? OfflineService();

  @override
  Future<List<Map<String, dynamic>>> getMyTickets() async {
    final user = _supabase.auth.currentUser;
    final isOnline = await _offlineService.checkConnectivity();

    if (!isOnline) {
      return _cacheManager.getCachedTickets(userId: user?.id);
    }

    if (user == null) {
      return [];
    }

    try {
      // Authenticated User: Query tickets owned by this registered user account via RLS (ADR 0001)
      final result = await _supabase
          .from('tickets')
          .select('*, events(*, venues(*))')
          .eq('user_id', user.id)
          .order('purchased_at', ascending: false)
          .timeout(const Duration(seconds: 4));

      final tickets = List<Map<String, dynamic>>.from(result);
      await _cacheManager.cacheTickets(tickets, userId: user.id);
      _offlineService.reportSuccessfulOnlineRequest();
      return tickets;
    } catch (e) {
      debugPrint('Error fetching tickets online, falling back to cache: $e');
      _offlineService.reportFailedNetworkRequest();
      return _cacheManager.getCachedTickets(userId: user.id);
    }
  }

  @override
  Future<ClaimTicketsResult> claimGuestTickets() async {
    // ADR 0001: Anonymous guest tickets retired; registered-only tickets are bound upon creation.
    return const ClaimTicketsResult(success: true, claimedCount: 0);
  }

  @override
  Future<Map<String, dynamic>?> getGuestTicketByCode(String ticketCode) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return null;
      final res = await _supabase
          .from('tickets')
          .select('*, events(*, venues(*))')
          .eq('ticket_code', ticketCode)
          .eq('user_id', user.id)
          .maybeSingle();
      return res;
    } catch (e) {
      debugPrint('Error fetching ticket by code: $e');
      return null;
    }
  }
}
