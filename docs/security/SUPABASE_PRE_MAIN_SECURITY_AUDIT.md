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
pass, but the current audit could not complete a fresh live security advisor /
catalog verification because the available MCP Supabase tools returned
`Insufficient scope` and the CLI security advisor/migration checks could not
connect without `SUPABASE_DB_PASSWORD`.

The branch is good enough for controlled branch testing. It is not yet a clean
production/main candidate until the live advisor run, authenticated role tests,
and production rollout configuration are verified.

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
