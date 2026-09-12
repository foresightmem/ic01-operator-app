# IC01 - Supabase Security & RLS Audit

Audit date: 2026-09-10  
Scope: IC01 / MAGMA Industrial Care Supabase implementation. Read-only audit only.  
Evidence base: repository source, local migrations, Supabase MCP `list_tables`, `list_migrations`, security advisors, and Supabase documentation. MCP raw SQL, bucket listing, storage config, and Edge Function listing were blocked by insufficient OAuth scope, so those live details are marked where relevant.

Current Supabase guidance consulted:

- https://supabase.com/docs/guides/database/postgres/row-level-security
- https://supabase.com/docs/guides/api/securing-your-api
- https://supabase.com/docs/guides/database/tables
- https://supabase.com/docs/guides/troubleshooting/deprecated-rls-features-Pm77Zs
- https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys

## 1. Executive Summary

Overall status: **🔴 NOT PRODUCTION SAFE**

The deployed Supabase project has multiple confirmed high-impact issues: five `public` tables have RLS disabled, Supabase reports they are fully exposed to `anon` and `authenticated`, and nine `public` views are deployed as security-definer views even though local fixtures intended several to be `security_invoker`. The strongest immediate risk is uncontrolled Data API/GraphQL exposure on public schema objects and possible RLS bypass through views.

Counts:

| Severity | Count |
| --- | ---: |
| P0 Critical | 1 |
| P1 High | 5 |
| P2 Medium | 6 |
| P3 Low | 4 |
| Functional blockers | 3 |

Production deployment is **not recommended** until P0/P1 findings are remediated and regression-tested. Multi-tenant isolation is not currently reliable: the live project has RLS disabled on operational tables, security-definer views are exposed, and the role/tenant model mixes `organization_id`, direct operator assignment, temporary assignment, and UI role checks.

## 2. System Authorization Model

Inferred model:

```text
auth.users.id
   |
   v
public.profiles.id
   | role: refill_operator | technician | admin | internal_admin
   | organization_id
   v
public.organizations
   |
   v
public.clients.organization_id
   |
   v
public.sites.client_id + organization_id
   |
   v
public.machines.site_id + assigned_operator_id + organization_id
   |
   +--> public.machine_consumables
   +--> public.refills
   +--> public.tickets / public.ticket_events / public.visits
   +--> public.devices / telemetry / commands
```

Tenant ownership is intended to be `organization_id` for `profiles`, `clients`, `sites`, and `machines` (`20260803150129...sql:19-74`). Operators also gain access through `machines.assigned_operator_id` and confirmed `temp_machine_assignments` (`20260803150129...sql:199-297`). The frontend uses `profiles.role` for routing and page guards (`lib/core/auth/app_role_service.dart:24-49`), but database policies/functions must remain the real security boundary.

## 3. Roles & Permissions Matrix

| Role | Resource | SELECT | INSERT | UPDATE | DELETE | RPC | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| anon/public | public ticket form | No direct table access intended | via Edge Function only | No | No | indirectly service-only `create_public_maintenance_ticket` | `public_maintenance_ticket` has `verify_jwt=false` in `config.toml:2-6`. |
| anon/public | RLS-off tables | Confirmed exposed | Confirmed exposed | Confirmed exposed | Confirmed exposed | N/A | Supabase MCP reports RLS disabled tables fully exposed to anon/authenticated. |
| refill_operator | assigned clients/sites/machines | Intended own/effective assignment only | onboarding RPC | ticket/status/refill own workflows | onboarding client delete if created and empty | onboarding/refill RPCs | Mixed ownership predicates. |
| technician | tickets/clients/sites/machines | Broad org or role based | tickets | tickets | No direct evidence | likely maintenance workflow | `tickets_select_by_role` grants all technicians ticket visibility in local policy. |
| admin | organization operational data | Broad organization | onboarding/admin operations | admin operations | constrained delete RPC | many RPCs | Local policies often check `current_app_role() = 'admin'`. |
| internal_admin | Control Center telemetry/devices | Control Center only | command RPC | command state via Edge/device flows | No direct app path | Control Center RPCs | Uses separate `internal_admin` role gate. |
| service_role | backend Edge Functions | Full | Full | Full | Full | Full | Must remain server-only; Edge Functions use env var service role. |

## 4. Database Security Inventory

| Object | Type | Exposed | RLS | anon | authenticated | Policies | Risk |
| --- | --- | ---: | ---: | --- | --- | --- | --- |
| `profiles` | table | Yes | Yes | GraphQL-visible per advisor | SELECT granted/visible | `profiles_select_own_or_admin` | P2 role/profile enumeration questions |
| `clients`, `sites`, `machines` | tables | Yes | Yes | anon revoked locally | SELECT granted | scope policies by role/org/operator | P2 mixed tenant model |
| `refills` | table | Yes | Yes | GraphQL-visible per advisor | SELECT granted | own/admin select | P2 broad grants; limited live policy detail |
| `tickets`, `ticket_events` | tables | Yes | Yes | anon revoked locally | SELECT/UPDATE/INSERT on tickets | role/assignment policies | P2 ownership mutation needs tests |
| `visits` | table | Yes | **No** | Exposed per MCP/advisor | Exposed per MCP/advisor | policies exist but inactive | **P0 SEC-001** |
| `beverage_recipes`, `beverage_recipe_items` | tables | Yes | **No** | Exposed per MCP/advisor | Exposed per MCP/advisor | none seen | **P0 SEC-001** |
| `dispense_events` | table | Yes | **No** | Exposed per MCP/advisor | Exposed per MCP/advisor | none seen | **P0 SEC-001** |
| `firmware_versions` | table | Yes | **No** | Exposed per MCP/advisor | Exposed per MCP/advisor | none seen | **P0 SEC-001** |
| `organizations` | table | Yes | Yes | revoked locally | revoked locally | none | P2 functional/visibility ambiguity |
| `public_ticket_request_log` | table | Yes | Yes | revoked locally | revoked locally | none | OK if service-only |
| device telemetry tables | tables | Yes | Yes | anon revoked locally | SELECT granted, RLS internal-admin | internal-admin select | P2 via service-role Edge Functions |
| `client_*`, `machine_*`, `operator_ranking`, `ticket_list` | views | Yes | N/A | many anon-visible per advisor | visible | live security-definer warnings | **P1 SEC-002** |
| SECURITY DEFINER RPCs | functions | Yes | N/A | some anon-executable | many authenticated-executable | function body checks | P1/P2, see RPC audit |
| Storage | storage | Unknown | storage tables RLS on | bucket listing blocked | bucket listing blocked | not verified | P2 needs verification |

## 5. Findings

### SEC-001 - Public schema tables have RLS disabled

