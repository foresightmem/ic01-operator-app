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
because the remaining authenticated real-user/UAT matrix and production
rollout approvals must still be completed or explicitly accepted.

## 2026-09-14 Pre-Merge Test Run

Production modified during this update: `NO`.

Supabase remediation branch modified: `NO` for schema/data, except temporary
RLS regression fixtures created and removed by the test script.

### Results

- Branch status: `security-rls-remediation` is `ACTIVE_HEALTHY`,
  `FUNCTIONS_DEPLOYED`, `with_data=true`.
- Security advisors on the branch: no ERROR findings; remaining WARN is
  accepted/documented `extension_in_public` for `pg_net`; remaining INFO items
  are RLS-enabled/no-policy service/backend tables.
- Performance advisors on the branch: INFO-only findings.
- Edge Functions on branch and production have the same slug set. Branch
  notification functions use `verify_jwt=false` with custom cron/internal
  secret authorization.
- Storage: one private `firmware` bucket and zero storage policies.
- `private.app_runtime_settings` contains both notification runtime keys; only
  presence and lengths were verified, not values.
- `supabase/tests/security_rls_regression.sql` passed through `psql` against
  the branch and now performs cleanup at the beginning and end of the script.
- PM-002 UAT found and fixed an admin coverage blocker: the app needed to
  delete previous `suggested` rows in `temp_machine_assignments`, but
  authenticated lacked table DELETE privilege. Branch migration
  `20260914100050_fix_admin_coverage_suggested_assignment_delete` grants
  DELETE to `authenticated` while RLS restricts it to same-org admins and
  `status = 'suggested'`.
- PM-002 UAT found and fixed an admin machine tank configuration blocker:
  `machine_consumables` writes fired `sync_machine_current_fill_percent()`,
  which attempted to update derived `machines.current_fill_percent` after
  direct machine update grants had been narrowed. Branch migration
  `20260914100936_fix_machine_consumables_fill_percent_trigger` makes only the
  trigger helper `SECURITY DEFINER`, fixes its `search_path`, and revokes direct
  execute from app roles.
- Post-regression cleanup check: `0` SEC test org/profile/client/site/machine
  fixture rows remained.
- Data parity: branch and production match exact `count(*)` values for all 26
  checked `public` base tables.
- Catalog checks: all public base tables have RLS enabled; legacy
  `perform_refill(uuid)` is executable by `service_role` only, not `anon` or
  `authenticated`; authenticated SECURITY DEFINER allowlist count is 25.
- Duplicate indexes on `device_commands` and `tickets` remain closed. One
  lower-priority duplicate pair remains on `devices(device_id)` and should be
  reviewed separately before high-volume device writes.
- Local checks passed: `flutter analyze`, `flutter test`, web build smoke with
  non-sensitive `--dart-define` values, Deno format/type checks, secret scan,
  and `git diff --check`.

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

No PM-003 or PM-011 blockers remain after the 2026-09-14 closure update.

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
- Data parity after fixture cleanup: branch and production match exact
  `count(*)` values for all 26 checked `public` base tables.
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

## 2026-09-14 PM-007 / PM-008 / PM-015 Closure Update

Production modified during this update: `NO`.

Supabase remediation branch modified: `YES`, only project ref
`gydjrznapplpgvmrcymq`.

New branch migration applied and mirrored locally:
`20260914082527_close_pm008_security_definer_allowlist`.

### Closed By Team Decision Or Branch Migration

- PM-007 closed by owner/team acceptance: authenticated GraphQL object
  visibility remains documented as an accepted residual platform/API exposure.
  Repo audit found no Flutter GraphQL client usage; the app relies on
  authenticated REST/Data API access with RLS as the authorization boundary.
  Future removal requires disabling/limiting GraphQL in Supabase API settings
  or changing the app grant model to narrower RPC/views.
- PM-008 closed on branch: `perform_refill(uuid)` is now legacy
  `service_role` only, while the live operator refill flow
  `perform_refill_consumable(uuid, consumable_type)` remains callable by
  `authenticated` and is documented as the allowlisted app RPC. The regression
  SQL now includes an exact authenticated SECURITY DEFINER allowlist gate,
  verifies `perform_refill(uuid)` is denied to authenticated app users,
  verifies cross-tenant refill denial, and verifies a legitimate assigned
  operator refill through the current RPC.
- PM-015 closed by owner/team acceptance: `pg_net` remains in `public` because
  branch testing confirmed `alter extension pg_net set schema extensions`
  fails with `extension "pg_net" does not support SET SCHEMA`. Current
  mitigations remain in place: notification runtime URL/secret are stored in
  `private.app_runtime_settings`, `anon`/`authenticated` have no direct access
  to that table, and the notification trigger function is not executable by
  `anon` or `authenticated`.

