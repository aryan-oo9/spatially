# Spatially System Remediation Specification: Bug Fixes, Schema Harmonization & Architecture Hardening

**Document Version**: 1.0.0  
**Target Architecture**: Spatially Real-Time Crowd Intelligence Platform  
**Scope**: Full Stack (`server/`, `client/`, `supabase/migrations/`, `apps/attendee_mobile/`, `apps/volunteer_mobile/`, `server/data/`)

---

## 1. Executive Summary & Remediation Strategy

A system-wide audit revealed key bugs, architectural drifts, and schema mismatches resulting from progressive development across the three main surfaces (Organizer Web, FastAPI Backend, and Flutter Mobile). 

This specification establishes an implementation blueprint organized into **5 sequential phases**:
1. **Phase 1: Database Schema & Constraint Harmonization** — Reconcile missing web-specific tables, fix check constraints, and make migrations the single source of truth.
2. **Phase 2: Backend API & Auth Hardening (`server/`)** — Fix auth privilege escalations, IDOR vulnerabilities, route schema mismatches, simulation script crashes, and timezone bugs.
3. **Phase 3: Frontend Web Contract & UX Remediation (`client/`)** — Fix attendee role assignment, restore broken auth flows (Profile, Password Reset, Verification), align request/response payloads with backend schemas, fix `VenueMap` layout corruption, and correct timestamp formatting.
4. **Phase 4: Mobile Client Reliability (`apps/`)** — Break the `LostFoundScreen` infinite network loop, fix BLE beacon rotation & lifecycle, repair dual-ownership ticket claiming, and ensure offline message queue flush on reconnect.
5. **Phase 5: Verification, Automated Testing & Build Validation** — Execute automated tests (`pytest`, `vitest`/`build`, `flutter test`), verify zero lint warnings, and run end-to-end simulations.

---

## 2. Phase 1: Database Schema & Constraint Harmonization

### 1.1 New Canonical Migration: `20261024_phase8c_reconcile_web_tables.sql`
Create a new migration in `supabase/migrations/20261024_phase8c_reconcile_web_tables.sql` to formally adopt tables previously existing only in uncommitted prototype SQL files (`server/database/`):

1. **`public.event_invitations`**:
   ```sql
   CREATE TABLE IF NOT EXISTS public.event_invitations (
       id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
       event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
       volunteer_email TEXT NOT NULL,
       volunteer_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
       status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'cancelled')),
       invited_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
       created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
       updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
   );
   CREATE INDEX IF NOT EXISTS idx_event_invitations_event ON public.event_invitations(event_id);
   CREATE INDEX IF NOT EXISTS idx_event_invitations_email ON public.event_invitations(volunteer_email);
   CREATE INDEX IF NOT EXISTS idx_event_invitations_user ON public.event_invitations(volunteer_user_id);
   ```

2. **`public.event_activity_logs`**:
   ```sql
   CREATE TABLE IF NOT EXISTS public.event_activity_logs (
       id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
       event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
       action_type TEXT NOT NULL,
       description TEXT NOT NULL,
       actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
       metadata JSONB DEFAULT '{}'::jsonb,
       created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
   );
   CREATE INDEX IF NOT EXISTS idx_event_activity_logs_event ON public.event_activity_logs(event_id, created_at DESC);
   ```

3. **`public.volunteer_switch_requests`**:
   ```sql
   CREATE TABLE IF NOT EXISTS public.volunteer_switch_requests (
       id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
       event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
       requester_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
       target_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
       status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'cancelled')),
       created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
       updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
   );
   CREATE INDEX IF NOT EXISTS idx_volunteer_switch_requests_event ON public.volunteer_switch_requests(event_id);
   CREATE INDEX IF NOT EXISTS idx_volunteer_switch_requests_target ON public.volunteer_switch_requests(target_id, status);
   ```

4. **`public.user_event_registrations`**:
   ```sql
   CREATE TABLE IF NOT EXISTS public.user_event_registrations (
       id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
       user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
       event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
       status TEXT NOT NULL DEFAULT 'registered' CHECK (status IN ('registered', 'cancelled')),
       created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
       updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
       CONSTRAINT uq_user_event_registration UNIQUE (user_id, event_id)
   );
   CREATE INDEX IF NOT EXISTS idx_user_event_registrations_user ON public.user_event_registrations(user_id);
   CREATE INDEX IF NOT EXISTS idx_user_event_registrations_event ON public.user_event_registrations(event_id);
   ```