**Severity:** P0  
**Type:** RLS / Data API / Grant  
**Functional impact:** None  
**Affected object:** `public.visits`, `public.beverage_recipes`, `public.beverage_recipe_items`, `public.dispense_events`, `public.firmware_versions`  
**Affected roles:** `anon`, `authenticated`  
**Status:** Confirmed

#### Problem

Five tables in the exposed `public` schema have RLS disabled. Supabase MCP explicitly reported these are fully exposed to the `anon` and `authenticated` roles used by client libraries.

#### Evidence

- MCP `list_tables`: `visits`, `beverage_recipes`, `beverage_recipe_items`, `dispense_events`, and `firmware_versions` returned `rls_enabled:false`.
- MCP advisory `rls_disabled_in_public`: all five are public with RLS disabled.
- MCP advisory `policy_exists_rls_disabled`: `public.visits` has policies `visits_insert_admin_or_own` and `visits_select_admin_or_own`, but RLS is not enabled.
- Local migration creates visits policies but does not enable RLS in that block (`20260724095612_fix_public_ticket_route_admin_rls.sql:79-105`).

#### Attack / Failure Scenario

An unauthenticated caller with the public anon key may read or modify all rows in these tables through the Data API or GraphQL. For `visits` and `dispense_events`, this can expose or alter operational history across tenants.

#### Root Cause

RLS and grants were treated separately in local migrations for some tables. Policies on `visits` exist but are inactive because RLS is disabled.

#### Recommended Remediation

PROPOSED - NOT EXECUTED: enable RLS on all exposed tables, revoke unnecessary `anon` grants, and add minimal policies. Do this carefully because enabling RLS without policies will block legitimate workflows.

#### Dependencies

None. This is emergency work.

#### Verification Test

As anon, SELECT/INSERT/UPDATE/DELETE on each table must be denied. As the intended role, only explicitly allowed operations should succeed; Tenant A must not see or modify Tenant B rows.

### SEC-002 - Deployed views are security-definer and can bypass RLS

**Severity:** P1  
**Type:** View / RLS bypass  
**Functional impact:** None  
**Affected object:** `client_machines`, `machine_effective_assignment`, `machine_effective_consumables`, `operator_ranking`, `client_states_effective`, `client_states`, `client_states_v2`, `machine_states`, `machine_states_v2`  
**Affected roles:** `anon`, `authenticated`  
**Status:** Confirmed

#### Problem

Supabase security advisors report nine `public` views defined as security-definer. Supabase documentation states views can bypass underlying table RLS unless `security_invoker=true` is used on Postgres 15+.

#### Evidence

- MCP advisor `security_definer_view` lists the nine affected views.
- Local fixture intended `security_invoker=true` for key views (`fixtures/.../20260724090000_core_schema_baseline.sql:326-474`).
- Frontend reads these views directly: dashboard reads `client_states_effective` (`lib/features/dashboard/presentation/dashboard_page.dart:145-149`), machine detail reads `machine_effective_consumables`/`machine_effective_assignment` (`lib/features/machines/presentation/machine_detail_page.dart:221-294`).
- Project Postgres version from `.temp/postgres-version`: `17.6.1.044`, so `security_invoker` is supported.

#### Attack / Failure Scenario

If anon or authenticated can SELECT the view, the view may run with owner privileges and return rows the caller could not read from base tables. Tenant A could retrieve Tenant B client/machine state through a view.

#### Root Cause

Live deployed view options differ from local expected state, or later migrations recreated views without `security_invoker`.

#### Recommended Remediation

PROPOSED - NOT EXECUTED: alter/recreate exposed views with `security_invoker=true` or revoke all access to views that should not be direct APIs.

#### Dependencies

SEC-003, SEC-004.

#### Verification Test

As Tenant A operator, select from each view and verify only assigned/effective Tenant A rows. As anon, verify all non-public views are denied.

### SEC-003 - GraphQL/Data API object exposure is broader than intended

**Severity:** P1  
**Type:** Grant / API exposure  
**Functional impact:** None  
**Affected object:** 21 anon-visible and 34 authenticated-visible objects from advisor  
**Affected roles:** `anon`, `authenticated`  
**Status:** Confirmed

#### Problem

Supabase advisors report many tables/views visible in the GraphQL schema because `anon` or `authenticated` have `SELECT`. Visibility includes non-public operational objects and security-definer views.

#### Evidence

- Advisor `pg_graphql_anon_table_exposed`: 21 objects, including `profiles`, `refills`, `temp_machine_assignments`, `visits`, `notification_outbox`, and multiple views.
- Advisor `pg_graphql_authenticated_table_exposed`: 34 objects, including device tables and all major operational tables.
- Local migrations grant broad SELECT to authenticated on core objects (`20260724092921...sql:520-526`, `20260828161317...sql:260-265`).

#### Attack / Failure Scenario

Even where RLS blocks rows, broad grants expose schema shape and alternate query paths. Combined with RLS-off tables or security-definer views, this can become direct cross-tenant data access.

#### Root Cause

Object grants were not minimized after adding RLS and views.

#### Recommended Remediation

PROPOSED - NOT EXECUTED: inventory actual client needs, revoke `anon` SELECT broadly, and grant `authenticated` only where the app uses direct table/view access.

#### Dependencies

SEC-001, SEC-002.

#### Verification Test

Run anon/authenticated GraphQL introspection and REST requests; only intentional objects should be visible and queryable.

### SEC-004 - SECURITY DEFINER functions are broadly executable

**Severity:** P1  
**Type:** RPC / SECURITY DEFINER  
**Functional impact:** None  
**Affected object:** 2 anon-executable and 27 authenticated-executable security-definer functions per advisor  
**Affected roles:** `anon`, `authenticated`  
**Status:** Confirmed

#### Problem

Supabase advisors report SECURITY DEFINER functions exposed through RPC. SECURITY DEFINER bypasses normal RLS, so every exposed function body must perform explicit auth and tenant checks.

#### Evidence

- Advisor `anon_security_definer_function_executable`: `perform_refill(uuid)` and `register_dispense(...)` are anon-callable.
- Advisor `authenticated_security_definer_function_executable`: 27 functions, including onboarding, Control Center, refill, role helper, and access helper RPCs.
- Local migrations show many functions set `security definer` and `set row_security = off` (`20260803150129...sql:129-181`, `314-618`; `20260828161317...sql:341-920`).

#### Attack / Failure Scenario

If any callable function misses an `auth.uid()`/role/tenant check, callers can perform privileged reads/writes that bypass table RLS. The anon-callable refill/dispense functions are especially dangerous unless truly intended and cryptographically authenticated.

#### Root Cause

Privileged helper/RPC pattern is widely used. Some functions are valid by design, but broad `EXECUTE` surface increases blast radius.

#### Recommended Remediation

PROPOSED - NOT EXECUTED: revoke default `PUBLIC` execute on all functions, keep only role-specific grants, move internal helpers to a private schema, and review anon-callable RPCs first.