### Fresh Evidence

- Catalog check confirms `public.perform_refill(uuid)` has
  `anon=-`, `authenticated=-`, and `service_role=Y`.
- Catalog check confirms `public.perform_refill_consumable(uuid,
  consumable_type)` has `anon=-`, `authenticated=Y`, and `service_role=Y`.
- Security advisors observed at `2026-09-14T08:28:18.523Z`: remaining WARNs
  are the accepted/documented `pg_net` in `public`, authenticated GraphQL
  object visibility, and 25 authenticated SECURITY DEFINER functions in the
  audited allowlist. `perform_refill(uuid)` is no longer in the authenticated
  SECURITY DEFINER advisor findings.
- Performance advisors observed at `2026-09-14T08:28:17.001Z`: remaining
  items are INFO-level unindexed foreign keys, unused indexes, and Auth DB
  connection strategy guidance.
- `psql -f supabase/tests/security_rls_regression.sql` passed against the
  branch session pooler after adding the PM-008 allowlist and refill checks.
- Test fixtures created by the regression run were removed immediately; final
  SEC fixture organization count was `0`.
- Follow-up hardening backlog was split into
  `docs/security/PM008_SECURITY_DEFINER_FUTURE_HARDENING_TODO.md`.

## 2026-09-14 PM-003 / PM-011 Closure Update

Production modified during this update: `NO`.

Supabase remediation branch modified: `YES`, only project ref
`gydjrznapplpgvmrcymq`.

### Closed

- PM-003 closed on branch: the owner confirmed the previously identified
  branch-only rows were test data. The targeted rows were removed from the
  remediation branch only: machine
  `67fc0a05-82d8-48b2-87bb-452fc9926fd6`, machine consumable
  `52245c2e-4a6f-4b3f-a198-a0ca31eafedb`, refill
  `1cd91078-c7ec-4add-85a8-89531b793d5b`, and public ticket request log rows
  `9f0921db-33f7-46ba-aa08-6d97c571b315`,
  `e316e1d2-0857-4cf1-8004-586d1f171bdc`, and
  `1830a886-18b7-4270-8226-5623cb20b73a`.
- PM-011 closed by promotion-path decision: production promotion must use the
  official Supabase branch merge from `gydjrznapplpgvmrcymq` into
  `atpfgkhechvdijqnflnc`. Manual `supabase db push` or hand-applied
  production migration batches are not approved for this release because older
  local migration filenames differ from remote migration versions.

### Fresh Evidence

- The targeted PM-003 test rows were verified absent from the remediation
  branch after cleanup.
- Exact `count(*)` parity was verified between remediation branch and
  production for all 26 `public` base tables.
- The four previously drifting tables now match production:
  `machines=26`, `machine_consumables=119`, `refills=42`, and
  `public_ticket_request_log=3`.
- Branch migration history ends at
  `20260914082527 close_pm008_security_definer_allowlist`.
- Production migration history was read-only checked and currently ends at
  `20260828161317 control_center_remote_repair`.
