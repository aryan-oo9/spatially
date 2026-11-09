-- ============================================================================
-- SPATIALLY — SCHEMA V2.1: MIGRATION 02 (UUID KEYS & PROFILES STANDARDIZATION)
-- File: 20261108_schema_v2_02_uuid_keys_profiles.sql
-- Description:
--   1. Converts events.organizer_id to UUID FK referencing public.profiles(id).
--   2. Converts event_invitations.volunteer_id and invited_by to UUID FKs referencing profiles(id).
--   3. Converts event_activity_logs.actor_id to UUID FK referencing profiles(id).
--   4. Adds zone_id UUID to observations and volunteer_counts, backfills from event_zones.
--   5. Converts safety_resources.poi_id to UUID FK referencing venue_pois(id).
--   6. Drops all duplicate FKs referencing auth.users(id) on public schema tables
--      and standardizes all user FKs to reference public.profiles(id) (PGRST201 fix).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. EVENTS: organizer_id text -> UUID FK
-- ----------------------------------------------------------------------------

-- Quarantine non-UUID or non-existent organizer_id records
INSERT INTO public.migration_quarantine (source_table, record_id, record_payload, violation_reason)
SELECT 'events', id::text, to_jsonb(e), 'Non-UUID or non-existent organizer_id: ' || coalesce(organizer_id, 'NULL')
FROM public.events e
WHERE organizer_id IS NOT NULL 
  AND (
    organizer_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    OR organizer_id::uuid NOT IN (SELECT id FROM public.profiles)
  );

UPDATE public.events
SET organizer_id = NULL
WHERE organizer_id IS NOT NULL 
  AND (
    organizer_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    OR organizer_id::uuid NOT IN (SELECT id FROM public.profiles)
  );

ALTER TABLE public.events
  ALTER COLUMN organizer_id TYPE UUID USING organizer_id::uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_events_organizer_profile'
  ) THEN
    ALTER TABLE public.events
      ADD CONSTRAINT fk_events_organizer_profile
      FOREIGN KEY (organizer_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_events_organizer_id ON public.events(organizer_id);

-- ----------------------------------------------------------------------------
-- 2. EVENT_INVITATIONS: volunteer_user_id & invited_by -> UUID FKs
-- ----------------------------------------------------------------------------

DO $$
BEGIN
  -- Rename legacy volunteer_user_id column to volunteer_id if needed
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'event_invitations' AND column_name = 'volunteer_user_id'
  ) THEN
    ALTER TABLE public.event_invitations RENAME COLUMN volunteer_user_id TO volunteer_id;
  END IF;
END $$;

-- Quarantine invalid volunteer_id
INSERT INTO public.migration_quarantine (source_table, record_id, record_payload, violation_reason)
SELECT 'event_invitations', id::text, to_jsonb(ei), 'Non-UUID or non-existent volunteer_id: ' || coalesce(volunteer_id, 'NULL')
FROM public.event_invitations ei
WHERE volunteer_id IS NOT NULL
  AND (
    volunteer_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    OR volunteer_id::uuid NOT IN (SELECT id FROM public.profiles)
  );

UPDATE public.event_invitations
SET volunteer_id = NULL
WHERE volunteer_id IS NOT NULL
  AND (
    volunteer_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    OR volunteer_id::uuid NOT IN (SELECT id FROM public.profiles)
  );

-- Quarantine invalid invited_by
INSERT INTO public.migration_quarantine (source_table, record_id, record_payload, violation_reason)
SELECT 'event_invitations', id::text, to_jsonb(ei), 'Non-UUID or non-existent invited_by: ' || coalesce(invited_by, 'NULL')
FROM public.event_invitations ei
WHERE invited_by IS NOT NULL
  AND (
    invited_by !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    OR invited_by::uuid NOT IN (SELECT id FROM public.profiles)
  );

UPDATE public.event_invitations
SET invited_by = NULL
WHERE invited_by IS NOT NULL
  AND (
    invited_by !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    OR invited_by::uuid NOT IN (SELECT id FROM public.profiles)
  );

