-- ============================================================================
-- SPATIALLY — SCHEMA MIGRATION: PROXY ATTENDANCE SESSIONS
-- File: 20261115_proxy_attendance_sessions.sql
-- Description:
--   1. Creates table public.proxy_attendance_sessions with lifecycle statuses:
--      'pending', 'active', 'revoked', 'declined', 'expired'.
--   2. Enforces mutual exclusion (requester != host) and cap of max 2 active
--      proxies per host (carried weight <= 3).
--   3. Configures RLS policies for authenticated requesters and hosts.
--   4. Registers table on supabase_realtime publication.
--   5. Provides atomic RPC functions for requesting, responding, and revoking proxy sessions.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.proxy_attendance_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
    requester_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    host_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'revoked', 'declined', 'expired')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    accepted_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    revoked_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    CONSTRAINT chk_proxy_different_users CHECK (requester_user_id != host_user_id)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_proxy_sessions_event_status 
    ON public.proxy_attendance_sessions(event_id, status);
CREATE INDEX IF NOT EXISTS idx_proxy_sessions_host 
    ON public.proxy_attendance_sessions(host_user_id, status);
CREATE INDEX IF NOT EXISTS idx_proxy_sessions_requester 
    ON public.proxy_attendance_sessions(requester_user_id, status);

-- At most one active proxy session per requester per event
CREATE UNIQUE INDEX IF NOT EXISTS idx_proxy_active_requester 
    ON public.proxy_attendance_sessions(event_id, requester_user_id) 
    WHERE (status = 'active');

-- Capacity trigger: hard cap of at most 2 active proxies per host (Carried Weight <= 3)
CREATE OR REPLACE FUNCTION public.check_host_proxy_capacity()
RETURNS TRIGGER AS $$
DECLARE
    active_count INT;
BEGIN
    IF NEW.status = 'active' THEN
        SELECT COUNT(*)
        INTO active_count
        FROM public.proxy_attendance_sessions
        WHERE event_id = NEW.event_id
          AND host_user_id = NEW.host_user_id
          AND status = 'active'
          AND id != NEW.id;

        IF active_count >= 2 THEN
            RAISE EXCEPTION 'Host capacity exceeded: a host can carry at most 2 proxy attendees (maximum carried weight of 3).';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_check_host_proxy_capacity ON public.proxy_attendance_sessions;
CREATE TRIGGER trg_check_host_proxy_capacity
    BEFORE INSERT OR UPDATE OF status, host_user_id ON public.proxy_attendance_sessions
    FOR EACH ROW
    EXECUTE FUNCTION public.check_host_proxy_capacity();

-- Enable Row Level Security
ALTER TABLE public.proxy_attendance_sessions ENABLE ROW LEVEL SECURITY;

