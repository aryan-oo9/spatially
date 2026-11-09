-- ============================================================================
-- SPATIALLY — SCHEMA V2.1: MIGRATION 05B (EVENTS TIMEZONE COLUMN)
-- File: 20261108_schema_v2_05b_events_timezone.sql
-- Description: Adds timezone column to events table (defaults to UTC).
-- ============================================================================

ALTER TABLE public.events 
  ADD COLUMN IF NOT EXISTS timezone TEXT NOT NULL DEFAULT 'UTC';

