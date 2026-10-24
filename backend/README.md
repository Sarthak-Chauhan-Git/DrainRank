# DrainRank backend

Supabase is the shared backend for the citizen app, municipal dashboard, and
field app. The migrations reuse the existing `profiles`, `citizen_reports`,
`dashboard_state`, `credit_awards`, and `leave_requests` schema, and add only
the field task/evidence tables and protected RPCs. Migrations live in
[`supabase/migrations`](./supabase/migrations/); the `create-crew-account`
Edge Function lives in
[`supabase/functions/create-crew-account`](./supabase/functions/create-crew-account).

## Before applying migrations

The project already has citizen/staff roles, data tables, storage buckets and
citizen-photo policies. The user has confirmed the relevant columns, constraints,
role helpers, and private bucket settings. Do not run an older migration or
replace those policies. The shared-app migration adds own-row/admin policies
for the existing credit and leave tables, without replacing their other
policies. Review both checked-in migration files; they have been adapted to
the existing schema.

After confirming compatibility, apply each complete migration in timestamp
order in Supabase SQL Editor. If you instead use the CLI, reconcile migration
history first; do not apply the same migration through both paths.

```powershell
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase functions deploy create-crew-account
```

An active admin row in `profiles` must exist before the Edge Function can
create crew profiles. Crew IDs in the dashboard must match field members'
Municipal IDs.

Clients use only the Supabase project URL and publishable key. The Edge
Function uses the server-managed service-role key from Supabase's runtime
environment; never expose that key in application code, client environment
files, or chat. See the [web setup](../apps/web/README.md),
[citizen setup](../apps/citizen-android/drainrank_citizen/README.md), and
[field setup](../apps/field-android/field_app/README.md).
