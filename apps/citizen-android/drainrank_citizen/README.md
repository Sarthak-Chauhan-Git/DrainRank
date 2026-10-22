# DrainRank Citizen

Flutter citizen app for submitting drain reports and tracking their workflow.

## Configure Supabase phone authentication

In the Supabase project, enable the Phone provider and configure an SMS provider.
The app supports phone-number sign-in and account creation using SMS one-time
codes. New accounts are activated after the code is verified. Use E.164 phone
format, including the country code (for example, `+919876543210`).

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

```powershell
flutter pub get
flutter analyze
flutter test
```

Citizen reports and demo status updates are currently stored locally on the
device. The phone authentication flow does not imply that reports or photos are
being synchronized to Supabase or Cloudinary.
