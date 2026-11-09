-- ============================================================================
-- SPATIALLY — SCHEMA V2.1: MIGRATION 04 (TICKETS, COVERAGE REQUESTS & RLS)
-- File: 20261108_schema_v2_04_tickets_coverage_rls.sql
-- Description:
--   1. Implements ADR 0001: Registered-only tickets (user_id NOT NULL referencing profiles).
--      Quarantines and deletes guest tickets and guest attendee engagements.
--      Drops guest device attendee_id, claim RPCs, and anonymous ticket RLS policies.
--   2. Retires user_event_registrations in favor of canonical tickets.
--   3. Expands coverage_requests with request_type ('relief' | 'swap'), target_shift_id,
--      target_zone_id, and chk_coverage_requests_not_self constraint.
--   4. Configures ON DELETE CASCADE on event_id across all event-scoped entities.
--   5. Restricts anonymous (anon role) access exclusively to events, event_zones,
--      and live crowd counts; all personal/operational data requires authenticated access.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. TICKETS & ATTENDEE ENGAGEMENTS (ADR 0001: REGISTERED-ONLY ATTENDEES)
-- ----------------------------------------------------------------------------

-- 1.1 Quarantine and delete guest tickets (tickets with NULL user_id)
INSERT INTO public.migration_quarantine (source_table, record_id, record_payload, violation_reason)
SELECT 'tickets', id::text, to_jsonb(t), 'Guest ticket with NULL user_id deleted under ADR 0001'
FROM public.tickets t
WHERE user_id IS NULL;

DELETE FROM public.tickets
WHERE user_id IS NULL;

-- 1.2 Quarantine and delete tickets where user_id does not exist in profiles
INSERT INTO public.migration_quarantine (source_table, record_id, record_payload, violation_reason)
SELECT 'tickets', id::text, to_jsonb(t), 'Ticket user_id not in profiles'
FROM public.tickets t
WHERE user_id NOT IN (SELECT id FROM public.profiles);

DELETE FROM public.tickets
WHERE user_id NOT IN (SELECT id FROM public.profiles);

-- 1.3 Make tickets.user_id NOT NULL with profile FK
ALTER TABLE public.tickets
  ALTER COLUMN user_id SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_tickets_user_profile') THEN
    ALTER TABLE public.tickets
      ADD CONSTRAINT fk_tickets_user_profile
      FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
  END IF;
END $$;

-- 1.4 Drop obsolete guest attendee_id and claim columns from tickets (CASCADE drops dependent guest policies/indexes)
ALTER TABLE public.tickets
  DROP COLUMN IF EXISTS attendee_id CASCADE,
  DROP COLUMN IF EXISTS claim_hash CASCADE;

-- 1.5 Update attendee_engagements: add ticket_id, quarantine guest engagements
ALTER TABLE public.attendee_engagements
  ADD COLUMN IF NOT EXISTS ticket_id UUID REFERENCES public.tickets(id) ON DELETE CASCADE;

-- Backfill ticket_id on attendee_engagements where matching (event_id, user_id) exists
UPDATE public.attendee_engagements ae
SET ticket_id = t.id
FROM public.tickets t
WHERE ae.ticket_id IS NULL
  AND ae.event_id = t.event_id
  AND ae.user_id = t.user_id;

-- Quarantine and remove engagements that cannot be linked to an authenticated ticket
INSERT INTO public.migration_quarantine (source_table, record_id, record_payload, violation_reason)
SELECT 'attendee_engagements', id::text, to_jsonb(ae), 'Guest or orphaned engagement deleted under ADR 0001'
FROM public.attendee_engagements ae
WHERE ticket_id IS NULL;

DELETE FROM public.attendee_engagements
WHERE ticket_id IS NULL;

ALTER TABLE public.attendee_engagements
  ALTER COLUMN ticket_id SET NOT NULL,
  DROP COLUMN IF EXISTS attendee_id CASCADE;

-- Drop obsolete guest claim functions
DROP FUNCTION IF EXISTS public.claim_ticket_by_hash(text, uuid);
DROP FUNCTION IF EXISTS public.claim_tickets_for_user(uuid, uuid);

