-- Repeatable checks for the Admin refill productivity KPI.
-- Run on a disposable/local database after applying the core baseline and
-- migrations:
--
--   psql -h /private/tmp -p 55432 -d postgres \
--     -v ON_ERROR_STOP=1 \
--     -f supabase/tests/refill_productivity_kpi_validation.sql

begin;

set local client_min_messages = warning;

create or replace function pg_temp.set_actor(p_uid uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, false);
end;
$$;

create or replace function pg_temp.expect_close(
  p_actual numeric,
  p_expected numeric,
  p_label text,
  p_tolerance numeric default 0.01
)
returns void
language plpgsql
as $$
begin
  if p_actual is null or abs(p_actual - p_expected) > p_tolerance then
    raise exception '% expected %, got %', p_label, p_expected, p_actual;
  end if;
end;
$$;

insert into public.organizations (id, name)
values
  ('30000000-0000-0000-0000-000000000001', 'Refill KPI Test Org A'),
  ('30000000-0000-0000-0000-000000000002', 'Refill KPI Test Org B')
on conflict (id) do nothing;

insert into auth.users (id)
values
  ('30000000-0000-0000-0000-0000000000a1'),
  ('30000000-0000-0000-0000-0000000000a2'),
  ('30000000-0000-0000-0000-0000000000b1'),
  ('30000000-0000-0000-0000-0000000000c1'),
  ('30000000-0000-0000-0000-0000000000d1'),
  ('30000000-0000-0000-0000-0000000000e1'),
  ('30000000-0000-0000-0000-0000000000f1')
on conflict (id) do nothing;

insert into public.profiles (id, full_name, role, organization_id)
values
  (
    '30000000-0000-0000-0000-0000000000a1',
    'Admin KPI A',
    'admin',
    '30000000-0000-0000-0000-000000000001'
  ),
  (
    '30000000-0000-0000-0000-0000000000a2',
    'Admin KPI B',
    'admin',
    '30000000-0000-0000-0000-000000000002'
  ),
  (
    '30000000-0000-0000-0000-0000000000b1',
    'Operatore Caso A',
    'refill_operator',
    '30000000-0000-0000-0000-000000000001'
  ),
  (
    '30000000-0000-0000-0000-0000000000c1',
    'Operatore Caso B',
    'refill_operator',
    '30000000-0000-0000-0000-000000000001'
  ),
  (
    '30000000-0000-0000-0000-0000000000d1',
    'Operatore Caso C',
    'refill_operator',
    '30000000-0000-0000-0000-000000000001'
  ),
  (
    '30000000-0000-0000-0000-0000000000e1',
    'Operatore Legacy',
    'refill_operator',
    '30000000-0000-0000-0000-000000000001'
  ),
  (
    '30000000-0000-0000-0000-0000000000f1',
    'Operatore No Previous',
    'refill_operator',
    '30000000-0000-0000-0000-000000000002'
  )
on conflict (id) do update
set full_name = excluded.full_name,
    role = excluded.role,
    organization_id = excluded.organization_id;

insert into public.clients (id, name, organization_id)
values
  (
    '31000000-0000-0000-0000-000000000001',
    'Cliente KPI A',
    '30000000-0000-0000-0000-000000000001'
  ),
  (
    '31000000-0000-0000-0000-000000000002',
    'Cliente KPI B',
    '30000000-0000-0000-0000-000000000002'
  )
on conflict (id) do update
set name = excluded.name,
    organization_id = excluded.organization_id;

insert into public.sites (id, client_id, name, organization_id)
values
  (
    '32000000-0000-0000-0000-000000000001',
    '31000000-0000-0000-0000-000000000001',
    'Sede KPI A',
    '30000000-0000-0000-0000-000000000001'
  ),
  (
    '32000000-0000-0000-0000-000000000002',
    '31000000-0000-0000-0000-000000000002',
    'Sede KPI B',
    '30000000-0000-0000-0000-000000000002'
  )
on conflict (id) do update
set name = excluded.name,
    organization_id = excluded.organization_id;

