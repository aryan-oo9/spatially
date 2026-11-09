-- ============================================================================
-- SPATIALLY — SCHEMA V2.1: MIGRATION 01 (FOUNDATION, CONSTRAINTS & INDEXES)
-- File: 20261108_schema_v2_01_foundation_constraints.sql
-- Description:
--   1. Creates public.migration_quarantine table for logging dirty/violating records.
--   2. Quarantines and removes duplicates, then enforces UNIQUE constraints.
--   3. Adds stored advisory_threshold to public.event_zones with 3-tier threshold check.
--   4. Quarantines invalid temporal records and enforces temporal CHECK constraints.
--   5. Creates missing operational, telemetry, shift, and networking indexes.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. MIGRATION QUARANTINE TABLE
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.migration_quarantine (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_table TEXT NOT NULL,
    record_id TEXT,
    record_payload JSONB NOT NULL,
    violation_reason TEXT NOT NULL,
    quarantined_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_quarantine_source_table 
  ON public.migration_quarantine(source_table, quarantined_at DESC);

COMMENT ON TABLE public.migration_quarantine IS 
  'Audit log of records quarantined and removed during Schema v2.1 migrations.';

-- ----------------------------------------------------------------------------
-- 2. UNIQUE CONSTRAINTS (WITH PRE-CLEAN QUARANTINE)
-- ----------------------------------------------------------------------------

-- 2.1 venue_levels: (venue_id, level_index)
WITH duplicates AS (
  SELECT id, ROW_NUMBER() OVER (PARTITION BY venue_id, level_index ORDER BY created_at ASC) as rn
  FROM public.venue_levels
  WHERE venue_id IS NOT NULL AND level_index IS NOT NULL
)
INSERT INTO public.migration_quarantine (source_table, record_id, record_payload, violation_reason)
SELECT 'venue_levels', d.id::text, to_jsonb(vl), 'Duplicate venue_levels (venue_id, level_index)'
FROM duplicates d
JOIN public.venue_levels vl ON vl.id = d.id
WHERE d.rn > 1;

DELETE FROM public.venue_levels
WHERE id IN (
  SELECT d.id FROM (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY venue_id, level_index ORDER BY created_at ASC) as rn
    FROM public.venue_levels
    WHERE venue_id IS NOT NULL AND level_index IS NOT NULL
  ) d WHERE d.rn > 1
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_venue_level_index'
  ) THEN
    ALTER TABLE public.venue_levels 
      ADD CONSTRAINT uq_venue_level_index UNIQUE (venue_id, level_index);
  END IF;
END $$;

-- 2.2 venue_levels: (venue_id, short_code)
WITH duplicates AS (
  SELECT id, ROW_NUMBER() OVER (PARTITION BY venue_id, short_code ORDER BY created_at ASC) as rn
  FROM public.venue_levels
  WHERE venue_id IS NOT NULL AND short_code IS NOT NULL
)
INSERT INTO public.migration_quarantine (source_table, record_id, record_payload, violation_reason)
SELECT 'venue_levels', d.id::text, to_jsonb(vl), 'Duplicate venue_levels (venue_id, short_code)'
FROM duplicates d
JOIN public.venue_levels vl ON vl.id = d.id
WHERE d.rn > 1;

DELETE FROM public.venue_levels
WHERE id IN (
  SELECT d.id FROM (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY venue_id, short_code ORDER BY created_at ASC) as rn
    FROM public.venue_levels
    WHERE venue_id IS NOT NULL AND short_code IS NOT NULL
  ) d WHERE d.rn > 1
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_venue_level_code'
  ) THEN
    ALTER TABLE public.venue_levels 
      ADD CONSTRAINT uq_venue_level_code UNIQUE (venue_id, short_code);
  END IF;
END $$;

-- 2.3 venue_zones: (venue_id, code)
WITH duplicates AS (
  SELECT id, ROW_NUMBER() OVER (PARTITION BY venue_id, code ORDER BY created_at ASC) as rn
  FROM public.venue_zones
  WHERE venue_id IS NOT NULL AND code IS NOT NULL
)
INSERT INTO public.migration_quarantine (source_table, record_id, record_payload, violation_reason)
SELECT 'venue_zones', d.id::text, to_jsonb(vz), 'Duplicate venue_zones (venue_id, code)'
FROM duplicates d
JOIN public.venue_zones vz ON vz.id = d.id
WHERE d.rn > 1;

