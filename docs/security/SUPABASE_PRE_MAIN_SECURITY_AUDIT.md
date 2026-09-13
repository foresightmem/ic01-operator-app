# IC01 Supabase Pre-Main Security Audit

Date: 2026-09-12

Git branch audited: `security-rls-remediation`

Supabase branch expected: `security-rls-remediation`

Supabase branch project ref expected: `gydjrznapplpgvmrcymq`

Production project ref: `atpfgkhechvdijqnflnc`

Production modified during this audit: `NO`

## Executive Decision

Do not copy or merge this work into `main` yet unless the blockers below are
closed or explicitly accepted by the team.

The remediation branch contains the intended security fixes and the app tests
pass. Fresh Supabase branch checks now confirm that the original P0 issues
remain closed, but the branch is not yet a clean production/main candidate
because data parity cleanup, residual risk acceptance, migration promotion
alignment, and the production promotion decision are still open.

## 2026-09-13 Gate Update

Production modified during this update: `NO`.

Supabase remediation branch modified: `YES`, only project ref
`gydjrznapplpgvmrcymq`.

New branch migration applied and mirrored locally:
`20260913082151_close_pre_main_perf_followups`.

Additional branch migration applied and mirrored locally:
`20260913092637_notification_runtime_settings`.

### Closed or Improved

- PM-001 partially closed: fresh branch security advisors ran successfully.
  No fresh findings for disabled RLS, security-definer views, anon GraphQL
  exposure, anon SECURITY DEFINER execution, or mutable function search paths.
  Remaining security advisor items are documented under residual risks below.
- PM-002 partially closed: a branch SQL role matrix was executed through MCP
  using deterministic test tenants for `anon`, `authenticated` operator, and
  admin paths. It verified anon denials, cross-tenant read isolation,
  protected profile/ticket mutation denials, a legitimate ticket status update,
  same-org admin unavailability insert, cross-org admin denial, and the
  symmetric operator-B/cannot-read-client-A check. Full app/JWT user acceptance
  testing remains recommended before production.
- PM-009 closed on branch: `supabase/tests/security_rls_regression.sql` now
  matches the current `profiles.organization_id not null` schema and passed
  end-to-end with `psql -f` against the branch session pooler. Test fixtures
  were removed after execution.
- PM-010 closed locally: Deno is installed at `~/.deno/bin/deno`;
  `deno fmt --check supabase/functions` passes after formatting the Edge
  Function sources, and `deno check` passes for every function entrypoint.
- PM-005 closed on branch: `NOTIFICATION_CRON_SECRET` was generated and set as
  a branch Edge Function secret. `send_notifications` and
  `schedule_daily_notifications` were deployed to the branch with
  `verify_jwt=false`, matching their custom shared-secret authorization model.
  The DB trigger now reads notification runtime settings from
  `private.app_runtime_settings` via a locked-down SECURITY DEFINER helper.
  Required runtime values are present; only lengths/booleans were printed.
- PM-006 closed on branch: Management API patch set
  `password_hibp_enabled=true`; the subsequent security advisor no longer
  reports `auth_leaked_password_protection`.
- PM-012 closed locally: the invalid first line in `.env.local` was moved to
  `/private/tmp/ic01_env_local_invalid_line1.backup` with mode `600`, and
  `.env.local` now parses. `supabase migration list --db-url` runs from the
  repo.
- PM-004 closed in source: `lib/app/env.dart` no longer contains branch
  fallback Supabase URL/key values. Production and branch builds must provide
  `--dart-define=SUPABASE_URL=...` and
  `--dart-define=SUPABASE_PUBLISHABLE_KEY=...`.
- PM-013 closed on branch: performance advisor no longer reports
  `auth_rls_initplan` or `multiple_permissive_policies` for `refills`,
  `temp_machine_assignments`, or `notification_settings`.
- PM-014 closed on branch: duplicate index advisor no longer reports duplicate
  indexes on `device_commands` or `tickets`.
