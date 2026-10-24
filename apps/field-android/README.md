# Field Android app

The Flutter application and its Supabase build/deployment instructions are in
[`field_app`](./field_app/README.md).

Install dependencies with `flutter pub get` inside `field_app`. To run the
isolated in-memory field workflow without connecting to Supabase:

```powershell
flutter run --dart-define=LOCAL_DEBUG_MODE=true
```
