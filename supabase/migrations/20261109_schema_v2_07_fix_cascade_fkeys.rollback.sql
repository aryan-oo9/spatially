-- ============================================================================
-- SPATIALLY — SCHEMA V2.1: MIGRATION 07 ROLLBACK
-- File: 20261109_schema_v2_07_fix_cascade_fkeys.rollback.sql
-- ============================================================================

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_name = 'volunteer_assignments'
  ) THEN
    ALTER TABLE public.volunteer_assignments
      DROP CONSTRAINT IF EXISTS volunteer_assignments_event_id_fkey,
      ADD CONSTRAINT volunteer_assignments_event_id_fkey 
        FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE NO ACTION;
  END IF;
END $$;

