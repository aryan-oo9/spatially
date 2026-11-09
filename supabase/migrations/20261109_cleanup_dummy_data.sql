-- ============================================================================
-- CLEANUP MIGRATION: Purge Legacy Dummy / Seed Data
-- ============================================================================
-- Keeps:
--   1. Real user accounts in public.profiles and auth.users
--   2. Venue master data in public.venues, venue_levels, venue_zones
--   3. Active 'Test' event (ba3219b7-7320-4318-98df-93bd9c0ac305) and its zones/invitations
-- Purges:
--   All dummy seed events, mock observations, shifts, incidents, assignments
-- ============================================================================

DO $$
DECLARE
    test_eid UUID := 'ba3219b7-7320-4318-98df-93bd9c0ac305';
BEGIN
    -- 1. Crowd observations & telemetry
    DELETE FROM public.observations WHERE event_id IS NULL OR event_id != test_eid;
    DELETE FROM public.volunteer_counts WHERE event_id IS NULL OR event_id != test_eid;

    -- 2. Coverage & shift handoffs
    DELETE FROM public.coverage_requests WHERE event_id != test_eid;
    DELETE FROM public.shift_handoffs WHERE event_id != test_eid;

    -- 3. Incidents & audit logs
    DELETE FROM public.operational_incident_logs WHERE event_id != test_eid;
    DELETE FROM public.operational_incidents WHERE event_id != test_eid;

    -- 4. Operational communications & receipts
    DELETE FROM public.operational_message_receipts WHERE message_id IN (
        SELECT id FROM public.operational_messages WHERE event_id != test_eid
    );
    DELETE FROM public.operational_messages WHERE event_id != test_eid;

    -- 5. Tasks & Tickets
    DELETE FROM public.supervisor_tasks WHERE event_id != test_eid;
    DELETE FROM public.tickets WHERE event_id != test_eid;

    -- 6. Shifts & Teams
    DELETE FROM public.volunteer_shifts WHERE event_id != test_eid;
    DELETE FROM public.event_team_members WHERE team_id IN (
        SELECT id FROM public.event_teams WHERE event_id != test_eid
    );
    DELETE FROM public.event_teams WHERE event_id != test_eid;

    -- 7. Assignments & Activity logs
    DELETE FROM public.volunteer_assignments WHERE event_id != test_eid;
    DELETE FROM public.event_activity_logs WHERE event_id != test_eid;

    -- 8. Invitations & Event zones
    DELETE FROM public.event_invitations WHERE event_id != test_eid;
    DELETE FROM public.event_zones WHERE event_id != test_eid;

    -- 9. Dummy events
    DELETE FROM public.events WHERE id != test_eid;

    RAISE NOTICE 'Successfully purged dummy seed data while preserving Test event and user profiles.';
END $$;