5. **Column Alignments & Constraint Patches**:
   - Add `resolution_notes TEXT` to `public.operational_incidents` (or ensure backward compatibility with `staff_notes`).
   - Add `due_at TIMESTAMPTZ` to `public.supervisor_tasks` (mapped to `due_time`).
   - Update `public.crowd_zone_snapshots`: Ensure `source` constraint supports `'volunteer_telemetry'` and `'ble_telemetry'`:
     ```sql
     ALTER TABLE public.crowd_zone_snapshots DROP CONSTRAINT IF EXISTS crowd_zone_snapshots_source_check;
     ALTER TABLE public.crowd_zone_snapshots ADD CONSTRAINT crowd_zone_snapshots_source_check 
     CHECK (source IN ('auto', 'manual_calibration', 'simulation', 'ble_telemetry', 'volunteer_telemetry'));
     ```
   - Enable RLS and add basic security policies on all newly created tables.

6. **Deprecate Obsolete SQL**:
   - Add a header notice in `server/database/schema.sql`, `organizer_missing_tables.sql`, `logs_migration.sql`, and `venue_map_migration.sql` indicating they are deprecated and that `supabase/migrations/` is the single source of truth.

---

## 3. Phase 2: Backend API & Auth Hardening (`server/`)

### 2.1 Auth Middleware & Privilege Escalation Fix (`server/middleware/auth.py`)
- **Fix**:
  1. Do **not** trust `metadata.get("user_type")` or `metadata.get("role")` from `user.user_metadata` for role elevation.
  2. Query `public.profiles` for `role`. If `profiles` row is missing or raises an error, default role to `"user"` (or `"attendee"`), **never** `"organizer"`.
  3. Normalize the role string: Map both `"attendee"` and `"user"` to `"user"` on the return payload so both `require_user` and frontend checks succeed.
  4. Implement `require_admin` dependency for sensitive system logs.

### 2.2 IDOR & Event Ownership Verification (`server/routes/organizer.py` & `venue_map.py`)
- **Fix**:
  - In `organizer.py`:
    - `PUT /incidents/{incident_id}`: Fetch incident's `event_id` and call `verify_event_ownership(supabase, event_id, current_user["user_id"])`.
    - `PUT /tasks/{task_id}` and `DELETE /tasks/{task_id}`: Fetch task's `event_id` and verify ownership.
    - `PUT /zones/{zone_id}`: Fetch zone's `event_id` and verify ownership.
    - `PUT /booths/{booth_id}` and `DELETE /booths/{booth_id}`: Fetch booth's `event_id` and verify ownership.
    - `PUT /sessions/{session_id}` and `DELETE /sessions/{session_id}`: Fetch session's `event_id` and verify ownership.
  - In `venue_map.py`:
    - Add `Depends(get_current_user)` to `GET /api/venue-map/{event_id}/density`, `layout`, `levels`, `volunteers`.
    - In `save_zone_layout`, `assign_volunteer_zone`, `update_volunteer_zone`, `remove_volunteer_zone`: Validate event ownership.

### 2.3 Route Contract & Schema Alignments in `server/routes/organizer.py`
- **Communications (`POST /api/organizer/comms`)**:
  - Map `data.content` $\to$ `body`.
  - Set `"sender_role": current_user.get("role", "organizer")`.
  - Normalize `data.target_type`: Map `"broadcast"` or `"all"` $\to$ `"event"`, `"individual"` $\to$ `"volunteer"`, `"zone"` $\to$ `"zone"`.
  - Normalize `data.priority`: Map `"routine"` $\to$ `"normal"`.
- **Incidents (`POST /api/organizer/incidents` & `/assign`)**:
  - For direct insert fallback: Set `reporter_type = 'organizer'`, `status = 'open'` (not `'reported'`), `priority = 'normal'` (if `'routine'`), and column `venue_zone_name = data.zone_name`.
  - In `assign_incident`: Accept `volunteer_id: str` or `assigned_to: str`. Update `operational_incidents` directly or align RPC call with `(p_incident_id, p_assigned_to_id)`.
  - In `update_incident`: Map `data.assigned_to` $\to$ `assigned_to_id`.
  - In `get_operational_health`: Query `venue_zone_name`, not `zone_name`.
- **Tasks (`POST /api/organizer/tasks` & `PUT /tasks/{task_id}`)**:
  - Insert into `supervisor_tasks` with `supervisor_id = current_user["user_id"]`, `supervisor_name = current_user.get("full_name", "Organizer")`.
  - If `data.assigned_to` is provided, resolve volunteer name into `assigned_to_name` and set `assigned_to_id = data.assigned_to`.
  - Set `status = "assigned"` (or `"in_progress"`), never `"pending"`.
  - Map `due_at` $\to$ `due_time`.
