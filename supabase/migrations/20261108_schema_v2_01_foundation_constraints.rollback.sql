-- ============================================================================
-- SPATIALLY — SCHEMA V2.1: MIGRATION 01 ROLLBACK SCRIPT
-- File: 20261108_schema_v2_01_foundation_constraints.rollback.sql
-- Description: Reverses all changes introduced in Migration 01.
-- ============================================================================

-- 1. Drop Indexes
DROP INDEX IF EXISTS public.idx_observations_event_zone_scanned;
DROP INDEX IF EXISTS public.idx_venue_pois_event_zone_category;
DROP INDEX IF EXISTS public.idx_sessions_event_time;
DROP INDEX IF EXISTS public.idx_temp_chat_connection_created;
DROP INDEX IF EXISTS public.idx_connections_event_addressee;
DROP INDEX IF EXISTS public.idx_connections_event_requester;
DROP INDEX IF EXISTS public.idx_engagements_event_user;
DROP INDEX IF EXISTS public.idx_tickets_event_user;
DROP INDEX IF EXISTS public.idx_event_notifications_event_target;
DROP INDEX IF EXISTS public.idx_op_message_receipts_recipient_status;
DROP INDEX IF EXISTS public.idx_op_messages_event_zone_created;
DROP INDEX IF EXISTS public.idx_team_members_volunteer;
DROP INDEX IF EXISTS public.idx_shifts_event_zone;
DROP INDEX IF EXISTS public.idx_shifts_event_volunteer_status;
DROP INDEX IF EXISTS public.idx_coverage_requests_event_status;
DROP INDEX IF EXISTS public.idx_supervisor_tasks_event_assignee;
DROP INDEX IF EXISTS public.idx_incident_logs_incident;
DROP INDEX IF EXISTS public.idx_incidents_event_status_priority;

-- 2. Drop Check Constraints
ALTER TABLE public.attendee_connections DROP CONSTRAINT IF EXISTS chk_connections_not_self;
ALTER TABLE public.shift_breaks DROP CONSTRAINT IF EXISTS chk_shift_breaks_temporal;
ALTER TABLE public.volunteer_shifts DROP CONSTRAINT IF EXISTS chk_volunteer_shifts_temporal;
ALTER TABLE public.activities DROP CONSTRAINT IF EXISTS chk_activities_temporal;
ALTER TABLE public.sessions DROP CONSTRAINT IF EXISTS chk_sessions_temporal;
ALTER TABLE public.events DROP CONSTRAINT IF EXISTS chk_events_temporal;

-- 3. Revert Zone Threshold Constraint
ALTER TABLE public.event_zones DROP CONSTRAINT IF EXISTS chk_event_zones_thresholds;

-- Re-add previous 2-tier threshold check if desired
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conrelid = 'public.event_zones'::regclass AND conname = 'chk_event_zones_2tier'
  ) THEN
    ALTER TABLE public.event_zones 
      ADD CONSTRAINT chk_event_zones_2tier CHECK (
        warning_threshold > 0 AND warning_threshold < critical_threshold AND critical_threshold <= 1.0
      );
  END IF;
END $$;

ALTER TABLE public.event_zones DROP COLUMN IF EXISTS advisory_threshold;

-- 4. Drop Unique Constraints and Indexes
DROP INDEX IF EXISTS public.idx_uq_bidirectional_connection;
ALTER TABLE public.operational_message_receipts DROP CONSTRAINT IF EXISTS uq_message_recipient;
ALTER TABLE public.event_team_members DROP CONSTRAINT IF EXISTS uq_team_volunteer;
ALTER TABLE public.booths DROP CONSTRAINT IF EXISTS uq_event_booth_number;
ALTER TABLE public.event_zones DROP CONSTRAINT IF EXISTS uq_event_zone_code;
ALTER TABLE public.venue_zones DROP CONSTRAINT IF EXISTS uq_venue_zone_code;
ALTER TABLE public.venue_levels DROP CONSTRAINT IF EXISTS uq_venue_level_code;
ALTER TABLE public.venue_levels DROP CONSTRAINT IF EXISTS uq_venue_level_index;

-- 5. Drop Migration Quarantine Table
DROP TABLE IF EXISTS public.migration_quarantine CASCADE;