- PM-016 improved: added a GitHub Actions secret-scan gate plus a local
  `tooling/secret_scan.sh` check for high-risk JWT, Supabase secret key,
  service-role assignment, and DB URL patterns.
- PM-017 closed in repo: `supabase/.temp/*` is ignored and previously tracked
  temp files were removed from the git index with `git rm --cached`. Local temp
  files remain on disk only.

### Still Blocking Main

- PM-003 remains open: branch/main row-count parity is currently not exact.
  Branch has additional rows versus production in `machines` (+1),
  `machine_consumables` (+1), `refills` (+1), and
  `public_ticket_request_log` (+3). Do not merge until the team decides whether
  these are expected branch test rows or drift to reset. Candidate branch-only
  rows were identified: machine `67fc0a05-82d8-48b2-87bb-452fc9926fd6`,
  machine consumable `52245c2e-4a6f-4b3f-a198-a0ca31eafedb`, refill
  `1cd91078-c7ec-4add-85a8-89531b793d5b`, and public ticket request log rows
  `9f0921db-33f7-46ba-aa08-6d97c571b315`,
  `e316e1d2-0857-4cf1-8004-586d1f171bdc`, and
  `1830a886-18b7-4270-8226-5623cb20b73a`. Deletion requires explicit owner
  approval because these are application data rows.
- PM-007 remains decision-needed: authenticated GraphQL object visibility
  remains for 30 objects because the Flutter app still uses authenticated
  REST/Data API grants with RLS as the authorization boundary. Repo search found
  no GraphQL client usage. Accept this residual only if GraphQL is intentionally
  allowed for signed-in users, otherwise disable/limit GraphQL in Supabase API
  settings instead of revoking REST grants needed by the app.
- PM-008 remains accepted-risk/decision-needed: public SECURITY DEFINER
  functions are not executable by `anon`; the remaining authenticated RPC
  allowlist is app-facing. Catalog review and targeted RLS tests passed for the
  highest-risk helper and mutation paths. Final owner acceptance is still needed
  because Supabase will continue to warn on authenticated SECURITY DEFINER RPCs.
- PM-011 remains open until promotion: branch migration history now includes the
  new remediation migration, and CLI `migration list --db-url` works from
  outside the repo. However local migration filenames still differ from several
  remote migration versions, so production promotion must use Supabase branch
  merge or a deliberate filename/history alignment plan.
- PM-015 remains accepted/documented risk: `pg_net` remains in `public`.
  Branch test showed `alter extension pg_net set schema extensions` fails with
  `extension "pg_net" does not support SET SCHEMA`. Closing this warning
  requires Supabase-supported extension reinstall/migration guidance or owner
  acceptance.

### Fresh Evidence

- Supabase CLI access token verified with read-only `branches list`; branch
  `security-rls-remediation` is `ACTIVE_HEALTHY` and `FUNCTIONS_DEPLOYED`.
- Security advisors observed at `2026-09-13T09:28:55.704Z`.
- Performance advisors observed at `2026-09-13T09:27:04.244Z`.
- Edge Functions on `gydjrznapplpgvmrcymq` are active with expected JWT flags:
  `device_telemetry_products` v12 and `device_commands` v9 custom-auth/public
  JWT off; `public_maintenance_ticket` v4 public JWT off;
  `send_notifications` v10 and `schedule_daily_notifications` v6 custom-secret
  JWT off; `places_autocomplete` v7 JWT on.
- Edge Function secret `NOTIFICATION_CRON_SECRET` is configured on the branch;
  no value was printed.
- Storage branch audit: one private `firmware` bucket; no
  `storage.objects`/`storage.buckets` policies.
- `private.app_runtime_settings` contains `send_notifications_url` and
  `notifications_internal_secret`; values were verified by set flags/lengths
  only. `anon` and `authenticated` have no direct table privileges.
- RLS regression via MCP: deterministic branch fixture rows were inserted,
  assertions passed, and fixture rows were removed. Final fixture cleanup check
  found `0` remaining SEC test organizations.
