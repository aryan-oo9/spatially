-- ============================================================================
-- SPATIALLY — SCHEMA V2.1: MIGRATION 07 (ENSURE ALL EVENT FOREIGN KEYS CASCADE)
-- File: 20261109_schema_v2_07_fix_cascade_fkeys.sql
-- Description:
--   Ensures that volunteer_assignments and any other tables referencing 
--   events(id) have ON DELETE CASCADE so that deleting an event cleanly 
--   removes all associated records.
-- ============================================================================

-- Step 1: Explicitly fix volunteer_assignments_event_id_fkey
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_name = 'volunteer_assignments'
  ) THEN
    ALTER TABLE public.volunteer_assignments
      DROP CONSTRAINT IF EXISTS volunteer_assignments_event_id_fkey,
      ADD CONSTRAINT volunteer_assignments_event_id_fkey 
        FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE CASCADE;
  END IF;
END $$;

-- Step 2: Dynamically detect and upgrade any other foreign keys pointing to events(id)
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT 
            tc.table_schema, 
            tc.table_name, 
            tc.constraint_name,
            kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.referential_constraints rc 
          ON tc.constraint_name = rc.constraint_name
          AND tc.table_schema = rc.constraint_schema
        JOIN information_schema.table_constraints c_pk 
          ON rc.unique_constraint_name = c_pk.constraint_name
          AND rc.unique_constraint_schema = c_pk.table_schema
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
          AND tc.table_schema = kcu.table_schema
        WHERE c_pk.table_name = 'events'
          AND rc.delete_rule <> 'CASCADE'
    ) LOOP
        RAISE NOTICE 'Upgrading constraint % on %.% (col: %) to ON DELETE CASCADE', 
            r.constraint_name, r.table_schema, r.table_name, r.column_name;
        EXECUTE format('ALTER TABLE %I.%I DROP CONSTRAINT %I', 
            r.table_schema, r.table_name, r.constraint_name);
        EXECUTE format('ALTER TABLE %I.%I ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES public.events(id) ON DELETE CASCADE', 
            r.table_schema, r.table_name, r.constraint_name, r.column_name);
    END LOOP;
END $$;

