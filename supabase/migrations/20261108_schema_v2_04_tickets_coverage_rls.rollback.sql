-- ============================================================================
-- SPATIALLY — SCHEMA V2.1: MIGRATION 04 ROLLBACK SCRIPT
-- File: 20261108_schema_v2_04_tickets_coverage_rls.rollback.sql
-- Description: Reverses all changes introduced in Migration 04.
-- ============================================================================

-- 1. Revert coverage_requests changes
DROP INDEX IF EXISTS public.idx_coverage_requests_target_shift;
DROP INDEX IF EXISTS public.idx_coverage_requests_type;
ALTER TABLE public.coverage_requests DROP CONSTRAINT IF EXISTS chk_coverage_requests_not_self;
ALTER TABLE public.coverage_requests DROP COLUMN IF EXISTS target_zone_id;
ALTER TABLE public.coverage_requests DROP COLUMN IF EXISTS target_shift_id;
ALTER TABLE public.coverage_requests DROP COLUMN IF EXISTS request_type;

-- 2. Revert attendee_engagements ticket_id
ALTER TABLE public.attendee_engagements DROP COLUMN IF EXISTS ticket_id;
ALTER TABLE public.attendee_engagements ADD COLUMN IF NOT EXISTS attendee_id UUID;

-- 3. Revert tickets user_id NOT NULL and restore columns
ALTER TABLE public.tickets ALTER COLUMN user_id DROP NOT NULL;
ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS attendee_id UUID;
ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS claim_hash TEXT;

-- 4. Restore guest claim functions
CREATE OR REPLACE FUNCTION public.claim_ticket_by_hash(p_claim_hash text, p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.tickets
  SET user_id = p_user_id, claimed_at = now()
  WHERE claim_hash = p_claim_hash;
  RETURN jsonb_build_object('success', true);
END;
$$;

