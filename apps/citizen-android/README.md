# Citizen Android app

The Flutter app, Supabase configuration, local-only debug mode, and Android
build/test instructions are documented in
[`drainrank_citizen/README.md`](./drainrank_citizen/README.md).

For a new clone, run `flutter pub get` from `drainrank_citizen`. To test the
in-memory workflow without Supabase, run:

```powershell
flutter run --dart-define=LOCAL_DEBUG_MODE=true
```
