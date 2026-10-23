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
