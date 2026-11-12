from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel, Field
import re
import uuid
from typing import Optional, List, Dict, Any
from config import get_supabase
from middleware.auth import require_organizer, get_current_user

router = APIRouter(prefix="/api/venues", tags=["Venues"])


class VenueLevelInput(BaseModel):
    id: Optional[str] = None
    level_index: int = 0
    name: str = "Ground Floor"
    short_code: str = "G"
    level_type: str = "indoor_floor"  # indoor_floor, outdoor_ground, mezzanine, parking, rooftop
    display_order: Optional[int] = 0
    aspect_ratio: Optional[float] = 1.25
    map_asset_url: Optional[str] = None


class VenueCreate(BaseModel):
    name: str
    address: Optional[str] = ""
    timezone: Optional[str] = "UTC"
    venue_type: Optional[str] = "multi_floor"
    default_capacity: Optional[int] = 0
    floors: Optional[List[VenueLevelInput]] = None
    metadata: Optional[Dict[str, Any]] = None


class VenueUpdate(BaseModel):
    name: Optional[str] = None
    address: Optional[str] = None
    timezone: Optional[str] = None
    venue_type: Optional[str] = None
    default_capacity: Optional[int] = None
    floors: Optional[List[VenueLevelInput]] = None
    metadata: Optional[Dict[str, Any]] = None


def generate_unique_slug(supabase, name: str, exclude_id: Optional[str] = None) -> str:
    """Generate a clean URL-friendly unique slug for a venue."""
    base_slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    if not base_slug:
        base_slug = f"venue-{uuid.uuid4().hex[:6]}"

    slug = base_slug
    counter = 1
    while True:
        query = supabase.table("venues").select("id").eq("slug", slug)
        if exclude_id:
            query = query.neq("id", exclude_id)
        existing = query.execute()
        if not existing.data:
            return slug
        slug = f"{base_slug}-{counter}"
        counter += 1


@router.get("")
async def list_venues():
    """List all registered venues along with their configured floor levels."""
    supabase = get_supabase()
    res = supabase.table("venues").select("*").order("name").execute()
    raw_venues = res.data or []

    if not raw_venues:
        return {"venues": []}

    venue_ids = [v["id"] for v in raw_venues]

    # Fetch all levels for these venues in one efficient query
    levels_res = (
        supabase.table("venue_levels")
        .select("id, venue_id, level_index, name, short_code, level_type, display_order, map_asset_url")
        .in_("venue_id", venue_ids)
        .order("display_order")
        .order("level_index")
        .execute()
    )
    levels_by_venue: Dict[str, List[Dict[str, Any]]] = {}
    for lvl in (levels_res.data or []):
        v_id = lvl["venue_id"]
        levels_by_venue.setdefault(v_id, []).append(lvl)

    enriched_venues = []
    for v in raw_venues:
        v_dict = dict(v)
        v_levels = levels_by_venue.get(v["id"], [])
        meta = v.get("metadata") or {}
        v_dict["default_capacity"] = meta.get("default_capacity", 0)
        v_dict["levels"] = v_levels
        v_dict["floor_count"] = len(v_levels)
        enriched_venues.append(v_dict)

    return {"venues": enriched_venues}


@router.get("/{venue_id}")
async def get_venue(venue_id: str):
    """Get single venue details along with its floor levels."""
    supabase = get_supabase()
    res = supabase.table("venues").select("*").eq("id", venue_id).execute()
    if not res.data:
        raise HTTPException(status_code=404, detail="Venue not found")

    v = res.data[0]
    levels_res = (
        supabase.table("venue_levels")
        .select("*")
        .eq("venue_id", venue_id)
        .order("display_order")
        .order("level_index")
        .execute()
    )
    v_dict = dict(v)
    v_dict["levels"] = levels_res.data or []
    v_dict["floor_count"] = len(v_dict["levels"])
    meta = v.get("metadata") or {}
    v_dict["default_capacity"] = meta.get("default_capacity", 0)
    return {"venue": v_dict}


@router.post("")
async def create_venue(
    data: VenueCreate,
    current_user: dict = Depends(require_organizer),
):
    """
    Create a new venue with customizable floor levels.
    Starts with a Base Floor (Level 0), plus any additional floors requested.
    """
    supabase = get_supabase()
    name = data.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Venue name is required")

    slug = generate_unique_slug(supabase, name)

    meta = data.metadata or {}
    if data.default_capacity is not None:
        meta["default_capacity"] = int(data.default_capacity)

    venue_payload = {
        "name": name,
        "slug": slug,
        "venue_type": data.venue_type or "multi_floor",
        "address": (data.address or "").strip(),
        "timezone": data.timezone or "UTC",
        "metadata": meta,
    }

    venue_res = supabase.table("venues").insert(venue_payload).execute()
    if not venue_res.data:
        raise HTTPException(status_code=500, detail="Failed to create venue record")

    new_venue = venue_res.data[0]
    venue_id = new_venue["id"]

    # Process floors / levels
    floor_inputs = data.floors or []
    # If no floors provided, default to a Base Floor (Level 0)
    if not floor_inputs:
        floor_inputs = [
            VenueLevelInput(
                level_index=0,
                name="Ground Floor",
                short_code="G",
                level_type="indoor_floor",
                display_order=0,
            )
        ]

    level_records = []
    for idx, f in enumerate(floor_inputs):
        f_name = f.name.strip() if f.name else (f"Level {idx}" if idx > 0 else "Ground Floor")
        f_code = f.short_code.strip() if f.short_code else (f"L{idx}" if idx > 0 else "G")
        level_records.append({
            "venue_id": venue_id,
            "level_index": f.level_index if f.level_index is not None else idx,
            "name": f_name,
            "short_code": f_code[:10],
            "level_type": f.level_type or "indoor_floor",
            "display_order": f.display_order if f.display_order is not None else idx,
            "aspect_ratio": f.aspect_ratio or 1.25,
            "map_asset_url": f.map_asset_url,
        })

    created_levels = []
    if level_records:
        lvl_res = supabase.table("venue_levels").insert(level_records).execute()
        created_levels = lvl_res.data or []

    result = dict(new_venue)
    result["levels"] = created_levels
    result["floor_count"] = len(created_levels)
    result["default_capacity"] = meta.get("default_capacity", 0)

    return {"message": "Venue created successfully", "venue": result}


