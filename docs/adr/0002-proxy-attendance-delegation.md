---
status: accepted
---
# Proxy Attendance Delegation via Reciprocal Friend Handshake

When an attendee's device battery is discharging, their physical event attendance can be carried by an accompanying friend (`Host Attendee`). The discharging attendee (`Proxy Attendee`) dispatches an in-app `Proxy Request` to an established connection who is also checked in to the same event. Once the friend explicitly accepts, the host's presence represents a `Carried Weight` of 2 (or up to 3 if carrying two proxies) for venue zone occupancy and crowd safety calculations.

## Considered Options
- **BLE Payload Advertising of Carried Weight**: Rejected because BLE legacy 31-byte packet budget is saturated (service UUID, flags, 6-byte rotating ephemeral ID) and cloud-only telemetry is authoritative for zone density and organizer dashboard analytics.
- **Unverified / Unsolicited Companion Counters**: Rejected because allowing attendees to unilaterally increment headcount without a reciprocal ticketed friend's consent enables venue capacity spoofing and distortion.
- **Automatic Sight Revocation**: Rejected in favor of explicit manual bilateral revocation. Either the proxy or the host attendee can terminate the delegation session at any time directly from the app, preventing flapping connections when a phone is briefly charged or power-cycled.
- **Open Attendee Directory vs Accepted Connections**: Restricted to mutually accepted connections (`attendee_connections.status = 'accepted'`) who hold a ticket for the same event and are checked in.
- **Synchronous vs Asynchronous Handshake**: Implemented as an asynchronous pending request stored in Supabase, allowing the host to accept even after the discharging phone powers off.
- **Gate Check-In Inheritance**: Initial physical check-in at the gate is mandatory before proxy delegation is allowed, preserving venue security.
- **Capacity Limits**: Host can carry at most 2 proxy attendees (`Carried Weight` capped at 3).
- **Gamified Quests**: Proxy attendees do not accrue gamified quest completion points while delegated; only physical venue presence and zone occupancy are maintained.

## Consequences
- A new table `proxy_attendance_sessions` tracks active delegations, linking `host_user_id`, `proxy_user_id`, `event_id`, and session status (`pending`, `active`, `revoked`, `declined`, `expired`).
- Battery telemetry in the Attendee app proactively alerts attendees when battery level is $\le 15\%$, offering a direct one-tap shortcut to delegate attendance.
- Host receives high-priority actionable notification (in-app pop-up and system notification bar) with Accept/Decline actions.
- Telemetry pipelines and crowd prediction algorithms factor in `carried_weight` when evaluating zone occupancy thresholds and overcrowding alerts.
- Organizer Dashboard and Live Crowd Heatmap display transparent attendance breakdowns (e.g., `142 Total (135 Active Devices + 7 Carried Proxies)`).
- All active proxy sessions automatically transition to `expired` when an event concludes.
