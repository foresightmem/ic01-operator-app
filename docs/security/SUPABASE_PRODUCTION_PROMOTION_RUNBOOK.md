# Supabase Production Promotion Runbook

Status: executed on 2026-09-14.

Production modified: `YES`.

Decision:

- Promote the remediation database changes using the official Supabase branch
  merge from `gydjrznapplpgvmrcymq` into production `atpfgkhechvdijqnflnc`.
- Do not use manual `supabase db push` or hand-applied production migration
  batches for this release.

Reason:

- The Supabase branch migration history is authoritative for this remediation.
- Several older local migration filenames differ from remote migration versions.
- Manual production application would increase the risk of duplicate,
  skipped, or out-of-order migrations.

Pre-merge checklist:

1. Confirm production merge approval from the owner.
2. Confirm branch project ref is `gydjrznapplpgvmrcymq`.
3. Confirm production project ref is `atpfgkhechvdijqnflnc`.
4. Confirm no production writes are pending outside the approved merge window.
5. Run Supabase security advisors on the branch.
6. Run Supabase performance advisors on the branch.
7. Run `supabase/tests/security_rls_regression.sql` against the branch.
8. Confirm PM-007, PM-008, and PM-015 accepted/closed statuses are still valid.
9. Confirm Edge Function secrets and runtime settings have production values
   planned, without printing secret values.
10. Confirm frontend production build defines `SUPABASE_URL` and
    `SUPABASE_PUBLISHABLE_KEY`.

Merge procedure:

1. Use Supabase branch merge for branch `gydjrznapplpgvmrcymq`.
2. Do not run separate manual SQL migrations against production unless the
   branch merge fails and the owner approves a recovery plan.
3. Deploy or verify Edge Functions as required by the branch merge result.
4. Apply production-only runtime configuration such as notification endpoint,
   notification secret, Auth leaked-password protection, and frontend build
   variables.

Post-merge verification:

1. Rerun security advisors on production.
2. Rerun performance advisors on production.
3. Verify migration history includes the remediation migrations.
4. Run smoke tests for:
   - operator login;
   - machine list/detail;
   - operator refill;
   - ticket read/update;
   - admin onboarding;
   - Control Center read path;
   - notification trigger path.
5. Verify no secret values are printed in logs or reports.

Rollback guidance:

- Prefer Supabase branch/backup restore guidance over ad hoc reverse SQL.
- If branch merge partially fails, stop and collect Supabase error output
  before making any manual production change.

Execution notes:

- Supabase branch merge from `gydjrznapplpgvmrcymq` to
  `atpfgkhechvdijqnflnc` completed successfully.
- Production migration history includes remediation migrations through
  `20260914132346 fix_ticket_protected_columns_trigger_definer`.
- Git `main` was fast-forwarded and pushed to `origin/main` at commit
  `e691db1`.
- Remaining manual/approved action: set production
  `private.app_runtime_settings.notifications_internal_secret` to match the
  production `NOTIFICATION_CRON_SECRET` Edge Function secret without exposing
  the secret value.
