# DrainRank backend

Supabase is the shared backend for the citizen app, municipal dashboard, and
field app. The migrations reuse the existing `profiles`, `citizen_reports`,
`dashboard_state`, `credit_awards`, and `leave_requests` schema, and add only
the field task/evidence tables and protected RPCs. Migrations live in
[`supabase/migrations`](./supabase/migrations/); the `create-crew-account`
Edge Function lives in
[`supabase/functions/create-crew-account`](./supabase/functions/create-crew-account).

## Fresh-project limitation

The checked-in migrations are incremental changes for an existing DrainRank
Supabase schema; they are **not** a complete bootstrap for an empty Supabase
project. They rely on pre-existing tables, role/helper functions, storage
buckets, and Supabase-managed `auth` and `storage` schemas. Keep the complete
timestamped migration history and apply it in order to a compatible project;
deleting earlier migrations can break existing installations and does not
produce a self-contained schema.

To recreate the full application database on a new Supabase project, first
capture and review the complete current schema (including table definitions,
constraints, functions, RLS policies, triggers, grants, and storage setup),
then create a tested baseline migration before relying on this migration
chain. Do not treat these migrations alone as sufficient for a fresh project.

## Before applying migrations

The project already has citizen/staff roles, data tables, storage buckets and
role helper functions. The checked-in citizen report access migration adds
owner-scoped report and photo permissions without changing table structure or
replacing existing policies. The shared-app migration adds own-row/admin
policies for the existing credit and leave tables. Review the migrations
against the live schema before applying them.

After confirming compatibility, apply each complete migration in timestamp
order in Supabase SQL Editor. Apply
`202610250002_allow_early_field_work_evidence.sql` to allow assigned crew
members to submit evidence before the scheduled date. If the field app still
shows “Future tasks cannot be updated yet,” this migration has not taken effect
in the Supabase project used by the app; apply it there and retry.
`202610250003_award_field_credits_on_evidence_acceptance.sql` grants 10 credits
to the assigned crew member when an administrator accepts that member's
evidence; the award is written with the review and streams to the field app.
Apply `202610250007_dual_task_credit_awards.sql` when the existing
`credit_awards.task_id` foreign key points only to the legacy `public.tasks`
table. It allows credit awards to reference either legacy tasks or
`field_tasks`, while removing awards if their task is deleted from both.
If an existing citizen Auth account has no matching `profiles` row, apply
`202610270001_repair_missing_citizen_profiles.sql` to restore its citizen
profile so report submissions can satisfy the `reporter_id` foreign key.
Apply `202610250005_reset_direct_cleaning_reports.sql` to include direct
cleaning reports and their credit rows in the operational reset. For a full
test-data reset that also deletes non-admin Auth accounts and crew rosters
while preserving accounts whose profile role is `admin`, apply
`202610250006_admin_only_operational_reset.sql` and deploy the updated web
dashboard. That reset clears operational records and app photos and resets
dashboard settings to defaults, while preserving Supabase project
configuration and migration history.
The prior
`202610250001_owner_authorized_report_withdrawal.sql` migration lets
authenticated owners withdraw their own eligible reports without relying on a
profile-role lookup. The earlier
`202610240004_citizen_upload_and_field_evidence_review.sql` migration lets
authenticated users submit reports only for their own profile, removes the
brittle citizen-role check from owner-folder photo uploads, and connects field
cleaning evidence to the dashboard review queue. If you instead use the CLI,
reconcile migration history first; do not apply the same migration through
both paths.

The municipal dashboard's Crew Management page reads active field-app worker
profiles through the admin-only
`202610250004_list_active_crew_profiles.sql` RPC. Apply this migration after
creating crew accounts if they are not visible in the dashboard roster.

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
