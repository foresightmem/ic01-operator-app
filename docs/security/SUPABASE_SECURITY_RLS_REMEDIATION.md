# IC01 Supabase Security Remediation

## Environment

Git branch: `security-rls-remediation`

Supabase branch: `security-rls-remediation`

Production project ref: `atpfgkhechvdijqnflnc`

Remediation project ref: `gydjrznapplpgvmrcymq`

Production modified: `NO`

Branch baseline: `with_data=true`, persistent, `ACTIVE_HEALTHY`,
`FUNCTIONS_DEPLOYED`.

The earlier empty branch was renamed to `security-rls-remediation-empty`
(`mljqeycmofhtqhbrppiw`) during setup and is not used for remediation. The
latest branch list shows only `main` and the active data-cloned remediation
branch.

## Data Parity

Before applying remediation, the branch row counts matched main for all 26
`public` base tables. After applying remediation migrations, the same counts
were verified again. No production rows were copied manually, edited manually,
or deleted by the remediation work.

## Remediation Summary

| Finding | Severity | Status | Migration / Code | Verification |
| --- | --- | --- | --- | --- |
| SEC-001 | P0 | Fixed on branch | `20260911102427_emergency_enable_rls_on_public_exposed_tables.sql` | Advisors no longer report disabled RLS; catalog confirms RLS enabled/forced and anon denied |
| SEC-002 | P1 | Fixed on branch | `20260911102433_secure_views_and_api_grants.sql` | Advisors no longer report security-definer views; audited views have `security_invoker=true` |
| SEC-003 | P1 | Fixed for anon, accepted residual for authenticated | `20260911102433_secure_views_and_api_grants.sql` | Anon GraphQL exposure warning cleared; authenticated object visibility remains for app REST/Data API compatibility |
| SEC-004 | P1 | Fixed for anon, reviewed for authenticated | `20260911102447_secure_security_definer_execute_surface.sql` | Anon SECURITY DEFINER warning cleared; intended authenticated RPC allowlist remains |
| SEC-005 | P1 | Fixed on branch | `20260911102447_secure_security_definer_execute_surface.sql`, `20260911110112_align_policy_helpers_and_push_token_roles.sql` | Caller-supplied helper RPCs are no longer executable by anon/authenticated |
| SEC-006 | P2 | Fixed in source | `lib/app/env.dart`, `lib/main.dart` | `dart analyze` and `flutter test` passed; secret pattern scan found no legacy key in app/function source |
| SEC-007 | P1 | Fixed on branch | `20260911102440_lock_profile_and_ticket_mutations.sql` | `profiles` has no anon grants and no authenticated insert/update/delete grant |
| SEC-008 | P2 | Fixed on branch | `20260911102454_admin_functional_rls_and_push_tokens.sql`, `20260911110015_tighten_machine_table_grants.sql` | Admin coverage/config policies installed; direct machine insert/delete revoked |
| SEC-009 | P2 | Fixed on branch | `20260911102440_lock_profile_and_ticket_mutations.sql` | Ticket protected-column trigger installed; delete revoked |
| SEC-010 | P2 | Fixed on branch | `supabase/functions/public_maintenance_ticket/index.ts` | Function deployed; nonexistent machine smoke test returned `202` without `ticket_id` or internal code |
| SEC-011 | P2 | Fixed on branch | Modified Edge Functions | Hardened functions deployed; unauthenticated smoke tests return `401` without backend detail |
| SEC-012 | P3 | Fixed on branch | `20260911102454_admin_functional_rls_and_push_tokens.sql`, `20260911110112_align_policy_helpers_and_push_token_roles.sql`, `lib/core/services/push_notifications_service.dart` | Unique index and authenticated self policies installed; `dart analyze` and `flutter test` passed |
| SEC-013 | P2 | Verified | No schema change required | Storage has one private `firmware` bucket and no client-opening object policies |
| SEC-014 | P3 | Fixed on branch | Edge Function deployment metadata | Hardened functions deployed to remediation project ref with expected `verify_jwt` settings |
| SEC-015 | P3 | Fixed for this remediation | Branch recreation with data | Current branch is production-equivalent by schema/data baseline and has remediation migration history |
| SEC-016 | P3 | Open operational config | Supabase Auth settings | Advisor still reports leaked-password protection disabled |

