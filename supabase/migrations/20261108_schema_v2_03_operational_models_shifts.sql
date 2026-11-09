-- ============================================================================
-- SPATIALLY — SCHEMA V2.1: MIGRATION 03 (OPERATIONAL MODELS, SHIFTS & MESSAGES)
-- File: 20261108_schema_v2_03_operational_models_shifts.sql
-- Description:
--   1. Fixes volunteer_counts primary key to composite (event_id, volunteer_id).
--   2. Links volunteer_shifts.assignment_id to volunteer_assignments(id) (ON DELETE CASCADE).
--   3. Renames operational_messages.target_id to target_user_id with profile FK
--      and enforces chk_operational_message_target constraint.
--   4. Converts shift_handoffs unresolved_incident_ids and pending_task_ids to uuid[].
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. VOLUNTEER_COUNTS: COMPOSITE PRIMARY KEY (event_id, volunteer_id)
-- ----------------------------------------------------------------------------

-- Quarantine and remove any records where event_id is NULL
INSERT INTO public.migration_quarantine (source_table, record_id, record_payload, violation_reason)
SELECT 'volunteer_counts', volunteer_id::text, to_jsonb(vc), 'volunteer_counts: NULL event_id'
FROM public.volunteer_counts vc
WHERE event_id IS NULL;

DELETE FROM public.volunteer_counts
WHERE event_id IS NULL;

-- Quarantine and remove duplicate (event_id, volunteer_id) records keeping newest updated_at
WITH duplicates AS (
  SELECT volunteer_id, event_id, ROW_NUMBER() OVER (PARTITION BY event_id, volunteer_id ORDER BY updated_at DESC) as rn
  FROM public.volunteer_counts
)
INSERT INTO public.migration_quarantine (source_table, record_id, record_payload, violation_reason)
SELECT 'volunteer_counts', d.volunteer_id::text, to_jsonb(vc), 'volunteer_counts: duplicate (event_id, volunteer_id)'
FROM duplicates d
JOIN public.volunteer_counts vc ON vc.volunteer_id = d.volunteer_id AND vc.event_id = d.event_id
WHERE d.rn > 1;

DELETE FROM public.volunteer_counts
WHERE (volunteer_id, event_id) IN (
  SELECT volunteer_id, event_id FROM (
    SELECT volunteer_id, event_id, ROW_NUMBER() OVER (PARTITION BY event_id, volunteer_id ORDER BY updated_at DESC) as rn
    FROM public.volunteer_counts
  ) d WHERE d.rn > 1
);

ALTER TABLE public.volunteer_counts
  ALTER COLUMN event_id SET NOT NULL;

-- Drop old primary key and add composite primary key
ALTER TABLE public.volunteer_counts
  DROP CONSTRAINT IF EXISTS volunteer_counts_pkey;

ALTER TABLE public.volunteer_counts
  ADD CONSTRAINT volunteer_counts_pkey PRIMARY KEY (event_id, volunteer_id);

-- ----------------------------------------------------------------------------
-- 2. VOLUNTEER_SHIFTS: assignment_id LINKAGE TO volunteer_assignments
-- ----------------------------------------------------------------------------

ALTER TABLE public.volunteer_shifts
  ADD COLUMN IF NOT EXISTS assignment_id UUID;

-- Backfill assignments for any shifts that don't have an assignment row yet
INSERT INTO public.volunteer_assignments (event_id, volunteer_id, zone_id, role, status)
SELECT DISTINCT s.event_id, s.volunteer_id, s.zone_id, 'crowd_monitor', 'active'
FROM public.volunteer_shifts s
WHERE NOT EXISTS (
  SELECT 1 FROM public.volunteer_assignments va 
  WHERE va.event_id = s.event_id AND va.volunteer_id = s.volunteer_id
);

-- Link volunteer_shifts.assignment_id to matching volunteer_assignments row
UPDATE public.volunteer_shifts vs
SET assignment_id = va.id
FROM public.volunteer_assignments va
WHERE vs.assignment_id IS NULL
  AND vs.event_id = va.event_id
  AND vs.volunteer_id = va.volunteer_id;

-- Quarantine any unlinked shifts
INSERT INTO public.migration_quarantine (source_table, record_id, record_payload, violation_reason)
SELECT 'volunteer_shifts', id::text, to_jsonb(vs), 'volunteer_shifts: could not link to volunteer_assignments'
FROM public.volunteer_shifts vs
WHERE assignment_id IS NULL;

