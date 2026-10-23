# DrainRank application and backend status

## Applications

| App | Client | Shared Supabase responsibilities |
|---|---|---|
| Citizen | Flutter | Email/password Auth, citizen profile, report submission and tracking, private `citizen-photos` Storage |
| Municipal dashboard | React/TypeScript | Admin Auth through `profiles`, state in `dashboard_state`, citizen report status, and task assignment |
| Field | Flutter | Crew/admin Auth through `profiles`, assigned tasks, private `work-photos` evidence, leave requests, and credits |

The clients use one Supabase project. The existing project schema is reused;
the migrations do not create parallel profile, dashboard-state, report, leave,
or credit tables.

## Existing schema confirmed by project inspection

- `profiles.id` references `auth.users.id`; roles are `citizen`, `crew`, and
  `admin`. The existing `current_profile_role()`, `is_admin()`, and `is_staff()`
  helpers are used for authorization.
- `citizen_reports` uses `reporter_id` and `image_sha256_hash`. App metadata is
  retained in its `payload`; `image_path` is added if absent.
- `dashboard_state` stores the municipal dashboard's JSON payload and update
  metadata.
- `credit_awards` and `leave_requests` retain their existing columns and store
  app-specific values in `payload`.
- `staff_accounts` is kept intact; crew sign-in uses Auth-linked profiles.

## Shared-backend migrations

Apply these only after reviewing them against the live project, in timestamp
order:

1. `backend/supabase/migrations/202610210001_shared_app_backend.sql`
   - adds field task and work-update tables, protected task/evidence/credit
     RPCs, realtime publication entries, and `work-photos` Storage policies;
   - preserves existing tables and their policies; and
   - supplies missing UUID/time defaults to the existing leave and credit
     tables only when those defaults are absent.
2. `backend/supabase/migrations/202610220001_web_dashboard_state.sql`
   - adds admin-only dashboard-save and citizen-report-status RPCs using the
     existing tables and `is_admin()` helper.

The administrator profile and private `citizen-photos` bucket/policies were
configured separately in Supabase. Keep both photo buckets private.

## Important integration boundaries

- The web dashboard bridges assignments to `field_tasks` by matching worker
  IDs to crew Municipal IDs.
- Dashboard evidence, field photos, and citizen photos use private Supabase
  Storage buckets.
- Field submissions are available to the field-app administrator review flow.
  The dashboard's manual evidence-review UI is not yet backed by those
  submissions; dashboard evidence approval and field evidence review are
  therefore not one synchronized workflow.
- Demo/seed dashboard records and static drain inventory are distinct from
  citizen reports and live field tasks.

## Validation and readiness

- The web build succeeds. Lint reports three existing React purity warnings in
  `apps/web/src/App.tsx`.
- Flutter validation is blocked until a Flutter/Dart SDK satisfying the
  projects' declared Dart `^3.13.5` requirement is available.
- Both SQL migrations succeeded in Supabase SQL Editor and
  `create-crew-account` was deployed. Live end-to-end behavior still needs
  smoke testing.

Do not treat the system as end-to-end ready until all three apps pass their
available checks and citizen reporting, dashboard status/assignment, crew
provisioning, evidence, and credit flows have been smoke-tested.