DELETE FROM public.venue_zones
WHERE id IN (
  SELECT d.id FROM (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY venue_id, code ORDER BY created_at ASC) as rn
    FROM public.venue_zones
    WHERE venue_id IS NOT NULL AND code IS NOT NULL
  ) d WHERE d.rn > 1
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_venue_zone_code'
  ) THEN
    ALTER TABLE public.venue_zones 
      ADD CONSTRAINT uq_venue_zone_code UNIQUE (venue_id, code);
  END IF;
END $$;

-- 2.4 event_zones: (event_id, code)
WITH duplicates AS (
  SELECT id, ROW_NUMBER() OVER (PARTITION BY event_id, code ORDER BY created_at ASC) as rn
  FROM public.event_zones
  WHERE event_id IS NOT NULL AND code IS NOT NULL
)
INSERT INTO public.migration_quarantine (source_table, record_id, record_payload, violation_reason)
SELECT 'event_zones', d.id::text, to_jsonb(ez), 'Duplicate event_zones (event_id, code)'
FROM duplicates d
JOIN public.event_zones ez ON ez.id = d.id
WHERE d.rn > 1;

DELETE FROM public.event_zones
WHERE id IN (
  SELECT d.id FROM (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY event_id, code ORDER BY created_at ASC) as rn
    FROM public.event_zones
    WHERE event_id IS NOT NULL AND code IS NOT NULL
  ) d WHERE d.rn > 1
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_event_zone_code'
  ) THEN
    ALTER TABLE public.event_zones 
      ADD CONSTRAINT uq_event_zone_code UNIQUE (event_id, code);
  END IF;
END $$;

-- 2.5 booths: (event_id, booth_number)
WITH duplicates AS (
  SELECT id, ROW_NUMBER() OVER (PARTITION BY event_id, booth_number ORDER BY created_at ASC) as rn
  FROM public.booths
  WHERE event_id IS NOT NULL AND booth_number IS NOT NULL
)
INSERT INTO public.migration_quarantine (source_table, record_id, record_payload, violation_reason)
SELECT 'booths', d.id::text, to_jsonb(b), 'Duplicate booths (event_id, booth_number)'
FROM duplicates d
JOIN public.booths b ON b.id = d.id
WHERE d.rn > 1;

DELETE FROM public.booths
WHERE id IN (
  SELECT d.id FROM (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY event_id, booth_number ORDER BY created_at ASC) as rn
    FROM public.booths
    WHERE event_id IS NOT NULL AND booth_number IS NOT NULL
  ) d WHERE d.rn > 1
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_event_booth_number'
  ) THEN
    ALTER TABLE public.booths 
      ADD CONSTRAINT uq_event_booth_number UNIQUE (event_id, booth_number);
  END IF;
END $$;

-- 2.6 event_team_members: (team_id, volunteer_id)
WITH duplicates AS (
  SELECT id, ROW_NUMBER() OVER (PARTITION BY team_id, volunteer_id ORDER BY created_at ASC) as rn
  FROM public.event_team_members
  WHERE team_id IS NOT NULL AND volunteer_id IS NOT NULL
)
INSERT INTO public.migration_quarantine (source_table, record_id, record_payload, violation_reason)
SELECT 'event_team_members', d.id::text, to_jsonb(etm), 'Duplicate event_team_members (team_id, volunteer_id)'
FROM duplicates d
JOIN public.event_team_members etm ON etm.id = d.id
WHERE d.rn > 1;

DELETE FROM public.event_team_members
WHERE id IN (
  SELECT d.id FROM (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY team_id, volunteer_id ORDER BY created_at ASC) as rn
    FROM public.event_team_members
    WHERE team_id IS NOT NULL AND volunteer_id IS NOT NULL
  ) d WHERE d.rn > 1
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_team_volunteer'
  ) THEN
    ALTER TABLE public.event_team_members 
      ADD CONSTRAINT uq_team_volunteer UNIQUE (team_id, volunteer_id);
  END IF;
END $$;

