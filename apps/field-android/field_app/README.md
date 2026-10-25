# Pravah Saarthi Field App

The Android launcher and in-app header use the Pravah Saarthi name. The source
icon is kept at `assets/field_app_icon.png`.

The field app uses the shared Supabase project for authentication, crew
profiles, assigned tasks, work evidence, credits, leave requests, and private
photo storage. Firebase is not required.

## Supabase setup

The project already has `profiles`, `leave_requests`, and `credit_awards`.
The checked-in migrations reuse those tables and add the missing field task and
evidence backend. Review and apply each complete migration in timestamp order
in Supabase SQL Editor. If you instead use the CLI, reconcile migration
history first; do not apply the same migration through both paths. Then deploy
the account-provisioning function:

```powershell
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase functions deploy create-crew-account
```

The app administrator must have an active `profiles` row with role `admin`.
The crew-provisioning Edge Function checks that profile and uses the
server-side Supabase service key; never put that key in the Flutter app or a
client `.env` file.

Create a crew account from the field app's administrator screen. Crew members
continue to sign in with their Municipal ID and password. The ID is mapped to a
Supabase Auth email alias internally; no email address is needed at sign-in.
After successful creation, the admin screen displays the Municipal ID and
temporary password once, with copy buttons. Share them securely and ask the
crew member to keep the temporary password secure. If account creation fails,
confirm that `create-crew-account` is deployed to this same Supabase project
and that the signed-in administrator has an active `admin` profile.

Crew navigation is organized into **Tasks**, **Report**, **Activity**, and
**Profile**. The Report tab submits GPS-tagged cleaning observations directly
to the dashboard cleaning queue, without creating an inspection task.
Administrators award the configured ward cleaning credits after verifying a
report. Apply
`../../../backend/supabase/migrations/202610240002_direct_cleaning_reports.sql` in
Supabase SQL Editor after the earlier shared-backend migrations.
The shared in-app camera keeps both the preview and captured photo in portrait
orientation.
Assigned cleaning tasks require a result (completed, partially completed, or
unable to complete) with the work photo and description. Submissions appear in
the dashboard's Evidence Review queue; a reviewer can accept them or return
them for rework. Tasks remain in **Active tasks** until the signed-in crew
member submits evidence; a rework request puts the task back in that list.
After submission, the task appears in **Last week** for seven days from its
submission date with its review state, including **Evidence accepted**.
Submitted tasks also appear in **Activity**, where review states update live.
Evidence may be submitted before or after the scheduled task date. This
requires applying
`../../../backend/supabase/migrations/202610250002_allow_early_field_work_evidence.sql`
in Supabase SQL Editor; without it, Supabase rejects early submissions with
“Future tasks cannot be updated yet.” Pull down on the Tasks screen to refresh
assignments, evidence, and credits. Accepted evidence grants 10 credits, which
update live in the field app. Apply all backend migrations in timestamp order,
including
`../../../backend/supabase/migrations/202610240004_citizen_upload_and_field_evidence_review.sql`
and
`../../../backend/supabase/migrations/202610250003_award_field_credits_on_evidence_acceptance.sql`.

After capturing the report photo, the app searches Geoapify Places for
hospitals, schools, universities, colleges, police stations, and fire stations
within 500 m. The map shows the search radius and matching places. A nearby
result marks the report urgent, as in the citizen app. The displayed priority
score uses the same DrainRank formula and known-drain matching rules as the
citizen client; the score, urgency flag, and linked drain ID are stored with
the report for dashboard ranking. Both mobile apps use the same
`GEOAPIFY_API_KEY` from the local, git-ignored `.env.local.json` file. Restrict
the key by API and quota in Geoapify; Flutter embeds compile-time defines in the
app package.

The profile tab shows the member's municipal ID card and includes leave
requests, account support, a PIN-protected debug-mode switch, and sign-out.
Debug previews use the demo PIN `12345678`; they are preview-only and never
modify live assignments, credits, location, or evidence. Enabling debug mode
does not disconnect the Supabase-backed app. Task date ranges remain available
inside the Tasks tab.

## Run and build

Pass the same Supabase project URL and **publishable** key used by the web and
citizen apps:

```powershell
flutter pub get
flutter run `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=your-publishable-key `
  --dart-define-from-file=.env.local.json
```

For an Android debug build:

```powershell
flutter build apk --debug `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=your-publishable-key `
  --dart-define-from-file=.env.local.json
```

Work-order assignment is synchronized from the dashboard to `field_tasks`.
Match a dashboard worker's ID to the crew member's Municipal ID. Row-level
security limits crew records and task/photo access to the signed-in, assigned
member; administrator operations run through protected SQL functions and the
Edge Function.

Inspection tasks ask the assigned worker whether cleaning is required.
Submitting that result completes the inspection task and moves the report area
to the dashboard's cleaning queue when needed. Apply the latest Supabase
migration before building this version of the app.

Run `flutter analyze` and `flutter test` to validate the app.
