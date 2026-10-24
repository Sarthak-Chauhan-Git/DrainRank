# Applications

This directory contains the three DrainRank clients:

- [`web/`](./web/README.md): React/Vite municipal dashboard. Start its
  dependency-free local workflow at `/debug`.
- [`citizen-android/drainrank_citizen/`](./citizen-android/drainrank_citizen/README.md):
  Flutter citizen reporting and tracking app.
- [`field-android/field_app/`](./field-android/field_app/README.md): Flutter
  Pravah Saarthi crew app.

For isolated mobile testing, run `flutter pub get` in the respective Flutter
app folder, then `flutter run --dart-define=LOCAL_DEBUG_MODE=true`. For local
web testing, run `npm ci` in `web` and open `/debug` on the Vite dev server.
These test modes require the shared PIN `12345678`, use in-memory sample data,
and do not access Supabase. See the root [README](../README.md) for complete
clone, install, build, and deployment instructions.