-- 2.7 operational_message_receipts: (message_id, recipient_id)
WITH duplicates AS (
  SELECT id, ROW_NUMBER() OVER (PARTITION BY message_id, recipient_id ORDER BY created_at ASC) as rn
  FROM public.operational_message_receipts
  WHERE message_id IS NOT NULL AND recipient_id IS NOT NULL
)
INSERT INTO public.migration_quarantine (source_table, record_id, record_payload, violation_reason)
SELECT 'operational_message_receipts', d.id::text, to_jsonb(omr), 'Duplicate operational_message_receipts (message_id, recipient_id)'
FROM duplicates d
JOIN public.operational_message_receipts omr ON omr.id = d.id
WHERE d.rn > 1;

DELETE FROM public.operational_message_receipts
WHERE id IN (
  SELECT d.id FROM (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY message_id, recipient_id ORDER BY created_at ASC) as rn
    FROM public.operational_message_receipts
    WHERE message_id IS NOT NULL AND recipient_id IS NOT NULL
  ) d WHERE d.rn > 1
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_message_recipient'
  ) THEN
    ALTER TABLE public.operational_message_receipts 
      ADD CONSTRAINT uq_message_recipient UNIQUE (message_id, recipient_id);
  END IF;
END $$;

-- 2.8 attendee_connections: bidirectional uniqueness
-- Quarantine any reverse-duplicate connections (A, B) where (B, A) already exists
WITH duplicates AS (
  SELECT id, ROW_NUMBER() OVER (
    PARTITION BY event_id, LEAST(requester_id, addressee_id), GREATEST(requester_id, addressee_id)
    ORDER BY created_at ASC
  ) as rn
  FROM public.attendee_connections
  WHERE event_id IS NOT NULL AND requester_id IS NOT NULL AND addressee_id IS NOT NULL
)
INSERT INTO public.migration_quarantine (source_table, record_id, record_payload, violation_reason)
SELECT 'attendee_connections', d.id::text, to_jsonb(ac), 'Duplicate bidirectional connection'
FROM duplicates d
JOIN public.attendee_connections ac ON ac.id = d.id
WHERE d.rn > 1;

