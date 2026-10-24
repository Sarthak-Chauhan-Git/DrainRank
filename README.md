# DrainRank

DrainRank is a municipal drainage-operations platform for receiving citizen
reports, ranking drainage assets, assigning inspection and cleaning work,
capturing field evidence, reviewing that evidence, and monitoring outcomes over
time. It is being developed as a multi-client hackathon/prototype system:

- a **citizen Flutter application** for reporting drainage problems;
- a **field-team Flutter application** for municipal crew accounts, task
  execution, geo-tagged work evidence, leave, activity, and credits; and
- a **React/TypeScript municipal dashboard** for operations staff.

The repository currently contains working UI and several real integrations, but
it is not yet a single end-to-end production deployment. Read the
[current development stage](#current-development-stage) and
[known gaps](#remaining-work-and-known-gaps) before extending it.

## Product workflow

The intended operational lifecycle is:

1. A citizen submits a drainage complaint with an issue category, location,
   description, urgency/consequence selection, and a photograph.
2. The report receives a unique ID, GPS and capture metadata, an image-quality
   check, duplicate/device-radius checks, and an estimated priority.
3. The municipality views drainage cases in the dashboard. Existing asset
   priority is combined with complaint history and persistent outcomes to
   produce the Drain Intelligence ranking.
4. Staff route a case to an inspection queue or cleaning queue and assign work
   to a crew.
5. A field worker views assigned Supabase tasks, captures one live-camera
   work photograph, attaches current GPS and capture time, and submits a
   description.
6. An authorized field-app administrator reviews submissions and awards
   credits. The web dashboard also has an evidence-review workflow, but it is
   not yet connected to the field app's Supabase work-evidence records. The AI
   assistant is advisory and never approves evidence.
7. The system retains activity, credit, complaint, and outcome history for
   follow-up and post-rain monitoring.

The clients now target one shared Supabase project. Citizen reports are stored
in `citizen_reports`; dashboard work orders are synchronized into `field_tasks`;
and field work submissions use Supabase Storage and database functions. This
integration still requires schema compatibility review and deployment to the
existing Supabase project before the end-to-end workflow is live.

## Repository structure

Generated dependencies and platform build output are intentionally omitted
below. `apps/web/node_modules`, Flutter `.dart_tool`/`build` directories,
Android Gradle output, iOS Pods, and compiled bundles should not be edited or
committed.

```text
DrainRank/
├── README.md
├── .github/
│   └── workflows/
│       └── web-build.yml                 # CI: npm ci + web TypeScript/Vite build
├── apps/
│   ├── README.md
│   ├── web/                              # Municipal operations dashboard
│   │   ├── package.json                  # React/Vite scripts and dependencies
│   │   ├── package-lock.json
│   │   ├── .env.example                  # Required web environment variables
│   │   ├── public/map.kml                # Drainage/waterway map overlay
│   │   ├── src/
│   │   │   ├── main.tsx                  # React entry; AuthGate wrapper
│   │   │   ├── App.tsx                   # Dashboard state, routes, pages, actions
│   │   │   ├── AuthGate.tsx              # Supabase staff authentication/authorization
│   │   │   ├── dataProvider.ts           # Supabase load/save and citizen merge
│   │   │   ├── supabase.ts               # Supabase browser client
│   │   │   ├── supabaseStorage.ts        # Private dashboard image upload/signing
│   │   │   ├── emptyState.ts             # Empty initial state and credit policy
│   │   │   ├── intelligence.ts           # Deterministic ranking/history analysis
│   │   │   ├── MonitoringIntelligencePage.tsx
│   │   │   ├── GlobalDrainAssistant.tsx  # Local Ollama chat UI
│   │   │   ├── server/
│   │   │   │   ├── drainRankOllama.ts    # Vite dev-server local API endpoint
│   │   │   │   └── drainRankKnowledge.ts # Verified product prompt/reference
│   │   │   ├── App.css, index.css,
│   │   │   │   MonitoringIntelligence.css, GlobalDrainAssistant.css
│   │   │   └── assets/
│   │   ├── shared/                       # Reserved for shared web code/types
│   │   └── README.md                     # Dashboard setup and security notes
│   ├── citizen-android/
│   │   ├── README.md
│   │   └── drainrank_citizen/             # Flutter citizen app
│   │       ├── lib/main.dart              # App shell and citizen screens
│   │       ├── lib/core/constants.dart    # Demo drains and policy constants
│   │       ├── lib/models/citizen_report.dart
│   │       ├── lib/services/drainrank_engine.dart
│   │       ├── lib/services/high_urgency_places_service.dart
│   │       ├── test/widget_test.dart
│   │       └── pubspec.yaml
│   └── field-android/
│       ├── README.md
│       └── field_app/                     # Flutter field/crew app
│           ├── lib/main.dart              # Supabase initialization and parts
│           ├── lib/app/app.dart           # Theme and app shell
│           ├── lib/auth/                  # Login, role and profile access checks
│           ├── lib/admin/admin.dart       # Admin dashboard/account/task controls
│           ├── lib/crew/                  # Home, activity, leave, credits
│           ├── lib/tasks/                 # Task list/detail and submissions
│           ├── lib/camera/                # Live camera and GPS/EXIF embedding
│           ├── lib/shared/date_helpers.dart
│           ├── test/widget_test.dart
│           └── pubspec.yaml
├── backend/
│   ├── README.md
│   ├── supabase/migrations/
│       ├── 202610210001_shared_app_backend.sql
│       └── 202610220001_web_dashboard_state.sql
│   └── supabase/functions/
│       └── create-crew-account/index.ts  # Admin-only crew provisioning
└── docs/README.md                         # Documentation area placeholder
```

## Application roles

### Citizen app

Location: `apps/citizen-android/drainrank_citizen`.

The Flutter app provides Supabase email/password authentication, account
creation/sign-in, a report form, report tracking/status cards, a map,
settings/preferences, and help/about surfaces. A report can include:

- blocked drain, waterlogging, overflow, needs inspection, or other category;
- location and GPS accuracy;
- a known drain pin or `PROVISIONAL-PIN`;
- urgency/consequence context such as a hospital, school, emergency route,
  market/main road, underpass, or residential street;
- a description and picked image;
- capture/upload timestamps, SHA-256 image hash, luminance/quality result,
  device ID, and estimated priority.

The local ranking engine uses the report category, consequence, catchment
proxy, blockage/quality inputs, and configured thresholds. The app also
contains a Geoapify Places integration that can find nearby hospitals, schools,
universities, colleges, police stations, and fire stations within a bounded
radius, with high priority for hospitals/police/fire stations.

Citizen report rows are submitted to Supabase and report photographs are
uploaded to the private `citizen-photos` bucket. `SharedPreferences` is used
only as a local cache; report tracking reads backend status and no longer
simulates status progression. Deployment and verification against the existing
project schema remain pending.

### Field app

Location: `apps/field-android/field_app`.

The field app initializes Supabase and supports:

- Supabase email/password login using a Municipal ID alias for crew members;
- profile-based admin and access-block checks;
- admin account creation through the protected
  `create-crew-account` Supabase Edge Function;
- assignment-based task streams for the logged-in crew member;
- today, previous-seven-days, and next-seven-days task views;
- task detail and status display;
- live-camera-only work-photo capture;
- current high-accuracy GPS, reverse geocoding, capture timestamp, and real JPEG
  EXIF GPS metadata;
- private Supabase Storage photo uploads and Supabase work-submission RPC;
- one work photo per crew member per task, task edit windows, assignment
  re-checks, and restrictions on future/past task editing;
- activity history, leave requests, credit displays, and admin review/overdue
  deduction helpers.

The dashboard synchronizes assigned work orders to `field_tasks`. The worker
ID in the dashboard must match the crew member's Municipal ID. Crew account
provisioning and protected work/credit operations run server-side through
Supabase functions; the service-role key must never be shipped to a client.

### Municipal web dashboard

Location: `apps/web`.

The dashboard is wrapped in `AuthGate`. Staff sign in with Supabase email and
password, and access is granted only when the authenticated user's active
`profiles` row has role `admin`. Navigation currently includes:

| Route | Responsibility |
| --- | --- |
| `/overview` | Operational summary and key measures |
| `/map` | Leaflet map of drain records, citizen reports, and `public/map.kml` overlay |
| `/queues` | Inspection/cleaning queues and crew assignment |
| `/work-orders` | Assigned work, deadlines, and work tracking |
| `/evidence` | Manual completion-evidence review, including rework |
| `/monitoring` | Ranked Drain Intelligence cases and next-action recommendations |
| `/reports` | Issue mix, lifecycle charts, filters, report table, and CSV export |
| `/crew-management` | Worker/crew records and crew assignment management |
| `/logs` | Activity and credit audit history, including CSV export |
| `/administration` | Preferences and local dashboard administration/reset controls |

`App.tsx` owns the typed `AppState` model: drains, reports, activities,
outcomes, workers, crews, credit policy, credit pools, credit allocations,
credit audits, and preferences. The UI uses React Router, React Leaflet,
Recharts, and Lucide icons.

## Data flow and persistence

```text
Citizen Flutter app
  ├─ Supabase Auth (email/password)
  ├─ citizen_reports (owned reports/status)
  └─ private citizen-photos bucket

Web dashboard
  ├─ Supabase Auth (staff email/password)
  ├─ profiles (admin authorization)
  ├─ dashboard_state (one JSONB municipal state row)
  ├─ citizen_reports (RLS-protected report access)
  ├─ field_tasks (dashboard-to-crew assignment bridge)
  ├─ dashboard-evidence (private Supabase Storage bucket)
  └─ local Vite API → local Ollama/Qwen3 (sanitized advisory questions)

Field Flutter app
  ├─ Supabase Auth (crew/admin login)
  ├─ Supabase profiles, field_tasks, activity, leave, and credit records
  ├─ private field-evidence Storage bucket
  └─ Supabase Edge Function/RPCs for privileged operations
```

### Web dashboard persistence details

The migration
`backend/supabase/migrations/202610220001_web_dashboard_state.sql` adds
`save_dashboard_state` and `update_citizen_report_statuses` RPCs to the existing
`dashboard_state` and `citizen_reports` tables. Both require the existing
`is_admin()` helper; dashboard saves use `updated_at` for optimistic
concurrency. It does not create `dashboard_admins` or
`web_dashboard_state`.

The dashboard loads the singleton state and the `citizen_reports` table in
parallel. Saves are serialized in the browser and use optimistic revision
checking, so a stale administrator cannot silently overwrite another save.
There is no browser `localStorage` fallback for the dashboard. A new valid
workspace starts empty; `emptyState.ts` supplies only the initial shape and
credit-policy defaults.

Citizen reports read by the dashboard are mapped into dashboard
`ReportRecord`s. Existing dashboard status is preserved when IDs match. The
shared-app migration creates the common report schema and grants the
appropriate citizen/admin access. Because the existing Supabase project
already has this table, verify its columns and policies before applying the
migration; `CREATE TABLE IF NOT EXISTS` does not reconcile incompatible
existing columns.

### AI and intelligence data flow

`intelligence.ts` deterministically calculates the monitoring snapshot:

- case score is the base drain priority plus a recurrence adjustment;
- additional linked non-duplicate complaints add up to 18 points in total;
- prior persistent outcomes add 6 points;
- scores are clamped to 0–100;
- cases are marked recurring, overdue, awaiting review, and assigned a
  history-aware next action.

The displayed score is an operational prioritization aid, not a probability,
guaranteed response time, or proof of severity.

The assistant sends only an allowlisted, sanitized subset of case fields to
`/api/drainrank/chat`: IDs, ward/location, scores, status, issue/condition,
evidence state, dates, counts, explanations, outcomes, and history. It refuses
personal-data requests and unrelated questions. The API accepts loopback
requests only, validates request size/types, and calls a local Ollama server
(default model `qwen3:8b`, default URL `http://127.0.0.1:11434`). It is a
development integration, not a hosted AI service, and it cannot approve
evidence or perform operational actions.

## Technology stack

| Area | Technology |
| --- | --- |
| Web UI | React 19, TypeScript 6, Vite 8 |
| Web navigation/charts/maps | React Router 7, Recharts, Leaflet, React Leaflet |
| Web backend/auth | Supabase JS/Auth/Postgres/RLS |
| Web evidence images | Supabase Storage private bucket and signed URLs |
| Local assistant | Vite middleware, Node HTTP types, Ollama, Qwen3 8B |
| Mobile clients | Flutter/Dart |
| Citizen persistence/auth | Supabase Auth/Postgres/Storage, SharedPreferences cache |
| Citizen maps/location | flutter_map, latlong2, geolocator, Geoapify Places |
| Shared backend | Supabase Auth, Postgres/RLS, Storage, Edge Functions |
| Quality tools | TypeScript build, Oxlint, Flutter analyze/test, widget tests |
| CI | GitHub Actions web build on pull requests to `main`/`develop` and pushes to `develop` |

## Current development stage

**Stage: functional prototype / integration hardening.**

The web dashboard has a substantial implemented surface and a real Supabase
authorization/persistence path. Citizen reports and dashboard-to-field
assignments now have shared Supabase paths in code. The field app uses
Supabase-backed accounts, tasks, work evidence, and credits. The shared schema
and crew-provisioning Edge Function are deployed; live smoke tests remain.
Field evidence review is not yet integrated into the web dashboard's separate
evidence workflow.

What is implemented now:

- web administrator authentication through the existing `profiles` role;
- RLS-protected web state with optimistic concurrency;
- dashboard navigation, maps, queues, work orders, evidence review, reports,
  crew/credit/log administration, and deterministic monitoring intelligence;
- private Supabase Storage evidence uploads across the web and mobile apps;
- local Ollama assistant with validation and personal-data guardrails;
- citizen email/password UI, Supabase report submission/tracking, local cache,
  location and urgency-place support;
- Supabase field login/roles, task stream, camera/GPS/EXIF evidence, storage
  upload, crew activity/leave/credit surfaces;
- shared report/task backend migration and protected crew-provisioning
  function (deployed, but not yet smoke-tested end to end);
- a web CI build and citizen responsive widget tests.

## Remaining work and known gaps

Prioritize these before calling the system production-ready:

1. **Smoke-test the shared backend.** Confirm deployed tables and RLS, then
   test    report submission/withdrawal, status updates, task assignment, crew
   provisioning, evidence submission, and credit approval.
2. **Connect field evidence review to dashboard operations.** Decide whether
   the web Evidence Review page or the field-app administrator screen owns
   approval, then synchronize evidence and reviewer decisions through
   Supabase.
3. **Align schemas and status transitions.** Map citizen workflow statuses,
   dashboard `DrainStatus`/report statuses, field task states, evidence
   decisions, and outcome history with explicit transition rules.
4. **Finish production security configuration.** Review Supabase RLS and
   Storage policies, secret
   management, rate limits, audit logging, and least-privilege deployment
   accounts.
5. **Replace demo/prototype configuration.** Move remaining ward/drain
   inventory and policy configuration to managed data and provide
   environment-specific builds. Remove or replace the citizen app's temporary
   `12345678` Debug Tool PIN before production.
6. **Complete automated verification.** Replace the generated counter smoke
   test in the field app, add unit/widget/integration tests for authentication,
   ranking, duplicate prevention, data mapping, evidence upload, task
   permissions, RLS, Edge Functions, and cross-client flows.
7. **Harden deployment and observability.** Add release build/signing
   documentation, staging environments, database migration execution,
   backups, monitoring, structured logs, crash reporting, and a rollback plan.
8. **Clarify privacy and retention.** Define consent, retention/deletion,
   citizen identity handling, image access, export authorization, and audit
   requirements. In particular, review report CSV export because it includes
   reporter identity in the current dashboard implementation.
9. **Make AI optional and verifiable.** Keep deterministic counts and ranking
   authoritative, add an explicit unavailable-model experience, test prompt
   and input boundaries, and never present local-model recommendations as
   approvals or completed actions.
10. **Update Flutter dependency metadata.** The field app's lockfile and
    generated platform plugin files still need regeneration with the required
    Flutter/Dart SDK; the installed SDK is older than the project's declared
    minimum.

## Local development

### Web dashboard

From `apps/web`:

```powershell
npm install
Copy-Item .env.example .env.local
# Set VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY.
npm run dev
npm run build
npm run lint
```

Inspect the existing Supabase schema and policies before applying migrations.
Promote the administrator's Auth-linked `profiles` row to role `admin`; do not
create a separate dashboard membership table.
The detailed Supabase Storage setup is in [`apps/web/README.md`](apps/web/README.md).
Never put a Supabase service-role key or Ollama credentials in browser code.

For the local assistant, install/run Ollama on the same machine and make the
configured model available. Optional environment variables are
`DRAINRANK_OLLAMA_URL` (loopback URL) and `DRAINRANK_OLLAMA_MODEL` (default
`qwen3:8b`). The assistant endpoint is intentionally restricted to local
loopback traffic.

### Citizen Flutter app

From `apps/citizen-android/drainrank_citizen`:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```

Enable Supabase Email authentication. The app displays a configuration message
when the URL/key are absent. Geoapify-based nearby
facility discovery additionally needs
`--dart-define=GEOAPIFY_API_KEY=...`.

### Field Flutter app

From `apps/field-android/field_app`:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```

Apply the two reviewed SQL migration files in order through Supabase SQL
Editor. From `backend`, deploy the protected Edge Function:

```powershell
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase functions deploy create-crew-account
```

### CI

`.github/workflows/web-build.yml` uses Node 22, runs `npm ci`, and executes
`npm run build` from `apps/web`. It does not currently build or test either
Flutter application.

## Development conventions

- Treat the root `DrainRank` directory as the project root; do not stage the
  unrelated files in the parent Git worktree.
- Work on feature branches from `develop`; pull requests target `develop`.
- Stage only the module being changed. Avoid `git add .`.
- Keep shared contracts, migrations, and security changes coordinated across
  the web, citizen, and field owners.
- Preserve explicit error messages and permission checks; do not replace real
  integrations with silent mock fallbacks.
- Do not commit `.env.local`, private keys, service-role keys, generated
  dependencies, or build output.

## Related documentation

- [Web dashboard setup](apps/web/README.md)
- [Citizen app setup](apps/citizen-android/drainrank_citizen/README.md)
- [Backend notes](backend/README.md)
- [Web CI workflow](.github/workflows/web-build.yml)
- [Supabase dashboard migration](backend/supabase/migrations/202610220001_web_dashboard_state.sql)
