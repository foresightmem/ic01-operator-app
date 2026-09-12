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
  ('92000000-0000-0000-0000-0000000000b1'),
  ('93000000-0000-0000-0000-000000000001')
on conflict (id) do nothing;

insert into public.profiles (id, full_name, role, organization_id)
values
  ('91000000-0000-0000-0000-0000000000a1', 'SEC Admin A', 'admin', '91000000-0000-0000-0000-000000000001'),
  ('91000000-0000-0000-0000-0000000000b1', 'SEC Operator A', 'refill_operator', '91000000-0000-0000-0000-000000000001'),
  ('91000000-0000-0000-0000-0000000000c1', 'SEC Technician A', 'technician', '91000000-0000-0000-0000-000000000001'),
  ('92000000-0000-0000-0000-0000000000a1', 'SEC Admin B', 'admin', '92000000-0000-0000-0000-000000000001'),
  ('92000000-0000-0000-0000-0000000000b1', 'SEC Operator B', 'refill_operator', '92000000-0000-0000-0000-000000000001'),
  ('93000000-0000-0000-0000-000000000001', 'SEC No Membership', 'refill_operator', null)
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
  ('92300000-0000-0000-0000-000000000001', 'SEC-B-001', '92200000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-0000000000b1', '92000000-0000-0000-0000-000000000001')
on conflict (id) do update
set code = excluded.code,
    site_id = excluded.site_id,
    assigned_operator_id = excluded.assigned_operator_id,
    organization_id = excluded.organization_id;

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

update public.tickets
set status = 'in_progress'
where id = '91400000-0000-0000-0000-000000000001';

set role authenticated;
select pg_temp.set_actor('91000000-0000-0000-0000-0000000000a1');

insert into public.operator_unavailability (operator_id, start_date, end_date, reason)
values ('91000000-0000-0000-0000-0000000000b1', current_date + 1, current_date + 2, 'SEC test')
returning id;

select pg_temp.expect_error(
  'insert into public.operator_unavailability (operator_id, start_date, end_date, reason) values (''92000000-0000-0000-0000-0000000000b1'', current_date + 1, current_date + 2, ''cross org'')',
  'admin A cannot manage operator B availability'
);

select pg_temp.set_actor('93000000-0000-0000-0000-000000000001');
select pg_temp.expect_zero(
  'select count(*) from public.clients',
  'authenticated user without organization sees no tenants'
);