- RLS regression via `psql -f supabase/tests/security_rls_regression.sql`:
  passed against the branch session pooler. Fixture cleanup afterwards found
  `0` remaining SEC test organizations.
- Data parity after fixture cleanup: branch differs from production by
  `machines` (+1), `machine_consumables` (+1), `refills` (+1), and
  `public_ticket_request_log` (+3).
- `.env.local` parser check: fixed; original invalid line backed up under
  `/private/tmp` with mode `600`.
- `supabase migration list --local`: now reaches local database connection and
  fails only because local Postgres is not running.
- `supabase migration list --db-url` from the repo: passed and confirmed remote
  latest migration `20260913092637`.
- `psql` branch connectivity: passed after switching to the session pooler URL.
- `~/.deno/bin/deno --version`: `2.9.6`.
- `~/.deno/bin/deno fmt --check supabase/functions`: passed.
- `~/.deno/bin/deno check` on all `supabase/functions/*/index.ts`: passed.
- `dart analyze lib/app/env.dart lib/main.dart
  lib/core/services/push_notifications_service.dart`: passed.
- `flutter test`: passed.
- `bash tooling/secret_scan.sh`: passed.
- `git diff --check`: passed.

The 2026-09-13 gate update supersedes older evidence and status rows below
where they describe earlier access limitations or pre-remediation advisor
findings.

## Evidence Collected In This Audit

- `supabase --version`: `2.109.1`.
- Local git status before creating this report was clean on
  `security-rls-remediation`.
- `.temp/project-ref` points to `gydjrznapplpgvmrcymq`.
- Edge Functions on branch `gydjrznapplpgvmrcymq` are active:
  - `device_telemetry_products`, version 10, `verify_jwt=false`.
  - `device_commands`, version 7, `verify_jwt=false`.
  - `send_notifications`, version 7, `verify_jwt=true`.
  - `schedule_daily_notifications`, version 3, `verify_jwt=true`.
  - `public_maintenance_ticket`, version 3, `verify_jwt=false`.
  - `places_autocomplete`, version 5, `verify_jwt=true`.
- `dart analyze lib/app/env.dart lib/main.dart
  lib/core/services/push_notifications_service.dart`: passed.
- `flutter test`: passed.
- `git diff --check`: passed.
- Deno is not installed locally, so Edge Function format/type checks were not
  run locally.
- Performance advisor on the linked branch returned WARN findings for:
  - RLS `auth_rls_initplan` on `refills`, `temp_machine_assignments`,
    `notification_settings`.
  - Multiple permissive policies on `refills` and
    `temp_machine_assignments`.
  - Duplicate indexes on `device_commands` and `tickets`.
- Fresh security advisor rerun: incomplete. MCP returned `Insufficient scope`;
  CLI required `SUPABASE_DB_PASSWORD`.
- Fresh branch list rerun: incomplete. CLI returned 403 for branch listing.
- Fresh migration history rerun: incomplete. CLI could not connect without
  `SUPABASE_DB_PASSWORD`.

## Main Blockers