@router.put("/{venue_id}")
async def update_venue(
    venue_id: str,
    data: VenueUpdate,
    current_user: dict = Depends(require_organizer),
):
    """Update a venue's details and synchronise its floor levels."""
    supabase = get_supabase()

    existing = supabase.table("venues").select("*").eq("id", venue_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Venue not found")

    old_venue = existing.data[0]
    updates: Dict[str, Any] = {}

    if data.name is not None:
        new_name = data.name.strip()
        if not new_name:
            raise HTTPException(status_code=400, detail="Venue name cannot be empty")
        updates["name"] = new_name
        if new_name.lower() != old_venue["name"].lower():
            updates["slug"] = generate_unique_slug(supabase, new_name, exclude_id=venue_id)

    if data.address is not None:
        updates["address"] = data.address.strip()
    if data.timezone is not None:
        updates["timezone"] = data.timezone
    if data.venue_type is not None:
        updates["venue_type"] = data.venue_type

    meta = old_venue.get("metadata") or {}
    if data.metadata is not None:
        meta.update(data.metadata)
    if data.default_capacity is not None:
        meta["default_capacity"] = int(data.default_capacity)
    updates["metadata"] = meta

    if updates:
        supabase.table("venues").update(updates).eq("id", venue_id).execute()

    # Synchronise floors if provided
    if data.floors is not None:
        # Get existing levels
        existing_lvls_res = supabase.table("venue_levels").select("*").eq("venue_id", venue_id).execute()
        existing_lvls = {l["id"]: l for l in (existing_lvls_res.data or [])}
        incoming_ids = set()

        for idx, f in enumerate(data.floors):
            f_name = f.name.strip() if f.name else (f"Level {idx}" if idx > 0 else "Ground Floor")
            f_code = f.short_code.strip() if f.short_code else (f"L{idx}" if idx > 0 else "G")
            lvl_index = f.level_index if f.level_index is not None else idx

            payload = {
                "name": f_name,
                "short_code": f_code[:10],
                "level_type": f.level_type or "indoor_floor",
                "display_order": f.display_order if f.display_order is not None else idx,
                "level_index": lvl_index,
            }
            if f.map_asset_url is not None:
                payload["map_asset_url"] = f.map_asset_url

            if f.id and f.id in existing_lvls:
                incoming_ids.add(f.id)
                supabase.table("venue_levels").update(payload).eq("id", f.id).execute()
            else:
                payload["venue_id"] = venue_id
                inserted = supabase.table("venue_levels").insert(payload).execute()
                if inserted.data:
                    incoming_ids.add(inserted.data[0]["id"])

        # Delete any levels that were removed, provided they have no critical dependencies
        for old_id in existing_lvls.keys():
            if old_id not in incoming_ids:
                try:
                    supabase.table("venue_levels").delete().eq("id", old_id).execute()
                except Exception as e:
                    print(f"[WARN] Could not delete venue level {old_id}: {e}")

    # Fetch final updated venue
    final_v = supabase.table("venues").select("*").eq("id", venue_id).execute().data[0]
    final_lvls = (
        supabase.table("venue_levels")
        .select("*")
        .eq("venue_id", venue_id)
        .order("display_order")
        .order("level_index")
        .execute()
        .data or []
    )
    final_dict = dict(final_v)
    final_dict["levels"] = final_lvls
    final_dict["floor_count"] = len(final_lvls)
    final_dict["default_capacity"] = meta.get("default_capacity", 0)

    return {"message": "Venue updated successfully", "venue": final_dict}


@router.delete("/{venue_id}")
async def delete_venue(
    venue_id: str,
    current_user: dict = Depends(require_organizer),
):
    """Delete a venue and its associated levels."""
    supabase = get_supabase()

    existing = supabase.table("venues").select("id, name").eq("id", venue_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Venue not found")

    # Set venue_id to null on any linked events before deletion
    try:
        supabase.table("events").update({"venue_id": None}).eq("venue_id", venue_id).execute()
    except Exception as e:
        print(f"[WARN] Error clearing event venue_ids: {e}")

    # Delete venue_levels
    supabase.table("venue_levels").delete().eq("venue_id", venue_id).execute()

    # Delete venue
    supabase.table("venues").delete().eq("id", venue_id).execute()

    return {"message": f"Venue '{existing.data[0]['name']}' deleted successfully"}

