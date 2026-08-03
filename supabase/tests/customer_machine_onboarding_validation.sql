-- Repeatable integration checks for customer/site/machine onboarding.
-- Run on a disposable/local database after applying the onboarding baseline
-- fixture and deployable migrations:
--
--   psql -h /private/tmp -p 55432 -d postgres \
--     -v ON_ERROR_STOP=1 \
--     -f supabase/tests/customer_machine_onboarding_validation.sql

begin;

set local client_min_messages = warning;

insert into public.organizations (id, name)
values
  ('10000000-0000-0000-0000-000000000001', 'Org A'),
  ('20000000-0000-0000-0000-000000000001', 'Org B')
on conflict (id) do nothing;

insert into auth.users (id)
values
  ('10000000-0000-0000-0000-0000000000a1'),
  ('10000000-0000-0000-0000-0000000000b1'),
  ('10000000-0000-0000-0000-0000000000c1'),
  ('10000000-0000-0000-0000-0000000000d1'),
  ('20000000-0000-0000-0000-0000000000a1'),
  ('20000000-0000-0000-0000-0000000000b1')
on conflict (id) do nothing;

insert into public.profiles (id, full_name, role, organization_id)
values
  (
    '10000000-0000-0000-0000-0000000000a1',
    'Admin A',
    'admin',
    '10000000-0000-0000-0000-000000000001'
  ),
  (
    '10000000-0000-0000-0000-0000000000b1',
    'Operator A',
    'refill_operator',
    '10000000-0000-0000-0000-000000000001'
  ),
  (
    '10000000-0000-0000-0000-0000000000c1',
    'Operator A2',
    'refill_operator',
    '10000000-0000-0000-0000-000000000001'
  ),
  (
    '10000000-0000-0000-0000-0000000000d1',
    'Technician A',
    'technician',
    '10000000-0000-0000-0000-000000000001'
  ),
  (
    '20000000-0000-0000-0000-0000000000a1',
    'Admin B',
    'admin',
    '20000000-0000-0000-0000-000000000001'
  ),
  (
    '20000000-0000-0000-0000-0000000000b1',
    'Operator B',
    'refill_operator',
    '20000000-0000-0000-0000-000000000001'
  )
on conflict (id) do update
set full_name = excluded.full_name,
    role = excluded.role,
    organization_id = excluded.organization_id;

commit;

create temp table onboarding_test_state (
  key text primary key,
  value uuid not null
) on commit preserve rows;

grant all on onboarding_test_state to public;

create or replace function pg_temp.set_actor(p_uid uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, false);
end;
$$;

create or replace function pg_temp.expect_error(p_sql text, p_label text)
returns void
language plpgsql
as $$
begin
  execute p_sql;
  raise exception 'Expected error did not occur: %', p_label;
exception
  when others then
    if sqlerrm like 'Expected error did not occur:%' then
      raise;
    end if;
end;
$$;

set role authenticated;

select pg_temp.set_actor('10000000-0000-0000-0000-0000000000a1');

with created as (
  select public.create_client_with_primary_site(
    'Cliente Admin A',
    'Via Admin 1',
    null,
    'Roma'
  ) as payload
)
insert into onboarding_test_state (key, value)
select key, value::uuid
from created,
lateral jsonb_each_text(payload)
where key in ('client_id', 'site_id');

select pg_temp.set_actor('10000000-0000-0000-0000-0000000000b1');

with created as (
  select public.create_client_with_primary_site(
    'Cliente Operator A',
    'Via Operator 1',
    'Sede principale',
    'Milano'
  ) as payload
)
insert into onboarding_test_state (key, value)
select 'operator_' || key, value::uuid
from created,
lateral jsonb_each_text(payload)
where key in ('client_id', 'site_id');

do $$
declare
  before_count integer;
  after_count integer;
begin
  select count(*) into before_count from public.clients;
  perform pg_temp.expect_error(
    $sql$
      select public.create_client_with_primary_site(
        'Cliente rollback',
        '',
        null
      )
    $sql$,
    'empty primary site address'
  );
  select count(*) into after_count from public.clients;
  if after_count <> before_count then
    raise exception 'Rollback failed for create_client_with_primary_site';
  end if;
end $$;

select public.add_site_to_client(
  (select value from onboarding_test_state where key = 'operator_client_id'),
  'Via Operator 2',
  'Seconda sede',
  'Torino'
);

select pg_temp.set_actor('10000000-0000-0000-0000-0000000000a1');