-- RLS Policies
DROP POLICY IF EXISTS "Participants and staff can view proxy sessions" ON public.proxy_attendance_sessions;
CREATE POLICY "Participants and staff can view proxy sessions"
    ON public.proxy_attendance_sessions
    FOR SELECT
    TO authenticated
    USING (
        auth.uid() IN (requester_user_id, host_user_id)
        OR EXISTS (
            SELECT 1 FROM public.events e 
            WHERE e.id = event_id AND e.organizer_id = auth.uid()
        )
        OR EXISTS (
            SELECT 1 FROM public.volunteers v 
            WHERE v.event_id = event_id AND v.user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Requesters can insert pending proxy sessions" ON public.proxy_attendance_sessions;
CREATE POLICY "Requesters can insert pending proxy sessions"
    ON public.proxy_attendance_sessions
    FOR INSERT
    TO authenticated
    WITH CHECK (
        auth.uid() = requester_user_id
        AND status = 'pending'
    );

DROP POLICY IF EXISTS "Participants can update proxy sessions" ON public.proxy_attendance_sessions;
CREATE POLICY "Participants can update proxy sessions"
    ON public.proxy_attendance_sessions
    FOR UPDATE
    TO authenticated
    USING (
        auth.uid() IN (requester_user_id, host_user_id)
        OR EXISTS (
            SELECT 1 FROM public.events e 
            WHERE e.id = event_id AND e.organizer_id = auth.uid()
        )
    )
    WITH CHECK (
        auth.uid() IN (requester_user_id, host_user_id)
        OR EXISTS (
            SELECT 1 FROM public.events e 
            WHERE e.id = event_id AND e.organizer_id = auth.uid()
        )
    );

-- Enable Realtime
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
          AND schemaname = 'public' 
          AND tablename = 'proxy_attendance_sessions'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.proxy_attendance_sessions;
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        NULL;
END $$;

-- RPC: Request proxy attendance
CREATE OR REPLACE FUNCTION public.request_proxy_attendance(
    p_event_id UUID,
    p_host_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_requester_id UUID;
    v_active_host_count INT;
    v_session_id UUID;
    v_session RECORD;
BEGIN
    v_requester_id := auth.uid();
    IF v_requester_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF v_requester_id = p_host_user_id THEN
        RAISE EXCEPTION 'Cannot delegate attendance to yourself';
    END IF;

    -- Verify requester is checked in to the event
    IF NOT EXISTS (
        SELECT 1 FROM public.tickets
        WHERE event_id = p_event_id 
          AND user_id = v_requester_id 
          AND status = 'checked_in'
    ) THEN
        RAISE EXCEPTION 'Requester must be checked in to the event to delegate attendance';
    END IF;

    -- Verify host is checked in to the event
    IF NOT EXISTS (
        SELECT 1 FROM public.tickets
        WHERE event_id = p_event_id 
          AND user_id = p_host_user_id 
          AND status = 'checked_in'
    ) THEN
        RAISE EXCEPTION 'Host attendee must be checked in to the event';
    END IF;

    -- Verify mutual accepted connection
    IF NOT EXISTS (
        SELECT 1 FROM public.attendee_connections
        WHERE event_id = p_event_id
          AND status = 'accepted'
          AND (
            (requester_id = v_requester_id AND addressee_id = p_host_user_id)
            OR (requester_id = p_host_user_id AND addressee_id = v_requester_id)
          )
    ) THEN
        RAISE EXCEPTION 'Proxy requests can only be sent to accepted connections';
    END IF;

    -- Check if host is already carrying 2 active proxies
    SELECT COUNT(*) INTO v_active_host_count
    FROM public.proxy_attendance_sessions
    WHERE event_id = p_event_id
      AND host_user_id = p_host_user_id
      AND status = 'active';

    IF v_active_host_count >= 2 THEN
        RAISE EXCEPTION 'Selected friend is already carrying the maximum number of proxy attendees (2)';
    END IF;

    -- Check if requester already has an active proxy session for this event
    IF EXISTS (
        SELECT 1 FROM public.proxy_attendance_sessions
        WHERE event_id = p_event_id
          AND requester_user_id = v_requester_id
          AND status = 'active'
    ) THEN
        RAISE EXCEPTION 'You already have an active proxy attendance session for this event';
    END IF;

    -- Cancel any previous pending request from this requester for this event
    UPDATE public.proxy_attendance_sessions
    SET status = 'declined', revoked_at = timezone('utc'::text, now()), revoked_by = v_requester_id
    WHERE event_id = p_event_id
      AND requester_user_id = v_requester_id
      AND status = 'pending';

    -- Insert new pending session
    INSERT INTO public.proxy_attendance_sessions (
        event_id,
        requester_user_id,
        host_user_id,
        status,
        created_at
    ) VALUES (
        p_event_id,
        v_requester_id,
        p_host_user_id,
        'pending',
        timezone('utc'::text, now())
    ) RETURNING * INTO v_session;

    RETURN to_jsonb(v_session);
END;
$$;

-- RPC: Respond to proxy request (Host accepts or declines)
CREATE OR REPLACE FUNCTION public.respond_to_proxy_request(
    p_session_id UUID,
    p_accept BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_caller_id UUID;
    v_session RECORD;
    v_active_host_count INT;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT * INTO v_session
    FROM public.proxy_attendance_sessions
    WHERE id = p_session_id;

    IF v_session IS NULL THEN
        RAISE EXCEPTION 'Proxy session not found';
    END IF;

    IF v_session.host_user_id != v_caller_id THEN
        RAISE EXCEPTION 'Only the designated host can respond to this proxy request';
    END IF;

    IF v_session.status != 'pending' THEN
        RAISE EXCEPTION 'Session is no longer pending (current status: %)', v_session.status;
    END IF;

    IF p_accept THEN
        -- Verify host capacity has not been filled in the meantime
        SELECT COUNT(*) INTO v_active_host_count
        FROM public.proxy_attendance_sessions
        WHERE event_id = v_session.event_id
          AND host_user_id = v_caller_id
          AND status = 'active';

        IF v_active_host_count >= 2 THEN
            RAISE EXCEPTION 'You are already carrying the maximum number of proxy attendees (2)';
        END IF;

        UPDATE public.proxy_attendance_sessions
        SET status = 'active',
            accepted_at = timezone('utc'::text, now())
        WHERE id = p_session_id
        RETURNING * INTO v_session;
    ELSE
        UPDATE public.proxy_attendance_sessions
        SET status = 'declined',
            revoked_at = timezone('utc'::text, now()),
            revoked_by = v_caller_id
        WHERE id = p_session_id
        RETURNING * INTO v_session;
    END IF;

    RETURN to_jsonb(v_session);
END;
$$;

-- RPC: Revoke proxy attendance (either requester or host)
CREATE OR REPLACE FUNCTION public.revoke_proxy_attendance(
    p_session_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_caller_id UUID;
    v_session RECORD;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT * INTO v_session
    FROM public.proxy_attendance_sessions
    WHERE id = p_session_id;

    IF v_session IS NULL THEN
        RAISE EXCEPTION 'Proxy session not found';
    END IF;

    IF v_caller_id NOT IN (v_session.requester_user_id, v_session.host_user_id) THEN
        RAISE EXCEPTION 'Only the proxy requester or host can revoke this session';
    END IF;

    IF v_session.status != 'active' AND v_session.status != 'pending' THEN
        RAISE EXCEPTION 'Session cannot be revoked (status: %)', v_session.status;
    END IF;

    UPDATE public.proxy_attendance_sessions
    SET status = 'revoked',
        revoked_at = timezone('utc'::text, now()),
        revoked_by = v_caller_id
    WHERE id = p_session_id
    RETURNING * INTO v_session;

    RETURN to_jsonb(v_session);
END;
$$;
