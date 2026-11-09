-- ============================================================================
-- SPATIALLY — SCHEMA V2.1: MIGRATION 02B (DEDUPLICATE PROFILE FOREIGN KEYS)
-- File: 20261108_schema_v2_02b_dedup_profiles_fks.sql
-- Description:
--   Drops legacy duplicate foreign keys on single user columns that were pointing
--   to profiles(id) under older generated names (e.g. *_profiles_fk), leaving exactly
--   one canonical foreign key per column.
-- ============================================================================

-- 1. event_teams: drop legacy duplicate on lead_id
ALTER TABLE public.event_teams 
  DROP CONSTRAINT IF EXISTS event_teams_lead_profiles_fk;

-- 2. event_team_members: drop legacy duplicate on volunteer_id
ALTER TABLE public.event_team_members 
  DROP CONSTRAINT IF EXISTS event_team_members_volunteer_profiles_fk;

-- 3. volunteer_shifts: drop legacy duplicate on volunteer_id
ALTER TABLE public.volunteer_shifts 
  DROP CONSTRAINT IF EXISTS volunteer_shifts_volunteer_profiles_fk;

-- 4. operational_incidents: drop legacy duplicates on reporter_id and assigned_to_id
ALTER TABLE public.operational_incidents 
  DROP CONSTRAINT IF EXISTS operational_incidents_reporter_id_fkey,
  DROP CONSTRAINT IF EXISTS operational_incidents_assigned_to_id_fkey;