-- ----------------------------------------------------------------------------
-- 2. RETIRE USER_EVENT_REGISTRATIONS (REPLACED BY TICKETS)
-- ----------------------------------------------------------------------------

-- Migrate any existing user_event_registrations into tickets if not already present
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'user_event_registrations'
  ) THEN
    INSERT INTO public.tickets (event_id, user_id, ticket_code, status, purchased_at)
    SELECT 
      uer.event_id, 
      uer.user_id::uuid, 
      'TICK-' || upper(substr(md5(random()::text), 1, 8)),
      CASE 
        WHEN uer.status = 'cancelled' THEN 'cancelled'
        ELSE 'valid'
      END,
      COALESCE(uer.registered_at, now())
    FROM public.user_event_registrations uer
    WHERE uer.user_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      AND uer.user_id::uuid IN (SELECT id FROM public.profiles)
      AND NOT EXISTS (
        SELECT 1 FROM public.tickets t 
        WHERE t.event_id = uer.event_id AND t.user_id = uer.user_id::uuid
      );

    -- Drop the deprecated table
    DROP TABLE IF EXISTS public.user_event_registrations CASCADE;
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 3. COVERAGE_REQUESTS: EXPAND FOR RELIEF & SWAP
-- ----------------------------------------------------------------------------

ALTER TABLE public.coverage_requests
  ADD COLUMN IF NOT EXISTS request_type TEXT NOT NULL DEFAULT 'relief' 
    CHECK (request_type IN ('relief', 'swap')),
  ADD COLUMN IF NOT EXISTS target_shift_id UUID REFERENCES public.volunteer_shifts(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS target_zone_id UUID REFERENCES public.event_zones(id) ON DELETE SET NULL;

-- Quarantine and remove any self-coverage requests
INSERT INTO public.migration_quarantine (source_table, record_id, record_payload, violation_reason)
SELECT 'coverage_requests', id::text, to_jsonb(cr), 'coverage_requests: covering_volunteer_id = requester_id'
FROM public.coverage_requests cr
WHERE covering_volunteer_id IS NOT NULL AND covering_volunteer_id = requester_id;

DELETE FROM public.coverage_requests
WHERE covering_volunteer_id IS NOT NULL AND covering_volunteer_id = requester_id;

-- Enforce check constraint that covering volunteer cannot be requester
ALTER TABLE public.coverage_requests
  DROP CONSTRAINT IF EXISTS chk_coverage_requests_not_self;

ALTER TABLE public.coverage_requests
  ADD CONSTRAINT chk_coverage_requests_not_self 
  CHECK (covering_volunteer_id IS NULL OR covering_volunteer_id <> requester_id);

CREATE INDEX IF NOT EXISTS idx_coverage_requests_type ON public.coverage_requests(request_type);
CREATE INDEX IF NOT EXISTS idx_coverage_requests_target_shift ON public.coverage_requests(target_shift_id);

-- ----------------------------------------------------------------------------
-- 4. EVENT HARD-DELETE CASCADES (ON DELETE CASCADE ON event_id)
-- ----------------------------------------------------------------------------

DO $$
DECLARE
  tbl_name TEXT;
  fk_name TEXT;
  tables_to_cascade TEXT[] := ARRAY[
    'event_zones', 'venue_pois', 'sessions', 'booths', 'activities', 
    'tickets', 'attendee_engagements', 'attendee_connections', 
    'temporary_chat_messages', 'event_notifications', 'event_teams', 
    'volunteer_shifts', 'shift_breaks', 'coverage_requests', 
    'supervisor_tasks', 'shift_handoffs', 'safety_resources', 
    'emergency_contacts', 'observations', 'volunteer_counts'
  ];
BEGIN
  FOREACH tbl_name IN ARRAY tables_to_cascade LOOP
    IF EXISTS (
      SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = tbl_name
    ) THEN
      -- Drop any existing event_id foreign key constraint
      FOR fk_name IN (
        SELECT tc.constraint_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON kcu.constraint_name = tc.constraint_name
          AND kcu.table_schema = tc.table_schema
        WHERE tc.table_schema = 'public'
          AND tc.table_name = tbl_name
          AND tc.constraint_type = 'FOREIGN KEY'
          AND kcu.column_name = 'event_id'
      ) LOOP
        EXECUTE 'ALTER TABLE public.' || quote_ident(tbl_name) || ' DROP CONSTRAINT IF EXISTS ' || quote_ident(fk_name);
      END LOOP;

      -- Add standardized ON DELETE CASCADE foreign key
      EXECUTE 'ALTER TABLE public.' || quote_ident(tbl_name) || 
              ' ADD CONSTRAINT ' || quote_ident('fk_' || tbl_name || '_event_cascade') ||
              ' FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE CASCADE';
    END IF;
  END LOOP;
END $$;

-- ----------------------------------------------------------------------------
-- 5. ROW LEVEL SECURITY: RESTRICT ANON TO PUBLIC CATALOGS ONLY
-- ----------------------------------------------------------------------------

-- Enable RLS on core attendee and operational tables
ALTER TABLE public.tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendee_engagements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendee_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.temporary_chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lost_found_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.observations ENABLE ROW LEVEL SECURITY;

-- 5.1 TICKETS RLS: Registered user reads own tickets, staff/assigned volunteers can view event tickets
DROP POLICY IF EXISTS "Users and guests can view their own tickets" ON public.tickets;
DROP POLICY IF EXISTS "Public can view tickets" ON public.tickets;
DROP POLICY IF EXISTS "Anonymous device can select their own ticket" ON public.tickets;
DROP POLICY IF EXISTS "Users can view own tickets" ON public.tickets;
DROP POLICY IF EXISTS "Staff can view event tickets" ON public.tickets;

CREATE POLICY "Users can view own tickets"
ON public.tickets FOR SELECT TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Staff can view event tickets"
ON public.tickets FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.events e 
    WHERE e.id = tickets.event_id AND e.organizer_id = auth.uid()
  ) OR
  EXISTS (
    SELECT 1 FROM public.volunteer_assignments va 
    WHERE va.event_id = tickets.event_id AND va.volunteer_id = auth.uid()
  )
);

