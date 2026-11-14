---
status: accepted
---
# Proxy Attendance Delegation via Reciprocal Friend Handshake

When an attendee's device battery is discharging, their physical event attendance can be carried by an accompanying friend (`Host Attendee`). The discharging attendee (`Proxy Attendee`) dispatches an in-app `Proxy Request` to a friend, who must explicitly accept before proxy attendance activates. The host's presence then represents a `Carried Weight` of 2 (or more if carrying additional proxies) for venue zone occupancy and crowd safety calculations.

## Considered Options
- **BLE Payload Advertising of Carried Weight**: Rejected because BLE legacy 31-byte packet budget is already near saturation (service UUID, flags, 6-byte rotating ephemeral ID) and cloud-only telemetry is authoritative for zone density and organizer dashboard analytics.
- **Unverified / Unsolicited Companion Counters**: Rejected because allowing attendees to unilaterally increment headcount without a reciprocal ticketed friend's consent enables venue capacity spoofing and distortion.
- **Automatic Sight Revocation**: Rejected in favor of explicit manual revocation. The proxy or host attendee can terminate the delegation session at any time directly from the app, preventing flapping connections when a phone is briefly charged or power-cycled.

## Consequences
- A new table `proxy_attendance_sessions` tracks the active delegations, linking `host_user_id`, `proxy_user_id`, `event_id`, and session status (`pending`, `active`, `revoked`, `expired`).
- Telemetry pipelines factor in `carried_weight` when evaluating zone occupancy thresholds and overcrowding alerts.
- Proxy attendees maintain verified event check-in records while their phone is off, but do not accrue gamified quest completion points while delegated.