- Promotion runbook added:
  `docs/security/SUPABASE_PRODUCTION_PROMOTION_RUNBOOK.md`.

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
| PM-001 | P0 | Closed On Branch | Fresh security advisors and catalog checks ran on `gydjrznapplpgvmrcymq`. No unaccepted ERROR/WARN findings remain for RLS disabled, security-definer views, anon GraphQL exposure, anon SECURITY DEFINER execution, mutable search paths, storage exposure, or public grants. | Keep this gate fresh: rerun immediately before production merge if the branch changes again. |
| PM-002 | P0 | Partially Closed / UAT In Progress | SQL role-matrix regression covers anon, authenticated operator, admin, cross-tenant denial, protected mutations, legacy refill denial, allowed assigned-operator refill, admin deletion of same-org `suggested` coverage assignments, and admin machine tank save with fill-percent trigger update. Manual admin UAT found and fixed blockers in coverage and machine tank configuration. Continue real app/JWT UAT with internal admin, technician, refill operator, assigned operator, and no-membership user before production. | RLS can fail silently by returning empty results or can allow too much. Production risk is either broken app screens for legitimate users or cross-tenant access that was not visible in SQL/catalog tests. |
| PM-003 | P1 | Closed On Branch | Owner confirmed the branch-only rows were test data. They were removed from the remediation branch only, and exact `count(*)` parity now matches production for all 26 `public` base tables. Reconfirm parity immediately before the actual production merge window. | If parity drifts again before merge, tests may no longer represent production. Treat the current closure as valid for this branch state, not as a permanent waiver. |
| PM-004 | P1 | Closed In Source / Release Values Required | `lib/app/env.dart` reads `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`; `flutter build web` smoke passed with non-sensitive dart defines. Production release must still supply production values in CI/manual build. | If production values are omitted or wrong during release, the app can fail at startup or point to the wrong Supabase project. |
| PM-005 | P1 | Closed On Branch / Prod Rollout Required | Branch `private.app_runtime_settings` contains `send_notifications_url` and `notifications_internal_secret`; values were verified by presence/length only. Production values must be set as part of the approved Supabase branch merge rollout. | If production runtime values are omitted or wrong, immediate notifications can stop or call the wrong endpoint. |
| PM-006 | P1 | Closed On Branch / Prod Rollout Required | Leaked-password protection was enabled on the remediation branch and the fresh security advisor no longer reports `auth_leaked_password_protection`. Confirm the setting after production promotion. | Production must be verified after merge because Auth settings are operational configuration, not only SQL migration state. |
| PM-007 | P1 | Closed / Accepted Residual | Team accepted authenticated GraphQL object visibility because Flutter has no GraphQL client and uses authenticated REST/Data API grants with RLS as the authorization boundary. Future removal requires disabling/limiting GraphQL in Supabase API settings or changing the app grant model. | Residual schema/object visibility remains for signed-in users. If future RLS changes are wrong, GraphQL can still be an alternate access path, so advisor output must stay reviewed before production promotion. |
| PM-008 | P1 | Closed On Branch | `20260914082527_close_pm008_security_definer_allowlist.sql` makes legacy `perform_refill(uuid)` service-role only. The regression SQL now enforces an exact authenticated SECURITY DEFINER allowlist and tests legacy refill denial, cross-tenant refill denial, and the live assigned-operator refill path. | Supabase may still warn because some app RPCs intentionally remain authenticated SECURITY DEFINER. The remaining risk is controlled by allowlist, body-level auth checks, and regression tests. |
| PM-009 | P1 | Closed On Branch | `supabase/tests/security_rls_regression.sql` passed against the branch via `psql` and now self-cleans fixtures before and after execution. | Keep this gate in the release checklist and rerun if any RLS, grant, function, or policy changes are added. |
| PM-010 | P2 | Closed Locally | Deno format and type checks passed for all Edge Function entrypoints. | Runtime secrets and third-party service behavior still require post-deploy smoke tests. |
| PM-011 | P2 | Closed / Path Locked | Production promotion path is locked to official Supabase branch merge from `gydjrznapplpgvmrcymq` into `atpfgkhechvdijqnflnc`. Manual `supabase db push` or hand-applied production migration batches are not approved. See `docs/security/SUPABASE_PRODUCTION_PROMOTION_RUNBOOK.md`. | The remaining risk is operational: production merge must not happen without explicit owner approval and post-merge verification. |
| PM-012 | P2 | Closed Locally | `.env.local` parsing was fixed and the invalid original line was backed up under `/private/tmp` with restrictive permissions. Supabase CLI branch checks now run from the repo. | Keep local env files out of git and avoid pasting secrets into terminal history. |

## Should Fix Soon

| ID | Severity | Status | What should be fixed | What could go wrong in production if not fixed |
| --- | --- | --- | --- | --- |
| PM-013 | P2 | Closed On Branch | Fresh performance advisors are INFO-only for this gate; prior RLS initplan and multiple permissive policy warnings are resolved on the branch. | Keep INFO performance findings in normal backlog; they are not a pre-main security blocker. |
| PM-014 | P2 | Closed On Branch | Duplicate indexes on `public.device_commands` and `public.tickets` are no longer present. A separate duplicate pair on `devices(device_id)` remains as a lower-priority follow-up. | Duplicate device index can add minor write overhead for device onboarding/updates; not tied to the ticket/device command duplicate-index blocker. |
| PM-015 | P2 | Closed / Accepted Residual | Team accepted `pg_net` in `public` after branch testing confirmed the extension does not support `SET SCHEMA`. Mitigations keep notification URL/secret in `private.app_runtime_settings` and prevent anon/authenticated direct access. | The advisor warning may remain. If future SQL exposes arbitrary outbound URL/header control, `pg_net` could become a misuse surface; keep this in periodic security review. |
| PM-016 | P3 | Closed In Repo | GitHub Actions secret-scan workflow and `tooling/secret_scan.sh` are present; local scan passed. | Extend patterns over time as new secret formats appear. |
| PM-017 | P3 | Closed In Repo | `supabase/.temp/*` is ignored and previously tracked temp files were removed from the git index. | Developers should still verify project refs before running destructive Supabase commands. |

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
7. Reconfirm documented PM-007/PM-015 residual-risk acceptance and PM-008
   allowlist before promotion.
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
