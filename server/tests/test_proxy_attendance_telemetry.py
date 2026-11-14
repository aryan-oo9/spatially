import pytest
from services.crowd_prediction import calculate_zone_occupancy_with_proxies

def test_single_proxy_carried_weight():
    """
    Host carrying 1 proxy attendee contributes a headcount multiplier of 2 (+1).
    """
    zone_device_counts = {"zone_main_stage": 10}
    zone_hosts = {"zone_main_stage": ["host_user_1"]}
    active_proxy_sessions = [
        {
            "id": "sess-1",
            "host_user_id": "host_user_1",
            "requester_user_id": "req_user_1",
            "status": "active"
        }
    ]

    weighted_counts, zone_carried = calculate_zone_occupancy_with_proxies(
        zone_device_counts=zone_device_counts,
        zone_hosts=zone_hosts,
        active_proxy_sessions=active_proxy_sessions,
    )

    assert zone_carried["zone_main_stage"] == 1
    assert weighted_counts["zone_main_stage"] == 11

def test_host_capacity_cap_enforced_at_max_two_proxies():
    """
    A single host can carry at most 2 active proxies (carried weight <= 3).
    Any additional proxies beyond 2 are capped.
    """
    zone_device_counts = {"zone_expo": 5}
    zone_hosts = {"zone_expo": ["host_user_alpha"]}
    active_proxy_sessions = [
        {"id": "s1", "host_user_id": "host_user_alpha", "requester_user_id": "r1", "status": "active"},
        {"id": "s2", "host_user_id": "host_user_alpha", "requester_user_id": "r2", "status": "active"},
        {"id": "s3", "host_user_id": "host_user_alpha", "requester_user_id": "r3", "status": "active"},  # Exceeds cap
    ]

    weighted_counts, zone_carried = calculate_zone_occupancy_with_proxies(
        zone_device_counts=zone_device_counts,
        zone_hosts=zone_hosts,
        active_proxy_sessions=active_proxy_sessions,
    )

    # Must be capped at 2 carried proxies
    assert zone_carried["zone_expo"] == 2
    assert weighted_counts["zone_expo"] == 7

def test_revoked_or_declined_sessions_not_counted():
    """
    Only active sessions contribute to zone occupancy. Revoked, pending, or declined sessions do not.
    """
    zone_device_counts = {"zone_food": 8}
    zone_hosts = {"zone_food": ["host_user_beta"]}
    active_proxy_sessions = [
        {"id": "s1", "host_user_id": "host_user_beta", "requester_user_id": "r1", "status": "revoked"},
        {"id": "s2", "host_user_id": "host_user_beta", "requester_user_id": "r2", "status": "pending"},
        {"id": "s3", "host_user_id": "host_user_beta", "requester_user_id": "r3", "status": "declined"},
    ]

    weighted_counts, zone_carried = calculate_zone_occupancy_with_proxies(
        zone_device_counts=zone_device_counts,
        zone_hosts=zone_hosts,
        active_proxy_sessions=active_proxy_sessions,
    )

    assert zone_carried["zone_food"] == 0
    assert weighted_counts["zone_food"] == 8

def test_multiple_zones_and_hosts():
    """
    Multiple hosts in different zones carry different numbers of proxies.
    """
    zone_device_counts = {
        "zone_a": 15,
        "zone_b": 20,
    }
    zone_hosts = {
        "zone_a": ["host_1", "host_2"],
        "zone_b": ["host_3"],
    }
    active_proxy_sessions = [
        {"id": "s1", "host_user_id": "host_1", "requester_user_id": "r1", "status": "active"},
        {"id": "s2", "host_user_id": "host_1", "requester_user_id": "r2", "status": "active"},
        {"id": "s3", "host_user_id": "host_2", "requester_user_id": "r3", "status": "active"},
        {"id": "s4", "host_user_id": "host_3", "requester_user_id": "r4", "status": "active"},
    ]

    weighted_counts, zone_carried = calculate_zone_occupancy_with_proxies(
        zone_device_counts=zone_device_counts,
        zone_hosts=zone_hosts,
        active_proxy_sessions=active_proxy_sessions,
    )

    # Zone A has host_1 (2 proxies) + host_2 (1 proxy) = 3 proxies
    assert zone_carried["zone_a"] == 3
    assert weighted_counts["zone_a"] == 18

    # Zone B has host_3 (1 proxy) = 1 proxy
    assert zone_carried["zone_b"] == 1
    assert weighted_counts["zone_b"] == 21
