-- ============================================================================
-- SPATIALLY — SCHEMA V2.1: MIGRATION 05 ROLLBACK SCRIPT
-- File: 20261108_schema_v2_05_relational_views.rollback.sql
-- Description: Reverses all changes introduced in Migration 05.
-- ============================================================================

DROP VIEW IF EXISTS public.v_event_teams;
DROP VIEW IF EXISTS public.v_safety_resources;
DROP VIEW IF EXISTS public.v_supervisor_tasks;
DROP VIEW IF EXISTS public.v_coverage_requests;
DROP VIEW IF EXISTS public.v_volunteer_shifts;
DROP VIEW IF EXISTS public.v_operational_incidents;