#### Dependencies

SEC-005, SEC-006.

#### Verification Test

For every sensitive RPC: anon denied unless explicitly public; authenticated non-owner denied; Tenant A cannot pass Tenant B IDs; intended admin/internal_admin succeeds.

### SEC-005 - SECURITY DEFINER access helpers accept arbitrary user IDs

**Severity:** P1  
**Type:** RPC / Architecture  
**Functional impact:** None  
**Affected object:** `client_has_operator_access`, `site_has_operator_access`, `machine_has_operator_access`  
**Affected roles:** `authenticated`  
**Status:** Confirmed

#### Problem

Access helper functions are SECURITY DEFINER, bypass RLS, executable by authenticated users, and accept `p_user_id` from the caller.

#### Evidence

- Functions accept `p_user_id` (`20260803150129...sql:199-227`, `244-270`, `272-297`).
- They are `security definer`, `row_security = off` (`20260803150129...sql:206-208`, `251-253`, `279-281`).
- They are granted to authenticated (`20260803150129...sql:302-312`).

#### Attack / Failure Scenario

A signed-in caller can ask whether another user has access to a client/site/machine, enabling relationship enumeration. If reused later in policies or app code with caller-supplied IDs, it can become an authorization bypass.

#### Root Cause

Internal policy helper functions were exposed as authenticated RPCs instead of being private or deriving the user from `auth.uid()`.

#### Recommended Remediation

PROPOSED - NOT EXECUTED: move helpers to a private schema or revoke client execute; create caller-safe wrappers that always use `(select auth.uid())`.

#### Dependencies

SEC-004.

#### Verification Test

As User A, direct RPC calls with User B's UUID must be denied or return no information.

### SEC-006 - Legacy anon key hard-coded in frontend source

**Severity:** P2  
**Type:** Secret / API key hygiene  
**Functional impact:** None  
**Affected object:** `lib/app/env.dart`  
**Affected roles:** public clients  
**Status:** Confirmed

#### Problem

The Flutter app contains a hard-coded Supabase URL and legacy anon JWT. The anon key is not a secret, but committing environment-specific keys complicates rotation and encourages treating the key as stable infrastructure.

#### Evidence

- `lib/app/env.dart:13-17` defines the Supabase URL and anon key inline. The file comments warn not to commit it publicly.
- `lib/main.dart:39-40` initializes Supabase using those constants.
- Supabase currently recommends publishable keys for browsers/mobile and secret keys for server workloads.

#### Attack / Failure Scenario

Anyone with the app binary or repo can use the anon key, so any over-exposed table/function is externally reachable. This amplifies SEC-001 through SEC-004.

#### Root Cause

Environment configuration is compiled into frontend source rather than injected per environment.

#### Recommended Remediation

PROPOSED - NOT EXECUTED: migrate frontend to publishable keys and environment/flavor injection; rotate legacy anon/service keys after exposure is reduced.

#### Dependencies

SEC-001 through SEC-004.

#### Verification Test

Build artifact should include only the intended publishable key; no service/secret keys should appear in repo or frontend bundle.

### SEC-007 - `profiles.role` is the central authorization source with no visible self-update guard

**Severity:** P1  
**Type:** Auth / Privilege escalation  
**Functional impact:** None  
**Affected object:** `public.profiles`  
**Affected roles:** `authenticated`  
**Status:** Needs Verification

#### Problem

Roles are stored in `public.profiles.role`, and app routing trusts that table. The audit could verify SELECT policies but did not find local UPDATE/INSERT policies for profiles. Live SQL policy introspection was blocked, so self-update exposure needs direct verification.

#### Evidence

- Role enum in app includes `refill_operator`, `technician`, `admin`, `internal_admin` (`lib/core/auth/app_role_service.dart:3-12`).
- App loads role from `profiles` for routing (`lib/core/auth/app_role_service.dart:24-49`).
- Local migration adds role constraint including `internal_admin` (`20260828161317...sql:9-31`).
- No local migration hit showed `profiles` UPDATE policies; live SQL introspection was unavailable.

#### Attack / Failure Scenario

If an authenticated user can update their own `profiles.role`, they can become admin or internal_admin and pass SECURITY DEFINER RPC gates.

#### Root Cause

Authorization source is mutable application data. The audit could not prove write grants/policies are locked down.

#### Recommended Remediation

PROPOSED - NOT EXECUTED: ensure no client role can update `role` or `organization_id`; administer roles only through a secured backend workflow.

#### Dependencies

SEC-004.

#### Verification Test

As a refill_operator, attempt `UPDATE profiles SET role='admin' WHERE id=auth.uid()` and `organization_id` mutation in a non-production clone; both must be denied.

### SEC-008 - Admin UI operations rely on frontend role checks and likely lack DB policies

**Severity:** P2  
**Type:** RLS / Functional authorization  
**Functional impact:** FUNCTIONAL-BLOCKER  
**Affected object:** `operator_unavailability`, `temp_machine_assignments`, `machines`, `machine_consumables`  
**Affected roles:** `admin`  
**Status:** Confirmed for code path; DB result needs live policy verification

#### Problem

Admin pages perform direct table inserts/updates/deletes after checking the user's role in the UI. Local migrations do not show matching policies for some objects, and MCP says `organizations` has no policies and `operator_unavailability`/`temp_machine_assignments` are GraphQL-visible.

#### Evidence

- Coverage page UI role check (`admin_coverage_page.dart:40-52`) then direct inserts/deletes/reads (`admin_coverage_page.dart:122-132`, `171-177`, `331`).
- Coverage plan updates `temp_machine_assignments` directly (`admin_coverage_plan_page.dart:164-188`).
- Machine config page updates `machines.temperature_mode` and upserts `machine_consumables` (`admin_machine_config_page.dart:453-479`).
- Local policy hits show `machine_consumables` admin policies (`20260803150129...sql:711-765`) but no local direct `machines` update policy in reviewed migrations.

#### Attack / Failure Scenario

If DB policies are missing, legitimate admin workflows fail. If broad policies are later added casually to fix UI errors, non-admin users may gain administrative operations.

#### Root Cause

Admin authorization is partly implemented in the frontend instead of consistently as database-enforced policies/RPCs.

#### Recommended Remediation

PROPOSED - NOT EXECUTED: implement DB-level admin policies or narrowly-scoped RPCs for coverage and machine configuration, deriving role/org from `auth.uid()`.

#### Dependencies

SEC-007.

#### Verification Test

Admin in Tenant A can perform intended operations only within Tenant A; refill_operator/technician cannot call the same writes even if they bypass navigation.

### SEC-009 - Ticket UPDATE policy may permit ownership/assignment mutation

**Severity:** P2  
**Type:** RLS / IDOR  
**Functional impact:** FUNCTIONAL-BLOCKER possible  
**Affected object:** `public.tickets`  
**Affected roles:** `technician`, assigned operator  
**Status:** Needs Verification