CREATE POLICY "Users can insert own tickets"
ON public.tickets FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

-- 5.2 ATTENDEE ENGAGEMENTS: Authenticated users can view and log own engagements
DROP POLICY IF EXISTS "Users and guests can view their own engagements" ON public.attendee_engagements;
DROP POLICY IF EXISTS "Users can view own engagements" ON public.attendee_engagements;
DROP POLICY IF EXISTS "Users can log engagements" ON public.attendee_engagements;
DROP POLICY IF EXISTS "Public view engagements" ON public.attendee_engagements;

CREATE POLICY "Users can view own engagements"
ON public.attendee_engagements FOR SELECT TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users can log engagements"
ON public.attendee_engagements FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

-- 5.3 PUBLIC ACCESS (ANON ROLE): Only events, event_zones, and live counts
CREATE OR REPLACE VIEW public.live_volunteer_counts 
WITH (security_invoker = true) AS
SELECT *
FROM public.volunteer_counts
WHERE updated_at >= (timezone('utc'::text, now()) - INTERVAL '5 minutes');

GRANT SELECT ON public.events TO anon, authenticated;
GRANT SELECT ON public.event_zones TO anon, authenticated;
GRANT SELECT ON public.live_volunteer_counts TO anon, authenticated;

-- Revoke anon select on non-public tables
REVOKE ALL ON public.tickets FROM anon;
REVOKE ALL ON public.attendee_engagements FROM anon;
REVOKE ALL ON public.attendee_connections FROM anon;
REVOKE ALL ON public.temporary_chat_messages FROM anon;
REVOKE ALL ON public.operational_messages FROM anon;
REVOKE ALL ON public.operational_incidents FROM anon;
REVOKE ALL ON public.supervisor_tasks FROM anon;
REVOKE ALL ON public.volunteer_shifts FROM anon;
REVOKE ALL ON public.volunteer_assignments FROM anon;
REVOKE ALL ON public.coverage_requests FROM anon;
REVOKE ALL ON public.shift_handoffs FROM anon;
REVOKE ALL ON public.event_activity_logs FROM anon;
REVOKE ALL ON public.migration_quarantine FROM anon;

