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

The profile tab shows the member's municipal ID card and includes leave
requests, account support, local debug previews, and sign-out. Debug previews
use the same demo PIN as the citizen app and never modify live assignments,
credits, location, or evidence. Task date ranges remain available inside the
Tasks tab.

## Local-only testing

Build the isolated local test app without Supabase credentials:

```powershell
flutter pub get
flutter test
flutter run --dart-define=LOCAL_DEBUG_MODE=true
```

Enter the shared demo PIN `12345678`. The sample task, direct cleaning report,
cleaning-queue review, activity, and credit award all exist only in app memory;
no Supabase, GPS, camera, or storage calls are made by this test mode. Use
`flutter build apk --debug --dart-define=LOCAL_DEBUG_MODE=true` and
`flutter install` to install this test variant on a connected Android device.
The PIN is embedded in the app and is not a production security boundary.

## Run and build

Pass the same Supabase project URL and **publishable** key used by the web and
citizen apps:

```powershell
flutter pub get
flutter run `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```

For an Android debug build:

```powershell
flutter build apk --debug `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=your-publishable-key
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
