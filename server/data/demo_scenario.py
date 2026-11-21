"""
Demo Scenario - scripted crowd storyline for the Admin Dashboard.

Plays a named sequence of crowd beats against ONE event so every dashboard
feature lights up: venue map colours, live feed, trend charts, prediction
panel, Overcrowding Alert (incident + notification).

Story (15 min default):
  1. Doors open        Entrance fills.
  2. Keynote fills     Main Hall climbs to ~72%.
  3. Keynote ends      Food Court starts to climb -> prediction warns.
  4. Surge             Food Court goes critical -> Overcrowding Alert fires.
  5. Dispersal         Counts fall, alert is resolved.

Writes (all reversible with --reset):
  volunteer_counts      live zone headcount (one row per scanning volunteer;
                        originals are saved to a manifest and restored)
  crowd_zone_snapshots  trend/prediction history, tagged source='simulation'
  operational_incidents / event_notifications  titled "[SIM] ..."
Never touches tickets, users, or other events.

Usage (from server/):
  python data/demo_scenario.py --event-id UUID                 # live, with 30 min backfill
  python data/demo_scenario.py --event-id UUID --mode scratch  # empty dashboard, story from 0
  python data/demo_scenario.py --event-id UUID --reset         # remove all dummy data

Hotkeys while running:  [s] surge Food Court  [a] fire alert now
                        [d] disperse / calm   [r] resolve alert  [q] quit
"""

import argparse
import json
import math
import os
import random
import sys
import time
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import get_supabase  # noqa: E402

try:
    import msvcrt  # Windows only
except ImportError:  # pragma: no cover
    msvcrt = None

SIM_SOURCE = "simulation"          # allowed by crowd_zone_snapshots CHECK constraint
SIM_PREFIX = "[SIM] "
SCANNER_EMAIL_PREFIX = "sim.scanner."
MANIFEST = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".demo_scenario_manifest.json")
BACKFILL_MIN = 30
BACKFILL_END_STORY_MIN = 6.0       # backfill maps story minutes 0..6 -> live resumes at keynote end
SNAP_EVERY_SEC = 30
ACTIVE_SHIFT = ["scheduled", "active", "on_break"]
ALERT_ON, ALERT_OFF = 0.90, 0.60

# (story minute, ratio of operating capacity). Scaled by duration/15.
CURVES = {
    "entrance": [(0, .05), (3, .70), (6, .45), (8, .35), (11, .25), (15, .15)],
    "main":     [(0, .04), (3, .20), (6, .72), (7, .75), (8, .45), (11, .25), (15, .15)],
    "food":     [(0, .04), (5, .15), (6, .30), (8, .62), (9.5, .90), (11, .97), (12, .80), (13.5, .50), (15, .30)],
}
BEATS = [(0, "Doors open"), (3, "Keynote fills the Main Hall"), (6, "Keynote ends - Food Court filling"),
         (8, "Surge building"), (11, "Dispersal")]


# ------------------------------------------------------------------ helpers
def interp(points, t):
    if t <= points[0][0]:
        return points[0][1]
    for (t0, v0), (t1, v1) in zip(points, points[1:]):
        if t <= t1:
            return v0 + (v1 - v0) * (t - t0) / (t1 - t0)
    return points[-1][1]


def iso(dt):
    return dt.astimezone(timezone.utc).isoformat()


def cap_of(z):
    return z.get("operating_capacity") or z.get("capacity_limit") or 100


