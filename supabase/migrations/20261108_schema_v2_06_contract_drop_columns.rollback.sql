-- ============================================================================
-- SPATIALLY — SCHEMA V2.1: MIGRATION 06 ROLLBACK
-- File: 20261108_schema_v2_06_contract_drop_columns.rollback.sql
-- Description:
--   Rolls back Migration 06 by restoring dropped denormalized columns on base
--   tables as nullable fields.
-- ============================================================================

-- 1. events
ALTER TABLE public.events 
  ADD COLUMN IF NOT EXISTS venue TEXT,
  ADD COLUMN IF NOT EXISTS zones TEXT[] DEFAULT '{}'::text[],
  ADD COLUMN IF NOT EXISTS organizer_name TEXT,
  ADD COLUMN IF NOT EXISTS start_time TEXT,
  ADD COLUMN IF NOT EXISTS end_time TEXT,
  ADD COLUMN IF NOT EXISTS event_date TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS location_address TEXT;

-- 2. operational_incidents
ALTER TABLE public.operational_incidents 
  ADD COLUMN IF NOT EXISTS venue_zone_name TEXT,
  ADD COLUMN IF NOT EXISTS assigned_to_name TEXT;

-- 3. event_teams
ALTER TABLE public.event_teams 
  ADD COLUMN IF NOT EXISTS zone_name TEXT;

-- 4. volunteer_shifts
ALTER TABLE public.volunteer_shifts 
  ADD COLUMN IF NOT EXISTS zone_name TEXT;

-- 5. coverage_requests
ALTER TABLE public.coverage_requests 
  ADD COLUMN IF NOT EXISTS requester_name TEXT,
  ADD COLUMN IF NOT EXISTS covering_volunteer_name TEXT,
  ADD COLUMN IF NOT EXISTS team_name TEXT,
  ADD COLUMN IF NOT EXISTS zone_name TEXT;

-- 6. supervisor_tasks
ALTER TABLE public.supervisor_tasks 
  ADD COLUMN IF NOT EXISTS team_name TEXT,
  ADD COLUMN IF NOT EXISTS assigned_to_name TEXT,
  ADD COLUMN IF NOT EXISTS supervisor_name TEXT,
  ADD COLUMN IF NOT EXISTS zone_name TEXT;

-- 7. safety_resources
ALTER TABLE public.safety_resources 
  ADD COLUMN IF NOT EXISTS zone_name TEXT;

-- 8. lost_found_reports
ALTER TABLE public.lost_found_reports 
  ADD COLUMN IF NOT EXISTS venue_zone_name TEXT;

