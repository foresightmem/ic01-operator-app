-- IC01 security regression checks for the RLS remediation branch.
-- Run only on a disposable local DB or the security-rls-remediation branch.

\set ON_ERROR_STOP on

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

create or replace function pg_temp.expect_zero(p_sql text, p_label text)
returns void
language plpgsql
as $$
declare
  v_count bigint;
begin
  execute p_sql into v_count;
  if v_count <> 0 then
    raise exception '% expected 0, got %', p_label, v_count;
  end if;
end;
$$;

create or replace function pg_temp.cleanup_security_rls_regression()
returns void
language plpgsql
as $$
begin
  delete from public.ticket_events
  where ticket_id in (
    '91400000-0000-0000-0000-000000000001',
    '92400000-0000-0000-0000-000000000001'
  );

  delete from public.refills
  where machine_id in (
    '91300000-0000-0000-0000-000000000001',
    '91300000-0000-0000-0000-000000000002',
    '92300000-0000-0000-0000-000000000001'
  );

  delete from public.operator_unavailability
  where operator_id in (
    '91000000-0000-0000-0000-0000000000b1',
    '92000000-0000-0000-0000-0000000000b1'
  );

  delete from public.temp_machine_assignments
  where machine_id in (
    '91300000-0000-0000-0000-000000000001',
    '91300000-0000-0000-0000-000000000002',
    '92300000-0000-0000-0000-000000000001'
  )
  or original_operator_id in (
    '91000000-0000-0000-0000-0000000000b1',
    '92000000-0000-0000-0000-0000000000b1'
  )
  or new_operator_id in (
    '91000000-0000-0000-0000-0000000000c1',
    '92000000-0000-0000-0000-0000000000b1'
  );

  delete from public.tickets
  where id in (
    '91400000-0000-0000-0000-000000000001',
    '92400000-0000-0000-0000-000000000001'
  );

  delete from public.machine_consumables
  where machine_id in (
    '91300000-0000-0000-0000-000000000001',
    '91300000-0000-0000-0000-000000000002',
    '92300000-0000-0000-0000-000000000001'
  );

  delete from public.machines
  where id in (
    '91300000-0000-0000-0000-000000000001',
    '91300000-0000-0000-0000-000000000002',
    '92300000-0000-0000-0000-000000000001'
  );

  delete from public.sites
  where id in (
    '91200000-0000-0000-0000-000000000001',
    '92200000-0000-0000-0000-000000000001'
  );

  delete from public.clients
  where id in (
    '91100000-0000-0000-0000-000000000001',
    '92100000-0000-0000-0000-000000000001'
  );

  delete from public.profiles
  where id in (
    '91000000-0000-0000-0000-0000000000a1',
    '91000000-0000-0000-0000-0000000000b1',
    '91000000-0000-0000-0000-0000000000c1',
    '92000000-0000-0000-0000-0000000000a1',
    '92000000-0000-0000-0000-0000000000b1'
  );

  delete from auth.users
  where id in (
    '91000000-0000-0000-0000-0000000000a1',
    '91000000-0000-0000-0000-0000000000b1',
    '91000000-0000-0000-0000-0000000000c1',
    '92000000-0000-0000-0000-0000000000a1',
    '92000000-0000-0000-0000-0000000000b1'
  );

  delete from public.organizations
  where id in (
    '91000000-0000-0000-0000-000000000001',
    '92000000-0000-0000-0000-000000000001'
  );
end;
$$;

select pg_temp.cleanup_security_rls_regression();

insert into public.organizations (id, name)
values
  ('91000000-0000-0000-0000-000000000001', 'SEC Test Org A'),
  ('92000000-0000-0000-0000-000000000001', 'SEC Test Org B')
on conflict (id) do nothing;

insert into auth.users (id)
values
  ('91000000-0000-0000-0000-0000000000a1'),
  ('91000000-0000-0000-0000-0000000000b1'),
  ('91000000-0000-0000-0000-0000000000c1'),
  ('92000000-0000-0000-0000-0000000000a1'),
  ('92000000-0000-0000-0000-0000000000b1')
on conflict (id) do nothing;