DELETE FROM public.attendee_connections
WHERE id IN (
  SELECT d.id FROM (
    SELECT id, ROW_NUMBER() OVER (
      PARTITION BY event_id, LEAST(requester_id, addressee_id), GREATEST(requester_id, addressee_id)
      ORDER BY created_at ASC
    ) as rn
    FROM public.attendee_connections
    WHERE event_id IS NOT NULL AND requester_id IS NOT NULL AND addressee_id IS NOT NULL
  ) d WHERE d.rn > 1
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_uq_bidirectional_connection
  ON public.attendee_connections (event_id, LEAST(requester_id, addressee_id), GREATEST(requester_id, addressee_id));

-- ----------------------------------------------------------------------------
-- 3. STORED ADVISORY THRESHOLD & ZONE THRESHOLD CHECK CONSTRAINT
-- ----------------------------------------------------------------------------

-- Add advisory_threshold column if missing
ALTER TABLE public.event_zones 
  ADD COLUMN IF NOT EXISTS advisory_threshold DOUBLE PRECISION NOT NULL DEFAULT 0.70;

-- Drop any previous threshold check constraints
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN (
    SELECT conname 
    FROM pg_constraint 
    WHERE conrelid = 'public.event_zones'::regclass 
      AND contype = 'c' 
      AND pg_get_constraintdef(oid) LIKE '%warning_threshold%'
  ) LOOP
    EXECUTE 'ALTER TABLE public.event_zones DROP CONSTRAINT IF EXISTS ' || quote_ident(r.conname);
  END LOOP;
END $$;

-- Normalize/quarantine any zones with inconsistent thresholds before applying constraint
UPDATE public.event_zones
SET 
  advisory_threshold = 0.70,
  warning_threshold = 0.80,
  critical_threshold = 0.90
WHERE 
  advisory_threshold IS NULL OR warning_threshold IS NULL OR critical_threshold IS NULL
  OR advisory_threshold <= 0 
  OR advisory_threshold >= warning_threshold 
  OR warning_threshold >= critical_threshold 
  OR critical_threshold > 1.0;

ALTER TABLE public.event_zones
  ADD CONSTRAINT chk_event_zones_thresholds CHECK (
    advisory_threshold > 0 
    AND advisory_threshold < warning_threshold 
    AND warning_threshold < critical_threshold 
    AND critical_threshold <= 1.0
  );

-- ----------------------------------------------------------------------------
-- 4. TEMPORAL & LOGICAL CHECK CONSTRAINTS
-- ----------------------------------------------------------------------------

-- 4.1 events: event_end_time > event_start_time
WITH invalid_events AS (
  SELECT id FROM public.events
  WHERE event_start_time IS NOT NULL AND event_end_time IS NOT NULL AND event_end_time <= event_start_time
)
INSERT INTO public.migration_quarantine (source_table, record_id, record_payload, violation_reason)
SELECT 'events', e.id::text, to_jsonb(e), 'event_end_time <= event_start_time'
FROM invalid_events ie
JOIN public.events e ON e.id = ie.id;

UPDATE public.events
SET event_end_time = event_start_time + INTERVAL '4 hours'
WHERE event_start_time IS NOT NULL AND event_end_time IS NOT NULL AND event_end_time <= event_start_time;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_events_temporal') THEN
    ALTER TABLE public.events
      ADD CONSTRAINT chk_events_temporal CHECK (
        event_end_time IS NULL OR event_start_time IS NULL OR event_end_time > event_start_time
      );
  END IF;
END $$;

-- 4.2 sessions: end_time > start_time
WITH invalid_sessions AS (
  SELECT id FROM public.sessions
  WHERE start_time IS NOT NULL AND end_time IS NOT NULL AND end_time <= start_time
)
INSERT INTO public.migration_quarantine (source_table, record_id, record_payload, violation_reason)
SELECT 'sessions', s.id::text, to_jsonb(s), 'sessions: end_time <= start_time'
FROM invalid_sessions ises
JOIN public.sessions s ON s.id = ises.id;

DELETE FROM public.sessions
WHERE start_time IS NOT NULL AND end_time IS NOT NULL AND end_time <= start_time;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_sessions_temporal') THEN
    ALTER TABLE public.sessions
      ADD CONSTRAINT chk_sessions_temporal CHECK (end_time > start_time);
  END IF;
END $$;

-- 4.3 activities: end_time > start_time (when provided)
WITH invalid_activities AS (
  SELECT id FROM public.activities
  WHERE start_time IS NOT NULL AND end_time IS NOT NULL AND end_time <= start_time
)
INSERT INTO public.migration_quarantine (source_table, record_id, record_payload, violation_reason)
SELECT 'activities', a.id::text, to_jsonb(a), 'activities: end_time <= start_time'
FROM invalid_activities ia
JOIN public.activities a ON a.id = ia.id;

DELETE FROM public.activities
WHERE start_time IS NOT NULL AND end_time IS NOT NULL AND end_time <= start_time;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_activities_temporal') THEN
    ALTER TABLE public.activities
      ADD CONSTRAINT chk_activities_temporal CHECK (
        end_time IS NULL OR start_time IS NULL OR end_time > start_time
      );
  END IF;
END $$;

-- 4.4 volunteer_shifts: scheduled_end > scheduled_start
WITH invalid_shifts AS (
  SELECT id FROM public.volunteer_shifts
  WHERE scheduled_start IS NOT NULL AND scheduled_end IS NOT NULL AND scheduled_end <= scheduled_start
)
INSERT INTO public.migration_quarantine (source_table, record_id, record_payload, violation_reason)
SELECT 'volunteer_shifts', vs.id::text, to_jsonb(vs), 'volunteer_shifts: scheduled_end <= scheduled_start'
FROM invalid_shifts ivs
JOIN public.volunteer_shifts vs ON vs.id = ivs.id;

DELETE FROM public.volunteer_shifts
WHERE scheduled_start IS NOT NULL AND scheduled_end IS NOT NULL AND scheduled_end <= scheduled_start;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_volunteer_shifts_temporal') THEN
    ALTER TABLE public.volunteer_shifts
      ADD CONSTRAINT chk_volunteer_shifts_temporal CHECK (scheduled_end > scheduled_start);
  END IF;
END $$;

-- 4.5 shift_breaks: end_time >= start_time (when provided)
WITH invalid_breaks AS (
  SELECT id FROM public.shift_breaks
  WHERE start_time IS NOT NULL AND end_time IS NOT NULL AND end_time < start_time
)
INSERT INTO public.migration_quarantine (source_table, record_id, record_payload, violation_reason)
SELECT 'shift_breaks', sb.id::text, to_jsonb(sb), 'shift_breaks: end_time < start_time'
FROM invalid_breaks ib
JOIN public.shift_breaks sb ON sb.id = ib.id;

DELETE FROM public.shift_breaks
WHERE start_time IS NOT NULL AND end_time IS NOT NULL AND end_time < start_time;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_shift_breaks_temporal') THEN
    ALTER TABLE public.shift_breaks
      ADD CONSTRAINT chk_shift_breaks_temporal CHECK (
        end_time IS NULL OR end_time >= start_time
      );
  END IF;
END $$;

-- 4.6 attendee_connections: requester_id <> addressee_id
WITH self_connections AS (
  SELECT id FROM public.attendee_connections
  WHERE requester_id = addressee_id
)
INSERT INTO public.migration_quarantine (source_table, record_id, record_payload, violation_reason)
SELECT 'attendee_connections', ac.id::text, to_jsonb(ac), 'Self-connection (requester_id = addressee_id)'
FROM self_connections sc
JOIN public.attendee_connections ac ON ac.id = sc.id;

DELETE FROM public.attendee_connections
WHERE requester_id = addressee_id;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_connections_not_self') THEN
    ALTER TABLE public.attendee_connections
      ADD CONSTRAINT chk_connections_not_self CHECK (requester_id <> addressee_id);
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 5. PERFORMANCE & OPERATION INDEXES
-- ----------------------------------------------------------------------------

-- Operational Incidents & Triage
CREATE INDEX IF NOT EXISTS idx_incidents_event_status_priority 
  ON public.operational_incidents (event_id, status, priority, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_incident_logs_incident 
  ON public.operational_incident_logs (incident_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_supervisor_tasks_event_assignee 
  ON public.supervisor_tasks (event_id, assigned_to_id, status);

CREATE INDEX IF NOT EXISTS idx_coverage_requests_event_status 
  ON public.coverage_requests (event_id, status, priority);

-- Volunteer Shifts & Teams
CREATE INDEX IF NOT EXISTS idx_shifts_event_volunteer_status 
  ON public.volunteer_shifts (event_id, volunteer_id, status);

CREATE INDEX IF NOT EXISTS idx_shifts_event_zone 
  ON public.volunteer_shifts (event_id, zone_id);

CREATE INDEX IF NOT EXISTS idx_team_members_volunteer 
  ON public.event_team_members (volunteer_id);

-- Comms & Notifications
CREATE INDEX IF NOT EXISTS idx_op_messages_event_zone_created 
  ON public.operational_messages (event_id, zone_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_op_message_receipts_recipient_status 
  ON public.operational_message_receipts (recipient_id, status);

CREATE INDEX IF NOT EXISTS idx_event_notifications_event_target 
  ON public.event_notifications (event_id, target_user_id, is_active);

-- Attendee Experience, Ticketing & Networking
CREATE INDEX IF NOT EXISTS idx_tickets_event_user 
  ON public.tickets (event_id, user_id);

CREATE INDEX IF NOT EXISTS idx_engagements_event_user 
  ON public.attendee_engagements (event_id, user_id);

CREATE INDEX IF NOT EXISTS idx_connections_event_requester 
  ON public.attendee_connections (event_id, requester_id, status);

CREATE INDEX IF NOT EXISTS idx_connections_event_addressee 
  ON public.attendee_connections (event_id, addressee_id, status);

CREATE INDEX IF NOT EXISTS idx_temp_chat_connection_created 
  ON public.temporary_chat_messages (connection_id, created_at ASC);

CREATE INDEX IF NOT EXISTS idx_sessions_event_time 
  ON public.sessions (event_id, start_time, end_time);

CREATE INDEX IF NOT EXISTS idx_venue_pois_event_zone_category 
  ON public.venue_pois (event_id, zone_id, category);

-- Telemetry conditional index (if zone_id column already exists on observations)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'observations' AND column_name = 'zone_id'
  ) THEN
    CREATE INDEX IF NOT EXISTS idx_observations_event_zone_scanned 
      ON public.observations (event_id, zone_id, scanned_at DESC);
  END IF;
END $$;