## Applied Branch Migrations

- `emergency_enable_rls_on_public_exposed_tables`
- `secure_views_and_api_grants`
- `lock_profile_and_ticket_mutations`
- `secure_security_definer_execute_surface`
- `admin_functional_rls_and_push_tokens`
- `harden_function_search_paths`
- `tighten_machine_table_grants`
- `align_policy_helpers_and_push_token_roles`
- `drop_duplicate_machine_consumables_index`

## Edge Functions Deployed To Branch

- `device_telemetry_products`: `verify_jwt=false`, custom HMAC auth retained.
- `device_commands`: `verify_jwt=false`, custom HMAC auth retained.
- `send_notifications`: `verify_jwt=true`.
- `schedule_daily_notifications`: `verify_jwt=true`.
- `public_maintenance_ticket`: `verify_jwt=false`, public route retained with
  enumeration-safe response body.

## Verification Evidence

- Supabase branch status: `ACTIVE_HEALTHY`, `FUNCTIONS_DEPLOYED`,
  `with_data=true`.
- Row counts matched main before and after remediation for all 26 `public` base
  tables.
- Security advisors on the branch no longer report:
  - `policy_exists_rls_disabled`
  - `rls_disabled_in_public`
  - `security_definer_view`
  - `pg_graphql_anon_table_exposed`
  - `anon_security_definer_function_executable`
  - `function_search_path_mutable`
- Catalog checks confirmed audited views use `security_invoker=true` and anon
  has no `SELECT`.
- Catalog checks confirmed P0 tables have RLS enabled/forced and anon denied.
- Catalog checks confirmed `client_has_operator_access`,
  `site_has_operator_access`, and `machine_has_operator_access` are not
  executable by anon/authenticated.
- HTTP smoke tests against branch:
  - unauthenticated device functions return `401`;
  - unauthenticated notification functions return `401`;
  - public maintenance missing input returns `400`;
  - public maintenance nonexistent machine returns `202` without leaking ticket
    IDs or internal machine-not-found codes.
- `dart analyze lib/app/env.dart lib/main.dart
  lib/core/services/push_notifications_service.dart` passed.
- `flutter test` passed.
- Performance advisors were reviewed; the duplicate index introduced during
  remediation was removed. Remaining performance findings are pre-existing
  tuning items outside the security remediation scope.

## Remaining Risks

Authenticated GraphQL object visibility remains as an advisor warning because
the Flutter app currently uses authenticated REST/Data API grants on the same
tables and views. RLS is now the authorization boundary. To remove that warning,
disable GraphQL for this API surface or move app reads to RPCs/views with a
different grant model.

The `pg_net` extension remains in `public`; catalog inspection shows it is not
relocatable in this project. Do not force-move it without a dedicated migration
and rollback test.

Supabase Auth leaked-password protection is still disabled. Enable it in Auth
settings before production rollout.

The saved SQL regression file is present at
`supabase/tests/security_rls_regression.sql`, but direct `psql` execution from
this environment was blocked by redacted CLI database URLs. Catalog and HTTP
smoke tests were used instead.

## Production Deployment Plan

1. Test the Flutter app against branch `gydjrznapplpgvmrcymq` using the branch
   `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`.
2. Run authenticated user smoke tests for admin, technician, refill operator,
   and no-membership users.
3. Enable leaked-password protection in Supabase Auth settings.
4. Decide whether authenticated GraphQL schema visibility is acceptable or
   whether GraphQL should be disabled/isolated.
5. After manual approval only, merge the Git branch and plan a Supabase branch
   merge or migration window. Do not apply these changes to production without
   that approval.
