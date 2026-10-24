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

Apply the migrations in `backend/supabase/migrations` before running the app.
The policies restrict each citizen to their own reports and photos; dashboard
administrators can review all reports.

Pass the project's URL and publishable key as Dart defines when running or
building the app. Do not commit credentials or paste them into source files:

```powershell
flutter run `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```

For a debug APK:

```powershell
flutter build apk --debug `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=your-publishable-key
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

Nearby hospital/school verification for high-urgency reports additionally
requires a Geoapify API key passed as
`--dart-define=GEOAPIFY_API_KEY=...`. Without it, standard-priority reports
remain available, but automatic high-urgency verification is unavailable.

Reports and photos are submitted to Supabase. The app keeps a local report
cache so previously loaded records remain visible if a refresh fails; any
refresh failure is shown in the tracking screen.

The profile menu's **Debug Tool** is protected by the temporary demo PIN
`12345678`. Its sample reports, status changes, and location preview are
in-memory/local preview data only. It never reads or deletes Supabase reports
or photos, and preview coordinates never affect the GPS captured for a real
report. The PIN is embedded in the app and is not a production security
boundary.

To run a fully isolated app workflow without Supabase, build the local test
variant:

```powershell
flutter pub get
flutter test
flutter run --dart-define=LOCAL_DEBUG_MODE=true
```

This opens a PIN-protected sample reporting/tracking app. Reports and simulated
statuses are kept in memory and cleared when the app closes. No account,
network, GPS, camera, or storage access is used by this mode. For an APK,
replace `flutter run` with
`flutter build apk --debug --dart-define=LOCAL_DEBUG_MODE=true`, then install
with `flutter install`.

Citizens may withdraw their own reports while they are in Complaint Received
or Under Verification and have no field work assigned. Withdrawal retains the
report record with a `withdrawn` status for municipal audit; it does not delete
the report.

Apply `backend/supabase/migrations/202610240001_citizen_debug_and_withdrawal.sql`
after the earlier migrations to enable owner-checked report withdrawal and
owner-only photo deletion. Local debug testing does not require this or any
other migration.