#### Problem

The later ticket update policy allows updates if the row is admin/technician-owned or assigned to the caller, but the `WITH CHECK` repeats the same role/assignment predicate and does not visibly lock tenant/resource columns.

#### Evidence

- Policy `tickets_update_by_role_or_assignment` (`20260724103842...sql:11-24`).
- Ticket detail updates assignment and status directly (`ticket_detail_page.dart:126-141`).
- Tickets include `machine_id`, `client_id`, `site_id`, `assigned_technician_id`, `assigned_operator_id` from public ticket creation (`20260724092921...sql:387-411`).

#### Attack / Failure Scenario

An assigned operator or technician might update a ticket they can see and change assignment/resource fields unless column privileges or additional policies block it.

#### Root Cause

RLS checks row eligibility but does not constrain which columns are mutable or ensure ownership fields remain within the same tenant.

#### Recommended Remediation

PROPOSED - NOT EXECUTED: add explicit `WITH CHECK` invariants and/or column-level grants/RPCs so status transitions cannot mutate tenant/resource ownership.

#### Dependencies

SEC-007.

#### Verification Test

Assigned Tenant A operator can move allowed status forward; attempts to set `client_id`, `site_id`, `machine_id`, `assigned_operator_id`, or `assigned_technician_id` to Tenant B values are denied.

### SEC-010 - Public maintenance endpoint is intentionally unauthenticated and service-role backed

**Severity:** P2  
**Type:** Edge Function / Public API  
**Functional impact:** None  
**Affected object:** `public_maintenance_ticket` Edge Function, `create_public_maintenance_ticket` RPC  
**Affected roles:** anon/public  
**Status:** Confirmed

#### Problem

The endpoint is intentionally public and uses a service-role client. It validates reason, normalizes machine code, deduplicates open tickets, and logs rate data, but it can still be abused for machine-code probing and ticket spam within the rate limit.

#### Evidence

- `verify_jwt=false` (`supabase/config.toml:2-6`).
- Edge Function uses `SUPABASE_SERVICE_ROLE_KEY` (`public_maintenance_ticket/index.ts:19-23`).
- Public CORS allows all origins (`public_maintenance_ticket/index.ts:26-31`).
- Rate limit is in-function: 12 requests / 10 minutes (`public_maintenance_ticket/index.ts:34-84`).
- RPC returns `machine_not_found` when code is unknown (`20260724092921...sql:334-335`).
- RPC execute is service-role only locally (`20260724092921...sql:476-479`).

#### Attack / Failure Scenario

Attackers can enumerate valid machine codes by observing `machine_not_found` vs successful/duplicate responses and create tickets for known machines.

#### Root Cause

Public reporting is a product requirement, but the response surface confirms machine existence.

#### Recommended Remediation

PROPOSED - NOT EXECUTED: make public responses less enumerable, add CAPTCHA/turnstile or stronger abuse controls, and monitor rate-log volume.

#### Dependencies

SEC-001.

#### Verification Test

Unknown and valid-but-rate-limited codes should not disclose more than necessary; repeated requests should be throttled per IP/device fingerprint.

### SEC-011 - Device Edge Functions return raw backend error details

**Severity:** P2  
**Type:** Edge Function / Information leakage  
**Functional impact:** None  
**Affected object:** `device_telemetry_products`, `device_commands`, notification functions  
**Affected roles:** device/public callers with endpoint access  
**Status:** Confirmed

#### Problem

Several service-role Edge Functions return raw Supabase error objects or exception strings in HTTP responses.

#### Evidence

- `device_telemetry_products/index.ts:125-129`, `162-166`, `179-182`, `206-210`, `224-227`.
- `device_commands/index.ts:110-114`, `129-133`, `204-207`, `217-220`.
- `schedule_daily_notifications/index.ts:124-128`, `166-169`.
- `send_notifications/index.ts:235-239`, `336-339`.

#### Attack / Failure Scenario

An attacker with endpoint reach can trigger malformed requests and collect schema/table/error details useful for later attacks.

#### Root Cause

Internal diagnostics are returned to clients instead of being logged server-side and mapped to generic responses.

#### Recommended Remediation

PROPOSED - NOT EXECUTED: return generic error codes to callers; keep detailed errors only in logs with request IDs.

#### Dependencies

None.

#### Verification Test

Malformed input and backend failures return generic response bodies with no table names, SQL state, stack traces, or secret-adjacent values.

### SEC-012 - Notification token upsert may be functionally blocked by conflict target

**Severity:** P3  
**Type:** RLS / Functional authorization  
**Functional impact:** FUNCTIONAL-BLOCKER  
**Affected object:** `public.push_tokens`  
**Affected roles:** authenticated  
**Status:** Needs Verification

#### Problem

Client upserts `push_tokens` with conflict target `device_id,platform`, while local table definition in `docs/NOTIFICHE_DB.sql` only shows primary key `id`; no unique constraint on `(device_id, platform)` was seen in reviewed migration/docs.

#### Evidence

- Client upsert: `push_notifications_service.dart:183-188`.
- RLS policies allow own insert/update (`docs/NOTIFICHE_DB.sql:91-106`).
- Local table DDL excerpt does not show unique `(device_id, platform)` (`docs/NOTIFICHE_DB.sql:12-24`, not quoted here).

#### Attack / Failure Scenario

Legitimate token registration may fail if the conflict target does not exist. If a broad unique constraint is later added without `user_id`, one user/device tuple could interfere with another user's token.

#### Root Cause

Application upsert contract and database uniqueness contract are not clearly aligned.

#### Recommended Remediation

PROPOSED - NOT EXECUTED: verify live indexes; use a unique key that matches tenancy, such as `(user_id, device_id, platform)`, with RLS preserving `user_id = auth.uid()`.

#### Dependencies

None.

#### Verification Test

Same user can refresh a token idempotently; different users cannot overwrite each other's token rows.

### SEC-013 - Storage live configuration and bucket policies could not be verified

**Severity:** P2  
**Type:** Storage  
**Functional impact:** None  
**Affected object:** Supabase Storage  
**Affected roles:** unknown  
**Status:** Needs Verification

#### Problem

MCP storage bucket/config listing failed with insufficient scope. Repository search found no direct Flutter storage API usage, but firmware docs mention firmware `storage_path`.

#### Evidence

- MCP `list_storage_buckets` and `get_storage_config` returned insufficient scope.
- Repository search found no `supabase.storage.from(...)` usage in app/function code.
- `firmware_versions` includes `storage_path` per MCP table metadata and firmware docs mention storage.

#### Attack / Failure Scenario

If firmware or operational files are in public buckets, attackers could read or replace assets depending on bucket and `storage.objects` policies.

#### Root Cause

Audit permissions did not include storage management scope.

