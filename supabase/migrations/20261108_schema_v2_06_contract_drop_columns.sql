-- ============================================================================
-- SPATIALLY — SCHEMA V2.1: MIGRATION 06 (FINAL CONTRACT & COLUMN DROPS)
-- File: 20261108_schema_v2_06_contract_drop_columns.sql
-- Description:
--   1. Ensures events.timezone exists and schedule timestamps are backfilled.
--   2. Updates relational read views to decouple from base table denormalized columns.
--   3. Updates stored procedures to omit dropped columns.
--   4. Permanently drops deprecated denormalized columns from base tables:
--      - events: venue, zones, organizer_name, start_time, end_time, event_date, location_address
--      - operational_incidents: venue_zone_name, assigned_to_name
--      - event_teams: zone_name
--      - volunteer_shifts: zone_name
--      - coverage_requests: requester_name, covering_volunteer_name, team_name, zone_name
--      - supervisor_tasks: team_name, assigned_to_name, supervisor_name, zone_name
--      - safety_resources: zone_name
--      - lost_found_reports: venue_zone_name
--   5. Retains the four immutable audit snapshot columns intact:
--      - operational_incident_logs.actor_name
--      - shift_handoffs.outgoing_volunteer_name
--      - shift_handoffs.incoming_volunteer_name
--      - operational_incidents.reporter_name
-- ============================================================================

-- Step 1: Ensure events.timezone column exists and backfill schedule
ALTER TABLE public.events 
  ADD COLUMN IF NOT EXISTS timezone TEXT NOT NULL DEFAULT 'UTC';

-- Backfill event_start_time / event_end_time from event_date if any nulls exist
UPDATE public.events 
SET event_start_time = event_date::timestamptz 
WHERE event_start_time IS NULL AND event_date IS NOT NULL;

UPDATE public.events 
SET event_end_time = event_start_time + INTERVAL '4 hours' 
WHERE event_end_time IS NULL AND event_start_time IS NOT NULL;

-- Step 2: Update relational read views to decouple from base table denormalized columns
CREATE OR REPLACE VIEW public.v_operational_incidents 
WITH (security_invoker = true) AS
SELECT 
  oi.id,
  oi.event_id,
  oi.reporter_type,
  oi.reporter_id,
  COALESCE(r.full_name, oi.reporter_name, 'Unknown') AS reporter_name,
  oi.reporter_device_id,
  oi.category,
  oi.priority,
  oi.status,
  oi.title,
  oi.description,
  oi.zone_id,
  ez.name AS zone_name,
  ez.name AS venue_zone_name,
  oi.venue_poi_id,
  oi.specific_location,
  oi.assigned_to_id,
  COALESCE(a.full_name, 'Unassigned') AS assigned_to_name,
  oi.assigned_at,
  oi.acknowledged_at,
  oi.resolved_at,
  oi.closed_at,
  oi.resolution_notes,
  oi.staff_notes,
  oi.image_url,
  oi.linked_message_id,
  oi.metadata,
  oi.created_at,
  oi.updated_at
FROM public.operational_incidents oi
LEFT JOIN public.profiles r ON r.id = oi.reporter_id
LEFT JOIN public.profiles a ON a.id = oi.assigned_to_id
LEFT JOIN public.event_zones ez ON ez.id = oi.zone_id;

CREATE OR REPLACE VIEW public.v_volunteer_shifts 
WITH (security_invoker = true) AS
SELECT 
  vs.id,
  vs.event_id,
  vs.volunteer_id,
  COALESCE(p.full_name, 'Volunteer') AS volunteer_name,
  p.avatar_url AS volunteer_avatar_url,
  vs.assignment_id,
  va.role AS assignment_role,
  vs.team_id,
  t.name AS team_name,
  vs.supervisor_id,
  s.full_name AS supervisor_name,
  vs.zone_id,
  ez.name AS zone_name,
  vs.shift_name,
  vs.scheduled_start,
  vs.scheduled_end,
  vs.actual_start,
  vs.actual_end,
  vs.status,
  vs.break_state,
  vs.notes,
  vs.created_at,
  vs.updated_at
