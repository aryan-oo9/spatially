from fastapi import APIRouter, HTTPException, Depends, Query
from config import get_supabase
from middleware.auth import get_current_user, require_organizer
from routes.events import synthesize_event_compat

router = APIRouter(prefix="/api/dashboard", tags=["Dashboard"])


@router.get("/user")
async def user_dashboard(current_user: dict = Depends(get_current_user)):
    if current_user["user_type"] != "user":
        raise HTTPException(status_code=403, detail="User access required")

    supabase = get_supabase()

    registrations = (
        supabase.table("tickets")
        .select("event_id")
        .eq("user_id", current_user["user_id"])
        .in_("status", ["valid", "checked_in"])
        .execute()
    )

    registered_ids = list(set([r["event_id"] for r in registrations.data]))

    registered_events = []
    if registered_ids:
        registered_res = (
            supabase.table("events")
            .select("*, venues(*)")
            .in_("id", registered_ids)
            .order("event_start_time", desc=False)
            .execute()
        )
        registered_events = [synthesize_event_compat(e) for e in (registered_res.data or [])]

    upcoming_events = (
        supabase.table("events")
        .select("*, venues(*)")
        .in_("status", ["upcoming", "live"])
        .order("event_start_time", desc=False)
        .limit(10)
        .execute()
    )
    upcoming_data = [synthesize_event_compat(e) for e in (upcoming_events.data or [])]

    live_count = sum(1 for e in registered_events if e.get("status") == "live")
    upcoming_count = sum(1 for e in registered_events if e.get("status") == "upcoming")

    return {
        "stats": {
            "total_registered": len(registered_ids),
            "live_events": live_count,
            "upcoming_events": upcoming_count,
        },
        "registered_events": registered_events,
        "upcoming_events": upcoming_data,
    }


@router.get("/volunteer")
async def volunteer_dashboard(current_user: dict = Depends(get_current_user)):
    if current_user["user_type"] != "volunteer":
        raise HTTPException(status_code=403, detail="Volunteer access required")

    supabase = get_supabase()

    assignments = (
        supabase.table("volunteer_assignments")
        .select("event_id")
        .eq("volunteer_id", current_user["user_id"])
        .execute()
    )

    assigned_ids = list(set(a["event_id"] for a in assignments.data))

    assigned_events = []
    if assigned_ids:
        assigned_res = (
            supabase.table("events")
            .select("*, venues(*)")
            .in_("id", assigned_ids)
            .order("event_start_time", desc=False)
            .execute()
        )
        assigned_events = [synthesize_event_compat(e) for e in (assigned_res.data or [])]

    pending_invitations = (
        supabase.table("event_invitations")
        .select("*")
        .eq("volunteer_id", current_user["user_id"])
        .eq("status", "pending")
        .execute()
    )

    live_events = [e for e in assigned_events if e.get("status") == "live"]
    upcoming_events = [e for e in assigned_events if e.get("status") == "upcoming"]

    total_observations = 0
    for eid in assigned_ids:
        obs = (
            supabase.table("observations")
            .select("id", count="exact")
            .eq("event_id", eid)
            .execute()
        )
        total_observations += obs.count or 0

    return {
        "stats": {
            "total_assignments": len(assigned_ids),
            "live_events": len(live_events),
            "upcoming_events": len(upcoming_events),
            "total_observations": total_observations,
            "pending_invitations": len(pending_invitations.data),
        },
        "assigned_events": assigned_events,
        "assignments": assignments.data,
        "pending_invitations": pending_invitations.data,
    }