| ID | Severity | Status | What must be fixed before main | What could go wrong in production if not fixed |
| --- | --- | --- | --- | --- |
| PM-001 | P0 | Open | Rerun Supabase security advisors and catalog checks on `gydjrznapplpgvmrcymq` with a token/scope and DB password that can read the branch. Confirm no unaccepted ERROR/WARN findings for RLS disabled, security-definer views, anon GraphQL exposure, anon SECURITY DEFINER execution, mutable search paths, storage exposure, and public grants. | We may merge assuming the branch is safe while a live object still exposes rows, bypasses RLS through a view, or leaves a privileged function callable. In production this can become tenant data leakage, unauthorized writes, or a public API surface that is much wider than expected. |
| PM-002 | P0 | Open | Run authenticated branch tests with real users/JWTs for admin, internal admin, technician, refill operator, assigned operator, and a no-membership user. Cover clients, sites, machines, tickets, visits, refills, push tokens, onboarding, coverage planning, machine config, Control Center, and public ticket flow. | RLS can fail silently by returning empty results or can allow too much. Production risk is either broken app screens for legitimate users or cross-tenant access that was not visible in anon smoke tests. |
| PM-003 | P1 | Open | Verify branch data parity again immediately before merge: table counts, key seed rows, auth users needed for testing, storage bucket metadata, and Edge Function secrets. | Tests may pass on a branch that no longer represents main. After merge, production can expose behavior that was never tested, or the app can fail because branch-only data/secrets were missing or stale. |
| PM-004 | P1 | Open | Verify rollout configuration for the frontend. The app now requires `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` Dart defines. Update CI/build scripts and release docs before main. | A production build can fail at startup with missing config, point to the wrong Supabase project, or accidentally keep using old local assumptions. This is a high-risk release failure even if DB security is correct. |
| PM-005 | P1 | Open | Verify DB settings used by `notify_outbox_immediate`: `app.settings.send_notifications_url` and `app.settings.notifications_internal_secret`. Decide exact main/prod values and set them during rollout. | Immediate notification delivery can stop because the trigger now safely does nothing when URL/secret are unset. If misconfigured, production could send to the wrong function endpoint or fail to notify users after ticket/refill events. |
| PM-006 | P1 | Open | Enable leaked-password protection in Supabase Auth settings, or formally accept this residual risk with a follow-up date. | Users can continue using passwords already present in breach lists. In production this increases credential-stuffing and account-takeover risk. |
| PM-007 | P1 | Open / Decision Needed | Decide whether authenticated GraphQL exposure is acceptable. Current remediation intentionally keeps authenticated REST/Data API access and relies on RLS. To remove the advisor warning, disable/limit GraphQL or move sensitive reads behind narrower RPC/views. | Signed-in users may enumerate schema and attempt GraphQL access to objects that were meant for REST flows only. If any RLS policy is wrong, GraphQL can become an alternate path to broader data exposure. |
| PM-008 | P1 | Open / Decision Needed | Review all public `SECURITY DEFINER` functions that remain executable by `authenticated`. Either accept the allowlist with body-level authorization tests or move privileged implementation details to a private schema behind narrow wrappers. | A `SECURITY DEFINER` function bypasses normal RLS. If one body check is incomplete, a signed-in user can invoke privileged behavior directly, causing unauthorized onboarding, refill, ticket, or Control Center actions. |
| PM-009 | P1 | Open | Run `supabase/tests/security_rls_regression.sql` through `supabase test db`, Dashboard SQL, CI, or `psql` against the branch with proper credentials. | Catalog checks and HTTP smoke tests do not prove every allow/deny case. Production can ship with a policy that blocks legitimate users, permits ownership changes, or allows cross-tenant reads only visible with real JWT context. |
| PM-010 | P2 | Open | Run Deno checks for all Edge Functions (`deno fmt --check`, `deno check`, or equivalent CI/Supabase function validation). | Edge Functions may deploy but still contain type/import/runtime issues that appear only on specific paths. Production risk is failed device telemetry, failed commands, broken notifications, or public ticket errors. |
| PM-011 | P2 | Open | Decide the migration promotion path before main: Supabase branch merge vs applying local migrations. Reconcile local migration timestamps with remote migration history and verify no duplicate/partial migration will run. | Production migration can fail halfway, try to recreate objects, skip expected changes, or leave the database in a state that is hard to roll back. |
| PM-012 | P2 | Open | Fix or document `.env.local` parsing before running Supabase CLI from repo root. It currently prevents `supabase migration list --linked` from running in this environment. | Release operators may be blocked during a migration window by local CLI parsing errors, slowing rollback or verification when time matters most. |

## Should Fix Soon