- **Zones (`GET /api/organizer/zones/{event_id}`)**:
  - Change `.order("sort_order")` to `.order("code")` or `.order("name")`.
  - In `ZoneCreate`: Default `operational_status = "active"`.
- **Booths & Sessions**:
  - `BoothCreate`: Ensure `company_name` is populated (defaulting to `name`), omit `contact_name`.
  - `SessionCreate`: Ensure `stage_name` is populated (defaulting to `location` or `'Main Stage'`).
- **Assistance**:
  - Consolidate duplicate `/assistance/{event_id}` routes into a single endpoint querying `category.in_(('assistance', 'attendee_assistance'))`.
  - In `escalate_assistance`: Accept `data.get("reason")` or `data.get("notes")` into `staff_notes`, and set `status = "open"`.
- **Shift Handoffs**:
  - Update route path to match frontend expectation: support `@router.get("/shift-handoffs/{event_id}")` as an alias or redirect to `/handoffs/{event_id}`.
  - Query canonical `public.shift_handoffs` table with `outgoing_volunteer_id` and `incoming_volunteer_id`.
- **Crowd Predictions**:
  - In `/crowd/{event_id}`: Include `"zone_id": z.get("id")` and `"snapshot_at"` in `zone_density[zone_name]`.
  - In `/crowd/{event_id}/predictions`: Query `tickets.checked_in_at` (not `check_in_at`).

### 2.4 Simulation Scripts Bug Fixes
- **`server/data/simulate_crowd.py`**:
  - Fix `NameError: name 'i' is not defined` on line 127: Use `enumerate(series)` to compute `(idx * 5)m ago` or calculate minutes relative to `now`.
  - Fix `volunteer_counts` update: Query and upsert using `volunteer_id: UUID` (or generate a deterministic demo volunteer UUID) instead of referencing non-existent `id` column.
- **`server/data/simulate_volunteers.py`**:
  - Change `"source": "volunteer_telemetry"` to `"source": "ble_telemetry"` at lines 460 and 564 to satisfy the database `CHECK` constraint.

### 2.5 `PredictionEngine` & Test Suites (`server/services/crowd_prediction.py`, `server/tests/`)
- Replace deprecated timezone-naive `datetime.utcnow()` with `datetime.now(timezone.utc)` across `server/services/crowd_prediction.py`.
- In `server/tests/test_simulation.py`: Ensure test functions do not take un-parameterized fixture arguments so `pytest` executes cleanly.

---

## 4. Phase 3: Frontend Web Contract & UX Remediation (`client/`)

### 3.1 AuthContext & Role Fixes (`client/src/context/AuthContext.jsx`)
- In `signup()`: Change `user_type: "organizer"` to `user_type: "user"` so public attendees register with attendee permissions.
- In `AuthContext.Provider`:
  - Export `updateProfile(fullName, nickname)`: Updates `supabase.auth.updateUser({ data: { full_name, nickname } })` and `public.profiles.update({ full_name, nickname }).eq('id', user.id)`.
  - Normalize `user.user_id = session.user.id` so components accessing `user.user_id` or `user.id` work interchangeably.
  - Add `.catch(() => setLoading(false))` to `supabase.auth.getSession()` to prevent eternal loading screen on storage/network failure.

### 3.2 Restore Auth Pages using Supabase Auth SDK
- **`client/src/pages/Profile.jsx`**:
  - Wire up `updateProfile` from `useAuth()`.
  - Replace `api.post("/api/auth/update-password")` with `supabase.auth.updateUser({ password: passwordForm.new_password })`.
- **`client/src/pages/ForgotPassword.jsx`**:
  - Replace removed `/api/auth/forgot-password` endpoint with `supabase.auth.resetPasswordForEmail(email, { redirectTo: `${window.location.origin}/reset-password` })`.
- **`client/src/pages/ResetPassword.jsx`**:
  - Replace removed `/api/auth/reset-password` endpoint with `supabase.auth.updateUser({ password: form.new_password })`.
- **`client/src/pages/VerifyEmail.jsx`**:
  - Inspect URL hash/params for Supabase confirmation token or session, and handle verification natively via `supabase.auth.getSession()`.

### 3.3 Client ↔ Server Route & Payload Alignment
- **`client/src/pages/OrganizerIncidents.jsx`**:
  - In `handleDispatch` (line 124): Send `{ volunteer_id: assigneeId, notes: dispatchNotes || undefined }`.