#### Recommended Remediation

PROPOSED - NOT EXECUTED: run a storage-specific policy audit with bucket listing scope; verify public/private flags and `storage.objects` policies.

#### Dependencies

SEC-001 for `firmware_versions`.

#### Verification Test

Anon cannot list or download private firmware/tenant files; authorized signed URLs work only for intended users/devices.

### SEC-014 - Edge Function deployment/JWT configuration could not be fully verified live

**Severity:** P3  
**Type:** Edge Function  
**Functional impact:** None  
**Affected object:** all Supabase Edge Functions  
**Affected roles:** anon, authenticated, service_role  
**Status:** Needs Verification

#### Problem

Local code defines several Edge Functions, but MCP live Edge Function listing failed with insufficient scope. `config.toml` only declares `public_maintenance_ticket` and `places_autocomplete`, leaving deployment/JWT config for other functions unclear.

#### Evidence

- Local directories: `device_commands`, `device_telemetry`, `device_telemetry_products`, `places_autocomplete`, `public_maintenance_ticket`, `schedule_daily_notifications`, `send_notifications`.
- `config.toml:2-11` explicitly configures only `public_maintenance_ticket` and `places_autocomplete`.
- MCP `list_edge_functions` returned insufficient scope.

#### Attack / Failure Scenario

Functions intended to be cron/device-only may be deployed with default public/JWT settings different from local assumptions.

#### Root Cause

Function deployment state is not represented completely in local config available to this audit.

#### Recommended Remediation

PROPOSED - NOT EXECUTED: audit deployed functions with management scope and document per-function auth requirements.

#### Dependencies

None.

#### Verification Test

Each endpoint returns expected 401/405 for unauthenticated callers, and only intended device/cron/auth callers can execute privileged operations.

### SEC-015 - Migration state drift and traceability gaps

**Severity:** P3  
**Type:** Architecture / Drift  
**Functional impact:** None  
**Affected object:** migrations and deployed schema  
**Affected roles:** maintainers  
**Status:** Confirmed

#### Problem

Live migration versions do not exactly match several local filenames, and live advisors contradict local fixture intent for security-invoker views.

#### Evidence

- Live MCP migrations include `20260724100230 public_maintenance_tickets_and_admin_rls`, while local file is `20260724092921_public_maintenance_tickets.sql`.
- Live includes `20260825124730 refill_productivity_kpi`, while local file is `20260825091804_refill_productivity_kpi.sql`.
- Local fixtures define `security_invoker=true` views; live advisors report security-definer views.

#### Attack / Failure Scenario

Future remediation may target local SQL that is not the exact production definition, causing incomplete fixes or regressions.

#### Root Cause

Schema drift or migration renaming after deployment.

#### Recommended Remediation

PROPOSED - NOT EXECUTED: pull or dump the live schema into a controlled artifact before remediation and reconcile migration history.

#### Dependencies

None.

#### Verification Test

Compare live `pg_policy`, `pg_proc`, `pg_views`, grants, and local migrations before applying security migrations.

### SEC-016 - Supabase Auth leaked-password protection disabled

**Severity:** P3  
**Type:** Auth hardening  
**Functional impact:** None  
**Affected object:** Supabase Auth  
**Affected roles:** all users  
**Status:** Confirmed

#### Problem

Supabase advisor reports leaked-password protection is disabled.

#### Evidence

- MCP advisor `auth_leaked_password_protection`: "Leaked Password Protection Disabled".

#### Attack / Failure Scenario

Users may choose compromised passwords, increasing account takeover risk.

#### Root Cause

Auth password hardening setting is not enabled.

#### Recommended Remediation

PROPOSED - NOT EXECUTED: enable leaked password protection and consider stricter password rules for admin/internal_admin accounts.

#### Dependencies

None.

#### Verification Test

Known compromised password should be rejected in a test account signup/password-change flow.

## 6. RLS Coverage Matrix

| Table | SELECT | INSERT | UPDATE | DELETE | Tenant isolation | Issues |
| --- | --- | --- | --- | --- | --- | --- |
| `profiles` | ⚠️ questionable | ⚠️ unknown | ⚠️ unknown | ⚠️ unknown | org + self/admin | SEC-007 |
| `organizations` | ➖ intentionally unavailable | ➖ intentionally unavailable | ➖ intentionally unavailable | ➖ intentionally unavailable | none visible | no policies; may be intentional |
| `clients` | ⚠️ questionable | ➖ RPC | ➖ RPC | ➖ RPC | org + created/effective assignment | mixed model |
| `sites` | ⚠️ questionable | ➖ RPC | ➖ RPC | ➖ RPC | org + client/site/operator | mixed model |
| `machines` | ⚠️ questionable | ➖ RPC | ⚠️ questionable | ⚠️ unknown | org + assignment | SEC-008 |
| `machine_consumables` | ⚠️ questionable | ⚠️ admin policy | ⚠️ admin policy | ➖ none visible | via machine org | upsert requires SELECT+INSERT+UPDATE |
| `refills` | ⚠️ questionable | ➖ RPC | ⚠️ unknown | ⚠️ unknown | operator/admin/org in RPC | direct exposure warning |
| `tickets` | ⚠️ questionable | ⚠️ admin/technician | ⚠️ questionable | ➖ none visible | role/assignment | SEC-009 |
| `ticket_events` | ⚠️ questionable | ➖ trigger only | ➖ none visible | ➖ none visible | via ticket access | OK if trigger-only |
| `visits` | ❌ vulnerable/missing | ❌ vulnerable/missing | ❌ vulnerable/missing | ❌ vulnerable/missing | none, RLS off | SEC-001 |
| `operator_unavailability` | ⚠️ unknown | ⚠️ unknown | ⚠️ unknown | ⚠️ unknown | not verified | SEC-008 |
| `temp_machine_assignments` | ⚠️ unknown | ⚠️ unknown | ⚠️ unknown | ⚠️ unknown | not verified | SEC-008 |
| `beverage_recipes` | ❌ vulnerable/missing | ❌ vulnerable/missing | ❌ vulnerable/missing | ❌ vulnerable/missing | none, RLS off | SEC-001 |
| `beverage_recipe_items` | ❌ vulnerable/missing | ❌ vulnerable/missing | ❌ vulnerable/missing | ❌ vulnerable/missing | none, RLS off | SEC-001 |
| `dispense_events` | ❌ vulnerable/missing | ❌ vulnerable/missing | ❌ vulnerable/missing | ❌ vulnerable/missing | none, RLS off | SEC-001 |
| `firmware_versions` | ❌ vulnerable/missing | ❌ vulnerable/missing | ❌ vulnerable/missing | ❌ vulnerable/missing | none, RLS off | SEC-001 |
| device tables | ⚠️ questionable | ➖ service-role functions | ➖ service-role functions | ⚠️ unknown | internal_admin RLS for reads | SEC-004, SEC-011 |
| notification tables | ⚠️ questionable | ⚠️ own/service | ⚠️ own/service | ➖ service | user_id | SEC-012 |