insert into public.profiles (id, full_name, role, organization_id)
values
  ('91000000-0000-0000-0000-0000000000a1', 'SEC Admin A', 'admin', '91000000-0000-0000-0000-000000000001'),
  ('91000000-0000-0000-0000-0000000000b1', 'SEC Operator A', 'refill_operator', '91000000-0000-0000-0000-000000000001'),
  ('91000000-0000-0000-0000-0000000000c1', 'SEC Technician A', 'technician', '91000000-0000-0000-0000-000000000001'),
  ('92000000-0000-0000-0000-0000000000a1', 'SEC Admin B', 'admin', '92000000-0000-0000-0000-000000000001'),
  ('92000000-0000-0000-0000-0000000000b1', 'SEC Operator B', 'refill_operator', '92000000-0000-0000-0000-000000000001')
on conflict (id) do update
set full_name = excluded.full_name,
    role = excluded.role,
    organization_id = excluded.organization_id;

insert into public.clients (id, name, organization_id)
values
  ('91100000-0000-0000-0000-000000000001', 'SEC Client A', '91000000-0000-0000-0000-000000000001'),
  ('92100000-0000-0000-0000-000000000001', 'SEC Client B', '92000000-0000-0000-0000-000000000001')
on conflict (id) do update
set name = excluded.name,
    organization_id = excluded.organization_id;

insert into public.sites (id, client_id, name, address, organization_id)
values
  ('91200000-0000-0000-0000-000000000001', '91100000-0000-0000-0000-000000000001', 'SEC Site A', 'SEC Address A', '91000000-0000-0000-0000-000000000001'),
  ('92200000-0000-0000-0000-000000000001', '92100000-0000-0000-0000-000000000001', 'SEC Site B', 'SEC Address B', '92000000-0000-0000-0000-000000000001')
on conflict (id) do update
set name = excluded.name,
    address = excluded.address,
    organization_id = excluded.organization_id;

insert into public.machines (id, code, site_id, assigned_operator_id, organization_id)
values
  ('91300000-0000-0000-0000-000000000001', 'SEC-A-001', '91200000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-0000000000b1', '91000000-0000-0000-0000-000000000001'),
  ('91300000-0000-0000-0000-000000000002', 'SEC-A-002', '91200000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-0000000000b1', '91000000-0000-0000-0000-000000000001'),
  ('92300000-0000-0000-0000-000000000001', 'SEC-B-001', '92200000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-0000000000b1', '92000000-0000-0000-0000-000000000001')
on conflict (id) do update
set code = excluded.code,
    site_id = excluded.site_id,
    assigned_operator_id = excluded.assigned_operator_id,
    organization_id = excluded.organization_id;

insert into public.machine_consumables (
  machine_id,
  type,
  capacity_units,
  current_units,
  is_enabled,
  updated_at
)
values
  ('91300000-0000-0000-0000-000000000001', 'hot'::public.consumable_type, 100, 25, true, now()),
  ('91300000-0000-0000-0000-000000000002', 'hot'::public.consumable_type, 100, 100, true, now()),
  ('92300000-0000-0000-0000-000000000001', 'hot'::public.consumable_type, 100, 25, true, now())
on conflict (machine_id, type) do update
set capacity_units = excluded.capacity_units,
    current_units = excluded.current_units,
    is_enabled = excluded.is_enabled,
    updated_at = excluded.updated_at;

insert into public.tickets (id, machine_id, client_id, site_id, status, reason, source, assigned_operator_id)
values
  ('91400000-0000-0000-0000-000000000001', '91300000-0000-0000-0000-000000000001', '91100000-0000-0000-0000-000000000001', '91200000-0000-0000-0000-000000000001', 'open', 'malfunction', 'operator_app', '91000000-0000-0000-0000-0000000000b1'),
  ('92400000-0000-0000-0000-000000000001', '92300000-0000-0000-0000-000000000001', '92100000-0000-0000-0000-000000000001', '92200000-0000-0000-0000-000000000001', 'open', 'malfunction', 'operator_app', '92000000-0000-0000-0000-0000000000b1')
on conflict (id) do update
set machine_id = excluded.machine_id,
    client_id = excluded.client_id,
    site_id = excluded.site_id,
    status = excluded.status,
    reason = excluded.reason,
    source = excluded.source,
    assigned_operator_id = excluded.assigned_operator_id;

