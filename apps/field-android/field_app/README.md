# DrainRank Field App

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

Run `flutter analyze` and `flutter test` to validate the app.
