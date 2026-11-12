from fastapi import APIRouter, HTTPException, Depends
from models import EventCreate, EventUpdate
from config import get_supabase
from middleware.auth import get_current_user, require_organizer
from datetime import datetime, timezone
import re

router = APIRouter(prefix="/api/events", tags=["Events"])


def synthesize_event_compat(ev: dict) -> dict:
    """Ensure backwards compatibility for client apps expecting dropped v1 columns."""
    if not ev:
        return ev
    res = dict(ev)
    start_time = res.get("event_start_time")
    end_time = res.get("event_end_time")
    if start_time:
        if not res.get("event_date"):
            res["event_date"] = start_time
        if not res.get("start_time"):
            res["start_time"] = start_time[11:16] if len(start_time) >= 16 else None
    if end_time:
        if not res.get("end_time"):
            res["end_time"] = end_time[11:16] if len(end_time) >= 16 else None
    
    # Resolve venue details from joined relation
    venues_rel = res.get("venues")
    if isinstance(venues_rel, dict):
        res["venue"] = venues_rel.get("name", "")
        res["location_address"] = venues_rel.get("address", "")
        if "timezone" not in res or not res["timezone"] or res["timezone"] == "UTC":
            res["timezone"] = venues_rel.get("timezone", res.get("timezone", "UTC"))
    elif "venue" not in res:
        res["venue"] = ""
        res["location_address"] = ""

    # Parse ticket price
    desc = res.get("description") or ""
    price_match = re.search(r"\[TICKET_PRICE:(\d+)\]", desc)
    if price_match:
        res["ticket_price"] = int(price_match.group(1))
        res["description"] = re.sub(r"\s*\[TICKET_PRICE:\d+\]", "", desc).strip()
    elif "ticket_price" in res and res["ticket_price"] is not None:
        try:
            res["ticket_price"] = int(res["ticket_price"])
        except (ValueError, TypeError):
            res["ticket_price"] = 0
    else:
        res["ticket_price"] = 0

    return res


@router.get("/public")
async def list_public_events():
    supabase = get_supabase()
    result = (
        supabase.table("events")
        .select("*, venues(*)")
        .in_("status", ["upcoming", "live"])
        .order("event_start_time", desc=False)
        .execute()
    )
    events = [synthesize_event_compat(ev) for ev in (result.data or [])]
    return {"events": events}


@router.get("/all")
async def list_all_events(current_user: dict = Depends(get_current_user)):
    supabase = get_supabase()
    result = (
        supabase.table("events")
        .select("*, venues(*)")
        .order("event_start_time", desc=False)
        .execute()
    )
    events = [synthesize_event_compat(ev) for ev in (result.data or [])]
    return {"events": events}