| ID | Severity | Status | What should be fixed | What could go wrong in production if not fixed |
| --- | --- | --- | --- | --- |
| PM-013 | P2 | Open | Optimize RLS policies flagged by performance advisor: wrap stable helper calls as `(select auth.uid())` / `(select current_setting(...))` where applicable and consolidate duplicate permissive policies on `refills` and `temp_machine_assignments`. | RLS policies may be evaluated once per row instead of once per query. As data grows, dashboards, refill screens, notification settings, and assignment views can become slow or expensive. |
| PM-014 | P2 | Open | Drop or consolidate duplicate indexes on `public.device_commands` and `public.tickets` after confirming query plans and index ownership. | Duplicate indexes increase write overhead, storage usage, and migration/index maintenance time. During production traffic this can slow ticket updates and device command processing. |
| PM-015 | P2 | Open / Decision Needed | Decide whether to address `pg_net` remaining in `public`. Previous notes say it was not relocatable in this project, so do not force-move without a dedicated migration and rollback test. | The advisor warning may remain. If extension privileges are later broadened accidentally, network-capable database functions can become a larger misuse surface. |
| PM-016 | P3 | Open | Add a permanent CI gate for secret scanning across `lib`, `supabase/functions`, migrations, and docs. Current scan did not find hardcoded Supabase JWT/project URL in app/function/migration source, but this should become automatic. | A future commit can accidentally reintroduce a service key, legacy anon key, or production URL into client code. Production risk is key exposure and unauthorized API access. |
| PM-017 | P3 | Open | Decide whether tracked `supabase/.temp/*` files should stay tracked. They currently point tooling at branch metadata. | A developer or CI job can accidentally run Supabase commands against the wrong project ref, creating confusion during release or remediation. |

## Already Fixed Or Verified On The Remediation Branch

- The branch was previously recreated with data (`with_data=true`) so app
  testing can use the same baseline rows as main.
- Previous remediation notes record matching row counts between main and the
  branch for all 26 `public` base tables before and after remediation.
- RLS was enabled/forced for the previously exposed public tables in the
  remediation migrations.
- Exposed views were updated to `security_invoker=true` and anon view access
  was revoked in the remediation migrations.
- Anon execution of public `SECURITY DEFINER` functions was narrowed in the
  remediation migrations.
- Profile mutation grants and ticket protected-column mutation paths were
  tightened.
- Admin machine config, coverage planning, and push token policies were added.
- The duplicate index introduced during remediation on `machine_consumables`
  was removed and the local migration was adjusted so it is not recreated.
- Public maintenance ticket responses were hardened to avoid leaking ticket IDs
  or machine-existence details.
- Device and notification Edge Functions now return generic public error codes
  while logging details server-side.
- Frontend hardcoded Supabase config was removed from `lib/app/env.dart`.

## Recommended Pre-Main Gate

1. Restore complete Supabase audit access:
   - MCP or CLI must be able to run security advisors.
   - CLI must be able to list linked migrations.
   - Branch list must be visible or verified in Dashboard.
2. Run security advisors and save the output summary.
3. Run authenticated role matrix tests on the branch.
4. Run `supabase/tests/security_rls_regression.sql` with real branch DB
   credentials.
5. Verify Edge Function secrets and DB `app.settings.*` values on branch.
6. Enable leaked-password protection or log a formal exception.
7. Decide GraphQL and authenticated `SECURITY DEFINER` residual risks.
8. Run Deno checks for Edge Functions.
9. Fix/accept performance advisor WARN findings.
10. Only then promote to `main` and schedule the Supabase production merge.

## Current Recommendation

Use the branch for app testing now, but do not merge/copy to `main` yet.

The highest-risk open items are not additional SQL rewrites; they are missing
fresh live verification and role-based tests. Once PM-001 through PM-009 are
closed, the branch can be considered a main candidate. PM-013 through PM-017
can be handled before production launch or accepted with explicit owners and
dates, depending on release urgency.

## References

- Supabase Row Level Security docs:
  https://supabase.com/docs/guides/database/postgres/row-level-security
- Supabase Data API security docs:
  https://supabase.com/docs/guides/api/securing-your-api
- Supabase password security docs:
  https://supabase.com/docs/guides/auth/password-security
- Supabase changelog breaking changes:
  https://supabase.com/changelog?types=breaking-change
