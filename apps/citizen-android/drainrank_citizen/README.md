# DrainRank Citizen

Flutter citizen app for submitting drain reports and tracking their workflow.

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