@router.get("/organizer/mine")
async def list_organizer_events(current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()
    result = (
        supabase.table("events")
        .select("*, venues(*)")
        .eq("organizer_id", current_user["user_id"])
        .order("event_start_time", desc=False)
        .execute()
    )
    events = [synthesize_event_compat(ev) for ev in (result.data or [])]
    return {"events": events}


@router.get("/user/registered")
async def list_user_registered_events(current_user: dict = Depends(get_current_user)):
    supabase = get_supabase()

    registrations = (
        supabase.table("tickets")
        .select("event_id")
        .eq("user_id", current_user["user_id"])
        .in_("status", ["valid", "checked_in"])
        .execute()
    )

    if not registrations.data:
        return {"events": []}

    event_ids = list(set([r["event_id"] for r in registrations.data]))
    events = (
        supabase.table("events")
        .select("*, venues(*)")
        .in_("id", event_ids)
        .order("event_start_time", desc=False)
        .execute()
    )

    res_events = [synthesize_event_compat(ev) for ev in (events.data or [])]
    return {"events": res_events}


@router.get("/volunteer/assigned")
async def list_volunteer_assigned_events(
    current_user: dict = Depends(get_current_user),
):
    supabase = get_supabase()

    if current_user["user_type"] != "volunteer":
        raise HTTPException(status_code=403, detail="Volunteer access required")

    assignments = (
        supabase.table("volunteer_assignments")
        .select("event_id")
        .eq("volunteer_id", current_user["user_id"])
        .execute()
    )

    if not assignments.data:
        return {"events": [], "assignments": []}

    event_ids = list(set(a["event_id"] for a in assignments.data))
    events = (
        supabase.table("events")
        .select("*, venues(*)")
        .in_("id", event_ids)
        .order("event_start_time", desc=False)
        .execute()
    )

    res_events = [synthesize_event_compat(ev) for ev in (events.data or [])]
    return {"events": res_events, "assignments": assignments.data}


@router.get("/{event_id}")
async def get_event(event_id: str, current_user: dict = Depends(get_current_user)):
    supabase = get_supabase()
    result = supabase.table("events").select("*, venues(*)").eq("id", event_id).execute()

    if not result.data:
        raise HTTPException(status_code=404, detail="Event not found")

    event = synthesize_event_compat(result.data[0])

    # Include zones list from event_zones table
    zones_res = supabase.table("event_zones").select("name").eq("event_id", event_id).order("created_at").execute()
    event["zones"] = [z["name"] for z in (zones_res.data or [])]

    ticket_count = (
        supabase.table("tickets")
        .select("id", count="exact")
        .eq("event_id", event_id)
        .execute()
    )

    checkin_count = (
        supabase.table("tickets")
        .select("id", count="exact")
        .eq("event_id", event_id)
        .eq("status", "checked_in")
        .execute()
    )

    volunteer_count = (
        supabase.table("volunteer_assignments")
        .select("id", count="exact")
        .eq("event_id", event_id)
        .execute()
    )

    event["ticket_count"] = ticket_count.count or 0
    event["checkin_count"] = checkin_count.count or 0
    event["volunteer_count"] = volunteer_count.count or 0

    return {"event": event}


@router.post("/")
async def create_event(data: EventCreate, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()

    start_dt = data.event_start_time
    end_dt = data.event_end_time
    if not start_dt and data.event_date:
        t = data.start_time or "00:00:00"
        start_dt = f"{data.event_date[:10]}T{t}Z"
    if not end_dt and data.event_date:
        t = data.end_time or "23:59:59"
        end_dt = f"{data.event_date[:10]}T{t}Z"

    existing = (
        supabase.table("events")
        .select("id, event_start_time, event_end_time")
        .eq("organizer_id", current_user["user_id"])
        .execute()
    )

    if start_dt and end_dt:
        for ev in (existing.data or []):
            ev_start = ev.get("event_start_time")
            ev_end = ev.get("event_end_time")
            if ev_start and ev_end:
                if not (end_dt <= ev_start or start_dt >= ev_end):
                    raise HTTPException(
                        status_code=409,
                        detail=f"You already have an event scheduled that overlaps with this time slot",
                    )

    ticket_price = getattr(data, "ticket_price", 0) or 0
    desc = data.description or ""
    if ticket_price > 0 and "[TICKET_PRICE:" not in desc:
        desc = f"{desc}\n\n[TICKET_PRICE:{ticket_price}]".strip()

    new_event = {
        "name": data.name,
        "venue_id": data.venue_id,
        "status": "upcoming",
        "description": desc,
        "capacity": data.capacity or 0,
        "organizer_id": current_user["user_id"],
        "timezone": data.timezone or "UTC",
    }
    if start_dt:
        new_event["event_start_time"] = start_dt
    if end_dt:
        new_event["event_end_time"] = end_dt

    result = supabase.table("events").insert(new_event).execute()
    created_event = result.data[0]

    # Automatically create initial event_zones if zones are provided
    if data.zones:
        base_level_id = None
        base_floor_level = 1
        if created_event.get("venue_id"):
            try:
                lvl_res = (
                    supabase.table("venue_levels")
                    .select("id, level_index")
                    .eq("venue_id", created_event["venue_id"])
                    .order("level_index")
                    .execute()
                )
                if lvl_res.data:
                    base_level_id = lvl_res.data[0]["id"]
                    base_floor_level = lvl_res.data[0].get("level_index", 0) + 1
            except Exception:
                pass

        zone_records = []
        for idx, z in enumerate(data.zones):
            if isinstance(z, dict):
                z_name = (z.get("name") or z.get("zone") or f"Zone {idx+1}").strip()
                z_level_id = z.get("level_id") or base_level_id
                z_floor_level = z.get("floor_level") if z.get("floor_level") is not None else base_floor_level
            else:
                z_name = str(z).strip()
                z_level_id = base_level_id
                z_floor_level = base_floor_level

            if not z_name:
                continue

            zone_records.append({
                "event_id": created_event["id"],
                "name": z_name,
                "code": z_name.upper().replace(" ", "_")[:20],
                "floor_level": z_floor_level,
                "level_id": z_level_id,
                "is_crowd_monitored": True,
            })
        if zone_records:
            try:
                supabase.table("event_zones").insert(zone_records).execute()
            except Exception as e:
                print(f"[WARN] Failed to insert initial event_zones: {e}")

    synth_event = synthesize_event_compat(created_event)
    synth_event["zones"] = data.zones or []

    return {"message": "Event created successfully", "event": synth_event}


@router.put("/{event_id}")
async def update_event(
    event_id: str, data: EventUpdate, current_user: dict = Depends(require_organizer)
):
    supabase = get_supabase()

    existing = supabase.table("events").select("*").eq("id", event_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Event not found")

    event = existing.data[0]
    if event.get("organizer_id") != current_user["user_id"]:
        raise HTTPException(status_code=403, detail="You can only update your own events")

    allowed_columns = {
        "name", "description", "capacity", "status", "venue_id",
        "event_start_time", "event_end_time", "timezone", "banner_url"
    }
    updates = {}
    dumped = data.model_dump(exclude_none=True)
    for field, value in dumped.items():
        if field in allowed_columns:
            updates[field] = value

    # Compute start / end times if event_date or times were provided
    start_dt = dumped.get("event_start_time")
    end_dt = dumped.get("event_end_time")

    date_str = dumped.get("event_date")
    if not date_str and event.get("event_start_time"):
        date_str = event["event_start_time"][:10]

    if date_str:
        if not start_dt and ("start_time" in dumped or "event_date" in dumped):
            t = dumped.get("start_time") or (event.get("event_start_time")[11:19] if event.get("event_start_time") else "00:00:00")
            if len(t) == 5:
                t = f"{t}:00"
            start_dt = f"{date_str[:10]}T{t}Z"
            updates["event_start_time"] = start_dt

        if not end_dt and ("end_time" in dumped or "event_date" in dumped):
            t = dumped.get("end_time") or (event.get("event_end_time")[11:19] if event.get("event_end_time") else "23:59:59")
            if len(t) == 5:
                t = f"{t}:00"
            end_dt = f"{date_str[:10]}T{t}Z"
            updates["event_end_time"] = end_dt

    if not updates and "ticket_price" not in dumped:
        raise HTTPException(status_code=400, detail="No fields to update")

    if "ticket_price" in dumped and dumped["ticket_price"] is not None:
        tp = int(dumped["ticket_price"])
        cur_desc = updates.get("description", event.get("description") or "")
        clean_desc = re.sub(r"\s*\[TICKET_PRICE:\d+\]", "", cur_desc).strip()
        if tp > 0:
            clean_desc = f"{clean_desc}\n\n[TICKET_PRICE:{tp}]".strip()
        updates["description"] = clean_desc

    supabase.table("events").update(updates).eq("id", event_id).execute()

    # Re-fetch event with venues joined, matching get_event
    updated = (
        supabase.table("events")
        .select("*, venues(*)")
        .eq("id", event_id)
        .execute()
    )
    if not updated.data:
        raise HTTPException(status_code=500, detail="Failed to retrieve updated event")

    synth_event = synthesize_event_compat(updated.data[0])

    zones_res = (
        supabase.table("event_zones")
        .select("name")
        .eq("event_id", event_id)
        .order("created_at")
        .execute()
    )
    synth_event["zones"] = [z["name"] for z in (zones_res.data or [])]

    ticket_count = (
        supabase.table("tickets")
        .select("id", count="exact")
        .eq("event_id", event_id)
        .execute()
    )
    checkin_count = (
        supabase.table("tickets")
        .select("id", count="exact")
        .eq("event_id", event_id)
        .eq("status", "checked_in")
        .execute()
    )
    volunteer_count = (
        supabase.table("volunteer_assignments")
        .select("id", count="exact")
        .eq("event_id", event_id)
        .execute()
    )

    synth_event["ticket_count"] = ticket_count.count or 0
    synth_event["checkin_count"] = checkin_count.count or 0
    synth_event["volunteer_count"] = volunteer_count.count or 0

    return {"message": "Event updated successfully", "event": synth_event}


@router.put("/{event_id}/status")
async def update_event_status(
    event_id: str, data: dict, current_user: dict = Depends(require_organizer)
):
    supabase = get_supabase()
    existing = supabase.table("events").select("id, organizer_id").eq("id", event_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Event not found")
    if existing.data[0].get("organizer_id") != current_user["user_id"]:
        raise HTTPException(status_code=403, detail="You can only update your own events")

    new_status = data.get("status")
    valid_statuses = ["draft", "upcoming", "published", "live", "paused", "ended"]
    if not new_status or new_status not in valid_statuses:
        raise HTTPException(status_code=400, detail=f"Invalid status '{new_status}'. Allowed: {valid_statuses}")

    result = supabase.table("events").update({"status": new_status}).eq("id", event_id).execute()
    return {"message": f"Event status updated to {new_status}", "event": result.data[0]}


@router.delete("/{event_id}")
async def delete_event(event_id: str, current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()

    existing = supabase.table("events").select("*").eq("id", event_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Event not found")

    if existing.data[0].get("organizer_id") != current_user["user_id"]:
        raise HTTPException(status_code=403, detail="You can only delete your own events")

    # Clean up storage files if present
    banner_url = existing.data[0].get("banner_url")
    if banner_url:
        try:
            file_name = banner_url.split("/")[-1].split("?")[0]
            supabase.storage.from_("event-banners").remove([file_name])
        except Exception as e:
            print(f"[WARN] Failed to delete event storage file: {e}")

    # Defensive cleanup of related child entities before deleting parent event
    child_tables = [
        "volunteer_assignments",
        "coverage_requests",
        "shift_handoffs",
        "supervisor_tasks",
        "volunteer_shifts",
        "operational_incident_logs",
        "operational_incidents",
        "operational_messages",
        "event_invitations",
        "observations",
        "lost_found_reports",
        "safety_resources",
        "event_activity_logs",
        "event_zones",
        "event_teams",
        "tickets",
    ]
    for table_name in child_tables:
        try:
            supabase.table(table_name).delete().eq("event_id", event_id).execute()
        except Exception:
            pass

    # Delete the event
    supabase.table("events").delete().eq("id", event_id).execute()

    return {"message": "Event deleted successfully"}


@router.post("/{event_id}/register")
async def register_for_event(
    event_id: str, current_user: dict = Depends(get_current_user)
):
    if current_user["user_type"] != "user":
        raise HTTPException(status_code=403, detail="Only users can register for events")

    supabase = get_supabase()

    event = supabase.table("events").select("*").eq("id", event_id).execute()
    if not event.data:
        raise HTTPException(status_code=404, detail="Event not found")

    ev = event.data[0]
    if ev.get("status") == "ended":
        raise HTTPException(status_code=400, detail="Cannot register for an ended event")

    existing = (
        supabase.table("tickets")
        .select("id, status")
        .eq("user_id", current_user["user_id"])
        .eq("event_id", event_id)
        .execute()
    )
    
    if existing.data:
        active_ticket = next((t for t in existing.data if t.get("status") in ["valid", "checked_in"]), None)
        if active_ticket:
            raise HTTPException(status_code=409, detail="You are already registered for this event")
        else:
            # Re-activate cancelled ticket if space allows
            if ev.get("capacity") and ev["capacity"] > 0:
                ticket_count = (
                    supabase.table("tickets")
                    .select("id", count="exact")
                    .eq("event_id", event_id)
                    .in_("status", ["valid", "checked_in"])
                    .execute()
                )
                if (ticket_count.count or 0) >= ev["capacity"]:
                    raise HTTPException(status_code=409, detail="Event has reached maximum capacity")
            
            supabase.table("tickets").update(
                {"status": "valid"}
            ).eq("id", existing.data[0]["id"]).execute()
            
            return {"message": "Successfully registered for the event"}

    if ev.get("capacity") and ev["capacity"] > 0:
        ticket_count = (
            supabase.table("tickets")
            .select("id", count="exact")
            .eq("event_id", event_id)
            .in_("status", ["valid", "checked_in"])
            .execute()
        )
        if (ticket_count.count or 0) >= ev["capacity"]:
            raise HTTPException(status_code=409, detail="Event has reached maximum capacity")

    import uuid
    ticket_code = f"TICK-{uuid.uuid4().hex[:8].upper()}"
    supabase.table("tickets").insert(
        {
            "user_id": current_user["user_id"],
            "event_id": event_id,
            "ticket_code": ticket_code,
            "status": "valid",
        }
    ).execute()

    return {"message": "Successfully registered for the event"}


@router.delete("/{event_id}/register")
async def cancel_registration(
    event_id: str, current_user: dict = Depends(get_current_user)
):
    supabase = get_supabase()

    existing = (
        supabase.table("tickets")
        .select("id")
        .eq("user_id", current_user["user_id"])
        .eq("event_id", event_id)
        .in_("status", ["valid", "checked_in"])
        .execute()
    )

    if not existing.data:
        raise HTTPException(status_code=404, detail="Registration not found")

    supabase.table("tickets").update(
        {"status": "cancelled"}
    ).eq("id", existing.data[0]["id"]).execute()

    return {"message": "Registration cancelled successfully"}


# ═══════════════════════════════════════════════════════════════
# VENUES ENDPOINT
# ═══════════════════════════════════════════════════════════════

venues_router = APIRouter(prefix="/api/venues", tags=["Venues"])


@venues_router.get("")
async def list_venues():
    supabase = get_supabase()
    result = supabase.table("venues").select("*").order("name").execute()
    venues = []
    for v in (result.data or []):
        meta = v.get("metadata") or {}
        v_dict = dict(v)
        v_dict["default_capacity"] = meta.get("default_capacity", None)
        venues.append(v_dict)
    return {"venues": venues}

