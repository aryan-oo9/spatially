-- ============================================================================
-- SPATIALLY — SCHEMA V2.1: MIGRATION 05 (RELATIONAL VIEWS & AUDIT SNAPSHOTS)
-- File: 20261108_schema_v2_05_relational_views.sql
-- Description:
--   1. Creates relational read views exposing joined names for incidents, shifts,
--      coverage requests, tasks, safety resources, and teams.
--   2. Views are configured with security_invoker = true to inherit underlying table RLS.
--   3. Retains immutable audit snapshot columns on base tables:
--      - operational_incident_logs.actor_name
--      - shift_handoffs.outgoing_volunteer_name
--      - shift_handoffs.incoming_volunteer_name
--      - operational_incidents.reporter_name
-- ============================================================================

-- 1. v_operational_incidents
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
  COALESCE(a.full_name, oi.assigned_to_name) AS assigned_to_name,
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

-- 2. v_volunteer_shifts
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

-- 3. v_coverage_requests
CREATE OR REPLACE VIEW public.v_coverage_requests 
WITH (security_invoker = true) AS
SELECT 
  cr.id,
  cr.event_id,
  cr.shift_id,
  cr.request_type,
  cr.requester_id,
  COALESCE(req.full_name, cr.requester_name) AS requester_name,
  cr.team_id,
  COALESCE(t.name, cr.team_name) AS team_name,
  cr.zone_id,
  COALESCE(ez.name, cr.zone_name) AS zone_name,
  cr.target_shift_id,
  cr.target_zone_id,
  tez.name AS target_zone_name,
  cr.reason,
  cr.notes,
  cr.priority,
  cr.status,
  cr.covering_volunteer_id,
  COALESCE(cov.full_name, cr.covering_volunteer_name) AS covering_volunteer_name,
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

-- 4. v_supervisor_tasks
CREATE OR REPLACE VIEW public.v_supervisor_tasks 
WITH (security_invoker = true) AS
SELECT 
  st.id,
  st.event_id,
  st.team_id,
  COALESCE(t.name, st.team_name) AS team_name,
  st.zone_id,
  COALESCE(ez.name, st.zone_name) AS zone_name,
  st.assigned_to_id,
  COALESCE(a.full_name, st.assigned_to_name) AS assigned_to_name,
  st.supervisor_id,
  COALESCE(s.full_name, st.supervisor_name) AS supervisor_name,
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

-- 5. v_safety_resources
CREATE OR REPLACE VIEW public.v_safety_resources 
WITH (security_invoker = true) AS
SELECT 
  sr.id,
  sr.event_id,
  sr.title,
  sr.subtitle,
  sr.category,
  sr.zone_id,
  COALESCE(ez.name, sr.zone_name) AS zone_name,
  sr.poi_id,
  vp.name AS poi_name,
  sr.availability,
  sr.guidance,
  sr.contact_channel,
  sr.created_at
FROM public.safety_resources sr
LEFT JOIN public.event_zones ez ON ez.id = sr.zone_id
LEFT JOIN public.venue_pois vp ON vp.id = sr.poi_id;

-- 6. v_event_teams
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
  COALESCE(ez.name, et.zone_name) AS zone_name,
  et.created_at,
  et.updated_at
FROM public.event_teams et
LEFT JOIN public.profiles l ON l.id = et.lead_id
LEFT JOIN public.event_zones ez ON ez.id = et.zone_id;

-- Grant access to authenticated users
GRANT SELECT ON public.v_operational_incidents TO authenticated;
GRANT SELECT ON public.v_volunteer_shifts TO authenticated;
GRANT SELECT ON public.v_coverage_requests TO authenticated;
GRANT SELECT ON public.v_supervisor_tasks TO authenticated;
GRANT SELECT ON public.v_safety_resources TO authenticated;
GRANT SELECT ON public.v_event_teams TO authenticated;