DELETE FROM public.volunteer_shifts
WHERE assignment_id IS NULL;

ALTER TABLE public.volunteer_shifts
  ALTER COLUMN assignment_id SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_volunteer_shifts_assignment'
  ) THEN
    ALTER TABLE public.volunteer_shifts
      ADD CONSTRAINT fk_volunteer_shifts_assignment
      FOREIGN KEY (assignment_id) REFERENCES public.volunteer_assignments(id) ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_volunteer_shifts_assignment ON public.volunteer_shifts(assignment_id);

-- ----------------------------------------------------------------------------
-- 3. OPERATIONAL_MESSAGES: target_user_id & TARGET VALIDATION CHECK
-- ----------------------------------------------------------------------------

DO $$
BEGIN
  -- Rename target_id to target_user_id if still named target_id
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'operational_messages' AND column_name = 'target_id'
  ) THEN
    ALTER TABLE public.operational_messages RENAME COLUMN target_id TO target_user_id;
  END IF;
END $$;

-- If target_type = 'zone' and target_user_id was set, shift it to zone_id
UPDATE public.operational_messages
SET 
  zone_id = COALESCE(zone_id, target_user_id),
  target_user_id = NULL
WHERE target_type = 'zone';

-- If target_type = 'event', clear targets
UPDATE public.operational_messages
SET target_user_id = NULL, zone_id = NULL
WHERE target_type = 'event';

-- Quarantine any invalid target_user_id not in profiles
INSERT INTO public.migration_quarantine (source_table, record_id, record_payload, violation_reason)
SELECT 'operational_messages', id::text, to_jsonb(om), 'operational_messages: target_user_id not in profiles'
FROM public.operational_messages om
WHERE target_user_id IS NOT NULL 
  AND target_user_id NOT IN (SELECT id FROM public.profiles);

UPDATE public.operational_messages
SET target_user_id = NULL
WHERE target_user_id IS NOT NULL 
  AND target_user_id NOT IN (SELECT id FROM public.profiles);

-- Normalize records for check constraint
UPDATE public.operational_messages
SET target_type = 'event', target_user_id = NULL, zone_id = NULL
WHERE target_type IN ('volunteer', 'organizer') AND target_user_id IS NULL;

-- Drop direct FKs on target_user_id and add profile FK
ALTER TABLE public.operational_messages
  DROP CONSTRAINT IF EXISTS operational_messages_target_id_fkey,
  DROP CONSTRAINT IF EXISTS fk_operational_messages_target_user;

ALTER TABLE public.operational_messages
  ADD CONSTRAINT fk_operational_messages_target_user
  FOREIGN KEY (target_user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Enforce target validation check
ALTER TABLE public.operational_messages
  DROP CONSTRAINT IF EXISTS chk_operational_message_target;

ALTER TABLE public.operational_messages
  ADD CONSTRAINT chk_operational_message_target CHECK (
    (target_type = 'event' AND target_user_id IS NULL AND zone_id IS NULL) OR
    (target_type = 'zone' AND zone_id IS NOT NULL AND target_user_id IS NULL) OR
    (target_type IN ('volunteer', 'organizer') AND target_user_id IS NOT NULL)
  );

CREATE INDEX IF NOT EXISTS idx_operational_messages_target_user 
  ON public.operational_messages (event_id, target_user_id);

-- ----------------------------------------------------------------------------
-- 4. SHIFT_HANDOFFS: UUID ARRAYS FOR UNRESOLVED INCIDENTS AND PENDING TASKS
-- ----------------------------------------------------------------------------

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'shift_handoffs'
  ) THEN
    -- Drop old JSONB columns and recreate as native UUID[] columns with empty defaults
    ALTER TABLE public.shift_handoffs
      DROP COLUMN IF EXISTS unresolved_incident_ids,
      DROP COLUMN IF EXISTS pending_task_ids;

    ALTER TABLE public.shift_handoffs
      ADD COLUMN unresolved_incident_ids UUID[] NOT NULL DEFAULT '{}'::uuid[],
      ADD COLUMN pending_task_ids UUID[] NOT NULL DEFAULT '{}'::uuid[];
  END IF;
END $$;

