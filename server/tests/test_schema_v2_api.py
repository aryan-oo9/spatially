import pytest
from fastapi.testclient import TestClient
from server.main import app

client = TestClient(app)

def test_api_health():
    response = client.get("/")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"

def test_public_venues_endpoint():
    response = client.get("/api/venues")
    assert response.status_code == 200
    data = response.json()
    assert "venues" in data
    assert isinstance(data["venues"], list)

def test_unauthenticated_registration_rejected():
    response = client.post("/api/events/00000000-0000-0000-0000-000000000000/register")
    assert response.status_code in (401, 403)

def test_public_events_endpoint():
    response = client.get("/api/events/public")
    assert response.status_code == 200
    data = response.json()
    assert "events" in data
    assert isinstance(data["events"], list)
    if data["events"]:
        ev = data["events"][0]
        # Verify schema v2 fields exist and synthesized compat fields exist
        assert "event_start_time" in ev
        assert "event_date" in ev
        assert "venue" in ev

def test_organizer_mine_endpoint():
    from routes.events import require_organizer
    # Override organizer auth dependency
    app.dependency_overrides[require_organizer] = lambda: {
        "user_id": "00000000-0000-0000-0000-000000000001",
        "user_type": "organizer",
        "email": "organizer@test.com",
    }
    try:
        response = client.get("/api/events/organizer/mine")
        assert response.status_code == 200
        data = response.json()
        assert "events" in data
        assert isinstance(data["events"], list)
    finally:
        app.dependency_overrides.clear()

def test_get_event_detail_endpoint():
    from routes.events import get_current_user
    app.dependency_overrides[get_current_user] = lambda: {
        "user_id": "dc0feb1a-aab8-448a-80ec-ad2eeb0ae747",
        "user_type": "organizer",
        "email": "organizer@test.com",
    }
    try:
        response = client.get("/api/events/ba3219b7-7320-4318-98df-93bd9c0ac305")
        assert response.status_code == 200
        data = response.json()
        assert "event" in data
        assert "zones" in data["event"]
        assert isinstance(data["event"]["zones"], list)
    finally:
        app.dependency_overrides.clear()

def test_venue_map_endpoints():
    from routes.events import get_current_user
    app.dependency_overrides[get_current_user] = lambda: {
        "user_id": "dc0feb1a-aab8-448a-80ec-ad2eeb0ae747",
        "user_type": "organizer",
        "email": "organizer@test.com",
    }
    event_id = "ba3219b7-7320-4318-98df-93bd9c0ac305"
    try:
        # Density
        r_density = client.get(f"/api/venue-map/{event_id}/density")
        assert r_density.status_code == 200
        assert "density" in r_density.json()

        # Layout
        r_layout = client.get(f"/api/venue-map/{event_id}/layout")
        assert r_layout.status_code == 200
        assert "layout" in r_layout.json()

        # Volunteers
        r_vols = client.get(f"/api/venue-map/{event_id}/volunteers")
        assert r_vols.status_code == 200
        assert "positions" in r_vols.json()
    finally:
        app.dependency_overrides.clear()


def test_organizer_volunteers_endpoint():
    from routes.events import get_current_user
    from middleware.auth import require_organizer
    mock_user = {
        "user_id": "dc0feb1a-aab8-448a-80ec-ad2eeb0ae747",
        "user_type": "organizer",
        "email": "organizer@test.com",
    }
    app.dependency_overrides[get_current_user] = lambda: mock_user
    app.dependency_overrides[require_organizer] = lambda: mock_user
    event_id = "ba3219b7-7320-4318-98df-93bd9c0ac305"
    try:
        r = client.get(f"/api/organizer/volunteers/{event_id}")
        assert r.status_code == 200
        data = r.json()
        assert "assignments" in data
        assert "shifts" in data
        assert isinstance(data["assignments"], list)
        assert isinstance(data["shifts"], list)
    finally:
        app.dependency_overrides.clear()


def test_invite_bulk_uuid_validation():
    from models import InviteBulkRequest
    req = InviteBulkRequest(
        event_id="ba3219b7-7320-4318-98df-93bd9c0ac305",
        volunteer_ids=["550e8400-e29b-41d4-a716-446655440000", "00000000-0000-0000-0001-000000000001"],
    )
    assert len(req.volunteer_ids) == 2
    assert req.volunteer_ids[0] == "550e8400-e29b-41d4-a716-446655440000"


def test_invite_bulk_endpoint_schema():
    from routes.events import get_current_user
    from middleware.auth import require_organizer
    mock_user = {
        "user_id": "dc0feb1a-aab8-448a-80ec-ad2eeb0ae747",
        "user_type": "organizer",
        "email": "organizer@test.com",
    }
    app.dependency_overrides[get_current_user] = lambda: mock_user
    app.dependency_overrides[require_organizer] = lambda: mock_user
    try:
        # Non-existent event returns 404 cleanly, proving request body parsed and matched schema
        r = client.post(
            "/api/volunteers/invite-bulk",
            json={
                "event_id": "00000000-0000-0000-0000-000000000000",
                "volunteer_ids": ["73015e90-8dbd-4422-88f0-d3fd48a29a8a"],
            },
        )
        assert r.status_code == 404
        assert r.json()["detail"] == "Event not found"
    finally:
        app.dependency_overrides.clear()