commit;

do $$
declare
  v_allowed text[] := array[
    'add_site_to_client(uuid,text,text)',
    'add_site_to_client(uuid,text,text,text)',
    'add_site_to_client(uuid,text,text,text,double precision,double precision)',
    'client_has_no_machines(uuid)',
    'control_center_is_internal_admin()',
    'control_center_supported_commands()',
    'create_client_with_primary_site(text,text,text)',
    'create_client_with_primary_site(text,text,text,text)',
    'create_client_with_primary_site(text,text,text,text,double precision,double precision)',
    'create_control_center_device_command(uuid,text,jsonb)',
    'create_machine_for_site(uuid,uuid,text,text,integer,uuid,text)',
    'current_app_organization_id()',
    'current_app_role()',
    'current_user_has_client_access(uuid)',
    'current_user_has_machine_access(uuid)',
    'current_user_has_site_access(uuid)',
    'delete_onboarding_client(uuid)',
    'delete_onboarding_machine(uuid)',
    'get_control_center_device_detail(uuid)',
    'get_control_center_devices()',
    'get_control_center_events(integer,uuid,text,text,timestamp with time zone,timestamp with time zone)',
    'get_control_center_overview()',
    'get_refill_productivity_kpi(integer,text,numeric)',
    'onboarding_actor_context()',
    'perform_refill_consumable(uuid,consumable_type)',
    'site_has_no_machines(uuid)'
  ];
  v_unexpected text[];
  v_missing text[];
begin
  select coalesce(array_agg(p.oid::regprocedure::text order by p.oid::regprocedure::text), '{}')
  into v_unexpected
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prosecdef
    and has_function_privilege('authenticated', p.oid, 'execute')
    and not (p.oid::regprocedure::text = any(v_allowed));

  if cardinality(v_unexpected) > 0 then
    raise exception 'Unexpected authenticated SECURITY DEFINER functions: %',
      array_to_string(v_unexpected, ', ');
  end if;

  select coalesce(array_agg(expected order by expected), '{}')
  into v_missing
  from unnest(v_allowed) as expected
  where to_regprocedure('public.' || expected) is null
     or not has_function_privilege(
       'authenticated',
       to_regprocedure('public.' || expected),
       'execute'
     );

  if cardinality(v_missing) > 0 then
    raise exception 'Missing authenticated SECURITY DEFINER allowlist functions: %',
      array_to_string(v_missing, ', ');
  end if;
end $$;

set role anon;
select pg_temp.expect_error('select count(*) from public.visits', 'anon cannot read visits');
select pg_temp.expect_error('select count(*) from public.dispense_events', 'anon cannot read dispense_events');
select pg_temp.expect_error('select count(*) from public.firmware_versions', 'anon cannot read firmware_versions');
select pg_temp.expect_error('select count(*) from public.client_states_effective', 'anon cannot read client_states_effective');
select pg_temp.expect_error('select public.perform_refill(''91300000-0000-0000-0000-000000000001'')', 'anon cannot execute perform_refill');
select pg_temp.expect_error(
  'select public.register_dispense(''91300000-0000-0000-0000-000000000001'', ''coffee''::public.beverage_type, 1, ''SEC-DEVICE'')',
  'anon cannot execute register_dispense'
);

set role authenticated;
select pg_temp.set_actor('91000000-0000-0000-0000-0000000000b1');