- **`client/src/pages/InviteVolunteer.jsx`**:
  - In lines 40–62: Check `const volId = v.user_id || v.id` and match `a.volunteer_id === volId` (fixing `undefined === undefined`).
- **`client/src/components/VolunteerPlacer.jsx`**:
  - Use `const volId = v.user_id || v.id` consistently for `placedIds`, keys, and selection handlers.
- **`client/src/pages/OrganizerAnalytics.jsx`**:
  - In `handleDownloadCsv`: Prepend `import.meta.env.VITE_API_URL || "http://localhost:8000"` to the fetch URL and obtain the bearer token from `supabase.auth.getSession()`.
- **`client/src/pages/OrganizerCrowd.jsx`**:
  - In `calibratingZoneId === data.zone_id`: Will now match properly once backend returns `zone_id`.
  - In `handleCalibrate`: Pass `data.zone_id || data.id`.
- **`client/src/pages/OrganizerVolunteers.jsx`**:
  - In line 76: Read `covData.coverage_requests || covData.requests || []`.
  - In line 71: Use `/api/organizer/shift-handoffs/${selectedEventId}` or `/api/organizer/handoffs/${selectedEventId}`.
  - In lines 408–409: Display `h.outgoing_volunteer_name || h.from_volunteer?.full_name || h.outgoing_volunteer_id` and incoming name.
- **`client/src/pages/OrganizerContent.jsx`**:
  - Map `points_reward` / `points_value` properly.
  - In session form: Combine event date with time or use `<input type="datetime-local">` to produce valid ISO `TIMESTAMPTZ` values.
- **`client/src/pages/EventLogs.jsx`**:
  - Change line 30 to `setEvent(eventRes.event || eventRes)`.
- **`client/src/components/EventLogsPanel.jsx`**:
  - Change table subscription from `shift_handoffs` to `shift_handoff_logs` (or canonical `shift_handoffs`).
  - Use composite key: `key={`${log.action}-${log.log_id || idx}`}`.
- **`client/src/pages/OrganizerComms.jsx`**:
  - Use `/api/organizer/comms/${msgId}/receipts` (or alias).
  - Display `rcpt.recipient?.full_name || rcpt.volunteer_name || rcpt.recipient_id?.slice(0, 8)`.
  - Add zone/team picker when target is `"zone"` or `"team"`.
- **`client/src/utils/validators.js`**:
  - In `formatTime(timeString)`: Detect ISO timestamps (`timeString.includes("T")`) and format using `new Date(timeString).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })` so 2026 timestamps do not all become `10:XX PM`.

### 3.4 VenueMap Improvements (`client/src/components/VenueMap.jsx`)
- Do not let default empty array overwrite `editLayout` before `serverLayout` arrives.
- When `serverLayout` arrives, update `editLayout` if not user-edited.
- Only poll `/api/organizer/incidents/${eventId}` when `mode === "organizer"` or `mode === "edit-zones"`.
- Check `(z.zone || z.name) === (inc.venue_zone_name || inc.zone_name)`.

---

## 5. Phase 4: Mobile Client Reliability (`apps/`)

### 4.1 Configuration Templates & Launcher Integration
- Create `apps/attendee_mobile/lib/config/supabase_config.dart.example` and `apps/volunteer_mobile/lib/config/supabase_config.dart.example`.
- If missing, auto-generate placeholder `supabase_config.dart` from the `.example` or backend `.env` during `start.bat` execution.

### 4.2 Fix Infinite Loop in `LostFoundScreen` (`apps/attendee_mobile`)
- In `apps/attendee_mobile/lib/features/safety/lost_found_screen.dart`:
  - Update `_reports` directly from the list emitted by `_repository.getReportsStream(widget.eventId)` and apply in-memory tab filtering instead of calling `_loadReports()` inside the stream listener.

### 4.3 App-Scoped BLE Advertising Service & UI State (`apps/attendee_mobile`)
- Move the 5-minute ephemeral ID rotation timer out of `_AdvertiserScreenState` into an app-level singleton service so background broadcasting continues after navigating back.
- In `apps/attendee_mobile/lib/screens/ticket_detail_screen.dart`:
  - Show the `'Reached at Event (Start Beacon)'` button when `isPurchased || isCheckedIn`.
- In `apps/attendee_mobile/lib/features/home/widgets/home_beacon_status.dart`:
  - Query `isBleAdvertisingServiceRunning` on `_bleServiceChannel` rather than relying on `FlutterBlePeripheral().onPeripheralStateChanged`.

