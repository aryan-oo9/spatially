from fastapi import APIRouter, HTTPException, Depends, Query
from fastapi.responses import StreamingResponse
from config import get_supabase
from middleware.auth import get_current_user, require_organizer
from pydantic import BaseModel
from typing import Optional, List, Any, Dict
from datetime import datetime, timezone, timedelta
from services import crowd_prediction
from services.quest_agent import generate_brand_quest, generate_crowd_diversion_quest
import csv
import io
import logging

logger = logging.getLogger("spatially.organizer")

AUTO_DIVERSION_EVENTS = set()
LAST_DIVERSION_DISPATCH: Dict[str, datetime] = {}

router = APIRouter(prefix="/api/organizer", tags=["Organizer"])


# ═══════════════════════════════════════════════════════════════
# PYDANTIC MODELS
# ═══════════════════════════════════════════════════════════════

class IncidentCreate(BaseModel):
    event_id: str
    title: str
    description: Optional[str] = ""
    category: Optional[str] = "other"
    priority: Optional[str] = "normal"
    zone_id: Optional[str] = None
    zone_name: Optional[str] = None

class IncidentUpdate(BaseModel):
    status: Optional[str] = None
    priority: Optional[str] = None
    assigned_to: Optional[str] = None
    assigned_to_id: Optional[str] = None
    resolution_notes: Optional[str] = None

class TaskCreate(BaseModel):
    event_id: str
    title: str
    description: Optional[str] = ""
    zone_id: Optional[str] = None
    zone_name: Optional[str] = None
    assigned_to: Optional[str] = None
    priority: str = "normal"

class TaskUpdate(BaseModel):
    status: Optional[str] = None
    priority: Optional[str] = None
    assigned_to: Optional[str] = None
    notes: Optional[str] = None

class DiversionDispatchPayload(BaseModel):
    event_id: str
    overcrowded_zone_id: Optional[str] = None
    overcrowded_zone_name: str
    target_zone_id: Optional[str] = None
    target_zone_name: str
    sponsor_id: Optional[str] = None
    brand_name: str
    booth_number: Optional[str] = None
    bonus_points: Optional[int] = 150
    custom_title: Optional[str] = None
    custom_description: Optional[str] = None
    auto_broadcast: Optional[bool] = True

class AutoDiversionTogglePayload(BaseModel):
    enabled: bool

class MessageCreate(BaseModel):
    event_id: str
    content: str
    target_type: str = "broadcast"
    target_id: Optional[str] = None
    priority: str = "routine"
    requires_ack: bool = False

class ZoneCreate(BaseModel):
    event_id: str
    name: str
    code: Optional[str] = None
    floor_level: Optional[int] = 1
    level_id: Optional[str] = None
    capacity_limit: Optional[int] = None
    operating_capacity: Optional[int] = None
    warning_threshold: Optional[float] = 0.85
    critical_threshold: Optional[float] = 0.95
    advisory_threshold: Optional[float] = 0.70
    operational_status: Optional[str] = "open"
    is_crowd_monitored: bool = True

class ZoneUpdate(BaseModel):
    name: Optional[str] = None
    code: Optional[str] = None
    floor_level: Optional[int] = None
    level_id: Optional[str] = None
    capacity_limit: Optional[int] = None
    operating_capacity: Optional[int] = None
    warning_threshold: Optional[float] = None
    critical_threshold: Optional[float] = None
    advisory_threshold: Optional[float] = None
    operational_status: Optional[str] = None
    is_crowd_monitored: Optional[bool] = None
    is_active: Optional[bool] = None

class BoothCreate(BaseModel):
    event_id: str
    name: str
    company_name: Optional[str] = None
    description: Optional[str] = ""
    booth_number: Optional[str] = None
    zone_id: Optional[str] = None
    category: Optional[str] = None
    contact_name: Optional[str] = None
    contact_email: Optional[str] = None
    website_url: Optional[str] = None
    is_active: Optional[bool] = True

class BoothUpdate(BaseModel):
    name: Optional[str] = None
    company_name: Optional[str] = None
    description: Optional[str] = None
    booth_number: Optional[str] = None
    zone_id: Optional[str] = None
    category: Optional[str] = None
    contact_name: Optional[str] = None
    contact_email: Optional[str] = None
    website_url: Optional[str] = None
    is_active: Optional[bool] = None

class SponsorLocationAssign(BaseModel):
    zone_id: Optional[str] = None
    booth_number: Optional[str] = None

class SessionCreate(BaseModel):
    event_id: str
    title: str
    description: Optional[str] = ""
    speaker_name: Optional[str] = None
    zone_id: Optional[str] = None
    location: Optional[str] = None
    start_time: Optional[str] = None
    end_time: Optional[str] = None
    session_type: Optional[str] = "presentation"

class SessionUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    speaker_name: Optional[str] = None
    zone_id: Optional[str] = None
    location: Optional[str] = None
    start_time: Optional[str] = None
    end_time: Optional[str] = None
    status: Optional[str] = None


# ═══════════════════════════════════════════════════════════════
# HELPER: Verify organizer owns event
# ═══════════════════════════════════════════════════════════════

def verify_event_ownership(supabase, event_id: str, user_id: str):
    """Verify the organizer owns this event."""
    event = supabase.table("events").select("id, organizer_id").eq("id", event_id).execute()
    if not event.data:
        raise HTTPException(status_code=404, detail="Event not found")
    if event.data[0].get("organizer_id") != user_id:
        raise HTTPException(status_code=403, detail="You do not own this event")
    return event.data[0]


# ═══════════════════════════════════════════════════════════════
# 1. OPERATIONAL HEALTH
# ═══════════════════════════════════════════════════════════════