select pg_temp.expect_zero(
  'select count(*) from public.clients where id = ''92100000-0000-0000-0000-000000000001''',
  'operator A cannot read client B'
);
select pg_temp.expect_zero(
  'select count(*) from public.machines where id = ''92300000-0000-0000-0000-000000000001''',
  'operator A cannot read machine B'
);
select pg_temp.expect_zero(
  'select count(*) from public.client_states_effective where client_id = ''92100000-0000-0000-0000-000000000001''',
  'operator A cannot read client B via view'
);
select pg_temp.expect_error(
  'select public.machine_has_operator_access(''92300000-0000-0000-0000-000000000001'', ''92000000-0000-0000-0000-0000000000b1'')',
  'operator A cannot call arbitrary-user machine access helper'
);
select pg_temp.expect_error(
  'update public.profiles set role = ''admin'' where id = ''91000000-0000-0000-0000-0000000000b1''',
  'operator A cannot self-escalate profile role'
);
select pg_temp.expect_error(
  'update public.tickets set machine_id = ''92300000-0000-0000-0000-000000000001'', client_id = ''92100000-0000-0000-0000-000000000001'', site_id = ''92200000-0000-0000-0000-000000000001'' where id = ''91400000-0000-0000-0000-000000000001''',
  'operator A cannot reassign ticket to tenant B'
);
select pg_temp.expect_error(
  'select public.perform_refill(''91300000-0000-0000-0000-000000000001'')',
  'authenticated operator cannot execute legacy perform_refill'
);
select pg_temp.expect_error(
  'select public.perform_refill_consumable(''92300000-0000-0000-0000-000000000001'', ''hot''::public.consumable_type)',
  'operator A cannot refill machine B'
);
select pg_temp.expect_error(
  'select public.delete_onboarding_machine(''91300000-0000-0000-0000-000000000002'')',
  'operator A cannot delete machine'
);

select public.perform_refill_consumable(
  '91300000-0000-0000-0000-000000000001',
  'hot'::public.consumable_type
);

update public.tickets
set status = 'in_progress'
where id = '91400000-0000-0000-0000-000000000001';

set role authenticated;
select pg_temp.set_actor('91000000-0000-0000-0000-0000000000a1');

insert into public.operator_unavailability (operator_id, start_date, end_date, reason)
values ('91000000-0000-0000-0000-0000000000b1', current_date + 1, current_date + 2, 'SEC test')
returning id;

update public.tickets
set status = 'open'
where id = '91400000-0000-0000-0000-000000000001';

select pg_temp.expect_zero(
  'select count(*) from public.tickets where id = ''91400000-0000-0000-0000-000000000001'' and status <> ''open''',
  'admin A can reopen maintenance ticket'
);

insert into public.temp_machine_assignments (
  id,
  machine_id,
  original_operator_id,
  new_operator_id,
  start_date,
  end_date,
  status
)
values (
  '91500000-0000-0000-0000-000000000001',
  '91300000-0000-0000-0000-000000000001',
  '91000000-0000-0000-0000-0000000000b1',
  '91000000-0000-0000-0000-0000000000c1',
  current_date + 1,
  current_date + 2,
  'suggested'
);

delete from public.temp_machine_assignments
where id = '91500000-0000-0000-0000-000000000001';

select pg_temp.expect_zero(
  'select count(*) from public.temp_machine_assignments where id = ''91500000-0000-0000-0000-000000000001''',
  'admin A can delete suggested coverage assignment in own org'
);

update public.machines
set temperature_mode = 'hot'
where id = '91300000-0000-0000-0000-000000000001';

update public.machine_consumables
set capacity_units = 100,
    current_units = 50,
    is_enabled = true,
    updated_at = now()
where machine_id = '91300000-0000-0000-0000-000000000001'
  and type = 'hot'::public.consumable_type;

select pg_temp.expect_zero(
  'select count(*) from public.machines where id = ''91300000-0000-0000-0000-000000000001'' and current_fill_percent <> 50',
  'admin A can save tank config and trigger updates current_fill_percent'
);

select pg_temp.expect_error(
  'select public.delete_onboarding_machine(''91300000-0000-0000-0000-000000000001'')',
  'admin A cannot delete machine with ticket/refill history'
);

select public.delete_onboarding_machine('91300000-0000-0000-0000-000000000002');

select pg_temp.expect_zero(
  'select count(*) from public.machines where id = ''91300000-0000-0000-0000-000000000002''',
  'admin A can delete machine without operational history'
);

select pg_temp.expect_error(
  'insert into public.operator_unavailability (operator_id, start_date, end_date, reason) values (''92000000-0000-0000-0000-0000000000b1'', current_date + 1, current_date + 2, ''cross org'')',
  'admin A cannot manage operator B availability'
);

select pg_temp.set_actor('92000000-0000-0000-0000-0000000000b1');
select pg_temp.expect_zero(
  'select count(*) from public.clients where id = ''91100000-0000-0000-0000-000000000001''',
  'operator B cannot read client A'
);

reset role;
select pg_temp.cleanup_security_rls_regression();
