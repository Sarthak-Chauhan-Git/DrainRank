# Swachh Pravah Citizen App

Flutter citizen app for submitting drain reports and tracking their workflow.
The Android launcher label is **Pravah**; the source
logo is kept at `assets/logo.png`.

## Configure Supabase email authentication and report storage

The app uses Supabase email/password authentication. Enable the Email provider
in Supabase Authentication. Email confirmation may be enabled or disabled
according to the project's authentication settings. Authenticated citizens
upload report photos to the private `citizen-photos` bucket and insert report
records in `public.citizen_reports`.

After a report photo is captured, the on-device detector identifies objects
and overlays their labels, confidence scores, and boxes on the preview. It
warns when no bottle is identified. Android builds require Android 8.0 (API 26)
or newer for the detector runtime.

Apply the migrations in `backend/supabase/migrations` before running the app,
including `202610240003_citizen_report_submission_access.sql` and the later
owner-folder upload policy in
`202610240004_citizen_upload_and_field_evidence_review.sql`. The policies
restrict each citizen to their own reports and photos; dashboard
administrators can review all reports. Migration
`202610250001_owner_authorized_report_withdrawal.sql` allows an authenticated
report owner to withdraw an eligible report without relying on a profile-role
lookup. If report submission fails because the authenticated user is missing
from `profiles`, apply
`202610270001_repair_missing_citizen_profiles.sql` to restore profiles for
existing citizen Auth accounts.

Pass the project's URL and publishable key as Dart defines when running or
building the app. The local, git-ignored `.env.local.json` provides the same
Geoapify key used by the field app. Geoapify keys are embedded in mobile builds,
so restrict the key by API and quota in the Geoapify dashboard:

```powershell
flutter run `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=your-publishable-key `
  --dart-define-from-file=.env.local.json
```

For a debug APK:

```powershell
flutter build apk --debug `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=your-publishable-key `
  --dart-define-from-file=.env.local.json
```

If the Supabase values are missing, the app displays a setup message instead of
starting with an invalid client.

## Build and test

This app requires Flutter 3.47 or newer (Dart `^3.13.5`), matching the
project's package lockfile. Check with `flutter --version` before resolving
packages.

```powershell
flutter pub get
flutter analyze
flutter test
```

Nearby hospital, school, university, college, police-station, and fire-station
verification for high-urgency reports uses the Geoapify Places API. After
capturing a report photo, the report form displays the 500 m search zone and
any matching nearby facilities below the urgency assessment. Lookup errors
are shown there with a retry option. Without the key, standard-priority
reports remain available, but automatic high-urgency verification is
unavailable.

Reports and photos are submitted to Supabase. The app keeps a local report
cache so previously loaded records remain visible if a refresh fails; any
refresh failure is shown in the tracking screen.

The profile menu's **Debug Tool** is protected by the temporary demo PIN
`12345678`. It can set a fixed report location, show local-only simulated
workflow statuses, and delete the signed-in account's unassigned test reports
and photos. Assigned reports are not deleted. The PIN is embedded in the app
and is not a production security boundary; replace/remove it before a public
release.

Citizens may withdraw their own reports while they are in Complaint Received
or Under Verification and have no field work assigned. Withdrawal retains the
report record with a `withdrawn` status for municipal audit; it does not delete
the report.

The tracking screen listens for changes to the signed-in citizen's reports and
refreshes their statuses automatically. Pull-to-refresh remains available.

Apply `backend/supabase/migrations/202610240001_citizen_debug_and_withdrawal.sql`
after the earlier migrations to enable owner-checked report withdrawal,
debug-only deletion RPCs, and owner-only photo deletion.