do $$
begin
  if not exists (
    select 1
    from public.sites
    where id = (select value from onboarding_test_state where key = 'site_id')
      and city = 'Roma'
  ) then
    raise exception 'Primary site city was not stored';
  end if;

  if not exists (
    select 1
    from public.sites
    where client_id = (select value from onboarding_test_state where key = 'operator_client_id')
      and name = 'Seconda sede'
      and city = 'Torino'
  ) then
    raise exception 'Additional site city was not stored';
  end if;
end $$;

with created as (
  select public.create_client_with_primary_site(
    'Cliente Coordinate A',
    'Via Appia Nuova, 123, 00183 Roma RM, Italia',
    'Sede coordinate',
    'Roma',
    41.8792,
    12.5146
  ) as payload
)
insert into onboarding_test_state (key, value)
select 'coordinate_' || key, value::uuid
from created,
lateral jsonb_each_text(payload)
where key in ('client_id', 'site_id');

do $$
declare
  v_latitude double precision;
  v_longitude double precision;
begin
  select latitude, longitude
  into v_latitude, v_longitude
  from public.sites
  where id = (select value from onboarding_test_state where key = 'coordinate_site_id');

  if v_latitude is distinct from 41.8792 or v_longitude is distinct from 12.5146 then
    raise exception 'Site coordinates were not stored';
  end if;
end $$;

with machine as (
  select public.create_machine_for_site(
    (select value from onboarding_test_state where key = 'client_id'),
    (select value from onboarding_test_state where key = 'site_id'),
    'IC-HOT-01',
    'hot',
    120,
    '10000000-0000-0000-0000-0000000000b1',
    'HW-A-001'
  ) as payload
)
insert into onboarding_test_state (key, value)
select 'admin_' || key, value::uuid
from machine,
lateral jsonb_each_text(payload)
where key = 'machine_id';

select pg_temp.set_actor('10000000-0000-0000-0000-0000000000b1');

with machine as (
  select public.create_machine_for_site(
    (select value from onboarding_test_state where key = 'operator_client_id'),
    (select value from onboarding_test_state where key = 'operator_site_id'),
    'IC-OP-01',
    'cold',
    80,
    '20000000-0000-0000-0000-0000000000b1',
    null
  ) as payload
)
insert into onboarding_test_state (key, value)
select 'operator_' || key, value::uuid
from machine,
lateral jsonb_each_text(payload)
where key = 'machine_id';

do $$
begin
  if exists (
    select 1
    from public.machines
    where id = (select value from onboarding_test_state where key = 'operator_machine_id')
      and assigned_operator_id <> '10000000-0000-0000-0000-0000000000b1'
  ) then
    raise exception 'Operator assignment was not forced to auth.uid()';
  end if;
end $$;

select pg_temp.set_actor('10000000-0000-0000-0000-0000000000a1');

select pg_temp.expect_error(
  $sql$
    select public.create_machine_for_site(
      (select value from onboarding_test_state where key = 'client_id'),
      (select value from onboarding_test_state where key = 'site_id'),
      'IC-HOT-01',
      'hot',
      100,
      '10000000-0000-0000-0000-0000000000b1',
      null
    )
  $sql$,
  'duplicate machine code'
);

select pg_temp.expect_error(
  $sql$
    select public.create_machine_for_site(
      (select value from onboarding_test_state where key = 'client_id'),
      (select value from onboarding_test_state where key = 'site_id'),
      'IC-ZERO-01',
      'hot',
      0,
      '10000000-0000-0000-0000-0000000000b1',
      null
    )
  $sql$,
  'zero capacity'
);

select pg_temp.expect_error(
  $sql$
    select public.create_machine_for_site(
      (select value from onboarding_test_state where key = 'client_id'),
      (select value from onboarding_test_state where key = 'site_id'),
      'IC-NEG-01',
      'hot',
      -1,
      '10000000-0000-0000-0000-0000000000b1',
      null
    )
  $sql$,
  'negative capacity'
);

select pg_temp.expect_error(
  $sql$
    select public.create_machine_for_site(
      (select value from onboarding_test_state where key = 'client_id'),
      (select value from onboarding_test_state where key = 'operator_site_id'),
      'IC-MISMATCH-01',
      'hot',
      100,
      '10000000-0000-0000-0000-0000000000b1',
      null
    )
  $sql$,
  'client-site mismatch'
);