## 7. RPC / Function Audit

| Function | Security Mode | Callable By | Auth Check | Tenant Check | Risk | Finding |
| --- | --- | --- | --- | --- | --- | --- |
| `create_public_maintenance_ticket` | SECURITY DEFINER | service_role locally | Edge-only public flow | machine lookup | Medium | SEC-010 |
| `current_app_role` | SECURITY DEFINER | authenticated | `auth.uid()` lookup | none | Medium | SEC-004 |
| `current_app_organization_id` | SECURITY DEFINER | authenticated | `auth.uid()` lookup | returns org | Medium | SEC-004 |
| `onboarding_actor_context` | SECURITY DEFINER | authenticated | `auth.uid()` | role + org | Medium | SEC-004 |
| `client/site/machine_has_operator_access` | SECURITY DEFINER | authenticated | caller supplies user id | assignment | High | SEC-005 |
| `create_client_with_primary_site` | SECURITY DEFINER | authenticated | yes | org | Medium | SEC-004 |
| `add_site_to_client` | SECURITY DEFINER | authenticated | yes | org + allowed | Medium | SEC-004 |
| `create_machine_for_site` | SECURITY DEFINER | authenticated | yes | org + assigned operator org | Medium | SEC-004 |
| `delete_onboarding_client` | SECURITY DEFINER | authenticated | yes | org + created/admin | Medium | SEC-004 |
| `perform_refill_consumable` | SECURITY DEFINER | authenticated | yes | org + assignment | Medium | SEC-004 |
| `get_refill_productivity_kpi` | SECURITY DEFINER | authenticated | admin | org | Medium | SEC-004 |
| Control Center read RPCs | SECURITY DEFINER | authenticated | internal_admin helper | role gate | Medium | SEC-004 |
| `create_control_center_device_command` | SECURITY DEFINER | authenticated | internal_admin helper | global/internal | High impact if role compromised | SEC-004, SEC-007 |
| `perform_refill`, `register_dispense` | SECURITY DEFINER | anon/auth per advisor | not verified locally | not verified | High | SEC-004 |

## 8. Views Audit

Advisor-confirmed security-definer views: `client_machines`, `machine_effective_assignment`, `machine_effective_consumables`, `operator_ranking`, `client_states_effective`, `client_states`, `client_states_v2`, `machine_states`, `machine_states_v2`.

Local fixtures intended `security_invoker=true` for several of these views, but live state contradicts that. `ticket_list` is created locally with `security_invoker=true` and anon revoked (`20260724092921...sql:481-518`), but live view options could not be independently queried because raw SQL was blocked.

## 9. Storage Audit

Storage system tables have RLS enabled per MCP `list_tables`. Bucket listing, storage config, and object policies could not be fetched due insufficient MCP scope. Repository search found no direct Supabase Storage client usage, but `firmware_versions.storage_path` and firmware docs imply storage may be part of firmware distribution. Treat storage as **not proven secure** until bucket policy audit is run.

## 10. Edge Function Audit

| Function | Local auth model | Privileged secret | Main risk |
| --- | --- | --- | --- |
| `public_maintenance_ticket` | `verify_jwt=false` | service role | public enumeration/spam, service-role blast radius |
| `places_autocomplete` | `verify_jwt=true` plus JWT role decode | Google Maps key | decodes JWT role without cryptographic verification in code, relying on platform JWT verification |
| `device_telemetry` | HMAC headers | service role | device secret compromise; no CORS issue seen |
| `device_telemetry_products` | HMAC headers | service role | raw error leakage |
| `device_commands` | HMAC headers | service role | raw error leakage; command ack status is caller supplied but tied to device id |
| `schedule_daily_notifications` | cron secret or service role bearer | service role | raw error leakage; broad backend write |
| `send_notifications` | cron secret or service role bearer | service role + Firebase SA | raw error leakage; token cleanup |

Live deployment/JWT settings could not be listed via MCP.

## 11. Secrets & API Key Audit

Confirmed:

- No full service-role key was found hard-coded in the searched repository.
- Edge Functions read `SUPABASE_SERVICE_ROLE_KEY` from environment only.
- Flutter app hard-codes the Supabase URL and legacy anon JWT in `lib/app/env.dart:13-17`; value redacted here.
- Google Maps/Firebase/cron secrets are referenced as environment variables, not hard-coded.
- `.env.local` exists but was not printed in this report; CLI failed parsing it. It should be checked manually without exposing contents.

## 12. Application <-> RLS Mismatch

| Application Operation | Code Location | DB Object | Expected Role | Current Result | Root Cause |
| --- | --- | --- | --- | --- | --- |
| Admin save machine config | `admin_machine_config_page.dart:453-479` | `machines`, `machine_consumables` | admin | likely blocked for `machines` update | no reviewed direct admin UPDATE policy for `machines` |
| Admin coverage create plan | `admin_coverage_page.dart:122-132`, `331` | `operator_unavailability`, `temp_machine_assignments` | admin | needs verification | UI role check; DB policies not found locally |
| Admin confirm coverage plan | `admin_coverage_plan_page.dart:164-188` | `temp_machine_assignments` | admin | needs verification | direct update policy not found locally |
| Ticket status update | `ticket_detail_page.dart:126-141` | `tickets` | technician/admin/assigned operator | allowed but mutation risk | broad row update policy |
| Ticket resolved visit insert | `ticket_detail_page.dart:150-158` | `visits` | technician | insecurely allowed due RLS disabled | inactive visits policies |
| Dashboard client view | `dashboard_page.dart:145-161` | `client_states_effective`, `clients` | assigned operator/admin | possible overexposure | security-definer view and frontend filter |
| Push token registration | `push_notifications_service.dart:183-188` | `push_tokens` | authenticated self | may fail | conflict target/index not verified |

## 13. REMEDIATION ROADMAP

## STEP 0 - Emergency Security Issues

| Order | Finding(s) | Action | Why now | Regression Risk | Verification |
| --- | --- | --- | --- | --- | --- |
| 0.1 | SEC-001 | Enable RLS and least-privilege grants/policies on all five RLS-off public tables | Immediate unauthenticated/authenticated exposure | `visits` and firmware/device flows may break | anon denied; intended service/admin flows pass |
| 0.2 | SEC-002 | Convert/recreate exposed views as `security_invoker=true` or revoke access | Alternate RLS bypass | dashboards may return fewer rows | Tenant A/B view tests |

## STEP 1 - Authorization Architecture

