-- ============================================================================
-- SPATIALLY — SCHEMA V2.1: MIGRATION 02 ROLLBACK SCRIPT
-- File: 20261108_schema_v2_02_uuid_keys_profiles.rollback.sql
-- Description: Reverses all changes introduced in Migration 02.
-- ============================================================================

-- 1. Revert standardized profiles FKs
ALTER TABLE public.tickets DROP CONSTRAINT IF EXISTS fk_tickets_checked_in_by_profile;
ALTER TABLE public.tickets DROP CONSTRAINT IF EXISTS fk_tickets_user_profile;
ALTER TABLE public.lost_found_reports DROP CONSTRAINT IF EXISTS fk_lost_found_reporter_profile;
ALTER TABLE public.operational_incident_logs DROP CONSTRAINT IF EXISTS fk_incident_logs_actor_profile;
ALTER TABLE public.operational_incidents DROP CONSTRAINT IF EXISTS fk_incidents_assigned_to_profile;
ALTER TABLE public.operational_incidents DROP CONSTRAINT IF EXISTS fk_incidents_reporter_profile;
ALTER TABLE public.supervisor_tasks DROP CONSTRAINT IF EXISTS fk_tasks_supervisor_profile;
ALTER TABLE public.supervisor_tasks DROP CONSTRAINT IF EXISTS fk_tasks_assigned_to_profile;
ALTER TABLE public.coverage_requests DROP CONSTRAINT IF EXISTS fk_coverage_requests_covering_profile;
ALTER TABLE public.coverage_requests DROP CONSTRAINT IF EXISTS fk_coverage_requests_requester_profile;
ALTER TABLE public.shift_breaks DROP CONSTRAINT IF EXISTS fk_shift_breaks_volunteer_profile;
ALTER TABLE public.volunteer_shifts DROP CONSTRAINT IF EXISTS fk_volunteer_shifts_supervisor_profile;
ALTER TABLE public.volunteer_shifts DROP CONSTRAINT IF EXISTS fk_volunteer_shifts_volunteer_profile;
ALTER TABLE public.event_team_members DROP CONSTRAINT IF EXISTS fk_team_members_volunteer_profile;
ALTER TABLE public.event_teams DROP CONSTRAINT IF EXISTS fk_event_teams_lead_profile;

-- 2. Revert safety_resources poi_id
DROP INDEX IF EXISTS public.idx_safety_resources_poi;
ALTER TABLE public.safety_resources DROP CONSTRAINT IF EXISTS fk_safety_resources_poi;
ALTER TABLE public.safety_resources ALTER COLUMN poi_id TYPE TEXT USING poi_id::text;

-- 3. Revert observations and volunteer_counts zone_id
DROP INDEX IF EXISTS public.idx_volunteer_counts_event_zone;
ALTER TABLE public.volunteer_counts DROP COLUMN IF EXISTS zone_id;

DROP INDEX IF EXISTS public.idx_observations_event_zone_scanned;
ALTER TABLE public.observations DROP COLUMN IF EXISTS zone_id;

-- 4. Revert event_activity_logs actor_id
DROP INDEX IF EXISTS public.idx_activity_logs_actor;
ALTER TABLE public.event_activity_logs DROP CONSTRAINT IF EXISTS fk_activity_logs_actor_profile;
ALTER TABLE public.event_activity_logs ALTER COLUMN actor_id TYPE TEXT USING actor_id::text;

-- 5. Revert event_invitations
DROP INDEX IF EXISTS public.idx_event_invitations_invited_by;
DROP INDEX IF EXISTS public.idx_event_invitations_volunteer;
ALTER TABLE public.event_invitations DROP CONSTRAINT IF EXISTS fk_invitations_invited_by_profile;
ALTER TABLE public.event_invitations DROP CONSTRAINT IF EXISTS fk_invitations_volunteer_profile;
ALTER TABLE public.event_invitations ALTER COLUMN invited_by TYPE TEXT USING invited_by::text;
ALTER TABLE public.event_invitations ALTER COLUMN volunteer_id TYPE TEXT USING volunteer_id::text;
ALTER TABLE public.event_invitations RENAME COLUMN volunteer_id TO volunteer_user_id;

-- 6. Revert events organizer_id
DROP INDEX IF EXISTS public.idx_events_organizer_id;
ALTER TABLE public.events DROP CONSTRAINT IF EXISTS fk_events_organizer_profile;
ALTER TABLE public.events ALTER COLUMN organizer_id TYPE TEXT USING organizer_id::text;