@router.get("/organizer")
async def organizer_dashboard(current_user: dict = Depends(require_organizer)):
    supabase = get_supabase()

    my_events = (
        supabase.table("events")
        .select("*, venues(*)")
        .eq("organizer_id", current_user["user_id"])
        .order("event_start_time", desc=False)
        .execute()
    )
    events_data = [synthesize_event_compat(e) for e in (my_events.data or [])]
    event_ids = [e["id"] for e in events_data]

    total_tickets = 0
    total_checkins = 0
    total_volunteers = 0
    total_observations = 0

    for eid in event_ids:
        tickets = (
            supabase.table("tickets")
            .select("id", count="exact")
            .eq("event_id", eid)
            .execute()
        )
        total_tickets += tickets.count or 0

        checkins = (
            supabase.table("tickets")
            .select("id", count="exact")
            .eq("event_id", eid)
            .eq("status", "checked_in")
            .execute()
        )
        total_checkins += checkins.count or 0

        vols = (
            supabase.table("volunteer_assignments")
            .select("id", count="exact")
            .eq("event_id", eid)
            .execute()
        )
        total_volunteers += vols.count or 0

        obs = (
            supabase.table("observations")
            .select("id", count="exact")
            .eq("event_id", eid)
            .execute()
        )
        total_observations += obs.count or 0

    live_events = [e for e in events_data if e.get("status") == "live"]
    upcoming_events = [e for e in events_data if e.get("status") == "upcoming"]
    ended_events = [e for e in events_data if e.get("status") == "ended"]

    user_registrations = []
    for eid in event_ids:
        regs = (
            supabase.table("tickets")
            .select("id", count="exact")
            .eq("event_id", eid)
            .in_("status", ["valid", "checked_in"])
            .execute()
        )
        user_registrations.append({"event_id": eid, "count": regs.count or 0})

    return {
        "stats": {
            "total_events": len(events_data),
            "live_events": len(live_events),
            "upcoming_events": len(upcoming_events),
            "ended_events": len(ended_events),
            "total_tickets": total_tickets,
            "total_checkins": total_checkins,
            "total_volunteers": total_volunteers,
            "total_observations": total_observations,
        },
        "events": events_data,
        "user_registrations": user_registrations,
    }


@router.get("/crowd-data/{event_id}")
async def get_crowd_data(event_id: str, current_user: dict = Depends(get_current_user)):
    supabase = get_supabase()

    event = supabase.table("events").select("id, name").eq("id", event_id).execute()
    if not event.data:
        raise HTTPException(status_code=404, detail="Event not found")

    counts = (
        supabase.table("volunteer_counts")
        .select("*")
        .eq("event_id", event_id)
        .execute()
    )

    zones_res = supabase.table("event_zones").select("name").eq("event_id", event_id).order("created_at").execute()
    zones = [z["name"] for z in (zones_res.data or [])]

    zone_data = {}
    for zone in zones:
        zone_counts = [c for c in counts.data if c.get("zone") == zone]
        total = sum(c.get("active_count", 0) for c in zone_counts)
        zone_data[zone] = {
            "active_count": total,
            "volunteer_count": len(zone_counts),
        }

    recent_observations = (
        supabase.table("observations")
        .select("zone, scanned_at, ephemeral_id")
        .eq("event_id", event_id)
        .eq("is_spatially_device", True)
        .order("scanned_at", desc=True)
        .limit(200)
        .execute()
    )

    hourly_data = {}
    for obs in recent_observations.data:
        ts = obs.get("scanned_at", "")
        if ts:
            hour = ts[:13]
            zone = obs.get("zone", "Unknown")
            key = f"{hour}|{zone}"
            if key not in hourly_data:
                hourly_data[key] = {"hour": hour, "zone": zone, "unique_devices": set()}
            hourly_data[key]["unique_devices"].add(obs.get("ephemeral_id", ""))

    timeline = []
    for entry in hourly_data.values():
        timeline.append({
            "hour": entry["hour"],
            "zone": entry["zone"],
            "count": len(entry["unique_devices"]),
        })

    timeline.sort(key=lambda x: x["hour"])

    # Active proxy attendance breakdown (ADR 0002)
    active_proxies_count = 0
    try:
        proxies_res = (
            supabase.table("proxy_attendance_sessions")
            .select("id")
            .eq("event_id", event_id)
            .eq("status", "active")
            .execute()
        )
        active_proxies_count = len(proxies_res.data or [])
    except Exception:
        active_proxies_count = 0

    total_devices = sum(z["active_count"] for z in zone_data.values())
    total_attendance = total_devices + active_proxies_count

    return {
        "zone_data": zone_data,
        "timeline": timeline,
        "raw_counts": counts.data,
        "total_attendance": total_attendance,
        "active_devices": total_devices,
        "carried_proxies": active_proxies_count,
    }