FROM public.volunteer_shifts vs
LEFT JOIN public.profiles p ON p.id = vs.volunteer_id
LEFT JOIN public.profiles s ON s.id = vs.supervisor_id
LEFT JOIN public.event_teams t ON t.id = vs.team_id
LEFT JOIN public.event_zones ez ON ez.id = vs.zone_id
LEFT JOIN public.volunteer_assignments va ON va.id = vs.assignment_id;

CREATE OR REPLACE VIEW public.v_coverage_requests 
WITH (security_invoker = true) AS
SELECT 
  cr.id,
  cr.event_id,
  cr.shift_id,
  cr.request_type,
  cr.requester_id,
  COALESCE(req.full_name, 'Volunteer') AS requester_name,
  cr.team_id,
  t.name AS team_name,
  cr.zone_id,
  ez.name AS zone_name,
  cr.target_shift_id,
  cr.target_zone_id,
  tez.name AS target_zone_name,
  cr.reason,
  cr.notes,
  cr.priority,
  cr.status,
  cr.covering_volunteer_id,
  COALESCE(cov.full_name, 'Unassigned') AS covering_volunteer_name,
  cr.accepted_at,
  cr.resolved_at,
  cr.created_at,
  cr.updated_at
FROM public.coverage_requests cr
LEFT JOIN public.profiles req ON req.id = cr.requester_id
LEFT JOIN public.profiles cov ON cov.id = cr.covering_volunteer_id
LEFT JOIN public.event_teams t ON t.id = cr.team_id
LEFT JOIN public.event_zones ez ON ez.id = cr.zone_id
LEFT JOIN public.event_zones tez ON tez.id = cr.target_zone_id;

CREATE OR REPLACE VIEW public.v_supervisor_tasks 
WITH (security_invoker = true) AS
SELECT 
  st.id,
  st.event_id,
  st.team_id,
  t.name AS team_name,
  st.zone_id,
  ez.name AS zone_name,
  st.assigned_to_id,
  COALESCE(a.full_name, 'Unassigned') AS assigned_to_name,
  st.supervisor_id,
  COALESCE(s.full_name, 'Supervisor') AS supervisor_name,
  st.title,
  st.description,
  st.priority,
  st.status,
  st.due_time,
  st.accepted_at,
  st.completed_at,
  st.completion_notes,
  st.linked_incident_id,
  st.created_at,
  st.updated_at
FROM public.supervisor_tasks st
LEFT JOIN public.profiles a ON a.id = st.assigned_to_id
LEFT JOIN public.profiles s ON s.id = st.supervisor_id
LEFT JOIN public.event_teams t ON t.id = st.team_id
LEFT JOIN public.event_zones ez ON ez.id = st.zone_id;

CREATE OR REPLACE VIEW public.v_safety_resources 
WITH (security_invoker = true) AS
SELECT 
  sr.id,
  sr.event_id,
  sr.title,
  sr.subtitle,
  sr.category,
  sr.zone_id,
  ez.name AS zone_name,
  sr.poi_id,
  vp.name AS poi_name,
  sr.availability,
  sr.guidance,
  sr.contact_channel,
  sr.created_at
FROM public.safety_resources sr
LEFT JOIN public.event_zones ez ON ez.id = sr.zone_id
LEFT JOIN public.venue_pois vp ON vp.id = sr.poi_id;

CREATE OR REPLACE VIEW public.v_event_teams 
WITH (security_invoker = true) AS
SELECT 
  et.id,
  et.event_id,
  et.name,
  et.description,
  et.lead_id,
  l.full_name AS lead_name,
  et.zone_id,
  ez.name AS zone_name,
  et.created_at,
  et.updated_at
FROM public.event_teams et
LEFT JOIN public.profiles l ON l.id = et.lead_id
LEFT JOIN public.event_zones ez ON ez.id = et.zone_id;

GRANT SELECT ON public.v_operational_incidents TO authenticated;
GRANT SELECT ON public.v_volunteer_shifts TO authenticated;
GRANT SELECT ON public.v_coverage_requests TO authenticated;
GRANT SELECT ON public.v_supervisor_tasks TO authenticated;
GRANT SELECT ON public.v_safety_resources TO authenticated;
GRANT SELECT ON public.v_event_teams TO authenticated;

