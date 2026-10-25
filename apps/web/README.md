# Swachh Pravah Seva municipal dashboard

The dashboard uses Supabase Auth for administrator sign-in and stores
operational records in the existing protected `dashboard_state` Postgres row.
Writes compare `updated_at` to avoid silently overwriting another
administrator's changes.
It does not read
or write dashboard records to browser `localStorage`; a new workspace starts
empty instead of loading sample records.

Citizen submissions are read from the shared `citizen_reports` table and
combined with dashboard-managed records for the report screens.
Each report also creates or joins an inspection-area queue item. The first
report fixes the area's center; later reports within 1 km are grouped there and
add five priority points each (capped at 100). Assigning an inspection crew
creates a field task. The field worker's inspection result moves the area to
the cleaning queue when cleaning is required, or to monitoring otherwise.

## Offline debug mode

Visit `/debug` (for example, `http://localhost:5173/debug` while the web app is
running) to open the standalone offline workflow preview. It bypasses the
Supabase `AuthGate` and does not require `.env.local` or any Supabase setup.
The demo PIN is `12345678`; the Administration page's local debug controls use
that same password. This PIN is public and is for testing only, not security.

Create a citizen report, move it through the inspection and cleaning queues,
then verify completed work to award 100 demo credits. The demo keeps all state
in React memory only: it does not use `localStorage` or `sessionStorage`, make
backend requests, or modify database/storage. Reloading, locking the session,
or leaving the route discards its data. Administration controls can load a
sample report or clear debug data without affecting the real dashboard.

## Supabase setup

1. The dashboard is adapted to the existing `profiles` and `dashboard_state`
   tables. Confirm the signed-in Auth user has an active `profiles` row with
   `role = 'admin'`; the signup trigger creates a citizen profile by default,
   so promote the project administrator separately.
2. Review the existing database columns and RLS policies before applying the
   additive migrations in timestamp order from
   `../../backend/supabase/migrations`. They preserve the existing
   `citizen_reports`, `profiles`, `dashboard_state`, `credit_awards`, and
   `leave_requests` tables.
   The `202610230001_citizen_report_inspection_flow.sql` migration adds the
   field inspection result and live citizen-report notifications.
   Apply `202610230002_reset_operational_data.sql` to enable the administrator
   reset control, then apply `202610230003_dashboard_evidence_storage.sql`
   to create the private dashboard evidence bucket and its admin-only policies.
3. In Supabase Authentication, keep Email enabled. Public sign-ups must remain
   enabled while the citizen app uses email registration.
4. Copy `.env.example` to `.env.local` and fill in the project URL and
   **publishable** key from Supabase Project Settings → API. Never use the
   `service_role` key in the browser or commit `.env.local`.

## Evidence review and report withdrawal

The `/evidence` page shows real field-worker submissions from
`field_work_updates`; it does not generate before/after placeholder images.
Apply `202610240004_citizen_upload_and_field_evidence_review.sql` and
`202610250003_award_field_credits_on_evidence_acceptance.sql` to the deployed
Supabase project for evidence review and credit awards. Citizen report
withdrawal also requires applying
`202610250001_owner_authorized_report_withdrawal.sql`; updating the mobile app
alone does not update the database RPC.

## Field-app workers in Crew Management

The Crew Management roster combines dashboard worker details with active
`profiles` created by the field app. Apply
`../../backend/supabase/migrations/202610250004_list_active_crew_profiles.sql`
in the Supabase SQL Editor. Use **Refresh workers** to pull in an account
created while the dashboard was already open. Newly synced workers appear as
Unassigned; add them to a crew or select them individually when assigning a
queue task.

## Reset test data

After applying the reset migration, an authenticated administrator can use
Administration → Reset all app data. The reset clears dashboard records and
logs, citizen reports, field tasks and evidence, leave requests, credit
history, and files in the `citizen-photos` and `work-photos` Supabase Storage
buckets, including `dashboard-evidence`. It preserves Supabase
admin/citizen/crew accounts and the crew roster; other dashboard settings
return to defaults. The button requires typing `RESET DATA` and verifies the
cleared state after reloading.

## Private photo storage

Citizen, field, and dashboard evidence photos use private Supabase Storage
buckets. Dashboard images are stored in `dashboard-evidence` with a 10 MB
limit and JPEG, PNG, WebP, or GIF formats. The bucket policies restrict
uploads, reads, and deletion to active administrators. The browser stores only
the object path in dashboard data and generates short-lived signed URLs for
image previews.

No image-provider credentials beyond the Supabase project URL and publishable
key are needed in the web environment.

## Run and validate

From this directory:

```powershell
npm install
npm run dev
npm run build
npm run lint
```

The local DrainRank assistant currently uses the Vite development server and
local Ollama integration; it is separate from dashboard storage and is not a
hosted AI service.