insert into public.machines (
  id,
  code,
  site_id,
  assigned_operator_id,
  organization_id
)
values
  (
    '33000000-0000-0000-0000-000000000001',
    'KPI-A-01',
    '32000000-0000-0000-0000-000000000001',
    '30000000-0000-0000-0000-0000000000b1',
    '30000000-0000-0000-0000-000000000001'
  ),
  (
    '33000000-0000-0000-0000-000000000002',
    'KPI-B-01',
    '32000000-0000-0000-0000-000000000001',
    '30000000-0000-0000-0000-0000000000c1',
    '30000000-0000-0000-0000-000000000001'
  ),
  (
    '33000000-0000-0000-0000-000000000003',
    'KPI-C-01',
    '32000000-0000-0000-0000-000000000001',
    '30000000-0000-0000-0000-0000000000d1',
    '30000000-0000-0000-0000-000000000001'
  ),
  (
    '33000000-0000-0000-0000-000000000004',
    'KPI-LEGACY-01',
    '32000000-0000-0000-0000-000000000001',
    '30000000-0000-0000-0000-0000000000e1',
    '30000000-0000-0000-0000-000000000001'
  ),
  (
    '33000000-0000-0000-0000-000000000005',
    'KPI-NO-PREVIOUS-01',
    '32000000-0000-0000-0000-000000000002',
    '30000000-0000-0000-0000-0000000000f1',
    '30000000-0000-0000-0000-000000000002'
  )
on conflict (id) do update
set code = excluded.code,
    assigned_operator_id = excluded.assigned_operator_id,
    organization_id = excluded.organization_id;

insert into public.refills (
  machine_id,
  operator_id,
  created_at,
  refilled_units,
  previous_units,
  capacity_units,
  consumable_type
)
values
  -- Case A: 600 doses, 3 refills, 4 observed hours.
  (
    '33000000-0000-0000-0000-000000000001',
    '30000000-0000-0000-0000-0000000000b1',
    ((current_date - 1)::timestamp + time '09:00') at time zone 'Europe/Rome',
    100,
    900,
    1000,
    'hot'
  ),
  (
    '33000000-0000-0000-0000-000000000001',
    '30000000-0000-0000-0000-0000000000b1',
    ((current_date - 1)::timestamp + time '10:00') at time zone 'Europe/Rome',
    150,
    850,
    1000,
    'hot'
  ),
  (
    '33000000-0000-0000-0000-000000000001',
    '30000000-0000-0000-0000-0000000000b1',
    ((current_date - 1)::timestamp + time '13:00') at time zone 'Europe/Rome',
    350,
    650,
    1000,
    'hot'
  ),
  -- Case B: one refill, no observed rate.
  (
    '33000000-0000-0000-0000-000000000002',
    '30000000-0000-0000-0000-0000000000c1',
    ((current_date - 2)::timestamp + time '12:00') at time zone 'Europe/Rome',
    300,
    700,
    1000,
    'cold'
  ),
  -- Case C: two days, observed windows must be summed per day.
  (
    '33000000-0000-0000-0000-000000000003',
    '30000000-0000-0000-0000-0000000000d1',
    ((current_date - 3)::timestamp + time '09:00') at time zone 'Europe/Rome',
    100,
    900,
    1000,
    'hot'
  ),
  (
    '33000000-0000-0000-0000-000000000003',
    '30000000-0000-0000-0000-0000000000d1',
    ((current_date - 3)::timestamp + time '13:00') at time zone 'Europe/Rome',
    300,
    700,
    1000,
    'hot'
  ),
  (
    '33000000-0000-0000-0000-000000000003',
    '30000000-0000-0000-0000-0000000000d1',
    ((current_date - 4)::timestamp + time '10:00') at time zone 'Europe/Rome',
    200,
    800,
    1000,
    'hot'
  ),
  (
    '33000000-0000-0000-0000-000000000003',
    '30000000-0000-0000-0000-0000000000d1',
    ((current_date - 4)::timestamp + time '12:00') at time zone 'Europe/Rome',
    200,
    800,
    1000,
    'hot'
  ),
  -- Case E: legacy event without quantity.
  (
    '33000000-0000-0000-0000-000000000004',
    '30000000-0000-0000-0000-0000000000e1',
    ((current_date - 5)::timestamp + time '11:00') at time zone 'Europe/Rome',
    null,
    null,
    null,
    null
  ),
  -- Case D: another org with no previous period.
  (
    '33000000-0000-0000-0000-000000000005',
    '30000000-0000-0000-0000-0000000000f1',
    ((current_date - 1)::timestamp + time '11:00') at time zone 'Europe/Rome',
    100,
    900,
    1000,
    'hot'
  );

set role authenticated;

select pg_temp.set_actor('30000000-0000-0000-0000-0000000000a1');

do $$
declare
  payload jsonb := public.get_refill_productivity_kpi(30, 'Europe/Rome', 6);
  summary jsonb := payload -> 'summary';
  op_a record;
  op_b record;
  op_c record;
  op_legacy record;