-- Step 3: Update stored procedures to omit dropped columns
CREATE OR REPLACE FUNCTION public.report_operational_incident(
  p_event_id UUID,
  p_category TEXT,
  p_priority TEXT,
  p_title TEXT,
  p_description TEXT,
  p_zone_id UUID DEFAULT NULL,
  p_venue_zone_name TEXT DEFAULT NULL,
  p_venue_poi_id UUID DEFAULT NULL,
  p_specific_location TEXT DEFAULT NULL,
  p_image_url TEXT DEFAULT NULL,
  p_link_operational_message BOOLEAN DEFAULT false,
  p_reporter_type TEXT DEFAULT 'volunteer',
  p_reporter_device_id TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_reporter_name TEXT := 'Staff Member';
  v_user_role TEXT := 'volunteer';
  v_incident_id UUID;
  v_linked_message_id UUID := NULL;
BEGIN
  IF p_reporter_type IN ('volunteer', 'organizer') THEN
    IF v_user_id IS NULL THEN
      RAISE EXCEPTION 'Authentication required to report staff incident';
    END IF;

    SELECT full_name, role INTO v_reporter_name, v_user_role
    FROM public.profiles WHERE id = v_user_id;

    IF v_reporter_name IS NULL THEN
      v_reporter_name := 'Staff Member';
    END IF;
  ELSE
    IF v_user_id IS NOT NULL THEN
      SELECT full_name INTO v_reporter_name FROM public.profiles WHERE id = v_user_id;
    END IF;
    v_reporter_name := COALESCE(v_reporter_name, 'Attendee');
  END IF;

  INSERT INTO public.operational_incidents (
    event_id,
    reporter_type,
    reporter_id,
    reporter_name,
    reporter_device_id,
    category,
    priority,
    status,
    title,
    description,
    zone_id,
    venue_poi_id,
    specific_location,
    image_url,
    created_at,
    updated_at
  ) VALUES (
    p_event_id,
    p_reporter_type,
    v_user_id,
    v_reporter_name,
    p_reporter_device_id,
    p_category,
    p_priority,
    'open',
    p_title,
    p_description,
    p_zone_id,
    p_venue_poi_id,
    p_specific_location,
    p_image_url,
    timezone('utc'::text, now()),
    timezone('utc'::text, now())
  ) RETURNING id INTO v_incident_id;

  INSERT INTO public.operational_incident_logs (
    incident_id,
    event_id,
    actor_id,
    actor_name,
    action,
    new_status,
    notes,
    created_at
  ) VALUES (
    v_incident_id,
    p_event_id,
    v_user_id,
    v_reporter_name,
    'reported',
    'open',
    p_description,
    timezone('utc'::text, now())
  );

  IF p_link_operational_message = true THEN
    INSERT INTO public.operational_messages (
      event_id,
      sender_id,
      sender_role,
      sender_name,
      target_type,
      zone_id,
      message_type,
      priority,
      body,
      requires_acknowledgment,
      created_at
    ) VALUES (
      p_event_id,
      v_user_id,
      v_user_role,
      v_reporter_name,
      CASE WHEN p_zone_id IS NOT NULL THEN 'zone' ELSE 'event' END,
      p_zone_id,
      'incident_alert',
      p_priority,
      '[' || upper(p_priority) || '] ' || p_title || ': ' || p_description,
      (p_priority = 'urgent'),
      timezone('utc'::text, now())
    ) RETURNING id INTO v_linked_message_id;

    UPDATE public.operational_incidents
    SET linked_message_id = v_linked_message_id
    WHERE id = v_incident_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'incident_id', v_incident_id,
    'linked_message_id', v_linked_message_id,
    'status', 'open'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.request_attendee_assistance(
  p_event_id UUID,
  p_category TEXT,
  p_title TEXT,
  p_description TEXT,
  p_zone_id UUID DEFAULT NULL,
  p_venue_zone_name TEXT DEFAULT NULL,
  p_specific_location TEXT DEFAULT NULL,
  p_device_id TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_reporter_name TEXT := 'Attendee';
  v_priority TEXT := 'normal';
  v_incident_id UUID;
BEGIN
  IF p_category IN ('medical', 'security') THEN
    v_priority := 'urgent';
  ELSIF p_category = 'accessibility' THEN
    v_priority := 'important';
  END IF;

  IF v_user_id IS NOT NULL THEN
    SELECT full_name INTO v_reporter_name FROM public.profiles WHERE id = v_user_id;
  END IF;

  INSERT INTO public.operational_incidents (
    event_id,
    reporter_type,
    reporter_id,
    reporter_name,
    reporter_device_id,
    category,
    priority,
    status,
    title,
    description,
    zone_id,
    specific_location,
    created_at,
    updated_at
  ) VALUES (
    p_event_id,
    'attendee',
    v_user_id,
    COALESCE(v_reporter_name, 'Attendee'),
    p_device_id,
    p_category,
    v_priority,
    'open',
    p_title,
    p_description,
    p_zone_id,
    p_specific_location,
    timezone('utc'::text, now()),
    timezone('utc'::text, now())
  ) RETURNING id INTO v_incident_id;

  INSERT INTO public.operational_incident_logs (
    incident_id,
    event_id,
    actor_id,
    actor_name,
    action,
    new_status,
    notes,
    created_at
  ) VALUES (
    v_incident_id,
    p_event_id,
    v_user_id,
    COALESCE(v_reporter_name, 'Attendee'),
    'reported',
    'open',
    p_description,
    timezone('utc'::text, now())
  );

  RETURN jsonb_build_object(
    'success', true,
    'incident_id', v_incident_id,
    'priority', v_priority,
    'status', 'open'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.assign_operational_incident(
  p_incident_id UUID,
  p_assigned_to_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_caller_name TEXT;
  v_existing_assigned_to_id UUID;
  v_existing_status TEXT;
  v_event_id UUID;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT full_name INTO v_caller_name FROM public.profiles WHERE id = v_caller_id;

  SELECT assigned_to_id, status, event_id
  INTO v_existing_assigned_to_id, v_existing_status, v_event_id
  FROM public.operational_incidents
  WHERE id = p_incident_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;

  IF v_existing_assigned_to_id IS NOT NULL AND v_existing_assigned_to_id <> p_assigned_to_id THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'ALREADY_ASSIGNED'
    );
  END IF;

  UPDATE public.operational_incidents
  SET assigned_to_id = p_assigned_to_id,
      assigned_at = timezone('utc'::text, now()),
      status = 'assigned',
      updated_at = timezone('utc'::text, now())
  WHERE id = p_incident_id;

  INSERT INTO public.operational_incident_logs (
    incident_id,
    event_id,
    actor_id,
    actor_name,
    action,
    new_status,
    notes,
    created_at
  ) VALUES (
    p_incident_id,
    v_event_id,
    v_caller_id,
    COALESCE(v_caller_name, 'Staff Member'),
    'assigned',
    'assigned',
    'Assigned to user ' || p_assigned_to_id::text,
    timezone('utc'::text, now())
  );

  RETURN jsonb_build_object('success', true, 'status', 'assigned');
END;
$$;

CREATE OR REPLACE FUNCTION public.create_supervisor_task(
  p_event_id UUID,
  p_title TEXT,
  p_description TEXT,
  p_assigned_to_id UUID,
  p_team_id UUID DEFAULT NULL,
  p_zone_id UUID DEFAULT NULL,
  p_priority TEXT DEFAULT 'normal',
  p_due_time TIMESTAMPTZ DEFAULT NULL,
  p_linked_incident_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_task_id UUID;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required to create tasks';
  END IF;

  INSERT INTO public.supervisor_tasks (
    event_id,
    team_id,
    title,
    description,
    assigned_to_id,
    supervisor_id,
    zone_id,
    priority,
    status,
    due_time,
    linked_incident_id,
    created_at,
    updated_at
  ) VALUES (
    p_event_id,
    p_team_id,
    p_title,
    p_description,
    p_assigned_to_id,
    v_caller_id,
    p_zone_id,
    p_priority,
    'assigned',
    p_due_time,
    p_linked_incident_id,
    timezone('utc'::text, now()),
    timezone('utc'::text, now())
  ) RETURNING id INTO v_task_id;

  RETURN jsonb_build_object(
    'success', true,
    'task_id', v_task_id,
    'status', 'assigned'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.request_shift_coverage(
  p_event_id UUID,
  p_shift_id UUID,
  p_reason TEXT,
  p_notes TEXT DEFAULT NULL,
  p_priority TEXT DEFAULT 'normal'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_shift RECORD;
  v_request_id UUID;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT id, team_id, zone_id INTO v_shift
  FROM public.volunteer_shifts
  WHERE id = p_shift_id AND volunteer_id = v_caller_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active shift not found or not owned by user';
  END IF;

  INSERT INTO public.coverage_requests (
    event_id,
    shift_id,
    requester_id,
    team_id,
    zone_id,
    reason,
    notes,
    priority,
    status,
    created_at,
    updated_at
  ) VALUES (
    p_event_id,
    p_shift_id,
    v_caller_id,
    v_shift.team_id,
    v_shift.zone_id,
    p_reason,
    p_notes,
    p_priority,
    'requested',
    timezone('utc'::text, now()),
    timezone('utc'::text, now())
  ) RETURNING id INTO v_request_id;

  RETURN jsonb_build_object(
    'success', true,
    'request_id', v_request_id,
    'status', 'requested'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.accept_shift_coverage(
  p_request_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_req RECORD;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT id, requester_id, status, shift_id INTO v_req
  FROM public.coverage_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;

  IF v_req.status <> 'requested' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'ALREADY_CLAIMED'
    );
  END IF;

  IF v_req.requester_id = v_caller_id THEN
    RAISE EXCEPTION 'Volunteers cannot accept their own coverage requests';
  END IF;

  UPDATE public.coverage_requests
  SET status = 'accepted',
      covering_volunteer_id = v_caller_id,
      accepted_at = timezone('utc'::text, now()),
      updated_at = timezone('utc'::text, now())
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'success', true,
    'request_id', p_request_id,
    'status', 'accepted'
  );
END;
$$;

-- Step 4: Permanently drop deprecated denormalized columns from base tables
-- 1. events
ALTER TABLE public.events 
  DROP COLUMN IF EXISTS venue CASCADE,
  DROP COLUMN IF EXISTS zones CASCADE,
  DROP COLUMN IF EXISTS organizer_name CASCADE,
  DROP COLUMN IF EXISTS start_time CASCADE,
  DROP COLUMN IF EXISTS end_time CASCADE,
  DROP COLUMN IF EXISTS event_date CASCADE,
  DROP COLUMN IF EXISTS location_address CASCADE;

-- 2. operational_incidents (retaining reporter_name snapshot)
ALTER TABLE public.operational_incidents 
  DROP COLUMN IF EXISTS venue_zone_name CASCADE,
  DROP COLUMN IF EXISTS assigned_to_name CASCADE;

-- 3. event_teams
ALTER TABLE public.event_teams 
  DROP COLUMN IF EXISTS zone_name CASCADE;

-- 4. volunteer_shifts
ALTER TABLE public.volunteer_shifts 
  DROP COLUMN IF EXISTS zone_name CASCADE;

-- 5. coverage_requests
ALTER TABLE public.coverage_requests 
  DROP COLUMN IF EXISTS requester_name CASCADE,
  DROP COLUMN IF EXISTS covering_volunteer_name CASCADE,
  DROP COLUMN IF EXISTS team_name CASCADE,
  DROP COLUMN IF EXISTS zone_name CASCADE;

-- 6. supervisor_tasks
ALTER TABLE public.supervisor_tasks 
  DROP COLUMN IF EXISTS team_name CASCADE,
  DROP COLUMN IF EXISTS assigned_to_name CASCADE,
  DROP COLUMN IF EXISTS supervisor_name CASCADE,
  DROP COLUMN IF EXISTS zone_name CASCADE;

-- 7. safety_resources
ALTER TABLE public.safety_resources 
  DROP COLUMN IF EXISTS zone_name CASCADE;

-- 8. lost_found_reports
ALTER TABLE public.lost_found_reports 
  DROP COLUMN IF EXISTS venue_zone_name CASCADE;

