# PM-008 Future SECURITY DEFINER Hardening TODO

Status: future hardening backlog, not a current pre-main blocker.

Production modified: `NO`.

Current decision:

- PM-008 is closed on the remediation branch with an audited authenticated
  `SECURITY DEFINER` allowlist.
- Legacy `public.perform_refill(uuid)` is `service_role` only.
- The live operator refill path remains
  `public.perform_refill_consumable(uuid, public.consumable_type)`.
- `supabase/tests/security_rls_regression.sql` fails if a new public
  authenticated `SECURITY DEFINER` function appears outside the approved
  allowlist.

Future hardening options:

1. Move implementation bodies for app-facing privileged RPCs into a private
   schema and keep only narrow public wrappers.
2. Replace compatibility overloads for onboarding RPCs after confirming no old
   app builds or scripts use them.
3. Decide whether helper functions such as `client_has_no_machines` and
   `site_has_no_machines` should stay directly executable by `authenticated` or
   be moved behind private wrappers/policy-only functions.
4. Add function-by-function pgTAP or SQL tests for:
   - unauthenticated caller;
   - wrong role;
   - wrong organization;
   - wrong resource ownership or assignment;
   - successful same-tenant happy path.
5. Add a release checklist item requiring reviewers to update the PM-008
   allowlist whenever a new public `SECURITY DEFINER` RPC is introduced.
6. Evaluate whether the generic legacy `perform_refill(uuid)` can be dropped
   entirely after confirming no legacy clients or internal scripts still use it.
7. Consider shortening JWT lifetime or adding session freshness checks for
   high-impact RPCs such as Control Center command creation.

Owner recommendation:

- Primary owner: backend/security owner.
- Review cadence: before production promotion and after every new RPC/migration
  that creates or replaces a `SECURITY DEFINER` function.