begin
  perform pg_temp.expect_close(
    (summary ->> 'total_refilled_doses')::numeric,
    1700,
    'summary total doses'
  );
  if (summary ->> 'refill_count')::integer <> 9 then
    raise exception 'summary refill_count expected 9, got %',
      summary ->> 'refill_count';
  end if;
  if (summary ->> 'active_refill_days')::integer <> 5 then
    raise exception 'summary active_refill_days expected 5, got %',
      summary ->> 'active_refill_days';
  end if;
  perform pg_temp.expect_close(
    (summary ->> 'observed_refill_hours')::numeric,
    10,
    'summary observed hours'
  );
  perform pg_temp.expect_close(
    (summary ->> 'doses_per_observed_hour')::numeric,
    140,
    'summary observed rate'
  );

  select *
  into op_a
  from jsonb_to_recordset(payload -> 'operators') as x(
    operator_name text,
    total_refilled_doses numeric,
    refill_count integer,
    active_refill_days integer,
    observed_refill_hours numeric,
    doses_per_theoretical_hour numeric,
    doses_per_observed_hour numeric,
    observed_window_utilization numeric,
    theoretical_residual_capacity_hours numeric
  )
  where operator_name = 'Operatore Caso A';

  perform pg_temp.expect_close(op_a.total_refilled_doses, 600, 'case A doses');
  if op_a.refill_count <> 3 or op_a.active_refill_days <> 1 then
    raise exception 'case A counts are wrong';
  end if;
  perform pg_temp.expect_close(op_a.observed_refill_hours, 4, 'case A window');
  perform pg_temp.expect_close(
    op_a.doses_per_theoretical_hour,
    100,
    'case A theoretical rate'
  );
  perform pg_temp.expect_close(
    op_a.doses_per_observed_hour,
    150,
    'case A observed rate'
  );
  perform pg_temp.expect_close(
    op_a.observed_window_utilization,
    0.6667,
    'case A utilization'
  );
  perform pg_temp.expect_close(
    op_a.theoretical_residual_capacity_hours,
    2,
    'case A residual capacity'
  );

  select *
  into op_b
  from jsonb_to_recordset(payload -> 'operators') as x(
    operator_name text,
    total_refilled_doses numeric,
    refill_count integer,
    observed_refill_hours numeric,
    doses_per_observed_hour numeric
  )
  where operator_name = 'Operatore Caso B';

  perform pg_temp.expect_close(op_b.total_refilled_doses, 300, 'case B doses');
  if op_b.refill_count <> 1 then
    raise exception 'case B refill_count expected 1';
  end if;
  if op_b.doses_per_observed_hour is not null then
    raise exception 'case B observed rate must be null';
  end if;

  select *
  into op_c
  from jsonb_to_recordset(payload -> 'operators') as x(
    operator_name text,
    total_refilled_doses numeric,
    theoretical_hours numeric,
    observed_refill_hours numeric
  )
  where operator_name = 'Operatore Caso C';

  perform pg_temp.expect_close(op_c.total_refilled_doses, 800, 'case C doses');
  perform pg_temp.expect_close(op_c.theoretical_hours, 12, 'case C hours');
  perform pg_temp.expect_close(
    op_c.observed_refill_hours,
    6,
    'case C daily windows'
  );

  select *
  into op_legacy
  from jsonb_to_recordset(payload -> 'operators') as x(
    operator_name text,
    refill_count integer,
    total_refilled_doses numeric,
    legacy_without_quantity_count integer,
    doses_per_theoretical_hour numeric
  )
  where operator_name = 'Operatore Legacy';

  if op_legacy.refill_count <> 1
    or op_legacy.legacy_without_quantity_count <> 1
    or op_legacy.total_refilled_doses <> 0
    or op_legacy.doses_per_theoretical_hour is not null then
    raise exception 'legacy quantity handling is wrong';
  end if;
end $$;

select pg_temp.set_actor('30000000-0000-0000-0000-0000000000a2');

do $$
declare
  comparison jsonb :=
    public.get_refill_productivity_kpi(30, 'Europe/Rome', 6) -> 'comparison';
begin
  if comparison ->> 'doses_delta_percent' is not null
    or comparison ->> 'refill_delta_percent' is not null
    or comparison ->> 'theoretical_productivity_delta_percent' is not null
    or comparison ->> 'observed_productivity_delta_percent' is not null then
    raise exception 'empty previous period deltas must be null';
  end if;
end $$;

rollback;