| Order | Finding(s) | Action | Why now | Regression Risk | Verification |
| --- | --- | --- | --- | --- | --- |
| 1.1 | SEC-007 | Lock down role and `organization_id` mutation | Prevent role escalation before policy rewrite | admin user-management flow may need backend RPC | self-update denied |
| 1.2 | SEC-015 | Pull/reconcile live schema and migrations | Avoid remediating stale SQL | none if read-only | diff reviewed |

## STEP 2 - Critical RLS

| Order | Finding(s) | Action | Why now | Regression Risk | Verification |
| --- | --- | --- | --- | --- | --- |
| 2.1 | SEC-003 | Reduce `anon`/`authenticated` object grants | Close API/schema overexposure | frontend direct queries may fail | route-by-route smoke tests |
| 2.2 | SEC-009 | Add immutable tenant/resource checks for ticket updates | Stop ownership mutation | ticket workflow may need RPC | status allowed, ownership denied |

## STEP 3 - RPC and SECURITY DEFINER

| Order | Finding(s) | Action | Why now | Regression Risk | Verification |
| --- | --- | --- | --- | --- | --- |
| 3.1 | SEC-004 | Revoke broad/public EXECUTE and review every SECURITY DEFINER body | Bypass layer is large | app RPC calls can fail | RPC matrix tests |
| 3.2 | SEC-005 | Hide caller-supplied access helpers or derive user from `auth.uid()` | Prevent enumeration and future bypass | policies depending on helpers need replacement | direct helper RPC denied |

## STEP 4 - Views / Grants / Data API

| Order | Finding(s) | Action | Why now | Regression Risk | Verification |
| --- | --- | --- | --- | --- | --- |
| 4.1 | SEC-002, SEC-003 | Audit REST/GraphQL exposure after view fixes | Close alternate paths | client schema queries may change | anon/auth introspection |

## STEP 5 - Storage

| Order | Finding(s) | Action | Why now | Regression Risk | Verification |
| --- | --- | --- | --- | --- | --- |
| 5.1 | SEC-013 | Run bucket/object policy audit with proper MCP scope | Unknown storage posture | unknown | bucket matrix tests |

## STEP 6 - Edge Functions / Public APIs

| Order | Finding(s) | Action | Why now | Regression Risk | Verification |
| --- | --- | --- | --- | --- | --- |
| 6.1 | SEC-010, SEC-014 | Verify live JWT/public settings and harden public endpoint responses | Public/service-role bridge | public ticket UX changes | unauth/public tests |
| 6.2 | SEC-011 | Remove raw error details from responses | Reduces recon value | debugging needs logs | forced errors return generic bodies |

## STEP 7 - Functional RLS Fixes

| Order | Finding(s) | Action | Why now | Regression Risk | Verification |
| --- | --- | --- | --- | --- | --- |
| 7.1 | SEC-008 | Add DB-enforced admin coverage/machine-config policies or RPCs | Unblock legitimate admins safely | admin screens | admin succeeds, non-admin denied |
| 7.2 | SEC-012 | Align `push_tokens` unique constraint/upsert | Fix push registration | duplicate tokens | idempotent token refresh |

## STEP 8 - Hardening

| Order | Finding(s) | Action | Why now | Regression Risk | Verification |
| --- | --- | --- | --- | --- | --- |
| 8.1 | SEC-006 | Move to publishable env-injected keys and rotate legacy keys | hygiene after exposure closed | build/deploy config | no legacy key in source |
| 8.2 | SEC-016 | Enable leaked-password protection | account hardening | user signup friction | compromised password rejected |

## STEP 9 - Regression Security Test Suite

| Order | Finding(s) | Action | Why now | Regression Risk | Verification |
| --- | --- | --- | --- | --- | --- |
| 9.1 | all | Build repeatable Tenant A/Tenant B RLS tests in a clone/local DB | Prevent regressions | test data maintenance | CI/security test pass |

## 14. PROPOSED SECURITY REGRESSION TESTS

Anonymous:

- Denied direct table SELECT/INSERT/UPDATE/DELETE on all non-public tables, especially SEC-001 tables.
- Allowed only `public_maintenance_ticket` flow with generic responses and rate limiting.
- Denied all non-public RPCs, including refill/dispense unless device-authenticated by design.

Authenticated Tenant A:

- Can read own/effective clients, sites, machines, tickets, refills.
- Cannot read Tenant B clients, sites, machines, tickets, refills, visits, device data, or views.
- Cannot update ownership columns to Tenant B IDs.

Operator:

- Can perform allowed refill and assigned maintenance workflows.
- Cannot perform admin onboarding, coverage planning, machine configuration, or Control Center RPCs.

Maintenance user / technician:

- Can see and update intended ticket workflow.
- Cannot mutate tenant/resource/assignment fields outside allowed transitions.

Admin:

- Can manage organization-scoped onboarding, coverage, machine config, KPI.
- Cannot cross organization unless explicitly intended.

Internal admin:

- Can call Control Center read and command RPCs.
- Non-internal roles get denied or empty results.

RPC:

- For each SECURITY DEFINER RPC: unauthenticated, wrong tenant, wrong role, own tenant, and ownership-mutation cases.

No tests should be executed against production if they modify data.

## 15. RECOMMENDED FUTURE MIGRATION PLAN

```text
001_reconcile_live_schema_snapshot
002_emergency_enable_rls_on_public_exposed_tables
003_secure_views_security_invoker_and_grants
004_lock_profile_role_and_org_mutation
005_reduce_public_and_authenticated_grants
006_secure_security_definer_execute_surface
007_private_authorization_helper_functions
008_ticket_update_column_and_tenant_guards
009_admin_coverage_and_machine_config_authorization
010_storage_bucket_object_policies
011_edge_function_public_api_hardening
012_push_token_upsert_contract
013_security_regression_tests
014_auth_and_key_hardening
```

Dependencies: run `001` first. Apply emergency exposure fixes before functional fixes. Do not use broad authenticated policies to unblock UI workflows.

## 16. OPEN QUESTIONS

1. What are the live `pg_policy` and grant definitions? Raw SQL MCP access was blocked; policies must be pulled before remediation.
2. Are `perform_refill` and `register_dispense` intentionally anon-callable? Advisors say yes; local migrations reviewed did not define them.
3. Which Edge Functions are actually deployed and what are their JWT settings? MCP Edge listing lacked scope.
4. Which Storage buckets exist and are any public? MCP storage scope was insufficient.
5. Is there a legitimate multi-organization production requirement, or is `organization_id` currently a future-proofing field? This affects whether admins are org-scoped or global.
6. How should `technician` visibility work? Local policies grant broad ticket/client/site/machine SELECT for technicians, which may or may not match business intent.

## 17. FINAL PRIORITY CHECKLIST

### Before next development

- [ ] Fix SEC-001 in a clone/staging migration.
- [ ] Pull live policies/functions/views/grants with sufficient scope.
- [ ] Confirm live Edge Function and Storage configuration.

### Before internal pilot

