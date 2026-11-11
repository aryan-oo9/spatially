import pytest
from fastapi.testclient import TestClient
from server.main import app
from routes.venues import require_organizer

client = TestClient(app)

def mock_organizer():
    return {
        "user_id": "00000000-0000-0000-0000-000000000001",
        "user_type": "organizer",
        "email": "organizer@test.com",
    }

def test_list_venues_enriched():
    response = client.get("/api/venues")
    assert response.status_code == 200
    data = response.json()
    assert "venues" in data
    assert isinstance(data["venues"], list)
    if data["venues"]:
        venue = data["venues"][0]
        assert "levels" in venue
        assert "floor_count" in venue
        assert isinstance(venue["levels"], list)

def test_create_and_delete_venue_with_custom_floors():
    app.dependency_overrides[require_organizer] = mock_organizer
    try:
        payload = {
            "name": "Pytest International Center",
            "address": "456 Test Blvd, Suite 100",
            "timezone": "UTC",
            "venue_type": "multi_floor",
            "default_capacity": 1500,
            "floors": [
                {
                    "level_index": 0,
                    "name": "Ground Base Floor",
                    "short_code": "G",
                    "level_type": "indoor_floor",
                    "display_order": 0,
                },
                {
                    "level_index": 1,
                    "name": "First Floor Showcase",
                    "short_code": "L1",
                    "level_type": "indoor_floor",
                    "display_order": 1,
                },
                {
                    "level_index": 2,
                    "name": "Second Floor Keynotes",
                    "short_code": "L2",
                    "level_type": "indoor_floor",
                    "display_order": 2,
                },
            ],
        }

        # 1. Create Venue
        create_res = client.post("/api/venues", json=payload)
        assert create_res.status_code == 200
        created = create_res.json()["venue"]
        venue_id = created["id"]
        assert created["name"] == "Pytest International Center"
        assert created["floor_count"] == 3
        assert len(created["levels"]) == 3
        assert created["levels"][0]["short_code"] == "G"
        assert created["levels"][1]["short_code"] == "L1"
        assert created["levels"][2]["short_code"] == "L2"

        # 2. Get Venue by ID
        get_res = client.get(f"/api/venues/{venue_id}")
        assert get_res.status_code == 200
        fetched = get_res.json()["venue"]
        assert fetched["id"] == venue_id
        assert fetched["floor_count"] == 3

        # 3. Update Venue
        update_payload = {
            "name": "Pytest International Center Updated",
            "default_capacity": 1800,
        }
        update_res = client.put(f"/api/venues/{venue_id}", json=update_payload)
        assert update_res.status_code == 200
        updated = update_res.json()["venue"]
        assert updated["name"] == "Pytest International Center Updated"
        assert updated["default_capacity"] == 1800

        # 4. Clean up / Delete Venue
        del_res = client.delete(f"/api/venues/{venue_id}")
        assert del_res.status_code == 200

        # Verify deletion
        get_deleted = client.get(f"/api/venues/{venue_id}")
        assert get_deleted.status_code == 404
    finally:
        app.dependency_overrides.pop(require_organizer, None)