### 4.4 Dual-Ownership Ticket Claim Fix (`apps/attendee_mobile`)
- In `apps/attendee_mobile/lib/features/explore/event_detail_screen.dart:195-202`:
  - Include `'user_id': _authService.currentUser?.id` when inserting claimed tickets.

### 4.5 Offline Operational Message Flush on Reconnect (`apps/volunteer_mobile`)
- In `apps/volunteer_mobile/lib/services/observation_queue.dart`:
  - Add `flushPendingMessages()` to `_startConnectivityListener()` and `flushAllNow()`.

---

## 6. Phase 5: Verification, Automated Testing & Build Validation

### 6.1 Backend Testing
```powershell
cd server
python -m pytest
```
- Validate all 12 existing tests pass, plus new tests for:
  - `simulate_crowd.py` execution without `NameError`.
  - UTC timezone handling in `PredictionEngine`.
  - Auth role fallback integrity (never elevating to organizer).

### 6.2 Frontend Lint & Production Build
```powershell
cd client
npm run lint
npm run build
```
- Ensure 0 errors and all warnings addressed.
- Verify `dist/` builds cleanly.

### 6.3 Simulation Verification
```powershell
python server/data/simulate_crowd.py --pattern ramp --minutes 10
python server/data/simulate_volunteers.py --seed-only
```
- Verify historical snapshots insert into `crowd_zone_snapshots` with code 0 and no constraint violations.

---

## 7. Implementation Checklist

| Task ID | Component | File(s) | Description | Priority |
|---|---|---|---|---|
| **T-1.1** | Supabase | `supabase/migrations/20261024_phase8c_reconcile_web_tables.sql` | Create canonical migration for missing web tables and constraints | High |
| **T-2.1** | Server | `server/data/simulate_crowd.py` | Fix `NameError: name 'i' is not defined` and `volunteer_counts` update | Critical |
| **T-2.2** | Server | `server/data/simulate_volunteers.py` | Fix `source: 'ble_telemetry'` constraint violation | High |
| **T-2.3** | Server | `server/middleware/auth.py` | Prevent privilege escalation from metadata and default to `"user"` | Critical |
| **T-2.4** | Server | `server/routes/organizer.py` | Fix `comms`, `incidents`, `tasks`, `zones`, `assistance`, IDOR checks | Critical |
| **T-2.5** | Server | `server/routes/volunteers.py`, `models.py` | Fix `KeyError: 'user_id'`, drop `V1`/`V2` legacy validator | Critical |
| **T-2.6** | Server | `server/services/crowd_prediction.py` | Migrate `datetime.utcnow()` to `datetime.now(timezone.utc)` | High |
| **T-3.1** | Client | `client/src/context/AuthContext.jsx` | Fix attendee `user_type: "user"`, export `updateProfile`, set `user_id` | Critical |
| **T-3.2** | Client | `client/src/pages/Profile.jsx`, `ForgotPassword.jsx`, `ResetPassword.jsx`, `VerifyEmail.jsx` | Migrate to Supabase Auth SDK | Critical |
| **T-3.3** | Client | `client/src/pages/OrganizerIncidents.jsx`, `InviteVolunteer.jsx`, `VolunteerPlacer.jsx` | Fix payload mismatches and undefined keys | Critical |
| **T-3.4** | Client | `client/src/pages/OrganizerAnalytics.jsx`, `OrganizerCrowd.jsx`, `OrganizerVolunteers.jsx`, `EventLogs.jsx` | Fix CSV export URL/token, calibration zone ID, and data mappings | High |
| **T-3.5** | Client | `client/src/components/VenueMap.jsx`, `client/src/utils/validators.js` | Fix layout save race condition, 403 polling, and 2026 timestamp parsing | High |
| **T-4.1** | Mobile | `apps/*/lib/config/supabase_config.dart.example` | Create config templates and verify imports | High |
| **T-4.2** | Mobile | `apps/attendee_mobile/lib/features/safety/lost_found_screen.dart` | Break stream listener infinite network loop | Critical |
| **T-4.3** | Mobile | `apps/attendee_mobile/lib/main.dart`, `ticket_detail_screen.dart` | Fix BLE beacon rotation timer and checked-in beacon trigger | Critical |
| **T-4.4** | Mobile | `apps/attendee_mobile/lib/features/explore/event_detail_screen.dart` | Set `user_id` when claiming tickets | High |
| **T-4.5** | Mobile | `apps/volunteer_mobile/lib/services/observation_queue.dart` | Add `flushPendingMessages()` on network reconnection | High |
| **T-5.1** | Verification | `server/tests/`, `client/`, `server/data/` | Run `pytest`, `npm run lint`, `npm run build`, and test simulation scripts | High |