- [ ] Fix security-definer views and GraphQL/Data API grants.
- [ ] Lock down profile role/org mutation.
- [ ] Reduce SECURITY DEFINER RPC execute surface.
- [ ] Add Tenant A/Tenant B RLS tests.

### Before external pilot

- [ ] Harden public ticket endpoint against enumeration/spam.
- [ ] Remove raw backend errors from Edge responses.
- [ ] Verify Storage and firmware distribution access.
- [ ] Rotate exposed legacy anon/service keys as appropriate.

### Before production

- [ ] All P0/P1 findings closed and regression tested.
- [ ] All functional blockers fixed without broad policies.
- [ ] Security advisors reviewed with no unaccepted ERROR findings.
- [ ] Auth hardening enabled for password protection and admin accounts.

## 18. REMEDIATION STATUS - 2026-09-12

Remediation is now active on Git branch `security-rls-remediation` and Supabase
branch `security-rls-remediation`. Production Supabase project
`atpfgkhechvdijqnflnc` was inspected read-only and was not modified.

The first empty Supabase branch was renamed to
`security-rls-remediation-empty` (`mljqeycmofhtqhbrppiw`) during setup and is
not used for remediation. The latest branch list shows only `main` and the
active data-cloned remediation branch. A new persistent branch named
`security-rls-remediation` was created from main with `with_data=true`, project
ref `gydjrznapplpgvmrcymq`, and reached `FUNCTIONS_DEPLOYED` /
`ACTIVE_HEALTHY`.

Branch row counts were verified to match main for all 26 `public` base tables
before remediation. After the DB migrations and Edge Function deploys, row
counts still match main for the application tables; only schema/grant/function
metadata changed.

| Finding | Severity | Remediation status | Migration / Code | Verification |
| --- | --- | --- | --- | --- |
| SEC-001 | P0 | FIXED ON BRANCH | `20260911102427_emergency_enable_rls_on_public_exposed_tables.sql` enables/forces RLS and removes broad grants for the five exposed tables. | Branch advisor no longer reports `policy_exists_rls_disabled` or `rls_disabled_in_public`; catalog confirms RLS forced and anon denied. |
| SEC-002 | P1 | FIXED ON BRANCH | `20260911102433_secure_views_and_api_grants.sql` sets affected views to `security_invoker=true` and removes anon grants. | Branch advisor no longer reports `security_definer_view`; catalog confirms `security_invoker=true` for all audited views. |
| SEC-003 | P1 | FIXED FOR ANON / ACCEPTED RESIDUAL FOR AUTH | `20260911102433_secure_views_and_api_grants.sql` removes anon grants from app data objects. | Branch advisor no longer reports anon GraphQL exposure. Authenticated GraphQL visibility remains because Flutter uses authenticated REST/Data API grants; RLS is the enforcement layer. |
| SEC-004 | P1 | FIXED FOR ANON / REVIEWED FOR AUTH | `20260911102447_secure_security_definer_execute_surface.sql` revokes anon execution on all public `SECURITY DEFINER` functions and allowlists intended authenticated RPCs. | Branch advisor no longer reports `anon_security_definer_function_executable`; catalog confirms refill/dispense/helper grants are narrowed. |
| SEC-005 | P1 | FIXED ON BRANCH | `20260911102447_secure_security_definer_execute_surface.sql` adds current-user helpers and revokes direct execute on caller-supplied helper RPCs; `20260911110112_align_policy_helpers_and_push_token_roles.sql` removes the remaining policy reference to the old helper. | Catalog confirms caller-supplied helper RPCs are not executable by anon/authenticated. |
| SEC-006 | P2 | FIXED IN SOURCE | `lib/app/env.dart` uses `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` Dart defines; `lib/main.dart` validates config. | `dart analyze` and `flutter test` passed; secret pattern scan found no legacy Supabase JWT/URL in `lib` or functions. Key rotation remains an operational step outside this branch. |
| SEC-007 | P1 | FIXED ON BRANCH | `20260911102440_lock_profile_and_ticket_mutations.sql` removes public-client profile mutation grants and self-update policy names. | Catalog confirms `profiles` has no anon grants and authenticated cannot insert/update/delete directly. |
| SEC-008 | P2 / Functional blocker | FIXED ON BRANCH | `20260911102454_admin_functional_rls_and_push_tokens.sql` adds org-scoped admin policies for machine config and coverage tables; `20260911110015_tighten_machine_table_grants.sql` closes residual machine write grants. | Catalog confirms admin policies exist, direct machine insert/delete is revoked, and only `temperature_mode`/`updated_at` are column-updatable. |
| SEC-009 | P2 / Functional blocker | FIXED ON BRANCH | `20260911102440_lock_profile_and_ticket_mutations.sql` adds trigger guards for ticket resource/tenant mutation. | Trigger and helper installed; `tickets` delete is revoked; update remains constrained by policy plus protected-column trigger. |
| SEC-010 | P2 | FIXED ON BRANCH | `supabase/functions/public_maintenance_ticket/index.ts` masks unknown/inactive machine outcomes and stops returning ticket IDs to public callers. | Function deployed to branch; HTTP smoke on nonexistent machine returned `202` with no `ticket_id` or `machine_not_found` in body. |
| SEC-011 | P2 | FIXED ON BRANCH | Device and notification Edge Functions now return generic error codes and log details server-side. | Modified functions deployed to branch; unauthenticated smoke tests return `401` without backend details. Deno is not installed locally, so no local Deno lint was run. |
| SEC-012 | P3 / Functional blocker | FIXED ON BRANCH | `20260911102454_admin_functional_rls_and_push_tokens.sql` adds `(user_id, device_id, platform)` uniqueness; app upsert now uses the same conflict target; `20260911110112_align_policy_helpers_and_push_token_roles.sql` scopes push token policies to authenticated. | `dart analyze` and `flutter test` passed; catalog confirms push token insert/update/select policies are authenticated self-only. |
| SEC-013 | P2 | VERIFIED | No DB change required. | Branch storage audit shows one private `firmware` bucket and no `storage.objects`/`storage.buckets` client-opening policies. |
| SEC-014 | P3 | FIXED ON BRANCH | Edge Function JWT settings preserved from main while deploying hardened function bodies to the branch. | Branch function list confirms modified functions are deployed under `gydjrznapplpgvmrcymq` with expected `verify_jwt` settings. |
| SEC-015 | P3 | FIXED FOR THIS REMEDIATION | New branch was created with production data after the initial empty branch was renamed. | Branch `security-rls-remediation` is `with_data=true`, `ACTIVE_HEALTHY`, `FUNCTIONS_DEPLOYED`; migration history includes all remediation migrations. |
| SEC-016 | P3 | OPEN OPERATIONAL CONFIG | No Auth configuration change made from code. | Branch advisor still reports leaked-password protection disabled; enable this in Supabase Auth settings before production rollout. |
