# DrainRank municipal dashboard

The dashboard uses Supabase Auth for administrator sign-in and stores
operational records in the existing protected `dashboard_state` Postgres row.
Writes compare `updated_at` to avoid silently overwriting another
administrator's changes.
It does not read
or write dashboard records to browser `localStorage`; a new workspace starts
empty instead of loading sample records.

Citizen submissions are read from the shared `citizen_reports` table and
combined with dashboard-managed records for the report screens.

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
3. In Supabase Authentication, keep Email enabled. Public sign-ups must remain
   enabled while the citizen app uses email registration.
4. Copy `.env.example` to `.env.local` and fill in the project URL and
   **publishable** key from Supabase Project Settings → API. Never use the
   `service_role` key in the browser or commit `.env.local`.

## Cloudinary photo uploads

1. Create a Cloudinary account and copy its **cloud name** from the dashboard.
2. In Settings → Upload, create an **unsigned upload preset** restricted to
   images. Set a 10 MB maximum and allow only the image formats needed by the
   project, and set the preset's folder to `drainrank/evidence`. Keep the preset
   unsigned; do not put the Cloudinary API secret in the web app.
3. Add the cloud name and preset name to `apps/web/.env.local` as
   `VITE_CLOUDINARY_CLOUD_NAME` and `VITE_CLOUDINARY_UPLOAD_PRESET`.

Dashboard evidence uploads use the Cloudinary HTTPS API and store the returned
secure URL with the dashboard record. Citizen and field photos use private
Supabase Storage buckets. The web uploader can stay on Cloudinary; this does
not affect the shared Supabase backend.

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
