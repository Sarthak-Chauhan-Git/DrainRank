# DrainRank backend

Supabase migrations live in [`supabase/migrations`](./supabase/migrations/).
Apply the web dashboard migration and provision an authorized dashboard
administrator by following the [web app setup guide](../apps/web/README.md).

The dashboard requires authenticated staff accounts and applies row-level
security to its shared Postgres state. Browser clients use only the Supabase
publishable key; never expose the service-role key in application code.
