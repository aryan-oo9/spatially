-- ============================================================================
-- SPATIALLY — SCHEMA V2.1: MIGRATION 03 ROLLBACK SCRIPT
-- File: 20261108_schema_v2_03_operational_models_shifts.rollback.sql
-- Description: Reverses all changes introduced in Migration 03.
-- ============================================================================

-- 1. Revert shift_handoffs columns to jsonb
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'shift_handoffs'
  ) THEN
    ALTER TABLE public.shift_handoffs
      ALTER COLUMN pending_task_ids DROP DEFAULT,
      ALTER COLUMN pending_task_ids TYPE JSONB USING to_jsonb(pending_task_ids),
      ALTER COLUMN pending_task_ids SET DEFAULT '[]'::jsonb,
      ALTER COLUMN pending_task_ids DROP NOT NULL;

    ALTER TABLE public.shift_handoffs
      ALTER COLUMN unresolved_incident_ids DROP DEFAULT,
      ALTER COLUMN unresolved_incident_ids TYPE JSONB USING to_jsonb(unresolved_incident_ids),
      ALTER COLUMN unresolved_incident_ids SET DEFAULT '[]'::jsonb,
      ALTER COLUMN unresolved_incident_ids DROP NOT NULL;
  END IF;
END $$;

-- 2. Revert operational_messages target check and columns
DROP INDEX IF EXISTS public.idx_operational_messages_target_user;
ALTER TABLE public.operational_messages DROP CONSTRAINT IF EXISTS chk_operational_message_target;
ALTER TABLE public.operational_messages DROP CONSTRAINT IF EXISTS fk_operational_messages_target_user;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'operational_messages' AND column_name = 'target_user_id'
  ) THEN
    ALTER TABLE public.operational_messages RENAME COLUMN target_user_id TO target_id;
  END IF;
END $$;

-- 3. Revert volunteer_shifts assignment_id
DROP INDEX IF EXISTS public.idx_volunteer_shifts_assignment;
ALTER TABLE public.volunteer_shifts DROP CONSTRAINT IF EXISTS fk_volunteer_shifts_assignment;
ALTER TABLE public.volunteer_shifts DROP COLUMN IF EXISTS assignment_id;

-- 4. Revert volunteer_counts primary key
ALTER TABLE public.volunteer_counts DROP CONSTRAINT IF EXISTS volunteer_counts_pkey;
ALTER TABLE public.volunteer_counts ADD CONSTRAINT volunteer_counts_pkey PRIMARY KEY (volunteer_id);
ALTER TABLE public.volunteer_counts ALTER COLUMN event_id DROP NOT NULL;