select pg_temp.expect_error(
  $sql$
    select public.create_machine_for_site(
      (select value from onboarding_test_state where key = 'client_id'),
      (select value from onboarding_test_state where key = 'site_id'),
      'IC-CROSS-OP-01',
      'hot',
      100,
      '20000000-0000-0000-0000-0000000000b1',
      null
    )
  $sql$,
  'operator from other organization'
);

select pg_temp.set_actor('20000000-0000-0000-0000-0000000000a1');

select pg_temp.expect_error(
  $sql$
    select public.add_site_to_client(
      (select value from onboarding_test_state where key = 'client_id'),
      'Via Cross Tenant',
      'Sede Cross'
    )
  $sql$,
  'add site to other organization client'
);

select pg_temp.expect_error(
  $sql$
    select public.create_machine_for_site(
      (select value from onboarding_test_state where key = 'client_id'),
      (select value from onboarding_test_state where key = 'site_id'),
      'IC-CROSS-SITE-01',
      'hot',
      100,
      '20000000-0000-0000-0000-0000000000b1',
      null
    )
  $sql$,
  'create machine in other organization site'
);

do $$
declare
  visible_count integer;
begin
  select count(*) into visible_count
  from public.clients
  where id = (select value from onboarding_test_state where key = 'client_id');

  if visible_count <> 0 then
    raise exception 'Cross-tenant client row is visible';
  end if;
end $$;

reset role;

set role anon;
select pg_temp.expect_error(
  $sql$
    select public.create_client_with_primary_site(
      'Anon client',
      'Anon address',
      null
    )
  $sql$,
  'anon execute onboarding RPC'
);
reset role;

set role authenticated;
select pg_temp.set_actor('10000000-0000-0000-0000-0000000000b1');

do $$
declare
  target_machine uuid := (
    select value from onboarding_test_state where key = 'operator_machine_id'
  );
  before_units integer;
  after_units integer;
begin
  select capacity_units into before_units
  from public.machine_consumables
  where machine_id = target_machine;

  update public.machine_consumables
  set capacity_units = capacity_units + 1
  where machine_id = target_machine;

  select capacity_units into after_units
  from public.machine_consumables
  where machine_id = target_machine;

  if after_units <> before_units then
    raise exception 'Operator modified machine_consumables directly';
  end if;
end $$;

select pg_temp.set_actor('10000000-0000-0000-0000-0000000000a1');

do $$
declare
  before_machines integer;
  after_machines integer;
begin
  select count(*) into before_machines from public.machines;
  perform pg_temp.expect_error(
    $sql$
      select public.create_machine_for_site(
        (select value from onboarding_test_state where key = 'client_id'),
        (select value from onboarding_test_state where key = 'site_id'),
        'IC-ROLLBACK-CAP',
        'hot',
        -10,
        '10000000-0000-0000-0000-0000000000b1',
        null
      )
    $sql$,
    'machine rollback on invalid capacity'
  );
  select count(*) into after_machines from public.machines;
  if after_machines <> before_machines then
    raise exception 'Machine rollback failed on invalid capacity';
  end if;
end $$;

do $$
declare
  no_machine_client uuid;
  no_machine_site uuid;
  visible_before integer;
  visible_after integer;
begin
  reset role;

  set local role authenticated;
  perform pg_temp.set_actor('10000000-0000-0000-0000-0000000000b1');

  select (payload ->> 'client_id')::uuid, (payload ->> 'site_id')::uuid
  into no_machine_client, no_machine_site
  from (
    select public.create_client_with_primary_site(
      'Cliente temporaneo creatore',
      'Via Temporanea 1',
      null
    ) as payload
  ) s;

  select count(*) into visible_before
  from public.clients
  where id = no_machine_client;

  if visible_before <> 1 then
    raise exception 'Creator cannot see newly created client without machines';
  end if;

  reset role;
  set local role authenticated;
  perform pg_temp.set_actor('10000000-0000-0000-0000-0000000000a1');

  perform public.create_machine_for_site(
    no_machine_client,
    no_machine_site,
    'IC-CREATOR-LOSES-ACCESS',
    'hot',
    50,
    '10000000-0000-0000-0000-0000000000c1',
    null
  );

  reset role;
  set local role authenticated;
  perform pg_temp.set_actor('10000000-0000-0000-0000-0000000000b1');

  select count(*) into visible_after
  from public.clients
  where id = no_machine_client;

  if visible_after <> 0 then
    raise exception 'Creator kept permanent access after machine assigned elsewhere';
  end if;
end $$;

reset role;

select 'customer_machine_onboarding_validation_ok' as result;