def assign_roles(zones: List[Dict[str, Any]]) -> Dict[str, str]:
    """zone_id -> role (entrance / main / food / ambient), derived from names then capacity."""
    def find(words):
        for z in zones:
            n = (z.get("name") or "").lower()
            if any(w in n for w in words):
                return z
        return None
    by_cap = sorted(zones, key=cap_of)
    roles: Dict[str, str] = {}
    main = find(["main", "hall", "stage", "auditorium", "arena"]) or by_cap[-1]
    roles[main["id"]] = "main"
    food = find(["food", "court", "cafe", "dining", "canteen"])
    if not food or food["id"] in roles:
        rest = [z for z in by_cap if z["id"] not in roles]
        food = rest[len(rest) // 2] if rest else None
    if food:
        roles[food["id"]] = "food"
    ent = find(["entr", "gate", "lobby", "reception"])
    if not ent or ent["id"] in roles:
        rest = [z for z in by_cap if z["id"] not in roles]
        ent = rest[0] if rest else None
    if ent:
        roles[ent["id"]] = "entrance"
    for z in zones:
        roles.setdefault(z["id"], "ambient")
    return roles


def load_manifest():
    if os.path.exists(MANIFEST):
        with open(MANIFEST, "r", encoding="utf-8") as f:
            return json.load(f)
    return None


def save_manifest(m):
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(m, f, indent=2)


def beat_name(t):
    name = BEATS[0][1]
    for start, n in BEATS:
        if t >= start:
            name = n
    return name


def snapshots_table_exists(sb) -> bool:
    try:
        sb.table("crowd_zone_snapshots").select("id").limit(1).execute()
        return True
    except Exception:
        return False


def remove_sim_scanners(sb, event_id: str, ids: List[str]):
    """Delete [SIM] scanner accounts created by this script (by manifest ids + email prefix sweep)."""
    swept = sb.table("profiles").select("id").like("email", f"{SCANNER_EMAIL_PREFIX}{event_id[:8]}.%@spatially.demo").execute().data or []
    for uid in set(ids) | {r["id"] for r in swept}:
        for tbl in ("volunteer_counts",):
            try:
                sb.table(tbl).delete().eq("volunteer_id", uid).execute()
            except Exception:
                pass
        try:
            sb.table("profiles").delete().eq("id", uid).execute()
        except Exception as e:
            print(f"    profile delete warning {uid[:8]}: {e}")
        try:
            sb.auth.admin.delete_user(uid)
        except Exception as e:
            print(f"    auth user delete warning {uid[:8]}: {e}")
    if ids or swept:
        print(f"    removed {len(set(ids) | {r['id'] for r in swept})} virtual scanner account(s)")


# ------------------------------------------------------------------ reset
def reset(sb, event_id: str):
    print(f"[*] Removing demo data for event {event_id} ...")
    m = load_manifest()
    started = None
    if m and m.get("event_id") == event_id:
        started = m.get("started_at")
        # restore / delete volunteer_counts
        for vid, orig in (m.get("original_counts") or {}).items():
            if orig:
                sb.table("volunteer_counts").upsert(orig).execute()
            else:
                sb.table("volunteer_counts").delete().eq("volunteer_id", vid).eq("event_id", event_id).execute()
        print(f"    volunteer_counts restored for {len(m.get('original_counts') or {})} scanner(s)")
        for iid in m.get("incident_ids", []):
            sb.table("operational_incidents").delete().eq("id", iid).execute()
        for nid in m.get("notification_ids", []):
            sb.table("event_notifications").delete().eq("id", nid).execute()
    else:
        print("    (no manifest for this event - sweeping by tags only; volunteer_counts left untouched)")

    if snapshots_table_exists(sb):
        sb.table("crowd_zone_snapshots").delete().eq("event_id", event_id).eq("source", SIM_SOURCE).execute()
        if started:  # 'auto' rows the prediction endpoint recorded from our fake counts
            sb.table("crowd_zone_snapshots").delete().eq("event_id", event_id).eq("source", "auto").gte("snapshot_at", started).execute()
    sb.table("operational_incidents").delete().eq("event_id", event_id).like("title", f"{SIM_PREFIX}%").execute()
    remove_sim_scanners(sb, event_id, (m or {}).get("created_users", []))
    sb.table("event_notifications").delete().eq("event_id", event_id).like("title", f"{SIM_PREFIX}%").execute()
    if m and m.get("event_id") == event_id and os.path.exists(MANIFEST):
        os.remove(MANIFEST)
    print("[OK] Clean. Real data untouched.")


# ------------------------------------------------------------------ main run
def main():
    ap = argparse.ArgumentParser(description="Spatially crowd Demo Scenario")
    ap.add_argument("--event-id", required=True)
    ap.add_argument("--mode", choices=["backfill", "scratch"], default="backfill")
    ap.add_argument("--reset", action="store_true", help="remove all dummy data and exit")
    ap.add_argument("--duration", type=float, default=15.0, help="story length in minutes")
    ap.add_argument("--tick", type=float, default=5.0, help="seconds between live updates")
    ap.add_argument("--yes", action="store_true", help="skip confirmation prompt")
    ap.add_argument("--no-interactive", action="store_true")
    ap.add_argument("--no-create-scanners", action="store_true", help="borrow spare real volunteers instead of creating [SIM] accounts")
    args = ap.parse_args()

    sb = get_supabase()
    ev = sb.table("events").select("id, name").eq("id", args.event_id).execute().data
    if not ev:
        sys.exit(f"[ERROR] Event {args.event_id} not found.")
    event_id, ev_name = ev[0]["id"], ev[0]["name"]
    host = (os.environ.get("SUPABASE_URL") or "<configured project>").replace("https://", "")

    if args.reset:
        if not args.yes and input(f"Delete ALL demo data for '{ev_name}' on {host}? [y/N] ").lower() != "y":
            return
        reset(sb, event_id)
        return

    HAS_SNAPSHOTS = snapshots_table_exists(sb)
    if not HAS_SNAPSHOTS:
        print("[WARN] Table 'crowd_zone_snapshots' does not exist in this Supabase project.\n"
              "       Live map/counts will work, but trend charts and the prediction engine will have no history.\n"
              "       Fix: run supabase/migrations/20261017_crowd_zone_snapshots.sql in the Supabase SQL editor, then re-run.\n")

    zones = sb.table("event_zones").select("*").eq("event_id", event_id).execute().data or []
    if not zones:
        sys.exit("[ERROR] Event has no zones.")
    shifts = (sb.table("volunteer_shifts").select("volunteer_id, zone_id").eq("event_id", event_id)
              .in_("status", ACTIVE_SHIFT).execute().data or [])
    scanners: Dict[str, List[str]] = {}
    for s in shifts:
        if s.get("zone_id") and s.get("volunteer_id"):
            scanners.setdefault(s["zone_id"], []).append(s["volunteer_id"])

    roles = assign_roles(zones)

    # Zones with no assigned volunteer get a "virtual scanner": a spare volunteer profile
    # (volunteer_counts needs a real user id). Originals are saved & restored on --reset.
    uncovered = [z for z in zones if z["id"] not in scanners]
    created_users: List[str] = []
    if uncovered and not args.no_create_scanners:
        for n, z in enumerate(uncovered, 1):
            email = f"{SCANNER_EMAIL_PREFIX}{event_id[:8]}.{n}@spatially.demo"
            try:
                existing = sb.table("profiles").select("id").eq("email", email).execute().data
                if existing:
                    uid = existing[0]["id"]
                else:
                    uid = sb.auth.admin.create_user({
                        "email": email, "password": "Password123!" + uuid.uuid4().hex[:6], "email_confirm": True,
                        "user_metadata": {"full_name": f"{SIM_PREFIX}Scanner {z['name']}", "role": "volunteer"},
                    }).user.id
                sb.table("profiles").upsert({"id": uid, "email": email, "role": "volunteer",
                                             "full_name": f"{SIM_PREFIX}Scanner {z['name']}"}).execute()
                scanners[z["id"]] = [uid]
                created_users.append(uid)
                print(f"[INFO] Zone '{z['name']}' has no volunteer - created virtual scanner {email}")
            except Exception as e:
                print(f"[WARN] Zone '{z['name']}': could not create scanner account ({e}) - skipped.")
    elif uncovered:
        used = {v for vs in scanners.values() for v in vs}
        profs = sb.table("profiles").select("id, full_name").eq("role", "volunteer").execute().data or []
        spare = [p for p in profs if p["id"] not in used and not (p.get("full_name") or "").startswith(SIM_PREFIX)]
        for z in uncovered:
            if not spare:
                print(f"[WARN] Zone '{z['name']}': no spare volunteer profile available - skipped.")
                continue
            p = spare.pop(0)
            scanners[z["id"]] = [p["id"]]
            print(f"[INFO] Zone '{z['name']}' has no volunteer - borrowing '{p.get('full_name') or p['id'][:8]}'.")
    live_zones = [z for z in zones if z["id"] in scanners]
    if not live_zones:
        sys.exit("[ERROR] No zone can be simulated (no assigned or spare volunteers found).")

    print(f"\nEvent : {ev_name}\nTarget: {host}\nMode  : {args.mode}, {args.duration:g}-min story, tick {args.tick:g}s")
    for z in live_zones:
        print(f"  {roles[z['id']]:<9} {z['name']:<24} cap {cap_of(z):<5} scanners {len(scanners[z['id']])}")
    if not args.yes and input("Write demo data to this event? [y/N] ").lower() != "y":
        return

    # Clean previous run, then record originals for restoration
    if load_manifest():
        prev = load_manifest()
        if prev.get("event_id") == event_id:
            reset(sb, event_id)
    if HAS_SNAPSHOTS:
        sb.table("crowd_zone_snapshots").delete().eq("event_id", event_id).eq("source", SIM_SOURCE).execute()

    all_vols = sorted({v for z in live_zones for v in scanners[z["id"]]})
    originals: Dict[str, Any] = {}
    for vid in all_vols:
        r = sb.table("volunteer_counts").select("*").eq("volunteer_id", vid).execute().data
        originals[vid] = r[0] if r else None
    now = datetime.now(timezone.utc)
    manifest = {"event_id": event_id, "started_at": iso(now), "original_counts": originals,
                "incident_ids": [], "notification_ids": [], "created_users": created_users}
    save_manifest(manifest)

    scale = 15.0 / args.duration  # curve minutes per story minute

    def ratio(zone, t, state):
        role = roles[zone["id"]]
        if role == "ambient":
            idx = sum(ord(c) for c in zone["name"]) % 7
            base = 0.28 + 0.07 * math.sin(t * 0.9 + idx)
        else:
            base = interp(CURVES[role], t * scale)
        if role == "food":
            if state["override"] == "surge":
                base = max(base, 0.97)
            elif state["override"] == "calm":
                base = min(base, 0.30)
        return max(0.0, min(1.05, base))

    # smoothed per-zone ratios so hotkeys ramp rather than jump
    smooth: Dict[str, float] = {}

    def zone_counts(t, state, ts_noise=True):
        out = {}
        for z in live_zones:
            target = ratio(z, t, state)
            cur = smooth.get(z["id"], target)
            cur += (target - cur) * 0.5
            smooth[z["id"]] = cur
            jitter = random.uniform(-0.015, 0.015) if ts_noise else 0
            out[z["id"]] = max(0, int(cap_of(z) * max(cur + jitter, 0)))
        return out

    # ---------------- backfill
    if args.mode == "backfill" and not HAS_SNAPSHOTS:
        t = BACKFILL_END_STORY_MIN * args.duration / 15.0   # no history table: just resume live
    elif args.mode == "backfill":
        print(f"[*] Backfilling {BACKFILL_MIN} min of history ...")
        rows = []
        step = SNAP_EVERY_SEC / 60.0
        n = int(BACKFILL_MIN / step)
        for i in range(n, -1, -1):
            minutes_ago = i * step
            story_t = (BACKFILL_END_STORY_MIN * args.duration / 15.0) * (1 - minutes_ago / BACKFILL_MIN)
            ts = now - timedelta(minutes=minutes_ago)
            for z in live_zones:
                c = int(cap_of(z) * max(ratio(z, story_t, {"override": None}) + random.uniform(-0.015, 0.015), 0))
                rows.append({"event_id": event_id, "zone_id": z["id"], "estimated_count": c,
                             "source": SIM_SOURCE, "notes": "demo scenario backfill", "snapshot_at": iso(ts)})
        for i in range(0, len(rows), 500):
            sb.table("crowd_zone_snapshots").insert(rows[i:i + 500]).execute()
        t = BACKFILL_END_STORY_MIN * args.duration / 15.0
    else:
        t = 0.0

    # ---------------- live loop
    state = {"override": None, "alert_id": None, "alert_fired": False, "quit": False}
    tick_n = 0
    snap_every = max(1, round(SNAP_EVERY_SEC / args.tick))
    t_wall = time.time()
    interactive = (msvcrt is not None) and not args.no_interactive and sys.stdin.isatty()
    print("[*] Live. Ctrl+C to stop (data stays; run with --reset to clean)."
          + ("  Hotkeys: s surge | a alert | d calm | r resolve | q quit" if interactive else ""))

    food = next((z for z in live_zones if roles[z["id"]] == "food"), None)

    def fire_alert(zone, count):
        cap = cap_of(zone)
        pct = round(100 * count / cap)
        n = now_dt = datetime.now(timezone.utc)
        inc = sb.table("operational_incidents").insert({
            "event_id": event_id, "category": "crowd", "priority": "urgent", "status": "assigned",
            "title": f"{SIM_PREFIX}CRITICAL: Overcrowding at {zone['name']} ({count}/{cap} - {pct}%)",
            "description": f"Attendee density reached {pct}% at {zone['name']}. Immediate diversion required.",
            "zone_id": zone["id"], "venue_zone_name": zone["name"],
            "reporter_type": "volunteer", "reporter_name": "Spatially Intelligence Engine",
        }).execute().data
        if inc:
            state["alert_id"] = inc[0]["id"]
            manifest["incident_ids"].append(inc[0]["id"])
        nt = sb.table("event_notifications").insert({
            "event_id": event_id, "title": f"{SIM_PREFIX}URGENT: Overcrowding at {zone['name']}",
            "body": f"Density reached {pct}%. Initiate diversion protocol.", "category": "urgent", "is_active": True,
        }).execute().data
        if nt:
            manifest["notification_ids"].append(nt[0]["id"])
        save_manifest(manifest)
        state["alert_fired"] = True
        print(f"\n[!] OVERCROWDING ALERT fired for {zone['name']} ({pct}%)")

    def resolve_alert():
        if state["alert_id"]:
            sb.table("operational_incidents").update({"status": "resolved"}).eq("id", state["alert_id"]).execute()
            print("\n[OK] Alert resolved")
            state["alert_id"] = None

    try:
        while t <= args.duration and not state["quit"]:
            counts = zone_counts(t, state)
            stamp = datetime.now(timezone.utc)
            for z in live_zones:
                vols = scanners[z["id"]]
                weights = [random.uniform(0.85, 1.15) for _ in vols]
                shares = [int(counts[z["id"]] * w / sum(weights)) for w in weights]
                for vid, share in zip(vols, shares):
                    sb.table("volunteer_counts").upsert({
                        "volunteer_id": vid, "event_id": event_id, "zone": z["name"],
                        "active_count": share, "updated_at": iso(stamp)}).execute()
                counts[z["id"]] = sum(shares)  # keep snapshot == what scanners report
            if HAS_SNAPSHOTS and tick_n % snap_every == 0:
                sb.table("crowd_zone_snapshots").insert([
                    {"event_id": event_id, "zone_id": z["id"], "estimated_count": counts[z["id"]],
                     "source": SIM_SOURCE, "notes": "demo scenario", "snapshot_at": iso(stamp)}
                    for z in live_zones]).execute()

            if food:
                fr = counts[food["id"]] / cap_of(food)
                if fr >= ALERT_ON and not state["alert_fired"]:
                    fire_alert(food, counts[food["id"]])
                elif state["alert_fired"] and state["alert_id"] and fr < ALERT_OFF:
                    resolve_alert()
            line = "  ".join(f"{roles[z['id']][:4]} {100*counts[z['id']]/cap_of(z):3.0f}%" for z in live_zones)
            print(f"\r[{t:5.1f}m] {beat_name(t * 15.0 / args.duration):<36} {line}   ", end="", flush=True)

            # sleep in small slices so hotkeys feel instant
            end = time.time() + args.tick
            while time.time() < end:
                if interactive and msvcrt.kbhit():
                    k = msvcrt.getwch().lower()
                    if k == "s":
                        state["override"] = "surge"
                    elif k == "d":
                        state["override"] = "calm"
                    elif k == "a" and food:
                        fire_alert(food, counts[food["id"]])
                    elif k == "r":
                        resolve_alert()
                    elif k == "q":
                        state["quit"] = True
                        break
                time.sleep(0.1)
            t += (time.time() - t_wall) / 60.0
            t_wall = time.time()
            tick_n += 1
        print("\n[OK] Scenario finished. Dashboard keeps last values; run with --reset to clean.")
    except KeyboardInterrupt:
        print("\n[*] Stopped. Run with --reset to remove demo data.")


if __name__ == "__main__":
    main()

