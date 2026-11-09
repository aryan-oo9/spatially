---
status: accepted
---
# Only registered users hold tickets; the attendee app requires sign-in at launch

Earlier migrations let anonymous devices hold tickets, keyed by a device UUID (`tickets.attendee_id`), with a claim RPC and anon RLS policies. We now require sign-in at app launch, so `tickets.user_id` becomes `NOT NULL` referencing `profiles(id)`. `attendee_id`, the guest-claim RPC and the guest RLS policies are removed. This removes a second identity path to secure and keep consistent, and it lets RLS and PostgREST joins rely on `profiles` alone.

## Considered Options
- Keep a guest device ID on tickets, with `user_id` nullable until claimed. Rejected because it needs a parallel identity path across RLS, RPCs and the passport and connect features, for guest use we no longer want.
- Anonymous browsing with sign-in only at registration. Rejected in favour of a simpler launch gate.

## Consequences
- Public read access to events, zones and live counts stays (separate decision), but the app itself gates on sign-in.
- Existing guest tickets and engagements are quarantined and deleted in the migration.
- Reintroducing guests later means rebuilding the claim flow and its RLS.

