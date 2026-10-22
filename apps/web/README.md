# DrainRank municipal dashboard

The dashboard uses Supabase Auth for staff sign-in and stores operational
records in the protected `web_dashboard_state` Postgres row. Writes use a
revision check to avoid silently overwriting another administrator's changes.
It does not read
or write dashboard records to browser `localStorage`; a new workspace starts
empty instead of loading sample records.

Citizen submissions are read from the shared `citizen_reports` table and
combined with dashboard-managed records for the report screens.

## Supabase setup

1. Ensure the shared base migration has created `citizen_reports`. Then, in
   the Supabase SQL Editor, run
   `../../backend/supabase/migrations/202610220001_web_dashboard_state.sql`.
2. In Supabase Authentication, create the staff administrator account with
   email and password. Disable public sign-ups for this staff-only dashboard.
3. In the SQL Editor, authorize that account. Replace the email below with the
   exact address used to create the account:

   ```sql
   insert into public.dashboard_admins (user_id)
   select id from auth.users where email = 'admin@example.com'
   on conflict (user_id) do nothing;
   ```

   The membership table is not writable by browser clients; an existing
   administrator or the project owner must grant/revoke dashboard access in
   the SQL Editor.
4. Copy `.env.example` to `.env.local` and fill in the project URL and
   **publishable** key from Supabase Project Settings → API. Never use the
   `service_role` key in the browser or commit `.env.local`.

## Cloudinary photo uploads

1. Create a Cloudinary account and copy its **cloud name** from the dashboard.
2. In Settings → Upload, create an **unsigned upload preset** restricted to
   images. Set a 10 MB maximum and allow only the image formats needed by the
   project, and set the preset's folder to `drainrank`. Keep the preset
   unsigned; do not put the Cloudinary API secret in the web app.
3. Add the cloud name and preset name to `apps/web/.env.local` as
   `VITE_CLOUDINARY_CLOUD_NAME` and `VITE_CLOUDINARY_UPLOAD_PRESET`.

Photo uploads use the Cloudinary HTTPS API and only the returned secure URL is
stored in Supabase. If these values are absent, uploads fail visibly; report
text and operations remain available.

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