ALTER TABLE public.event_invitations
  ALTER COLUMN volunteer_id TYPE UUID USING volunteer_id::uuid,
  ALTER COLUMN invited_by DROP NOT NULL,
  ALTER COLUMN invited_by TYPE UUID USING invited_by::uuid;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_invitations_volunteer_profile') THEN
    ALTER TABLE public.event_invitations
      ADD CONSTRAINT fk_invitations_volunteer_profile
      FOREIGN KEY (volunteer_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_invitations_invited_by_profile') THEN
    ALTER TABLE public.event_invitations
      ADD CONSTRAINT fk_invitations_invited_by_profile
      FOREIGN KEY (invited_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_event_invitations_volunteer ON public.event_invitations(volunteer_id);
CREATE INDEX IF NOT EXISTS idx_event_invitations_invited_by ON public.event_invitations(invited_by);

-- ----------------------------------------------------------------------------
-- 3. EVENT_ACTIVITY_LOGS: actor_id text -> UUID FK
-- ----------------------------------------------------------------------------

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'event_activity_logs'
  ) THEN
    -- Quarantine invalid actor_id
    INSERT INTO public.migration_quarantine (source_table, record_id, record_payload, violation_reason)
    SELECT 'event_activity_logs', id::text, to_jsonb(eal), 'Non-UUID or non-existent actor_id: ' || coalesce(actor_id, 'NULL')
    FROM public.event_activity_logs eal
    WHERE actor_id IS NOT NULL
      AND (
        actor_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR actor_id::uuid NOT IN (SELECT id FROM public.profiles)
      );

    UPDATE public.event_activity_logs
    SET actor_id = NULL
    WHERE actor_id IS NOT NULL
      AND (
        actor_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR actor_id::uuid NOT IN (SELECT id FROM public.profiles)
      );

    ALTER TABLE public.event_activity_logs
      ALTER COLUMN actor_id DROP NOT NULL,
      ALTER COLUMN actor_id TYPE UUID USING actor_id::uuid;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_activity_logs_actor_profile') THEN
      ALTER TABLE public.event_activity_logs
        ADD CONSTRAINT fk_activity_logs_actor_profile
        FOREIGN KEY (actor_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
    END IF;

    CREATE INDEX IF NOT EXISTS idx_activity_logs_actor ON public.event_activity_logs(actor_id);
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 4. OBSERVATIONS & VOLUNTEER_COUNTS: zone text -> zone_id UUID FK
-- ----------------------------------------------------------------------------

-- 4.1 observations.zone_id
ALTER TABLE public.observations
  ADD COLUMN IF NOT EXISTS zone_id UUID REFERENCES public.event_zones(id) ON DELETE SET NULL;

-- Backfill observations.zone_id from event_zones using zone text
UPDATE public.observations o
SET zone_id = ez.id
FROM public.event_zones ez
WHERE o.zone_id IS NULL
  AND o.zone IS NOT NULL
  AND o.event_id = ez.event_id
  AND (
    (o.zone ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' AND o.zone::uuid = ez.id)
    OR lower(trim(o.zone)) = lower(trim(ez.name))
    OR lower(trim(o.zone)) = lower(trim(ez.code))
  );

CREATE INDEX IF NOT EXISTS idx_observations_event_zone_scanned 
  ON public.observations (event_id, zone_id, scanned_at DESC);

-- 4.2 volunteer_counts.zone_id
ALTER TABLE public.volunteer_counts
  ADD COLUMN IF NOT EXISTS zone_id UUID REFERENCES public.event_zones(id) ON DELETE SET NULL;

-- Backfill volunteer_counts.zone_id from event_zones using zone text
UPDATE public.volunteer_counts vc
SET zone_id = ez.id
FROM public.event_zones ez
WHERE vc.zone_id IS NULL
  AND vc.zone IS NOT NULL
  AND vc.event_id = ez.event_id
  AND (
    (vc.zone ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' AND vc.zone::uuid = ez.id)
    OR lower(trim(vc.zone)) = lower(trim(ez.name))
    OR lower(trim(vc.zone)) = lower(trim(ez.code))
  );

CREATE INDEX IF NOT EXISTS idx_volunteer_counts_event_zone 
  ON public.volunteer_counts (event_id, zone_id);

-- ----------------------------------------------------------------------------
-- 5. SAFETY_RESOURCES: poi_id text -> UUID FK
-- ----------------------------------------------------------------------------

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'safety_resources'
  ) THEN
    -- Quarantine non-UUID or non-existent poi_id
    INSERT INTO public.migration_quarantine (source_table, record_id, record_payload, violation_reason)
    SELECT 'safety_resources', id::text, to_jsonb(sr), 'Non-UUID or non-existent poi_id: ' || coalesce(poi_id, 'NULL')
    FROM public.safety_resources sr
    WHERE poi_id IS NOT NULL
      AND (
        poi_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR poi_id::uuid NOT IN (SELECT id FROM public.venue_pois)
      );

    UPDATE public.safety_resources
    SET poi_id = NULL
    WHERE poi_id IS NOT NULL
      AND (
        poi_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR poi_id::uuid NOT IN (SELECT id FROM public.venue_pois)
      );

    ALTER TABLE public.safety_resources
      ALTER COLUMN poi_id TYPE UUID USING poi_id::uuid;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_safety_resources_poi') THEN
      ALTER TABLE public.safety_resources
        ADD CONSTRAINT fk_safety_resources_poi
        FOREIGN KEY (poi_id) REFERENCES public.venue_pois(id) ON DELETE SET NULL;
    END IF;

    CREATE INDEX IF NOT EXISTS idx_safety_resources_poi ON public.safety_resources(poi_id);
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 6. STANDARDIZE USER FKS TO PUBLIC.PROFILES (PGRST201 FIX)
-- ----------------------------------------------------------------------------
-- Drop any direct foreign key constraints from public schema tables to auth.users.
-- Re-point user columns cleanly to public.profiles(id).

DO $$
DECLARE
  rec RECORD;
BEGIN
  -- Dynamically find and drop any foreign key constraints referencing auth.users
  FOR rec IN (
    SELECT 
      tc.table_name,
      tc.constraint_name
    FROM information_schema.table_constraints tc
    JOIN information_schema.constraint_column_usage ccu
      ON ccu.constraint_name = tc.constraint_name
      AND ccu.table_schema = tc.table_schema
    WHERE tc.table_schema = 'public'
      AND tc.constraint_type = 'FOREIGN KEY'
      AND ccu.table_schema = 'auth'
      AND ccu.table_name = 'users'
  ) LOOP
    EXECUTE 'ALTER TABLE public.' || quote_ident(rec.table_name) || 
            ' DROP CONSTRAINT IF EXISTS ' || quote_ident(rec.constraint_name);
  END LOOP;
END $$;

-- Explicitly establish standardized foreign keys to public.profiles(id)
DO $$
BEGIN
  -- event_teams: lead_id -> profiles(id) ON DELETE SET NULL
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'event_teams') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_event_teams_lead_profile') THEN
      ALTER TABLE public.event_teams
        ADD CONSTRAINT fk_event_teams_lead_profile
        FOREIGN KEY (lead_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
    END IF;
  END IF;

  -- event_team_members: volunteer_id -> profiles(id) ON DELETE CASCADE
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'event_team_members') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_team_members_volunteer_profile') THEN
      ALTER TABLE public.event_team_members
        ADD CONSTRAINT fk_team_members_volunteer_profile
        FOREIGN KEY (volunteer_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
    END IF;
  END IF;

  -- volunteer_shifts: volunteer_id -> profiles(id) ON DELETE CASCADE, supervisor_id -> profiles(id) ON DELETE SET NULL
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'volunteer_shifts') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_volunteer_shifts_volunteer_profile') THEN
      ALTER TABLE public.volunteer_shifts
        ADD CONSTRAINT fk_volunteer_shifts_volunteer_profile
        FOREIGN KEY (volunteer_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_volunteer_shifts_supervisor_profile') THEN
      ALTER TABLE public.volunteer_shifts
        ADD CONSTRAINT fk_volunteer_shifts_supervisor_profile
        FOREIGN KEY (supervisor_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
    END IF;
  END IF;

  -- shift_breaks: volunteer_id -> profiles(id) ON DELETE CASCADE
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'shift_breaks') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_shift_breaks_volunteer_profile') THEN
      ALTER TABLE public.shift_breaks
        ADD CONSTRAINT fk_shift_breaks_volunteer_profile
        FOREIGN KEY (volunteer_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
    END IF;
  END IF;

  -- coverage_requests: requester_id -> profiles(id) ON DELETE CASCADE, covering_volunteer_id -> profiles(id) ON DELETE SET NULL
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'coverage_requests') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_coverage_requests_requester_profile') THEN
      ALTER TABLE public.coverage_requests
        ADD CONSTRAINT fk_coverage_requests_requester_profile
        FOREIGN KEY (requester_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_coverage_requests_covering_profile') THEN
      ALTER TABLE public.coverage_requests
        ADD CONSTRAINT fk_coverage_requests_covering_profile
        FOREIGN KEY (covering_volunteer_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
    END IF;
  END IF;

  -- supervisor_tasks: assigned_to_id, supervisor_id -> profiles(id) ON DELETE SET NULL
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'supervisor_tasks') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_tasks_assigned_to_profile') THEN
      ALTER TABLE public.supervisor_tasks
        ADD CONSTRAINT fk_tasks_assigned_to_profile
        FOREIGN KEY (assigned_to_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_tasks_supervisor_profile') THEN
      ALTER TABLE public.supervisor_tasks
        ADD CONSTRAINT fk_tasks_supervisor_profile
        FOREIGN KEY (supervisor_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
    END IF;
  END IF;

  -- operational_incidents: reporter_id, assigned_to_id -> profiles(id) ON DELETE SET NULL
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'operational_incidents') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_incidents_reporter_profile') THEN
      ALTER TABLE public.operational_incidents
        ADD CONSTRAINT fk_incidents_reporter_profile
        FOREIGN KEY (reporter_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_incidents_assigned_to_profile') THEN
      ALTER TABLE public.operational_incidents
        ADD CONSTRAINT fk_incidents_assigned_to_profile
        FOREIGN KEY (assigned_to_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
    END IF;
  END IF;

  -- operational_incident_logs: actor_id -> profiles(id) ON DELETE SET NULL
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'operational_incident_logs') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_incident_logs_actor_profile') THEN
      ALTER TABLE public.operational_incident_logs
        ADD CONSTRAINT fk_incident_logs_actor_profile
        FOREIGN KEY (actor_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
    END IF;
  END IF;

  -- lost_found_reports: reporter_user_id -> profiles(id) ON DELETE SET NULL
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'lost_found_reports') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_lost_found_reporter_profile') THEN
      ALTER TABLE public.lost_found_reports
        ADD CONSTRAINT fk_lost_found_reporter_profile
        FOREIGN KEY (reporter_user_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
    END IF;
  END IF;

  -- tickets: user_id -> profiles(id) ON DELETE CASCADE, checked_in_by -> profiles(id) ON DELETE SET NULL
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'tickets') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_tickets_user_profile') THEN
      ALTER TABLE public.tickets
        ADD CONSTRAINT fk_tickets_user_profile
        FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_tickets_checked_in_by_profile') THEN
      ALTER TABLE public.tickets
        ADD CONSTRAINT fk_tickets_checked_in_by_profile
        FOREIGN KEY (checked_in_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
    END IF;
  END IF;
END $$;