@router.get("/health/{event_id}")
async def get_operational_health(event_id: str, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    verify_event_ownership(supabase, event_id, current_user["user_id"])
    
    # Try RPC first
    try:
        result = supabase.rpc("get_event_operational_health", {"p_event_id": event_id}).execute()
        if result.data:
            data = result.data
            # Enrich with tickets if missing
            if "tickets" not in data:
                try:
                    tickets_res = supabase.table("tickets").select("id, status, checked_in_at").eq("event_id", event_id).execute()
                    t_data = tickets_res.data or []
                    data["tickets"] = {
                        "total": len(t_data),
                        "checked_in": sum(1 for t in t_data if t.get("checked_in_at") or t.get("status") == "checked_in"),
                    }
                except Exception:
                    data["tickets"] = {"total": 0, "checked_in": 0}
            return {"health": data}
    except Exception as e:
        print(f"[organizer] get_event_operational_health RPC error ({e}), aggregating directly")

    # Authoritative direct fallback aggregation
    try:
        # Incidents via relational view v_operational_incidents
        incidents_res = supabase.table("v_operational_incidents").select("id, priority, status, category, created_at, zone_name").eq("event_id", event_id).execute()
        incidents = incidents_res.data or []
        active_incidents = [i for i in incidents if i.get("status") not in ("resolved", "closed")]
        urgent_incidents = [i for i in active_incidents if i.get("priority") in ("urgent", "critical")]
        resolved_incidents = [i for i in incidents if i.get("status") in ("resolved", "closed")]

        # Shifts via relational view v_volunteer_shifts
        shifts_res = supabase.table("v_volunteer_shifts").select("id, status, break_state, zone_id, zone_name").eq("event_id", event_id).execute()
        shifts = shifts_res.data or []
        active_shifts = [s for s in shifts if s.get("status") == "active"]
        on_break_shifts = [s for s in shifts if s.get("status") == "active" and s.get("break_state") in ("taking_break", "on_break")]

        # Coverage requests
        cov_res = supabase.table("coverage_requests").select("id, status").eq("event_id", event_id).execute()
        coverage = cov_res.data or []
        pending_cov = [c for c in coverage if c.get("status") == "pending"]

        # Tasks
        tasks_res = supabase.table("supervisor_tasks").select("id, status").eq("event_id", event_id).execute()
        tasks = tasks_res.data or []
        pending_tasks = [t for t in tasks if t.get("status") == "pending"]
        in_prog_tasks = [t for t in tasks if t.get("status") == "in_progress"]
        completed_tasks = [t for t in tasks if t.get("status") == "completed"]

        # Zones
        zones_res = supabase.table("event_zones").select("id, name, capacity_limit, operating_capacity").eq("event_id", event_id).execute()
        zones_data = zones_res.data or []
        
        # Get real zone active crowd counts from volunteer_counts
        zone_counts = {}
        try:
            vc_res = supabase.table("volunteer_counts").select("zone, zone_id, active_count").eq("event_id", event_id).execute()
            for c in (vc_res.data or []):
                zid = c.get("zone_id")
                zname = c.get("zone")
                cnt = c.get("active_count", 0) or 0
                if zid:
                    zone_counts[zid] = zone_counts.get(zid, 0) + cnt
                if zname:
                    zone_counts[zname] = zone_counts.get(zname, 0) + cnt
        except Exception:
            pass

        zones_summary = []
        for z in zones_data:
            zid = z["id"]
            zname = z.get("name", "Zone")
            cnt = zone_counts.get(zid) or zone_counts.get(zname) or 0
            z_inc = [i for i in active_incidents if i.get("zone_name") == zname]
            z_staff = [s for s in active_shifts if s.get("zone_id") == zid or s.get("zone_name") == zname]
            zones_summary.append({
                "zone_id": zid,
                "zone_name": zname,
                "active_count": cnt,
                "operating_capacity": z.get("operating_capacity") or z.get("capacity_limit") or 0,
                "active_incidents": len(z_inc),
                "active_staff": len(z_staff),
                "is_monitored": True,
            })

        # Tickets
        tickets_summary = {"total": 0, "checked_in": 0}
        try:
            tickets_res = supabase.table("tickets").select("id, status, checked_in_at").eq("event_id", event_id).execute()
            t_data = tickets_res.data or []
            tickets_summary = {
                "total": len(t_data),
                "checked_in": sum(1 for t in t_data if t.get("checked_in_at") or t.get("status") == "checked_in"),
            }
        except Exception:
            pass

        # Overall operational status gauge calculation
        health_status = "healthy"
        if len(urgent_incidents) > 0:
            health_status = "critical"
        elif any((z["operating_capacity"] > 0 and (z["active_count"] / z["operating_capacity"]) > 0.85) for z in zones_summary) or len(active_incidents) > 0:
            health_status = "elevated"

        health_obj = {
            "event_id": event_id,
            "status": health_status,
            "computed_at": datetime.now(timezone.utc).isoformat(),
            "incidents": {
                "total": len(incidents),
                "active": len(active_incidents),
                "urgent": len(urgent_incidents),
                "resolved": len(resolved_incidents),
            },
            "shifts": {
                "total": len(shifts),
                "active": len(active_shifts),
                "on_break": len(on_break_shifts),
            },
            "coverage": {
                "total": len(coverage),
                "pending": len(pending_cov),
            },
            "tasks": {
                "total": len(tasks),
                "pending": len(pending_tasks),
                "in_progress": len(in_prog_tasks),
                "completed": len(completed_tasks),
            },
            "zones": zones_summary,
            "tickets": tickets_summary,
            "communications": {
                "total_messages": 0,
                "broadcasts": 0,
                "urgent": 0,
            }
        }
        return {"health": health_obj}
    except Exception as fallback_err:
        return {"health": None, "error": str(fallback_err)}


@router.get("/timeline/{event_id}")
async def get_operational_timeline(event_id: str, limit: int = Query(50, ge=1, le=200), current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    verify_event_ownership(supabase, event_id, current_user["user_id"])
    
    # Calculate real chronological crowd telemetry from database
    timeline_points = []
    try:
        now = datetime.now(timezone.utc)
        since_30m = (now - timedelta(minutes=30)).isoformat()
        
        obs_res = (
            supabase.table("observations")
            .select("scanned_at, ephemeral_id")
            .eq("event_id", event_id)
            .gte("scanned_at", since_30m)
            .execute()
        )
        obs_data = obs_res.data or []
        
        # Current active crowd from volunteer_counts
        vc_res = supabase.table("volunteer_counts").select("active_count").eq("event_id", event_id).execute()
        current_devices = sum((c.get("active_count") or 0) for c in (vc_res.data or []))
        
        if obs_data:
            buckets = {"-25m": set(), "-20m": set(), "-15m": set(), "-10m": set(), "-5m": set(), "Now": set()}
            for o in obs_data:
                try:
                    s_dt = datetime.fromisoformat(o["scanned_at"].replace("Z", "+00:00"))
                    diff_min = (now - s_dt).total_seconds() / 60.0
                    dev_id = o.get("ephemeral_id") or o.get("id")
                    if diff_min <= 5:
                        buckets["Now"].add(dev_id)
                    elif diff_min <= 10:
                        buckets["-5m"].add(dev_id)
                    elif diff_min <= 15:
                        buckets["-10m"].add(dev_id)
                    elif diff_min <= 20:
                        buckets["-15m"].add(dev_id)
                    elif diff_min <= 25:
                        buckets["-20m"].add(dev_id)
                    elif diff_min <= 30:
                        buckets["-25m"].add(dev_id)
                except Exception:
                    pass
            timeline_points = [
                {"time": k, "devices": len(v) if k != "Now" else max(len(v), current_devices)}
                for k, v in buckets.items()
            ]
        else:
            # Baseline reflects actual current devices (0 if none)
            timeline_points = [
                {"time": "-20m", "devices": current_devices},
                {"time": "-15m", "devices": current_devices},
                {"time": "-10m", "devices": current_devices},
                {"time": "-5m", "devices": current_devices},
                {"time": "Now", "devices": current_devices},
            ]
    except Exception as e:
        print(f"[timeline] Telemetry aggregation fallback: {e}")
        timeline_points = [
            {"time": "-20m", "devices": 0},
            {"time": "-15m", "devices": 0},
            {"time": "-10m", "devices": 0},
            {"time": "-5m", "devices": 0},
            {"time": "Now", "devices": 0},
        ]

    return {"timeline": timeline_points}


# ═══════════════════════════════════════════════════════════════
# 2. INCIDENTS
# ═══════════════════════════════════════════════════════════════

@router.get("/incidents/{event_id}")
async def list_incidents(event_id: str, status: Optional[str] = None, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    verify_event_ownership(supabase, event_id, current_user["user_id"])
    query = supabase.table("v_operational_incidents").select("*").eq("event_id", event_id).order("created_at", desc=True)
    if status:
        query = query.eq("status", status)
    result = query.execute()
    return {"incidents": result.data}


@router.post("/incidents")
async def create_incident(data: IncidentCreate, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    verify_event_ownership(supabase, data.event_id, current_user["user_id"])

    # 1. Normalize priority to ('normal', 'important', 'urgent')
    priority_map = {
        "routine": "normal",
        "low": "normal",
        "normal": "normal",
        "medium": "normal",
        "important": "important",
        "high": "important",
        "urgent": "urgent",
        "critical": "urgent",
    }
    priority_val = priority_map.get((data.priority or "").lower(), "normal")

    # 2. Normalize category
    valid_categories = {
        'crowd', 'safety', 'security', 'medical', 'infrastructure',
        'equipment', 'accessibility', 'lost_found', 'attendee_assistance',
        'operational', 'other'
    }
    cat_val = (data.category or "").lower().strip()
    if cat_val not in valid_categories:
        cat_val = "other"

    # 3. Ensure description meets length constraint (1..1000)
    desc_val = (data.description or "").strip()
    if not desc_val:
        desc_val = data.title.strip() or "Operational incident reported"

    # 4. Resolve zone_id
    zone_id = data.zone_id
    if not zone_id and data.zone_name:
        z_res = supabase.table("event_zones").select("id").eq("event_id", data.event_id).ilike("name", data.zone_name.strip()).execute()
        if z_res.data:
            zone_id = z_res.data[0]["id"]

    user_id = current_user.get("user_id") or current_user.get("id")
    reporter_name = current_user.get("full_name") or "Organizer"

    new_incident = {
        "event_id": data.event_id,
        "reporter_type": "organizer",
        "reporter_id": user_id,
        "reporter_name": reporter_name,
        "category": cat_val,
        "priority": priority_val,
        "status": "open",
        "title": data.title.strip(),
        "description": desc_val,
    }
    if zone_id:
        new_incident["zone_id"] = zone_id

    result = supabase.table("operational_incidents").insert(new_incident).execute()
    created = result.data[0] if result.data else None

    # Log in audit trail
    if created:
        try:
            supabase.table("operational_incident_logs").insert({
                "incident_id": created["id"],
                "event_id": data.event_id,
                "actor_id": user_id,
                "actor_name": reporter_name,
                "action": "created",
                "new_status": "open",
                "notes": f"Incident reported by organizer: {data.title.strip()}"
            }).execute()
        except Exception:
            pass

    return {"message": "Incident created", "data": result.data}


@router.put("/incidents/{incident_id}")
async def update_incident(incident_id: str, data: IncidentUpdate, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    # Verify incident exists
    existing = supabase.table("operational_incidents").select("*").eq("id", incident_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Incident not found")
    
    prev_status = existing.data[0].get("status")
    now_iso = datetime.now(timezone.utc).isoformat()
    updates = {}

    priority_map = {
        "routine": "normal",
        "low": "normal",
        "normal": "normal",
        "medium": "normal",
        "important": "important",
        "high": "important",
        "urgent": "urgent",
        "critical": "urgent",
    }
    if data.priority:
        updates["priority"] = priority_map.get(data.priority.lower(), data.priority)

    if data.status:
        st = data.status.lower().strip()
        if st in ('open', 'acknowledged', 'assigned', 'in_progress', 'resolved', 'closed', 'cancelled'):
            updates["status"] = st
            if st == "resolved":
                updates["resolved_at"] = now_iso
            elif st == "closed":
                updates["closed_at"] = now_iso
            elif st == "acknowledged":
                updates["acknowledged_at"] = now_iso

    assign_id = data.assigned_to_id or data.assigned_to
    if assign_id:
        updates["assigned_to_id"] = assign_id
        updates["assigned_at"] = now_iso
        if not data.status:
            updates["status"] = "assigned"

    if data.resolution_notes:
        updates["resolution_notes"] = data.resolution_notes

    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update")

    updates["updated_at"] = now_iso
    result = supabase.table("operational_incidents").update(updates).eq("id", incident_id).execute()

    # Log in audit trail
    try:
        new_status = updates.get("status", prev_status)
        action_name = "resolved" if new_status == "resolved" else ("closed" if new_status == "closed" else ("assigned" if assign_id else "note_added"))
        supabase.table("operational_incident_logs").insert({
            "incident_id": incident_id,
            "event_id": existing.data[0]["event_id"],
            "actor_id": current_user["user_id"],
            "actor_name": current_user.get("full_name") or "Organizer",
            "action": action_name,
            "previous_status": prev_status,
            "new_status": new_status,
            "notes": data.resolution_notes or f"Incident updated ({new_status})"
        }).execute()
    except Exception:
        pass

    return {"message": "Incident updated", "data": result.data}


# ═══════════════════════════════════════════════════════════════
# 3. VOLUNTEER SHIFTS & TEAMS
# ═══════════════════════════════════════════════════════════════

@router.get("/shifts/{event_id}")
async def list_shifts(event_id: str, current_user: dict = Depends(require_organizer)):
    try:
        supabase = get_supabase()
        verify_event_ownership(supabase, event_id, current_user["user_id"])
        shifts = supabase.table("v_volunteer_shifts").select("*").eq("event_id", event_id).order("created_at", desc=True).execute()
        return {"shifts": shifts.data}
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/teams/{event_id}")
async def list_teams(event_id: str, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    verify_event_ownership(supabase, event_id, current_user["user_id"])
    teams = supabase.table("v_event_teams").select("*").eq("event_id", event_id).execute()
    return {"teams": teams.data}


@router.get("/coverage/{event_id}")
async def list_coverage_requests(event_id: str, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    verify_event_ownership(supabase, event_id, current_user["user_id"])
    coverage = supabase.table("v_coverage_requests").select("*").eq("event_id", event_id).order("created_at", desc=True).execute()
    return {"coverage_requests": coverage.data}


@router.get("/volunteers/{event_id}")
async def list_event_volunteers(event_id: str, current_user: dict = Depends(require_organizer)):
    try:
        supabase = get_supabase()
        verify_event_ownership(supabase, event_id, current_user["user_id"])

        # Canonical assignment table only (web_volunteer_assignments retired)
        assignments_res = supabase.table("volunteer_assignments").select("*").eq("event_id", event_id).execute()
        assignments = assignments_res.data or []

        # Enrich with volunteer profiles manually (avoids PostgREST FK relationship cache dependency)
        vol_ids = list({a["volunteer_id"] for a in assignments if a.get("volunteer_id")})
        profiles_map = {}
        if vol_ids:
            try:
                prof_res = supabase.table("profiles").select("id, full_name, avatar_url, email").in_("id", vol_ids).execute()
                profiles_map = {p["id"]: p for p in (prof_res.data or [])}
            except Exception as pe:
                print(f"[organizer] Failed to fetch profiles for assignments: {pe}")

        for a in assignments:
            a["volunteer"] = profiles_map.get(a.get("volunteer_id")) or {
                "id": a.get("volunteer_id"),
                "full_name": "Volunteer",
                "avatar_url": None,
            }

        shifts = supabase.table("v_volunteer_shifts").select("*").eq("event_id", event_id).order("scheduled_start").execute()

        return {
            "assignments": assignments,
            "shifts": shifts.data or [],
        }
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


# ═══════════════════════════════════════════════════════════════
# 4. TASKS
# ═══════════════════════════════════════════════════════════════

@router.get("/tasks/{event_id}")
async def list_tasks(event_id: str, status: Optional[str] = None, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    verify_event_ownership(supabase, event_id, current_user["user_id"])
    query = supabase.table("v_supervisor_tasks").select("*").eq("event_id", event_id).order("created_at", desc=True)
    if status:
        query = query.eq("status", status)
    result = query.execute()
    return {"tasks": result.data}


@router.post("/tasks")
async def create_task(data: TaskCreate, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    verify_event_ownership(supabase, data.event_id, current_user["user_id"])
    new_task = {
        "event_id": data.event_id,
        "title": data.title,
        "description": data.description or "",
        "priority": data.priority,
        "status": "pending",
        "created_by": current_user.get("id", current_user.get("user_id")),
    }
    if data.zone_id:
        new_task["zone_id"] = data.zone_id
    elif data.zone_name:
        z_res = supabase.table("event_zones").select("id").eq("event_id", data.event_id).ilike("name", data.zone_name.strip()).execute()
        if z_res.data:
            new_task["zone_id"] = z_res.data[0]["id"]
    if data.assigned_to:
        new_task["assigned_to"] = data.assigned_to
    
    result = supabase.table("supervisor_tasks").insert(new_task).execute()
    return {"message": "Task created", "data": result.data}


@router.put("/tasks/{task_id}")
async def update_task(task_id: str, data: TaskUpdate, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    existing = supabase.table("supervisor_tasks").select("*").eq("id", task_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Task not found")
    
    updates = {}
    if data.status:
        updates["status"] = data.status
    if data.priority:
        updates["priority"] = data.priority
    if data.assigned_to:
        updates["assigned_to"] = data.assigned_to
    if data.notes:
        updates["completion_notes"] = data.notes
    
    if updates:
        updates["updated_at"] = datetime.now(timezone.utc).isoformat()
        result = supabase.table("supervisor_tasks").update(updates).eq("id", task_id).execute()
        return {"message": "Task updated", "data": result.data}
    raise HTTPException(status_code=400, detail="No fields to update")


# ═══════════════════════════════════════════════════════════════
# 5. COMMUNICATIONS
# ═══════════════════════════════════════════════════════════════

@router.get("/comms/{event_id}")
async def list_communications(event_id: str, target_type: Optional[str] = None, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    verify_event_ownership(supabase, event_id, current_user["user_id"])
    query = supabase.table("operational_messages").select("*").eq("event_id", event_id).order("created_at", desc=True).limit(100)
    if target_type:
        query = query.eq("target_type", target_type)
    result = query.execute()
    return {"messages": result.data}


@router.post("/comms")
async def send_communication(data: MessageCreate, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    verify_event_ownership(supabase, data.event_id, current_user["user_id"])
    new_msg = {
        "event_id": data.event_id,
        "sender_id": current_user.get("id", current_user.get("user_id")),
        "sender_name": current_user.get("full_name", current_user.get("nickname", "Organizer")),
        "content": data.content,
        "target_type": data.target_type,
        "priority": data.priority,
        "requires_acknowledgment": data.requires_ack,
    }
    if data.target_id:
        new_msg["target_id"] = data.target_id
    
    result = supabase.table("operational_messages").insert(new_msg).execute()
    return {"message": "Message sent", "data": result.data}


# ═══════════════════════════════════════════════════════════════
# 6. CROWD MONITORING
# ═══════════════════════════════════════════════════════════════

@router.get("/crowd/{event_id}")
async def get_crowd_data(event_id: str, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    verify_event_ownership(supabase, event_id, current_user["user_id"])
    
    # Get live counts
    counts = supabase.table("volunteer_counts").select("*").eq("event_id", event_id).execute()
    
    # Get zones
    zones = supabase.table("event_zones").select("*").eq("event_id", event_id).execute()
    
    # Aggregate per zone
    zone_density = {}
    for z in zones.data:
        zone_name = z.get("name", "Unknown")
        zone_counts = [c for c in counts.data if c.get("zone") == zone_name or c.get("zone_id") == z.get("id")]
        total_active = sum(c.get("active_count", 0) for c in zone_counts)
        zone_density[zone_name] = {
            "zone_id": z.get("id"),
            "active_count": total_active,
            "capacity_limit": z.get("capacity_limit"),
            "operating_capacity": z.get("operating_capacity"),
            "is_monitored": z.get("is_crowd_monitored", True),
            "volunteer_scanners": len(zone_counts),
        }
    
    # Evaluate automated crowd diversion if enabled
    auto_quest = await check_and_auto_dispatch_diversion(supabase, event_id, current_user["user_id"])

    return {
        "zone_density": zone_density,
        "raw_counts": counts.data,
        "zones": zones.data,
        "auto_diversion_enabled": event_id in AUTO_DIVERSION_EVENTS,
        "auto_diversion_dispatched": auto_quest is not None,
    }


SNAPSHOT_MIN_INTERVAL_SEC = 60
PREDICTION_HISTORY_MIN = 30
SNAPSHOT_RETENTION_HOURS = 24


@router.get("/crowd/{event_id}/predictions")
async def get_crowd_predictions(
    event_id: str,
    horizon: int = Query(15, ge=5, le=60),
    current_user: dict = Depends(require_organizer),
):
    """Algorithmic overcrowding forecast (graph-based, no ML). Organizer only."""
    supabase = get_supabase()
    verify_event_ownership(supabase, event_id, current_user["user_id"])
    now = datetime.now(timezone.utc)

    zones = supabase.table("event_zones").select("*").eq("event_id", event_id).execute().data or []
    counts = supabase.table("volunteer_counts").select("*").eq("event_id", event_id).execute().data or []

    # Live count per zone (sum across scanners, like /crowd/{event_id})
    current: Dict[str, Any] = {}
    for z in zones:
        zc = [c for c in counts if c.get("zone") == z.get("name") or c.get("zone_id") == z.get("id")]
        if zc:
            stamps = [crowd_prediction.parse_ts(c.get("updated_at")) for c in zc]
            stamps = [s for s in stamps if s]
            current[z["id"]] = (sum(c.get("active_count", 0) or 0 for c in zc), max(stamps) if stamps else now)

    # Recent history
    since = (now - timedelta(minutes=PREDICTION_HISTORY_MIN)).isoformat()
    history: Dict[str, list] = {}
    last_snapshot: Dict[str, Any] = {}
    try:
        snaps = (supabase.table("crowd_zone_snapshots").select("zone_id, estimated_count, snapshot_at")
                 .eq("event_id", event_id).gte("snapshot_at", since).order("snapshot_at").limit(3000).execute().data or [])
        for s in snaps:
            ts = crowd_prediction.parse_ts(s.get("snapshot_at"))
            if ts and s.get("zone_id"):
                history.setdefault(s["zone_id"], []).append((ts, float(s.get("estimated_count") or 0)))
                last_snapshot[s["zone_id"]] = ts
    except Exception:
        pass

    # Throttled auto-recorder: builds the history the forecast depends on
    try:
        rows = []
        for zid, (count, _) in current.items():
            last = last_snapshot.get(zid)
            if not last or (now - last).total_seconds() >= SNAPSHOT_MIN_INTERVAL_SEC:
                rows.append({"event_id": event_id, "zone_id": zid, "estimated_count": count,
                             "source": "auto", "snapshot_at": now.isoformat()})
                history.setdefault(zid, []).append((now, float(count)))
        if rows:
            supabase.table("crowd_zone_snapshots").insert(rows).execute()
            # Prune stale snapshots older than 24h
            cutoff = (now - timedelta(hours=SNAPSHOT_RETENTION_HOURS)).isoformat()
            supabase.table("crowd_zone_snapshots").delete().eq("event_id", event_id).lt("snapshot_at", cutoff).execute()
    except Exception:
        pass

    # Scheduled surges (sessions ending or starting within the horizon)
    sessions: list = []
    try:
        sessions = (supabase.table("sessions").select("zone_id, title, start_time, end_time")
                    .eq("event_id", event_id).gte("end_time", now.isoformat())
                    .lte("start_time", (now + timedelta(minutes=horizon)).isoformat()).execute().data or [])
    except Exception:
        pass

    # Gate check-in rate (last 10 min) mapped to zones by id or name
    arrivals: Dict[str, float] = {}
    try:
        tk = (supabase.table("tickets").select("checked_in_zone, check_in_at").eq("event_id", event_id)
              .gte("check_in_at", (now - timedelta(minutes=10)).isoformat()).execute().data or [])
        key = {}
        for z in zones:
            key[z["id"]] = z["id"]
            key[z.get("name")] = z["id"]
        for t in tk:
            zid = key.get(t.get("checked_in_zone"))
            if zid:
                arrivals[zid] = arrivals.get(zid, 0.0) + 0.1
    except Exception:
        pass

    predictions = crowd_prediction.predict(
        zones, history, current, sessions=sessions, arrivals_per_min=arrivals,
        horizon_min=horizon, now=now,
    )
    return {"event_id": event_id, "horizon_minutes": horizon, "computed_at": now.isoformat(),
            "predictions": predictions}


# ═══════════════════════════════════════════════════════════════
# 6B. AI CROWD REDISTRIBUTION & DIVERSION ENGINE
# ═══════════════════════════════════════════════════════════════

async def check_and_auto_dispatch_diversion(supabase, event_id: str, actor_id: Optional[str] = None):
    """
    Autonomous Crowd Diversion Evaluator:
    If auto-diversion is enabled for this event, checks if any zone is >= 85% full.
    If so and cooldown (15m) has passed, generates and dispatches a surge diversion quest
    directing attendees to an under-capacity sponsor stall.
    """
    if event_id not in AUTO_DIVERSION_EVENTS:
        return None

    now = datetime.now(timezone.utc)
    last = LAST_DIVERSION_DISPATCH.get(event_id)
    if last and (now - last).total_seconds() < 900:  # 15 min cooldown
        return None

    try:
        zones_res = supabase.table("event_zones").select("*").eq("event_id", event_id).execute()
        counts_res = supabase.table("volunteer_counts").select("*").eq("event_id", event_id).execute()
        booths_res = supabase.table("booths").select("*").eq("event_id", event_id).execute()

        zones = zones_res.data or []
        counts = counts_res.data or []
        booths = booths_res.data or []

        if not zones or not booths:
            return None

        zone_stats = []
        for z in zones:
            zid = z["id"]
            zname = z.get("name", "Unknown")
            zc = [c for c in counts if c.get("zone") == zname or c.get("zone_id") == zid]
            active = sum(c.get("active_count", 0) for c in zc)
            cap = z.get("operating_capacity") or z.get("capacity_limit") or 100
            ratio = (active / cap) if cap > 0 else 0
            zone_stats.append({"id": zid, "name": zname, "active": active, "capacity": cap, "ratio": ratio})

        congested = [zs for zs in zone_stats if zs["ratio"] >= 0.85]
        if not congested:
            return None

        congested_zone = sorted(congested, key=lambda x: x["ratio"], reverse=True)[0]
        destination_zones = sorted([zs for zs in zone_stats if zs["id"] != congested_zone["id"]], key=lambda x: x["ratio"])
        if not destination_zones:
            return None
        target_zone = destination_zones[0]

        # Prefer booths in target_zone
        booths_in_target = [b for b in booths if b.get("zone_id") == target_zone["id"]]
        if booths_in_target:
            target_booth = booths_in_target[0]
        else:
            stalls = [b for b in booths if (b.get("booth_number") and str(b.get("booth_number")).strip())]
            target_booth = stalls[0] if stalls else booths[0]

        brand_name = target_booth.get("name") or target_booth.get("company_name") or "Featured Sponsor"
        booth_num = target_booth.get("booth_number") or ""

        ev_res = supabase.table("events").select("name").eq("id", event_id).execute()
        ev_name = ev_res.data[0]["name"] if ev_res.data else "Event"

        quest = await generate_crowd_diversion_quest({
            "event_name": ev_name,
            "overcrowded_zone_name": congested_zone["name"],
            "brand_name": brand_name,
            "target_zone_name": target_zone["name"],
            "target_booth_number": booth_num,
            "bonus_points": 200,
        })

        # Insert activity
        supabase.table("activities").insert({
            "event_id": event_id,
            "zone_id": target_zone["id"],
            "title": quest.get("title", f"⚡ Surge Bonus: Visit {brand_name}"),
            "description": quest.get("description", ""),
            "activity_type": "scavenger",
            "points_reward": 200,
            "is_active": True,
        }).execute()

        # Push notification broadcast
        supabase.table("event_notifications").insert({
            "event_id": event_id,
            "target_user_id": None,
            "title": quest.get("title"),
            "body": quest.get("description"),
            "category": "crowd",
            "action_route": "/activities",
            "is_active": True,
        }).execute()

        try:
            supabase.table("event_activity_logs").insert({
                "event_id": event_id,
                "action_type": "auto_crowd_diversion_quest",
                "description": f"Automated AI surge quest '{quest.get('title')}' dispatched to relieve {congested_zone['name']} by directing attendees to {brand_name} at {target_zone['name']}.",
                "actor_id": actor_id
            }).execute()
        except Exception:
            pass

        LAST_DIVERSION_DISPATCH[event_id] = now
        logger.info(f"Auto-diversion executed for event {event_id}: {congested_zone['name']} -> {brand_name}")
        return quest
    except Exception as e:
        logger.warning(f"Error in check_and_auto_dispatch_diversion: {e}")
        return None


@router.get("/crowd/{event_id}/diversion-recommendations")
async def get_diversion_recommendations(
    event_id: str,
    source_zone_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_organizer)
):
    """
    Evaluates venue zones to detect overcrowded zones and pairs them with sponsor stalls
    in low-density zones to formulate crowd redistribution diversion quests.
    """
    supabase = get_supabase()
    verify_event_ownership(supabase, event_id, current_user["user_id"])

    # 1. Fetch zones
    zones_res = supabase.table("event_zones").select("*").eq("event_id", event_id).execute()
    zones = zones_res.data or []

    # 2. Fetch live counts
    counts_res = supabase.table("volunteer_counts").select("*").eq("event_id", event_id).execute()
    counts = counts_res.data or []

    # 3. Fetch booths/sponsors with stall info
    booths_res = supabase.table("booths").select("*, event_zones(id, name)").eq("event_id", event_id).execute()
    booths = booths_res.data or []

    # Calculate zone occupancy stats
    zone_stats = []
    for z in zones:
        zid = z["id"]
        zname = z.get("name", "Unknown")
        zc = [c for c in counts if c.get("zone") == zname or c.get("zone_id") == zid]
        active_count = sum(c.get("active_count", 0) for c in zc)
        capacity = z.get("operating_capacity") or z.get("capacity_limit") or 100
        ratio = (active_count / capacity) if capacity > 0 else 0
        zone_stats.append({
            "id": zid,
            "name": zname,
            "active_count": active_count,
            "capacity": capacity,
            "ratio": round(ratio, 2),
            "is_overcrowded": ratio >= 0.8 or (ratio >= 0.6 and active_count > 30),
            "is_low_density": ratio < 0.5
        })

    def is_stall(b):
        return bool(b.get("zone_id") or (b.get("booth_number") and str(b.get("booth_number")).strip()))

    # Find candidate congested zones
    if source_zone_id:
        target_src = [zs for zs in zone_stats if zs["id"] == source_zone_id]
        congested_zones = target_src if target_src else [zs for zs in zone_stats if zs["is_overcrowded"]]
    else:
        congested_zones = [zs for zs in zone_stats if zs["is_overcrowded"]]
        # If no zone strictly passes threshold, but there is disparity among zones with traffic, offer the highest density zone
        if not congested_zones and zone_stats:
            sorted_zones = sorted(zone_stats, key=lambda x: x["ratio"], reverse=True)
            if len(sorted_zones) > 1 and sorted_zones[0]["ratio"] > sorted_zones[-1]["ratio"]:
                congested_zones = [sorted_zones[0]]
            elif sorted_zones and sorted_zones[0]["active_count"] > 0:
                congested_zones = [sorted_zones[0]]

    # Find candidate low-density destination zones (sorted by ratio ascending)
    destination_zones = sorted([zs for zs in zone_stats if zs["is_low_density"]], key=lambda x: x["ratio"])
    if not destination_zones and zone_stats:
        destination_zones = sorted(zone_stats, key=lambda x: x["ratio"])

    recommendations = []
    seen_pairings = set()
    for c_zone in congested_zones:
        # Find target booths in low-density zones
        target_pairings = []
        for d_zone in destination_zones:
            if d_zone["id"] == c_zone["id"]:
                continue
            
            # Find booths assigned directly to this destination zone
            zone_booths = [b for b in booths if b.get("zone_id") == d_zone["id"]]
            for b in zone_booths:
                pair_key = (c_zone["id"], d_zone["id"], b["id"])
                if pair_key not in seen_pairings:
                    seen_pairings.add(pair_key)
                    target_pairings.append((d_zone, b))

        # If no booths are placed in this specific d_zone, pick booths not placed in the congested zone
        if not target_pairings and booths:
            available_booths = [b for b in booths if b.get("zone_id") != c_zone["id"]]
            for b in available_booths:
                valid_dest = [d for d in destination_zones if d["id"] != c_zone["id"]]
                if valid_dest:
                    dest = valid_dest[0]
                    pair_key = (c_zone["id"], dest["id"], b["id"])
                    if pair_key not in seen_pairings:
                        seen_pairings.add(pair_key)
                        target_pairings.append((dest, b))

        for d_zone, b in target_pairings:
            bonus = 150 if c_zone["ratio"] < 0.9 else 200
            b_name = b.get("name") or b.get("company_name") or "Sponsor Stall"
            recommendations.append({
                "id": f"{c_zone['id']}_{b['id']}_{d_zone['id']}",
                "source_zone": c_zone,
                "target_zone": d_zone,
                "sponsor": {
                    "id": b["id"],
                    "name": b_name,
                    "company_name": b.get("company_name") or b_name,
                    "booth_number": b.get("booth_number") or "",
                    "category": b.get("category") or "Sponsor",
                    "website_url": b.get("website_url"),
                    "has_stall": is_stall(b)
                },
                "suggested_bonus_points": bonus,
                "urgency": "critical" if c_zone["ratio"] >= 0.85 else "moderate",
                "reasoning": f"Zone '{c_zone['name']}' is at {int(c_zone['ratio']*100)}% capacity ({c_zone['active_count']}/{c_zone['capacity']}). Directing foot traffic to '{b_name}' at '{d_zone['name']}' ({int(d_zone['ratio']*100)}% capacity) will alleviate bottleneck pressure."
            })
            recommendations.append({
                "id": f"{c_zone['id']}_{b['id']}",
                "source_zone": c_zone,
                "target_zone": d_zone,
                "sponsor": {
                    "id": b["id"],
                    "name": b_name,
                    "company_name": b.get("company_name") or b_name,
                    "booth_number": b.get("booth_number") or "",
                    "category": b.get("category") or "Sponsor",
                    "website_url": b.get("website_url"),
                    "has_stall": b.get("has_stall", True)
                },
                "suggested_bonus_points": bonus,
                "urgency": "critical" if c_zone["ratio"] >= 0.85 else "moderate",
                "reasoning": f"Zone '{c_zone['name']}' is at {int(c_zone['ratio']*100)}% capacity ({c_zone['active_count']}/{c_zone['capacity']}). Directing foot traffic to '{b_name}' at '{d_zone['name']}' ({int(d_zone['ratio']*100)}% capacity) will alleviate bottleneck pressure."
            })

    auto_active = event_id in AUTO_DIVERSION_EVENTS
    last_disp = LAST_DIVERSION_DISPATCH.get(event_id)

    return {
        "event_id": event_id,
        "auto_diversion_enabled": auto_active,
        "last_dispatch": last_disp.isoformat() if last_disp else None,
        "congested_zones_count": len(congested_zones),
        "recommendations": recommendations,
        "all_zone_stats": zone_stats
    }


@router.post("/crowd/{event_id}/dispatch-diversion-quest")
async def dispatch_diversion_quest(
    event_id: str,
    data: DiversionDispatchPayload,
    current_user: dict = Depends(require_organizer)
):
    """
    Generates and broadcasts an AI crowd diversion quest using Gemini 3.5 Flash Lite
    to redirect attendees from an overcrowded venue area to an under-crowded sponsor stall.
    """
    supabase = get_supabase()
    verify_event_ownership(supabase, event_id, current_user["user_id"])

    ev_res = supabase.table("events").select("name").eq("id", event_id).execute()
    event_name = ev_res.data[0]["name"] if ev_res.data else "the event"

    # 1. Generate quest via Gemini 3.5 Flash Lite
    quest_payload = {
        "event_name": event_name,
        "overcrowded_zone_name": data.overcrowded_zone_name,
        "brand_name": data.brand_name,
        "target_zone_name": data.target_zone_name,
        "target_booth_number": data.booth_number,
        "bonus_points": data.bonus_points or 150,
    }
    quest = await generate_crowd_diversion_quest(quest_payload)

    final_title = data.custom_title or quest.get("title", f"⚡ Flash Surge: Visit {data.brand_name}")
    final_desc = data.custom_description or quest.get("description", "")
    pts = int(data.bonus_points or quest.get("points_reward") or 150)

    # 2. Insert into activities table
    activity_row = {
        "event_id": event_id,
        "title": final_title,
        "description": final_desc,
        "activity_type": "scavenger",
        "points_reward": pts,
        "is_active": True,
    }
    if data.target_zone_id:
        activity_row["zone_id"] = data.target_zone_id

    act_res = supabase.table("activities").insert(activity_row).execute()
    created_act = act_res.data[0] if act_res.data else {}

    # 3. Broadcast in-app push notification to all attendees (target_user_id=None)
    notification_res = None
    if data.auto_broadcast:
        try:
            notif_row = {
                "event_id": event_id,
                "target_user_id": None,
                "title": final_title,
                "body": final_desc,
                "category": "crowd",
                "action_route": "/activities",
                "is_active": True,
            }
            n_res = supabase.table("event_notifications").insert(notif_row).execute()
            notification_res = n_res.data[0] if n_res.data else {}
        except Exception as e:
            logger.warning(f"Failed to insert notification: {e}")

    # 4. Record to event_activity_logs
    try:
        supabase.table("event_activity_logs").insert({
            "event_id": event_id,
            "action_type": "crowd_diversion_quest_dispatched",
            "description": f"AI Flash Surge Quest '{final_title}' dispatched to divert attendees from {data.overcrowded_zone_name} to {data.brand_name} at {data.target_zone_name} (+{pts} bonus pts).",
            "actor_id": current_user["user_id"]
        }).execute()
    except Exception:
        pass

    LAST_DIVERSION_DISPATCH[event_id] = datetime.now(timezone.utc)

    return {
        "success": True,
        "message": f"AI Crowd Diversion Quest dispatched successfully! Attendees are incentivized to move to {data.brand_name}.",
        "quest": quest,
        "activity": created_act,
        "notification": notification_res
    }


@router.post("/crowd/{event_id}/auto-diversion/toggle")
async def toggle_auto_diversion(
    event_id: str,
    data: AutoDiversionTogglePayload,
    current_user: dict = Depends(require_organizer)
):
    """Enable or disable autonomous AI crowd diversion for an event."""
    supabase = get_supabase()
    verify_event_ownership(supabase, event_id, current_user["user_id"])
    if data.enabled:
        AUTO_DIVERSION_EVENTS.add(event_id)
    else:
        AUTO_DIVERSION_EVENTS.discard(event_id)
    return {
        "event_id": event_id,
        "auto_diversion_enabled": data.enabled,
        "message": f"Autonomous Crowd Diversion Agent {'activated' if data.enabled else 'paused'}."
    }


@router.get("/crowd/{event_id}/auto-diversion/status")
async def get_auto_diversion_status(
    event_id: str,
    current_user: dict = Depends(require_organizer)
):
    """Retrieve status of autonomous crowd diversion agent."""
    supabase = get_supabase()
    verify_event_ownership(supabase, event_id, current_user["user_id"])
    last_disp = LAST_DIVERSION_DISPATCH.get(event_id)
    return {
        "event_id": event_id,
        "auto_diversion_enabled": event_id in AUTO_DIVERSION_EVENTS,
        "last_dispatch": last_disp.isoformat() if last_disp else None
    }


# ═══════════════════════════════════════════════════════════════
# 7. ZONES
# ═══════════════════════════════════════════════════════════════

@router.get("/zones/{event_id}")
async def list_zones(event_id: str, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    verify_event_ownership(supabase, event_id, current_user["user_id"])
    result = supabase.table("event_zones").select("*").eq("event_id", event_id).order("created_at").execute()
    return {"zones": result.data}


@router.post("/zones")
async def create_zone(data: ZoneCreate, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    verify_event_ownership(supabase, data.event_id, current_user["user_id"])
    new_zone = {
        "event_id": data.event_id,
        "name": data.name,
        "code": data.code or data.name,
        "floor_level": data.floor_level or 1,
        "is_crowd_monitored": data.is_crowd_monitored,
    }
    if data.capacity_limit:
        new_zone["capacity_limit"] = data.capacity_limit
    if data.operating_capacity:
        new_zone["operating_capacity"] = data.operating_capacity
    
    result = supabase.table("event_zones").insert(new_zone).execute()
    return {"message": "Zone created", "data": result.data}


@router.put("/zones/{zone_id}")
async def update_zone(zone_id: str, data: ZoneUpdate, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    existing = supabase.table("event_zones").select("*").eq("id", zone_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Zone not found")

    updates = {k: v for k, v in data.model_dump(exclude_none=True).items()}
    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update")

    result = supabase.table("event_zones").update(updates).eq("id", zone_id).execute()
    return {"message": "Zone updated", "data": result.data}


@router.delete("/zones/{zone_id}")
async def delete_zone(zone_id: str, current_user: dict = Depends(require_organizer)):
    """Delete a zone. Verifies event ownership first."""
    supabase = get_supabase()
    existing = supabase.table("event_zones").select("id, event_id, name").eq("id", zone_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Zone not found")
    zone = existing.data[0]
    verify_event_ownership(supabase, zone["event_id"], current_user["user_id"])

    supabase.table("event_zones").delete().eq("id", zone_id).execute()
    return {"message": f"Zone {zone['name']} deleted"}


# ═══════════════════════════════════════════════════════════════
# 8. BRANDS & SPONSORS (BOOTHS)
# ═══════════════════════════════════════════════════════════════

@router.get("/booths/{event_id}")
async def list_booths(event_id: str, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    verify_event_ownership(supabase, event_id, current_user["user_id"])
    result = supabase.table("booths").select("*, event_zones(id, name, floor_level)").eq("event_id", event_id).order("created_at").execute()
    data = []
    for item in (result.data or []):
        z = item.get("event_zones")
        if z and isinstance(z, dict):
            item["zone_name"] = z.get("name")
        data.append(item)
    return {"booths": data}


@router.post("/booths")
async def create_booth(data: BoothCreate, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    verify_event_ownership(supabase, data.event_id, current_user["user_id"])
    new_booth = {
        "event_id": data.event_id,
        "name": data.name,
        "company_name": data.company_name or data.name,
        "description": data.description or "",
        "is_active": data.is_active if data.is_active is not None else True,
    }
    if data.booth_number:
        new_booth["booth_number"] = data.booth_number
    if data.zone_id:
        new_booth["zone_id"] = data.zone_id
    if data.category:
        new_booth["category"] = data.category
    if data.contact_email:
        new_booth["contact_email"] = data.contact_email
    if data.website_url:
        new_booth["website_url"] = data.website_url
    
    result = supabase.table("booths").insert(new_booth).execute()
    return {"message": "Brand / Sponsor created", "data": result.data}


@router.put("/booths/{booth_id}")
async def update_booth(booth_id: str, data: BoothUpdate, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    existing = supabase.table("booths").select("*").eq("id", booth_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Sponsor / booth not found")
    
    updates = {k: v for k, v in data.model_dump(exclude_none=True).items()}
    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update")
    
    result = supabase.table("booths").update(updates).eq("id", booth_id).execute()
    return {"message": "Brand / Sponsor updated", "data": result.data}


@router.put("/booths/{booth_id}/location")
async def assign_booth_location(booth_id: str, data: SponsorLocationAssign, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    existing = supabase.table("booths").select("*").eq("id", booth_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Sponsor / booth not found")
    
    updates = {}
    if data.zone_id is not None:
        updates["zone_id"] = data.zone_id if data.zone_id.strip() != "" else None
    if data.booth_number is not None:
        updates["booth_number"] = data.booth_number.strip()
    
    if not updates:
        raise HTTPException(status_code=400, detail="No location fields provided")
        
    result = supabase.table("booths").update(updates).eq("id", booth_id).execute()
    return {"message": "Venue location assigned successfully", "data": result.data}


@router.delete("/booths/{booth_id}")
async def delete_booth(booth_id: str, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    existing = supabase.table("booths").select("*").eq("id", booth_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Sponsor / booth not found")
    supabase.table("booths").delete().eq("id", booth_id).execute()
    return {"message": "Brand / Sponsor deleted"}


# Aliases for Brands & Sponsors
@router.get("/sponsors/{event_id}")
async def list_sponsors(event_id: str, current_user: dict = Depends(require_organizer)):
    return await list_booths(event_id, current_user)

@router.post("/sponsors")
async def create_sponsor(data: BoothCreate, current_user: dict = Depends(require_organizer)):
    return await create_booth(data, current_user)

@router.put("/sponsors/{sponsor_id}")
async def update_sponsor(sponsor_id: str, data: BoothUpdate, current_user: dict = Depends(require_organizer)):
    return await update_booth(sponsor_id, data, current_user)

@router.put("/sponsors/{sponsor_id}/location")
async def assign_sponsor_location(sponsor_id: str, data: SponsorLocationAssign, current_user: dict = Depends(require_organizer)):
    return await assign_booth_location(sponsor_id, data, current_user)

@router.delete("/sponsors/{sponsor_id}")
async def delete_sponsor(sponsor_id: str, current_user: dict = Depends(require_organizer)):
    return await delete_booth(sponsor_id, current_user)


# ═══════════════════════════════════════════════════════════════
# 9. SESSIONS
# ═══════════════════════════════════════════════════════════════

@router.get("/sessions/{event_id}")
async def list_sessions(event_id: str, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    verify_event_ownership(supabase, event_id, current_user["user_id"])
    result = supabase.table("sessions").select("*").eq("event_id", event_id).order("start_time").execute()
    return {"sessions": result.data}


@router.post("/sessions")
async def create_session(data: SessionCreate, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    verify_event_ownership(supabase, data.event_id, current_user["user_id"])
    new_session = {
        "event_id": data.event_id,
        "title": data.title,
        "description": data.description or "",
    }
    if data.speaker_name:
        new_session["speaker_name"] = data.speaker_name
    if data.zone_id:
        new_session["zone_id"] = data.zone_id
    if data.location:
        new_session["location"] = data.location
    if data.start_time:
        new_session["start_time"] = data.start_time
    if data.end_time:
        new_session["end_time"] = data.end_time
    if data.session_type:
        new_session["session_type"] = data.session_type
    
    result = supabase.table("sessions").insert(new_session).execute()
    return {"message": "Session created", "data": result.data}


@router.put("/sessions/{session_id}")
async def update_session(session_id: str, data: SessionUpdate, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    existing = supabase.table("sessions").select("*").eq("id", session_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Session not found")
    
    updates = {k: v for k, v in data.model_dump(exclude_none=True).items()}
    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update")
    
    result = supabase.table("sessions").update(updates).eq("id", session_id).execute()
    return {"message": "Session updated", "data": result.data}


@router.delete("/sessions/{session_id}")
async def delete_session(session_id: str, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    existing = supabase.table("sessions").select("*").eq("id", session_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Session not found")
    supabase.table("sessions").delete().eq("id", session_id).execute()
    return {"message": "Session deleted"}


# ═══════════════════════════════════════════════════════════════
# 10. ASSISTANCE
# ═══════════════════════════════════════════════════════════════

@router.get("/assistance/{event_id}")
async def list_assistance_requests(event_id: str, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    verify_event_ownership(supabase, event_id, current_user["user_id"])
    # Assistance requests are stored as incidents with category='assistance'
    result = (
        supabase.table("operational_incidents")
        .select("*")
        .eq("event_id", event_id)
        .eq("category", "assistance")
        .order("created_at", desc=True)
        .execute()
    )
    return {"assistance_requests": result.data}


# ═══════════════════════════════════════════════════════════════
# 11. ANALYTICS
# ═══════════════════════════════════════════════════════════════

@router.get("/analytics/{event_id}")
async def get_event_analytics(event_id: str, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    verify_event_ownership(supabase, event_id, current_user["user_id"])
    
    # Tickets
    total_tickets = supabase.table("tickets").select("id", count="exact").eq("event_id", event_id).execute()
    checked_in = supabase.table("tickets").select("id", count="exact").eq("event_id", event_id).eq("status", "checked_in").execute()
    
    # Incidents
    incidents = supabase.table("operational_incidents").select("*").eq("event_id", event_id).execute()
    total_incidents = len(incidents.data)
    resolved_incidents = len([i for i in incidents.data if i.get("status") in ("resolved", "closed")])
    urgent_incidents = len([i for i in incidents.data if i.get("priority") == "urgent"])
    
    # Tasks
    tasks = supabase.table("supervisor_tasks").select("*").eq("event_id", event_id).execute()
    total_tasks = len(tasks.data)
    completed_tasks = len([t for t in tasks.data if t.get("status") == "completed"])
    
    # Shifts
    shifts = supabase.table("volunteer_shifts").select("*").eq("event_id", event_id).execute()
    active_shifts = len([s for s in shifts.data if s.get("status") == "active"])
    
    # Booths
    booths = supabase.table("booths").select("id", count="exact").eq("event_id", event_id).execute()
    
    # Sessions
    sessions = supabase.table("sessions").select("id", count="exact").eq("event_id", event_id).execute()
    
    # Zones
    zones = supabase.table("event_zones").select("*").eq("event_id", event_id).execute()
    
    # Crowd data
    counts = supabase.table("volunteer_counts").select("*").eq("event_id", event_id).execute()
    total_crowd = sum(c.get("active_count", 0) for c in counts.data)
    
    # Messages
    messages = supabase.table("operational_messages").select("id", count="exact").eq("event_id", event_id).execute()
    
    # Incident categories breakdown
    incident_categories = {}
    for inc in incidents.data:
        cat = inc.get("category", "other")
        incident_categories[cat] = incident_categories.get(cat, 0) + 1
    
    # Incident priority breakdown
    incident_priorities = {}
    for inc in incidents.data:
        pri = inc.get("priority", "routine")
        incident_priorities[pri] = incident_priorities.get(pri, 0) + 1

    # Real Attendance Velocity Curve calculated from actual tickets check-ins
    tickets_res = supabase.table("tickets").select("id, status, checked_in_at").eq("event_id", event_id).execute()
    tickets_data = tickets_res.data or []
    checked_in_tickets = [t for t in tickets_data if t.get("checked_in_at")]
    attendance_velocity = []
    if checked_in_tickets:
        checked_in_tickets.sort(key=lambda t: t["checked_in_at"])
        hourly_counts = {}
        cumulative = 0
        for t in checked_in_tickets:
            try:
                dt = datetime.fromisoformat(t["checked_in_at"].replace("Z", "+00:00"))
                hr_key = dt.strftime("%H:00")
            except Exception:
                hr_key = "Check-in"
            hourly_counts[hr_key] = hourly_counts.get(hr_key, 0) + 1
        for hr, count in hourly_counts.items():
            cumulative += count
            attendance_velocity.append({
                "hour": hr,
                "checkins": count,
                "cumulative": cumulative,
            })

    # Real Zone Footfall vs Operating Limit from event_zones and volunteer_counts
    zone_footfall = []
    for z in zones.data:
        zname = z.get("name", "Zone")
        zid = z.get("id")
        z_counts = [c for c in counts.data if c.get("zone") == zname or c.get("zone_id") == zid]
        current_cnt = sum(c.get("active_count", 0) for c in z_counts)
        cap = z.get("operating_capacity") or z.get("capacity_limit") or 0
        zone_footfall.append({
            "zone": zname,
            "current": current_cnt,
            "capacity": cap,
        })

    # Real Incident Response Latency (MTTA & MTTR) from operational_incidents
    incident_resolution = []
    category_latencies = {}
    for inc in incidents.data:
        cat = (inc.get("category") or "other").capitalize()
        created_str = inc.get("created_at")
        ack_str = inc.get("acknowledged_at")
        res_str = inc.get("resolved_at")
        
        if created_str:
            try:
                c_dt = datetime.fromisoformat(created_str.replace("Z", "+00:00"))
                mtta = None
                mttr = None
                if ack_str:
                    a_dt = datetime.fromisoformat(ack_str.replace("Z", "+00:00"))
                    mtta = max(0.0, (a_dt - c_dt).total_seconds() / 60.0)
                if res_str:
                    r_dt = datetime.fromisoformat(res_str.replace("Z", "+00:00"))
                    mttr = max(0.0, (r_dt - c_dt).total_seconds() / 60.0)
                
                if cat not in category_latencies:
                    category_latencies[cat] = {"mtta": [], "mttr": []}
                if mtta is not None:
                    category_latencies[cat]["mtta"].append(mtta)
                if mttr is not None:
                    category_latencies[cat]["mttr"].append(mttr)
            except Exception:
                pass
                
    for cat, lat in category_latencies.items():
        avg_mtta = round(sum(lat["mtta"]) / len(lat["mtta"]), 1) if lat["mtta"] else 0.0
        avg_mttr = round(sum(lat["mttr"]) / len(lat["mttr"]), 1) if lat["mttr"] else 0.0
        incident_resolution.append({
            "category": cat,
            "mtta": avg_mtta,
            "mttr": avg_mttr,
        })
    
    return {
        "attendance": {
            "total_tickets": total_tickets.count or 0,
            "checked_in": checked_in.count or 0,
            "check_in_rate": round((checked_in.count or 0) / max(total_tickets.count or 1, 1) * 100, 1),
        },
        "crowd": {
            "current_total": total_crowd,
            "zones_monitored": len([z for z in zones.data if z.get("is_crowd_monitored")]),
        },
        "incidents": {
            "total": total_incidents,
            "resolved": resolved_incidents,
            "urgent": urgent_incidents,
            "resolution_rate": round(resolved_incidents / max(total_incidents, 1) * 100, 1),
            "by_category": incident_categories,
            "by_priority": incident_priorities,
        },
        "tasks": {
            "total": total_tasks,
            "completed": completed_tasks,
            "completion_rate": round(completed_tasks / max(total_tasks, 1) * 100, 1),
        },
        "volunteers": {
            "active_shifts": active_shifts,
            "total_shifts": len(shifts.data),
        },
        "content": {
            "booths": booths.count or 0,
            "sessions": sessions.count or 0,
            "zones": len(zones.data),
        },
        "communications": {
            "total_messages": messages.count or 0,
        },
        "attendance_velocity": attendance_velocity,
        "zone_footfall": zone_footfall,
        "incident_resolution": incident_resolution,
    }


# ═══════════════════════════════════════════════════════════════
# 12. EXPORT
# ═══════════════════════════════════════════════════════════════

@router.get("/export/{event_id}")
async def export_event_data(event_id: str, report_type: str = Query("summary"), current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    verify_event_ownership(supabase, event_id, current_user["user_id"])
    
    event = supabase.table("events").select("*").eq("id", event_id).execute()
    
    if report_type == "incidents":
        data = supabase.table("operational_incidents").select("*").eq("event_id", event_id).order("created_at").execute()
        return {"report_type": "incidents", "event": event.data[0] if event.data else {}, "data": data.data}
    elif report_type == "attendance":
        data = supabase.table("tickets").select("*").eq("event_id", event_id).execute()
        return {"report_type": "attendance", "event": event.data[0] if event.data else {}, "data": data.data}
    elif report_type == "shifts":
        data = supabase.table("volunteer_shifts").select("*").eq("event_id", event_id).execute()
        return {"report_type": "shifts", "event": event.data[0] if event.data else {}, "data": data.data}
    elif report_type == "tasks":
        data = supabase.table("supervisor_tasks").select("*").eq("event_id", event_id).execute()
        return {"report_type": "tasks", "event": event.data[0] if event.data else {}, "data": data.data}
    else:
        # Summary: return analytics
        analytics = await get_event_analytics(event_id, current_user)
        return {"report_type": "summary", "event": event.data[0] if event.data else {}, "data": analytics}


# ═══════════════════════════════════════════════════════════════
# 13. LOST & FOUND
# ═══════════════════════════════════════════════════════════════

VALID_LF_STATUSES = {"draft", "submitted", "in_review", "matched", "resolved"}
VALID_LF_CATEGORIES = {"electronics", "wallet", "id_card", "bag", "clothing", "keys", "other"}

def _normalize_lf_status(raw_status: Optional[str]) -> str:
    if not raw_status:
        return "submitted"
    s = raw_status.lower().strip()
    if s in ("open", "new", "pending"):
        return "submitted"
    if s in ("returned", "closed", "expired"):
        return "resolved"
    if s in VALID_LF_STATUSES:
        return s
    return "submitted"

def _normalize_lf_category(raw_cat: Optional[str]) -> str:
    if not raw_cat:
        return "other"
    c = raw_cat.lower().strip()
    return c if c in VALID_LF_CATEGORIES else "other"

class LostFoundCreate(BaseModel):
    event_id: str
    report_type: str = "lost"  # 'lost' | 'found'
    category: str = "other"
    title: str
    description: Optional[str] = ""
    zone_id: Optional[str] = None
    venue_zone_name: Optional[str] = None
    specific_location: Optional[str] = None
    image_url: Optional[str] = None
    status: Optional[str] = "submitted"
    pickup_instructions: Optional[str] = None

class LostFoundUpdate(BaseModel):
    report_type: Optional[str] = None
    category: Optional[str] = None
    title: Optional[str] = None
    description: Optional[str] = None
    zone_id: Optional[str] = None
    venue_zone_name: Optional[str] = None
    specific_location: Optional[str] = None
    image_url: Optional[str] = None
    status: Optional[str] = None
    pickup_instructions: Optional[str] = None

@router.get("/lost-found/{event_id}")
async def list_lost_found(event_id: str, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    verify_event_ownership(supabase, event_id, current_user["user_id"])
    result = supabase.table("lost_found_reports").select("*, event_zones(name)").eq("event_id", event_id).order("created_at", desc=True).execute()
    return {"items": result.data or []}

@router.post("/lost-found")
async def create_lost_found(data: LostFoundCreate, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    verify_event_ownership(supabase, data.event_id, current_user["user_id"])

    report_type = data.report_type.lower() if data.report_type in ("lost", "found") else "lost"
    category = _normalize_lf_category(data.category)
    status = _normalize_lf_status(data.status)

    payload = {
        "event_id": data.event_id,
        "reporter_user_id": current_user["user_id"],
        "reporter_device_id": "organizer-dashboard",
        "report_type": report_type,
        "category": category,
        "title": data.title.strip(),
        "description": data.description.strip() if data.description else "",
        "status": status,
        "specific_location": data.specific_location.strip() if data.specific_location else None,
        "zone_id": data.zone_id if data.zone_id else None,
        "image_url": data.image_url if data.image_url else None,
        "pickup_instructions": data.pickup_instructions.strip() if data.pickup_instructions else None,
    }

    result = supabase.table("lost_found_reports").insert(payload).execute()
    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to create Lost & Found report")
    return {"item": result.data[0]}

@router.put("/lost-found/{item_id}")
async def update_lost_found(item_id: str, data: LostFoundUpdate, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    existing = supabase.table("lost_found_reports").select("id, event_id").eq("id", item_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Lost & Found report not found")
    verify_event_ownership(supabase, existing.data[0]["event_id"], current_user["user_id"])

    payload = {
        "updated_at": datetime.now(timezone.utc).isoformat()
    }
    if data.report_type is not None:
        payload["report_type"] = data.report_type.lower() if data.report_type in ("lost", "found") else "lost"
    if data.category is not None:
        payload["category"] = _normalize_lf_category(data.category)
    if data.title is not None:
        payload["title"] = data.title.strip()
    if data.description is not None:
        payload["description"] = data.description.strip()
    if data.specific_location is not None:
        payload["specific_location"] = data.specific_location.strip() or None
    if data.zone_id is not None:
        payload["zone_id"] = data.zone_id or None
    if data.image_url is not None:
        payload["image_url"] = data.image_url or None
    if data.status is not None:
        payload["status"] = _normalize_lf_status(data.status)
    if data.pickup_instructions is not None:
        payload["pickup_instructions"] = data.pickup_instructions.strip() or None

    result = supabase.table("lost_found_reports").update(payload).eq("id", item_id).execute()
    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to update Lost & Found report")
    return {"item": result.data[0]}

@router.delete("/lost-found/{item_id}")
async def delete_lost_found(item_id: str, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    existing = supabase.table("lost_found_reports").select("id, event_id").eq("id", item_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Lost & Found report not found")
    verify_event_ownership(supabase, existing.data[0]["event_id"], current_user["user_id"])

    supabase.table("lost_found_reports").delete().eq("id", item_id).execute()
    return {"success": True, "id": item_id}


# ═══════════════════════════════════════════════════════════════
# 14. INCIDENT — ATOMIC DISPATCH + AUDIT LOGS
# ═══════════════════════════════════════════════════════════════

class IncidentAssignRequest(BaseModel):
    volunteer_id: Optional[str] = None
    assigned_to: Optional[str] = None
    notes: Optional[str] = None


@router.post("/incidents/{incident_id}/assign")
async def assign_incident(incident_id: str, data: IncidentAssignRequest, current_user: dict = Depends(require_organizer)):
    """Atomic volunteer dispatch and assignment."""
    supabase = get_supabase()
    existing = supabase.table("operational_incidents").select("id, event_id, status").eq("id", incident_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Incident not found")
    verify_event_ownership(supabase, existing.data[0]["event_id"], current_user["user_id"])

    target_assignee_id = data.assigned_to or data.volunteer_id
    if not target_assignee_id:
        raise HTTPException(status_code=400, detail="assigned_to or volunteer_id is required")

    # Fetch assignee profile
    prof_res = supabase.table("profiles").select("full_name").eq("id", target_assignee_id).execute()
    assignee_name = prof_res.data[0]["full_name"] if prof_res.data else "Assigned Staff"

    now_iso = datetime.now(timezone.utc).isoformat()
    update_data = {
        "assigned_to_id": target_assignee_id,
        "assigned_at": now_iso,
        "status": "assigned",
        "updated_at": now_iso,
    }
    if data.notes:
        update_data["staff_notes"] = data.notes

    res = supabase.table("operational_incidents").update(update_data).eq("id", incident_id).execute()

    # Log in audit trail
    try:
        supabase.table("operational_incident_logs").insert({
            "incident_id": incident_id,
            "event_id": existing.data[0]["event_id"],
            "actor_id": current_user["user_id"],
            "actor_name": current_user.get("full_name") or "Organizer",
            "action": "assigned",
            "previous_status": existing.data[0].get("status"),
            "new_status": "assigned",
            "notes": f"Assigned to {assignee_name}" + (f": {data.notes}" if data.notes else "")
        }).execute()
    except Exception:
        pass

    return {"message": "Incident assigned successfully", "data": res.data}


@router.get("/incident-logs/{incident_id}")
async def get_incident_logs(incident_id: str, current_user: dict = Depends(require_organizer)):
    """Get audit trail for an incident."""
    supabase = get_supabase()
    existing = supabase.table("operational_incidents").select("id, event_id").eq("id", incident_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Incident not found")
    verify_event_ownership(supabase, existing.data[0]["event_id"], current_user["user_id"])

    logs_res = (
        supabase.table("operational_incident_logs")
        .select("*")
        .eq("incident_id", incident_id)
        .order("created_at")
        .execute()
    )
    logs_data = []
    for log in (logs_res.data or []):
        log["actor"] = {"id": log.get("actor_id"), "full_name": log.get("actor_name") or "Staff"}
        logs_data.append(log)
    return {"logs": logs_data}


# ═══════════════════════════════════════════════════════════════
# 15. SHIFTS CRUD
# ═══════════════════════════════════════════════════════════════

class ShiftCreate(BaseModel):
    event_id: str
    volunteer_id: str
    zone_id: Optional[str] = None
    zone_name: Optional[str] = None
    team_id: Optional[str] = None
    shift_name: str = "Operational Shift"
    scheduled_start: str
    scheduled_end: str
    notes: Optional[str] = None


class ShiftUpdate(BaseModel):
    zone_id: Optional[str] = None
    zone_name: Optional[str] = None
    status: Optional[str] = None
    scheduled_start: Optional[str] = None
    scheduled_end: Optional[str] = None
    notes: Optional[str] = None


@router.post("/shifts")
async def create_shift(data: ShiftCreate, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    verify_event_ownership(supabase, data.event_id, current_user["user_id"])

    # Ensure volunteer_assignments row exists to satisfy assignment_id FK constraint
    assign = (
        supabase.table("volunteer_assignments")
        .select("id")
        .eq("event_id", data.event_id)
        .eq("volunteer_id", data.volunteer_id)
        .execute()
    )
    if not assign.data:
        as_res = supabase.table("volunteer_assignments").insert({
            "event_id": data.event_id,
            "volunteer_id": data.volunteer_id,
            "status": "active",
            "role": "crowd_monitor",
            "zone_id": getattr(data, "zone_id", None)
        }).execute()
        assignment_id = as_res.data[0]["id"]
    else:
        assignment_id = assign.data[0]["id"]

    new_shift = {
        "event_id": data.event_id,
        "volunteer_id": data.volunteer_id,
        "assignment_id": assignment_id,
        "shift_name": data.shift_name,
        "scheduled_start": data.scheduled_start,
        "scheduled_end": data.scheduled_end,
        "status": "scheduled",
    }
    for field in ["zone_id", "team_id", "notes"]:
        v = getattr(data, field, None)
        if v:
            new_shift[field] = v
    if not new_shift.get("zone_id") and getattr(data, "zone_name", None):
        z_res = supabase.table("event_zones").select("id").eq("event_id", data.event_id).ilike("name", data.zone_name.strip()).execute()
        if z_res.data:
            new_shift["zone_id"] = z_res.data[0]["id"]

    if new_shift.get("zone_id"):
        supabase.table("volunteer_assignments").update({
            "zone_id": new_shift["zone_id"]
        }).eq("id", assignment_id).execute()

    result = supabase.table("volunteer_shifts").insert(new_shift).execute()
    return {"message": "Shift created", "data": result.data}


@router.put("/shifts/{shift_id}")
async def update_shift(shift_id: str, data: ShiftUpdate, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    existing = supabase.table("volunteer_shifts").select("id, event_id").eq("id", shift_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Shift not found")
    verify_event_ownership(supabase, existing.data[0]["event_id"], current_user["user_id"])
    updates = {k: v for k, v in data.model_dump(exclude_none=True).items()}
    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update")
    updates["updated_at"] = datetime.now(timezone.utc).isoformat()
    result = supabase.table("volunteer_shifts").update(updates).eq("id", shift_id).execute()
    return {"message": "Shift updated", "data": result.data}


@router.delete("/shifts/{shift_id}")
async def delete_shift(shift_id: str, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    existing = supabase.table("volunteer_shifts").select("id, event_id").eq("id", shift_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Shift not found")
    verify_event_ownership(supabase, existing.data[0]["event_id"], current_user["user_id"])
    supabase.table("volunteer_shifts").delete().eq("id", shift_id).execute()
    return {"message": "Shift deleted"}


# ═══════════════════════════════════════════════════════════════
# 16. TEAMS CRUD
# ═══════════════════════════════════════════════════════════════

class TeamCreate(BaseModel):
    event_id: str
    name: str
    description: Optional[str] = None
    zone_id: Optional[str] = None
    zone_name: Optional[str] = None
    lead_id: Optional[str] = None


class TeamUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    zone_id: Optional[str] = None
    zone_name: Optional[str] = None
    lead_id: Optional[str] = None


@router.post("/teams")
async def create_team(data: TeamCreate, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    verify_event_ownership(supabase, data.event_id, current_user["user_id"])
    new_team = {"event_id": data.event_id, "name": data.name}
    for field in ["description", "zone_id", "lead_id"]:
        v = getattr(data, field, None)
        if v:
            new_team[field] = v
    if not new_team.get("zone_id") and getattr(data, "zone_name", None):
        z_res = supabase.table("event_zones").select("id").eq("event_id", data.event_id).ilike("name", data.zone_name.strip()).execute()
        if z_res.data:
            new_team["zone_id"] = z_res.data[0]["id"]
    result = supabase.table("event_teams").insert(new_team).execute()
    return {"message": "Team created", "data": result.data}


@router.put("/teams/{team_id}")
async def update_team(team_id: str, data: TeamUpdate, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    existing = supabase.table("event_teams").select("id, event_id").eq("id", team_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Team not found")
    verify_event_ownership(supabase, existing.data[0]["event_id"], current_user["user_id"])
    updates = {k: v for k, v in data.model_dump(exclude_none=True).items()}
    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update")
    updates["updated_at"] = datetime.now(timezone.utc).isoformat()
    result = supabase.table("event_teams").update(updates).eq("id", team_id).execute()
    return {"message": "Team updated", "data": result.data}


@router.delete("/teams/{team_id}")
async def delete_team(team_id: str, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    existing = supabase.table("event_teams").select("id, event_id").eq("id", team_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Team not found")
    verify_event_ownership(supabase, existing.data[0]["event_id"], current_user["user_id"])
    supabase.table("event_teams").delete().eq("id", team_id).execute()
    return {"message": "Team deleted"}


# ═══════════════════════════════════════════════════════════════
# 17. ASSISTANCE — PROPER QUERY + ESCALATION
# ═══════════════════════════════════════════════════════════════

@router.get("/assistance/{event_id}")
async def list_assistance_requests(event_id: str, current_user: dict = Depends(require_organizer)):
    """List attendee assistance requests (not operational_incidents)."""
    supabase = get_supabase()
    verify_event_ownership(supabase, event_id, current_user["user_id"])
    # Query operational_incidents with category='attendee_assistance'
    result = (
        supabase.table("operational_incidents")
        .select("*")
        .eq("event_id", event_id)
        .eq("category", "attendee_assistance")
        .order("created_at", desc=True)
        .execute()
    )
    return {"assistance_requests": result.data}


@router.post("/assistance/{incident_id}/escalate")
async def escalate_assistance(incident_id: str, data: dict, current_user: dict = Depends(require_organizer)):
    """Escalate an attendee assistance request to a formal operational incident."""
    supabase = get_supabase()
    existing = supabase.table("operational_incidents").select("*").eq("id", incident_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Assistance request not found")
    inc = existing.data[0]
    verify_event_ownership(supabase, inc["event_id"], current_user["user_id"])

    # Promote category and priority
    updates = {
        "category": data.get("escalated_category", "safety"),
        "priority": data.get("priority", "important"),
        "status": "open",
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }
    if data.get("notes"):
        updates["staff_notes"] = data["notes"]

    result = supabase.table("operational_incidents").update(updates).eq("id", incident_id).execute()

    # Log the escalation
    try:
        supabase.table("operational_incident_logs").insert({
            "incident_id": incident_id,
            "actor_id": current_user["user_id"],
            "action": "escalated",
            "notes": f"Escalated from assistance to {updates['category']}",
        }).execute()
    except Exception:
        pass

    return {"message": "Assistance request escalated", "data": result.data}


# ═══════════════════════════════════════════════════════════════
# 18. COVERAGE APPROVAL
# ═══════════════════════════════════════════════════════════════

@router.put("/coverage/{request_id}/approve")
async def approve_coverage(request_id: str, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    existing = supabase.table("coverage_requests").select("id, event_id").eq("id", request_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Coverage request not found")
    verify_event_ownership(supabase, existing.data[0]["event_id"], current_user["user_id"])
    result = supabase.table("coverage_requests").update({
        "status": "approved",
        "approved_by": current_user["user_id"],
        "approved_at": datetime.now(timezone.utc).isoformat(),
    }).eq("id", request_id).execute()
    return {"message": "Coverage request approved", "data": result.data}


# ═══════════════════════════════════════════════════════════════
# 19. SHIFT HANDOFF LOGS
# ═══════════════════════════════════════════════════════════════

@router.get("/handoffs/{event_id}")
async def list_handoffs(event_id: str, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    verify_event_ownership(supabase, event_id, current_user["user_id"])
    try:
        result = (
            supabase.table("shift_handoff_logs")
            .select("*, from_volunteer:profiles!from_volunteer_id(id, full_name), to_volunteer:profiles!to_volunteer_id(id, full_name)")
            .eq("event_id", event_id)
            .order("created_at", desc=True)
            .execute()
        )
        return {"handoffs": result.data}
    except Exception as e:
        # Table may not exist yet
        return {"handoffs": [], "error": str(e)}


# ═══════════════════════════════════════════════════════════════
# 20. COMMS RECEIPTS (ACK TRACKING)
# ═══════════════════════════════════════════════════════════════

@router.get("/comms/{msg_id}/receipts")
async def get_message_receipts(msg_id: str, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    msg = supabase.table("operational_messages").select("id, event_id").eq("id", msg_id).execute()
    if not msg.data:
        raise HTTPException(status_code=404, detail="Message not found")
    verify_event_ownership(supabase, msg.data[0]["event_id"], current_user["user_id"])
    try:
        receipts = (
            supabase.table("operational_message_receipts")
            .select("*, recipient:profiles(id, full_name)")
            .eq("message_id", msg_id)
            .order("acknowledged_at")
            .execute()
        )
        return {"receipts": receipts.data}
    except Exception as e:
        return {"receipts": [], "error": str(e)}


# ═══════════════════════════════════════════════════════════════
# 21. ACTIVITIES & AI QUEST AGENT
# ═══════════════════════════════════════════════════════════════

class ActivityCreate(BaseModel):
    event_id: str
    title: str
    description: Optional[str] = None
    activity_type: Optional[str] = "scavenger"
    points_reward: Optional[int] = 10
    points_value: Optional[int] = None
    points: Optional[int] = None
    max_completions: Optional[int] = None
    zone_id: Optional[str] = None
    checkpoint_code: Optional[str] = None
    is_active: bool = True


class ActivityUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    activity_type: Optional[str] = None
    points_reward: Optional[int] = None
    points_value: Optional[int] = None
    points: Optional[int] = None
    max_completions: Optional[int] = None
    zone_id: Optional[str] = None
    checkpoint_code: Optional[str] = None
    is_active: Optional[bool] = None


class QuestGenerateRequest(BaseModel):
    event_id: str
    brand_name: str
    company_name: Optional[str] = None
    has_stall: bool = False
    zone_id: Optional[str] = None
    zone_name: Optional[str] = None
    booth_number: Optional[str] = None
    website_url: Optional[str] = None
    category: Optional[str] = None
    description: Optional[str] = None
    points_tier: Optional[int] = 100


class QuestSaveRequest(BaseModel):
    event_id: str
    title: str
    description: Optional[str] = ""
    activity_type: Optional[str] = "scavenger"
    points_reward: Optional[int] = 100
    zone_id: Optional[str] = None
    is_active: Optional[bool] = True


@router.post("/ai/generate-quest")
async def ai_generate_quest(data: QuestGenerateRequest, current_user: dict = Depends(require_organizer)):
    """AI Agent endpoint that builds gamified quests for a brand (stall visit vs website exploration) using Gemini."""
    supabase = get_supabase()
    verify_event_ownership(supabase, data.event_id, current_user["user_id"])

    req_dict = data.model_dump()
    if data.zone_id and not data.zone_name:
        z_res = supabase.table("event_zones").select("name").eq("id", data.zone_id).execute()
        if z_res.data:
            req_dict["zone_name"] = z_res.data[0]["name"]

    ev_res = supabase.table("events").select("name").eq("id", data.event_id).execute()
    if ev_res.data:
        req_dict["event_name"] = ev_res.data[0]["name"]

    quest = await generate_brand_quest(req_dict)
    return {"quest": quest}


@router.post("/ai/save-quest")
async def ai_save_quest(data: QuestSaveRequest, current_user: dict = Depends(require_organizer)):
    """Saves an AI-generated quest directly into the event activities table."""
    supabase = get_supabase()
    verify_event_ownership(supabase, data.event_id, current_user["user_id"])

    valid_types = {'workshop', 'contest', 'scavenger', 'networking', 'keynote', 'game'}
    act_type = (data.activity_type or 'scavenger').lower()
    if act_type not in valid_types:
        act_type = 'scavenger' if ('stall' in act_type or 'booth' in act_type) else 'game'

    new_act = {
        "event_id": data.event_id,
        "title": data.title,
        "description": data.description or "",
        "activity_type": act_type,
        "points_reward": int(data.points_reward or 100),
        "is_active": data.is_active if data.is_active is not None else True,
    }
    if data.zone_id:
        new_act["zone_id"] = data.zone_id

    result = supabase.table("activities").insert(new_act).execute()
    return {"message": "Gamified quest saved successfully", "data": result.data}


@router.get("/activities/{event_id}")
async def list_activities(event_id: str, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    verify_event_ownership(supabase, event_id, current_user["user_id"])
    result = supabase.table("activities").select("*, event_zones(id, name)").eq("event_id", event_id).order("created_at").execute()
    data = []
    for item in (result.data or []):
        item["points"] = item.get("points_reward", 10)
        z = item.get("event_zones")
        if z and isinstance(z, dict):
            item["zone_name"] = z.get("name")
        data.append(item)
    return {"activities": data}


@router.post("/activities")
async def create_activity(data: ActivityCreate, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    verify_event_ownership(supabase, data.event_id, current_user["user_id"])

    valid_types = {'workshop', 'contest', 'scavenger', 'networking', 'keynote', 'game'}
    act_type = (data.activity_type or 'scavenger').lower()
    if act_type not in valid_types:
        act_type = 'scavenger' if ('stall' in act_type or 'booth' in act_type) else 'game'

    pts = data.points_reward if data.points_reward is not None else (data.points_value or data.points or 50)

    new_act = {
        "event_id": data.event_id,
        "title": data.title,
        "description": data.description or "",
        "activity_type": act_type,
        "points_reward": int(pts),
        "is_active": data.is_active,
    }
    if data.zone_id:
        new_act["zone_id"] = data.zone_id

    result = supabase.table("activities").insert(new_act).execute()
    return {"message": "Activity created", "data": result.data}


@router.put("/activities/{activity_id}")
async def update_activity(activity_id: str, data: ActivityUpdate, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    existing = supabase.table("activities").select("id, event_id").eq("id", activity_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Activity not found")
    verify_event_ownership(supabase, existing.data[0]["event_id"], current_user["user_id"])
    updates = {k: v for k, v in data.model_dump(exclude_none=True).items()}
    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update")
    result = supabase.table("activities").update(updates).eq("id", activity_id).execute()
    return {"message": "Activity updated", "data": result.data}


@router.delete("/activities/{activity_id}")
async def delete_activity(activity_id: str, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    existing = supabase.table("activities").select("id, event_id").eq("id", activity_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Activity not found")
    verify_event_ownership(supabase, existing.data[0]["event_id"], current_user["user_id"])
    supabase.table("activities").delete().eq("id", activity_id).execute()
    return {"message": "Activity deleted"}


# ═══════════════════════════════════════════════════════════════
# 22. CSV STREAMING EXPORT
# ═══════════════════════════════════════════════════════════════

@router.get("/export/{event_id}/csv")
async def export_csv(event_id: str, report_type: str = Query("attendance"), current_user: dict = Depends(require_organizer)):
    """Stream a CSV download of attendance or incident data."""
    supabase = get_supabase()
    verify_event_ownership(supabase, event_id, current_user["user_id"])

    if report_type == "incidents":
        rows = supabase.table("v_operational_incidents").select(
            "id, title, category, priority, status, venue_zone_name, created_at, resolved_at, resolution_notes"
        ).eq("event_id", event_id).order("created_at").execute().data
        fieldnames = ["id", "title", "category", "priority", "status", "venue_zone_name", "created_at", "resolved_at", "resolution_notes"]
        filename = f"incidents_{event_id[:8]}.csv"
    else:
        # Default: attendance
        rows = supabase.table("tickets").select(
            "id, user_id, ticket_code, status, purchased_at, checked_in_at, claimed_at"
        ).eq("event_id", event_id).order("purchased_at").execute().data
        fieldnames = ["id", "user_id", "ticket_code", "status", "purchased_at", "checked_in_at", "claimed_at"]
        filename = f"attendance_{event_id[:8]}.csv"

    def generate():
        buf = io.StringIO()
        writer = csv.DictWriter(buf, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        yield buf.getvalue()
        buf.truncate(0)
        buf.seek(0)
        for row in rows:
            writer.writerow(row)
            yield buf.getvalue()
            buf.truncate(0)
            buf.seek(0)

    return StreamingResponse(
        generate(),
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


# ═══════════════════════════════════════════════════════════════
# 23. CROWD CALIBRATION
# ═══════════════════════════════════════════════════════════════

class CrowdCalibrationRequest(BaseModel):
    zone_id: str
    manual_count: int
    notes: Optional[str] = None


@router.post("/crowd/calibrate")
async def calibrate_crowd(data: CrowdCalibrationRequest, event_id: str = Query(...), current_user: dict = Depends(require_organizer)):
    """Submit manual turnstile headcount calibration for a zone."""
    supabase = get_supabase()
    verify_event_ownership(supabase, event_id, current_user["user_id"])

    # Insert a calibration snapshot
    result = supabase.table("crowd_zone_snapshots").insert({
        "event_id": event_id,
        "zone_id": data.zone_id,
        "estimated_count": data.manual_count,
        "source": "manual_calibration",
        "notes": data.notes or "Manual headcount calibration",
        "snapshot_at": datetime.now(timezone.utc).isoformat(),
    }).execute()
    return {"message": "Calibration recorded", "data": result.data}


# ═══════════════════════════════════════════════════════════════
# 28. EMERGENCY ACTION PLAN (EAP)
# ═══════════════════════════════════════════════════════════════

@router.post("/eap/{event_id}/publish")
async def publish_eap(event_id: str, current_user: dict = Depends(require_organizer)):
    """Publish Emergency Action Plan (EAP) to event operational staff."""
    supabase = get_supabase()
    verify_event_ownership(supabase, event_id, current_user["user_id"])
    try:
        supabase.table("event_activity_logs").insert({
            "event_id": event_id,
            "action_type": "eap_publish",
            "description": "Emergency Action Plan published to operational staff",
            "actor_id": current_user["user_id"],
        }).execute()
    except Exception:
        pass
    return {"message": "Emergency Action Plan published to active event staff", "event_id": event_id}

