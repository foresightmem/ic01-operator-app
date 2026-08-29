-- MAGMA Control Center MVP.
--
-- This migration promotes the already designed device telemetry model into the
-- versioned app migrations, extends it for internal troubleshooting, and locks
-- it behind a DB-backed `internal_admin` role.

create extension if not exists pgcrypto;

alter table public.profiles
  drop constraint if exists profiles_role_check;

do $$
declare
  v_constraint text;
begin
  for v_constraint in
    select conname
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%role%'
  loop
    execute format(
      'alter table public.profiles drop constraint if exists %I',
      v_constraint
    );
  end loop;

  alter table public.profiles
    add constraint profiles_role_check
    check (role in ('refill_operator', 'technician', 'admin', 'internal_admin'));
end $$;

create or replace function public.control_center_is_internal_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
set row_security = off
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'internal_admin'
  );
$$;

revoke all on function public.control_center_is_internal_admin()
  from public, anon;
grant execute on function public.control_center_is_internal_admin()
  to authenticated;

insert into public.profiles (id, full_name, role, organization_id)
select
  u.id,
  coalesce(nullif(u.raw_user_meta_data->>'full_name', ''), 'MAGMA Control Center'),
  'internal_admin',
  coalesce(
    (select id from public.organizations order by created_at asc limit 1),
    '00000000-0000-0000-0000-000000000001'::uuid
  )
from auth.users u
where lower(u.email) = 'foresightmem@gmail.com'
on conflict (id) do update
set role = 'internal_admin',
    updated_at = now();

create table if not exists public.devices (
  id uuid primary key default gen_random_uuid(),
  device_id text unique not null,
  device_secret text not null,
  device_secret_next text,
  machine_id uuid references public.machines(id) on delete set null,
  serial_number text,
  hardware_revision text,
  firmware_channel text,
  metadata jsonb not null default '{}'::jsonb,
  installed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.devices
  add column if not exists device_secret_next text,
  add column if not exists machine_id uuid references public.machines(id) on delete set null,
  add column if not exists serial_number text,
  add column if not exists hardware_revision text,
  add column if not exists firmware_channel text,
  add column if not exists metadata jsonb not null default '{}'::jsonb,
  add column if not exists installed_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();

create table if not exists public.device_status (
  device_id uuid primary key references public.devices(id) on delete cascade,
  last_seen_at timestamptz,
  fw_version text,
  hardware_revision text,
  app_version text,
  last_operator_id uuid references public.profiles(id) on delete set null,
  last_event_at timestamptz,
  health_hint text,
  diagnostic jsonb not null default '{}'::jsonb,
  sensor_data jsonb not null default '{}'::jsonb,
  calibration_state text,
  updated_at timestamptz not null default now()
);

alter table public.device_status
  add column if not exists fw_version text,
  add column if not exists hardware_revision text,
  add column if not exists app_version text,
  add column if not exists last_operator_id uuid references public.profiles(id) on delete set null,
  add column if not exists last_event_at timestamptz,
  add column if not exists health_hint text,
  add column if not exists diagnostic jsonb not null default '{}'::jsonb,
  add column if not exists sensor_data jsonb not null default '{}'::jsonb,
  add column if not exists calibration_state text,
  add column if not exists updated_at timestamptz not null default now();

create table if not exists public.device_counters_bucket (
  device_id uuid not null references public.devices(id) on delete cascade,
  ts_bucket timestamptz not null,
  interval_s integer not null default 30,
  idle_count integer not null default 0,
  coffee_count integer not null default 0,
  cappuccino_count integer not null default 0,
  powders_count integer not null default 0,
  unknown_count integer not null default 0,
  created_at timestamptz not null default now(),
  primary key (device_id, ts_bucket)
);

create table if not exists public.device_events (
  id uuid primary key default gen_random_uuid(),
  device_id uuid references public.devices(id) on delete set null,
  machine_id uuid references public.machines(id) on delete set null,
  operator_id uuid references public.profiles(id) on delete set null,
  event_type text not null,
  severity text not null default 'info'
    check (severity in ('info', 'warning', 'error', 'critical')),
  summary text,
  source text not null default 'backend',
  firmware_version text,
  app_version text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.ble_sessions (
  id uuid primary key default gen_random_uuid(),
  device_id uuid references public.devices(id) on delete set null,
  machine_id uuid references public.machines(id) on delete set null,
  operator_id uuid references public.profiles(id) on delete set null,
  app_version text,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  disconnected_at timestamptz,
  result text not null default 'unknown'
    check (result in ('success', 'failed', 'cancelled', 'unknown')),
  disconnect_reason text,
  error_code text,
  duration_ms integer,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.device_commands (
  id uuid primary key default gen_random_uuid(),
  device_id uuid references public.devices(id) on delete cascade,
  command text not null,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'queued',
  requested_by uuid references public.profiles(id) on delete set null,
  requested_at timestamptz not null default now(),
  delivered_at timestamptz,
  sent_at timestamptz,
  executed_at timestamptz,
  completed_at timestamptz,
  ack_at timestamptz,
  response jsonb,
  error text,
  expires_at timestamptz not null default (now() + interval '7 days'),
  created_at timestamptz not null default now()
);

alter table public.device_commands
  add column if not exists payload jsonb not null default '{}'::jsonb,
  add column if not exists requested_by uuid references public.profiles(id) on delete set null,
  add column if not exists requested_at timestamptz not null default now(),
  add column if not exists delivered_at timestamptz,
  add column if not exists sent_at timestamptz,
  add column if not exists executed_at timestamptz,
  add column if not exists completed_at timestamptz,
  add column if not exists ack_at timestamptz,
  add column if not exists response jsonb,
  add column if not exists error text,
  add column if not exists expires_at timestamptz not null default (now() + interval '7 days');

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'device_commands'
      and column_name = 'status'
  ) then
    alter table public.device_commands
      alter column status set default 'queued';
  end if;
end $$;

create index if not exists devices_device_id_idx
  on public.devices (device_id);
create index if not exists devices_machine_id_idx
  on public.devices (machine_id)
  where machine_id is not null;
create index if not exists device_status_last_seen_idx
  on public.device_status (last_seen_at desc);
create index if not exists device_events_device_created_idx
  on public.device_events (device_id, created_at desc);
create index if not exists device_events_type_created_idx
  on public.device_events (event_type, created_at desc);
create index if not exists device_events_severity_created_idx
  on public.device_events (severity, created_at desc);
create index if not exists device_events_machine_created_idx
  on public.device_events (machine_id, created_at desc)
  where machine_id is not null;
create index if not exists ble_sessions_device_started_idx
  on public.ble_sessions (device_id, started_at desc);
create index if not exists ble_sessions_result_started_idx
  on public.ble_sessions (result, started_at desc);
create index if not exists device_commands_device_status_idx
  on public.device_commands (device_id, status);
create index if not exists device_commands_requested_at_idx
  on public.device_commands (requested_at desc);
create index if not exists device_commands_status_expires_idx
  on public.device_commands (status, expires_at);

drop trigger if exists devices_set_updated_at on public.devices;
create trigger devices_set_updated_at
before update on public.devices
for each row execute function public.set_current_timestamp_updated_at();

alter table public.devices enable row level security;
alter table public.device_status enable row level security;
alter table public.device_counters_bucket enable row level security;
alter table public.device_events enable row level security;
alter table public.ble_sessions enable row level security;
alter table public.device_commands enable row level security;

revoke all on public.devices from anon;
revoke all on public.device_status from anon;
revoke all on public.device_counters_bucket from anon;
revoke all on public.device_events from anon;
revoke all on public.ble_sessions from anon;
revoke all on public.device_commands from anon;

grant select on public.devices to authenticated;
grant select on public.device_status to authenticated;
grant select on public.device_counters_bucket to authenticated;
grant select on public.device_events to authenticated;
grant select on public.ble_sessions to authenticated;
grant select on public.device_commands to authenticated;

drop policy if exists devices_select_internal_admin on public.devices;
create policy devices_select_internal_admin
  on public.devices
  for select
  to authenticated
  using (public.control_center_is_internal_admin());

drop policy if exists device_status_select_internal_admin on public.device_status;
create policy device_status_select_internal_admin
  on public.device_status
  for select
  to authenticated
  using (public.control_center_is_internal_admin());

drop policy if exists device_counters_select_internal_admin on public.device_counters_bucket;
create policy device_counters_select_internal_admin
  on public.device_counters_bucket
  for select
  to authenticated
  using (public.control_center_is_internal_admin());

drop policy if exists device_events_select_internal_admin on public.device_events;
create policy device_events_select_internal_admin
  on public.device_events
  for select
  to authenticated
  using (public.control_center_is_internal_admin());

drop policy if exists ble_sessions_select_internal_admin on public.ble_sessions;
create policy ble_sessions_select_internal_admin
  on public.ble_sessions
  for select
  to authenticated
  using (public.control_center_is_internal_admin());

drop policy if exists device_commands_select_internal_admin on public.device_commands;
create policy device_commands_select_internal_admin
  on public.device_commands
  for select
  to authenticated
  using (public.control_center_is_internal_admin());

create or replace function public.control_center_device_health(
  p_last_contact timestamptz,
  p_health_hint text,
  p_calibration_state text,
  p_error_count integer,
  p_warning_count integer,
  p_offline_after interval default interval '7 days'
)
returns text
language sql
stable
as $$
  select case
    when p_last_contact is null then 'never_connected'
    when p_last_contact < now() - p_offline_after then 'offline'
    when lower(coalesce(p_health_hint, '')) = 'degraded'
      or coalesce(p_error_count, 0) >= 3 then 'degraded'
    when lower(coalesce(p_health_hint, '')) = 'warning'
      or coalesce(p_warning_count, 0) > 0
      or lower(coalesce(p_calibration_state, '')) in ('missing', 'invalid', 'required')
      then 'warning'
    else 'healthy'
  end;
$$;

revoke all on function public.control_center_device_health(
  timestamptz, text, text, integer, integer, interval
) from public, anon;
grant execute on function public.control_center_device_health(
  timestamptz, text, text, integer, integer, interval
) to authenticated;

create or replace function public.get_control_center_devices()
returns jsonb
language sql
stable
security definer
set search_path = ''
set row_security = off
as $$
  with authorized as (
    select public.control_center_is_internal_admin() as ok
  ),
  event_rollup as (
    select
      e.device_id,
      max(e.created_at) as last_event_at,
      count(*) filter (
        where e.created_at >= now() - interval '24 hours'
          and e.severity in ('error', 'critical')
      )::integer as error_count,
      count(*) filter (
        where e.created_at >= now() - interval '24 hours'
          and e.severity = 'warning'
      )::integer as warning_count
    from public.device_events e
    group by e.device_id
  ),
  ble_rollup as (
    select
      b.device_id,
      max(coalesce(b.completed_at, b.disconnected_at, b.started_at)) as last_ble_at,
      count(*) filter (
        where b.started_at >= now() - interval '24 hours'
      )::integer as ble_attempts_24h,
      count(*) filter (
        where b.started_at >= now() - interval '24 hours'
          and b.result = 'success'
      )::integer as ble_success_24h
    from public.ble_sessions b
    group by b.device_id
  ),
  rows as (
    select
      d.id,
      d.device_id,
      d.serial_number,
      coalesce(d.hardware_revision, ds.hardware_revision) as hardware_revision,
      d.machine_id,
      m.code as machine_code,
      c.id as client_id,
      c.name as client_name,
      s.id as site_id,
      s.name as site_name,
      s.city as site_city,
      ds.fw_version,
      ds.app_version,
      ds.calibration_state,
      ds.last_operator_id,
      coalesce(nullif(op.full_name, ''), 'Operatore') as last_operator_name,
      greatest(ds.last_seen_at, ds.last_event_at, er.last_event_at, br.last_ble_at) as last_contact_at,
      er.last_event_at,
      coalesce(er.error_count, 0) as error_count,
      coalesce(er.warning_count, 0) as warning_count,
      coalesce(br.ble_attempts_24h, 0) as ble_attempts_24h,
      coalesce(br.ble_success_24h, 0) as ble_success_24h,
      public.control_center_device_health(
        greatest(ds.last_seen_at, ds.last_event_at, er.last_event_at, br.last_ble_at),
        ds.health_hint,
        ds.calibration_state,
        coalesce(er.error_count, 0),
        coalesce(er.warning_count, 0)
      ) as health
    from public.devices d
    left join public.device_status ds on ds.device_id::text = d.id::text
    left join event_rollup er on er.device_id = d.id
    left join ble_rollup br on br.device_id = d.id
    left join public.machines m on m.id = d.machine_id
    left join public.sites s on s.id = m.site_id
    left join public.clients c on c.id = s.client_id
    left join public.profiles op on op.id = ds.last_operator_id
    where (select ok from authorized)
  )
  select coalesce(
    jsonb_agg(to_jsonb(rows) order by last_contact_at desc nulls last, device_id),
    '[]'::jsonb
  )
  from rows;
$$;

create or replace function public.get_control_center_overview()
returns jsonb
language sql
stable
security definer
set search_path = ''
set row_security = off
as $$
  with devices as (
    select * from jsonb_to_recordset(public.get_control_center_devices()) as x(
      id uuid,
      device_id text,
      serial_number text,
      hardware_revision text,
      machine_id uuid,
      machine_code text,
      client_id uuid,
      client_name text,
      site_id uuid,
      site_name text,
      site_city text,
      fw_version text,
      app_version text,
      calibration_state text,
      last_operator_id uuid,
      last_operator_name text,
      last_contact_at timestamptz,
      last_event_at timestamptz,
      error_count integer,
      warning_count integer,
      ble_attempts_24h integer,
      ble_success_24h integer,
      health text
    )
  ),
  latest_events as (
    select coalesce(
      jsonb_agg(to_jsonb(e) order by e.created_at desc),
      '[]'::jsonb
    ) as events
    from (
      select
        de.id,
        de.created_at,
        de.severity,
        de.event_type,
        de.summary,
        de.source,
        d.device_id,
        m.code as machine_code
      from public.device_events de
      left join public.devices d on d.id = de.device_id
      left join public.machines m on m.id = coalesce(de.machine_id, d.machine_id)
      where public.control_center_is_internal_admin()
      order by de.created_at desc
      limit 10
    ) e
  )
  select jsonb_build_object(
    'fleet_health', jsonb_build_object(
      'total', count(*),
      'healthy', count(*) filter (where health = 'healthy'),
      'warning', count(*) filter (where health = 'warning'),
      'degraded', count(*) filter (where health = 'degraded'),
      'offline', count(*) filter (where health = 'offline'),
      'never_connected', count(*) filter (where health = 'never_connected'),
      'calibration_missing', count(*) filter (
        where lower(coalesce(calibration_state, '')) in ('missing', 'invalid', 'required')
      ),
      'firmware_outdated', null
    ),
    'system_health', jsonb_build_object(
      'database_backend', 'available',
      'edge_functions', 'not_available',
      'ble_success_rate_24h',
        case
          when sum(ble_attempts_24h) > 0
            then round(sum(ble_success_24h)::numeric / sum(ble_attempts_24h)::numeric * 100, 2)
          else null
        end,
      'error_rate_24h',
        case
          when count(*) > 0
            then round(sum(error_count)::numeric / greatest(count(*), 1)::numeric, 2)
          else null
        end,
      'app_versions', (
        select coalesce(jsonb_agg(distinct app_version), '[]'::jsonb)
        from devices
        where app_version is not null and trim(app_version) <> ''
      ),
      'latest_event_received', (select max(last_event_at) from devices)
    ),
    'attention_required',
      coalesce(
        (
          select jsonb_agg(to_jsonb(d) order by last_contact_at asc nulls first)
          from (
            select *
            from devices
            where health <> 'healthy'
               or lower(coalesce(calibration_state, '')) in ('missing', 'invalid', 'required')
            limit 8
          ) d
        ),
        '[]'::jsonb
      ),
    'latest_events', (select events from latest_events),
    'not_available', jsonb_build_array(
      'Edge Function health check non instrumented',
      'Firmware latest version catalog not configured',
      'Cloud reachability is inferred from observed syncs, not direct device online state'
    )
  )
  from devices;
$$;

create or replace function public.get_control_center_device_detail(p_device_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
set row_security = off
as $$
  with authorized as (
    select public.control_center_is_internal_admin() as ok
  ),
  base as (
    select d.*
    from jsonb_to_recordset(public.get_control_center_devices()) as d(
      id uuid,
      device_id text,
      serial_number text,
      hardware_revision text,
      machine_id uuid,
      machine_code text,
      client_id uuid,
      client_name text,
      site_id uuid,
      site_name text,
      site_city text,
      fw_version text,
      app_version text,
      calibration_state text,
      last_operator_id uuid,
      last_operator_name text,
      last_contact_at timestamptz,
      last_event_at timestamptz,
      error_count integer,
      warning_count integer,
      ble_attempts_24h integer,
      ble_success_24h integer,
      health text
    )
    where d.id = p_device_id
      and (select ok from authorized)
  )
  select case
    when not exists (select 1 from authorized where ok) then
      jsonb_build_object('error', 'access_denied')
    when not exists (select 1 from base) then
      jsonb_build_object('error', 'not_found')
    else jsonb_build_object(
      'device', (select to_jsonb(base) from base limit 1),
      'status', coalesce(
        (
          select to_jsonb(ds)
          from public.device_status ds
          where ds.device_id::text = p_device_id::text
          limit 1
        ),
        '{}'::jsonb
      ),
      'latest_sensor_data', coalesce(
        (
          select ds.sensor_data
          from public.device_status ds
          where ds.device_id::text = p_device_id::text
          limit 1
        ),
        '{}'::jsonb
      ),
      'ble_sessions', coalesce(
        (
          select jsonb_agg(to_jsonb(b) order by b.started_at desc)
          from (
            select
              bs.id,
              bs.started_at,
              bs.completed_at,
              bs.disconnected_at,
              bs.result,
              bs.disconnect_reason,
              bs.error_code,
              bs.duration_ms,
              bs.app_version,
              coalesce(nullif(p.full_name, ''), 'Operatore') as operator_name
            from public.ble_sessions bs
            left join public.profiles p on p.id = bs.operator_id
            where bs.device_id = p_device_id
            order by bs.started_at desc
            limit 12
          ) b
        ),
        '[]'::jsonb
      ),
      'events', coalesce(
        (
          select jsonb_agg(to_jsonb(e) order by e.created_at desc)
          from (
            select
              de.id,
              de.created_at,
              de.severity,
              de.event_type,
              de.summary,
              de.source,
              de.firmware_version,
              de.app_version,
              de.payload,
              coalesce(nullif(p.full_name, ''), 'Operatore') as operator_name
            from public.device_events de
            left join public.profiles p on p.id = de.operator_id
            where de.device_id = p_device_id
            order by de.created_at desc
            limit 30
          ) e
        ),
        '[]'::jsonb
      ),
      'commands', coalesce(
        (
          select jsonb_agg(to_jsonb(c) order by c.requested_at desc)
          from (
            select
              dc.id,
              dc.command,
              dc.payload,
              dc.status,
              dc.requested_at,
              dc.delivered_at,
              dc.sent_at,
              dc.ack_at,
              dc.completed_at,
              dc.response,
              dc.error,
              dc.expires_at,
              coalesce(nullif(p.full_name, ''), 'Internal admin') as requested_by_name
            from public.device_commands dc
            left join public.profiles p on p.id = dc.requested_by
            where dc.device_id::text = p_device_id::text
            order by dc.requested_at desc
            limit 20
          ) c
        ),
        '[]'::jsonb
      )
    )
  end;
$$;

create or replace function public.get_control_center_events(
  p_limit integer default 100,
  p_device_id uuid default null,
  p_severity text default null,
  p_event_type text default null,
  p_from timestamptz default null,
  p_to timestamptz default null
)
returns jsonb
language sql
stable
security definer
set search_path = ''
set row_security = off
as $$
  select case
    when not public.control_center_is_internal_admin() then
      '[]'::jsonb
    else coalesce(jsonb_agg(to_jsonb(e) order by e.created_at desc), '[]'::jsonb)
  end
  from (
    select
      de.id,
      de.created_at,
      de.severity,
      de.event_type,
      de.summary,
      de.source,
      de.firmware_version,
      de.app_version,
      de.payload,
      d.id as device_pk,
      d.device_id,
      m.id as machine_id,
      m.code as machine_code,
      c.id as client_id,
      c.name as client_name,
      s.id as site_id,
      s.name as site_name,
      coalesce(nullif(p.full_name, ''), 'Operatore') as operator_name
    from public.device_events de
    left join public.devices d on d.id = de.device_id
    left join public.machines m on m.id = coalesce(de.machine_id, d.machine_id)
    left join public.sites s on s.id = m.site_id
    left join public.clients c on c.id = s.client_id
    left join public.profiles p on p.id = de.operator_id
    where (p_device_id is null or de.device_id = p_device_id)
      and (p_severity is null or de.severity = p_severity)
      and (p_event_type is null or de.event_type = p_event_type)
      and (p_from is null or de.created_at >= p_from)
      and (p_to is null or de.created_at <= p_to)
    order by de.created_at desc
    limit greatest(1, least(coalesce(p_limit, 100), 500))
  ) e;
$$;

create or replace function public.control_center_supported_commands()
returns jsonb
language sql
stable
security definer
set search_path = ''
set row_security = off
as $$
  select case
    when not public.control_center_is_internal_admin() then
      '[]'::jsonb
    else jsonb_build_array(
      jsonb_build_object(
        'command', 'set_products',
        'label', 'Set products',
        'supported', true,
        'read_only', false,
        'requires_payload', true,
        'description', 'Supported by current firmware via HTTP downlink; configuration write, queued until device polls.'
      ),
      jsonb_build_object('command', 'ping', 'label', 'Ping', 'supported', false, 'read_only', true),
      jsonb_build_object('command', 'get_device_info', 'label', 'Get device info', 'supported', false, 'read_only', true),
      jsonb_build_object('command', 'get_firmware_version', 'label', 'Get firmware version', 'supported', false, 'read_only', true),
      jsonb_build_object('command', 'get_calibration', 'label', 'Get calibration', 'supported', false, 'read_only', true),
      jsonb_build_object('command', 'read_accelerometer', 'label', 'Read accelerometer', 'supported', false, 'read_only', true),
      jsonb_build_object('command', 'read_light_sensor', 'label', 'Read light sensor', 'supported', false, 'read_only', true),
      jsonb_build_object('command', 'read_microphone_level', 'label', 'Read microphone level', 'supported', false, 'read_only', true),
      jsonb_build_object('command', 'run_self_test', 'label', 'Run self test', 'supported', false, 'read_only', true),
      jsonb_build_object('command', 'restart_device', 'label', 'Restart device', 'supported', false, 'read_only', false)
    )
  end;
$$;

create or replace function public.create_control_center_device_command(
  p_device_id uuid,
  p_command text,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set row_security = off
as $$
declare
  v_uid uuid := auth.uid();
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_command_id uuid;
  v_device_id_type text;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  if not public.control_center_is_internal_admin() then
    raise exception 'Internal admin role required' using errcode = '42501';
  end if;

  if not exists (select 1 from public.devices d where d.id = p_device_id) then
    raise exception 'Device not found' using errcode = 'P0002';
  end if;

  if p_command <> 'set_products' then
    insert into public.device_events (
      device_id,
      event_type,
      severity,
      summary,
      source,
      payload,
      operator_id
    )
    values (
      p_device_id,
      'command_unsupported',
      'warning',
      'Unsupported Control Center command requested',
      'control_center',
      jsonb_build_object('command', p_command),
      v_uid
    );

    raise exception 'Unsupported command' using errcode = '0A000';
  end if;

  if jsonb_typeof(v_payload->'names') <> 'array'
    or coalesce((v_payload->>'count')::integer, -1) < 0
    or coalesce((v_payload->>'count')::integer, -1) > 3 then
    raise exception 'set_products payload must contain count 0..3 and names array'
      using errcode = '22023';
  end if;

  select udt_name
  into v_device_id_type
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'device_commands'
    and column_name = 'device_id'
  limit 1;

  if v_device_id_type = 'uuid' then
    insert into public.device_commands (
      device_id,
      command,
      payload,
      status,
      requested_by,
      requested_at,
      expires_at
    )
    values (
      p_device_id,
      p_command,
      v_payload,
      'queued',
      v_uid,
      now(),
      now() + interval '7 days'
    )
    returning id into v_command_id;
  else
    execute $sql$
      insert into public.device_commands (
        device_id,
        command,
        payload,
        status,
        requested_by,
        requested_at,
        expires_at
      )
      values (
        $1::text,
        $2,
        $3,
        'queued',
        $4,
        now(),
        now() + interval '7 days'
      )
      returning id
    $sql$
    into v_command_id
    using p_device_id, p_command, v_payload, v_uid;
  end if;

  insert into public.device_events (
    device_id,
    event_type,
    severity,
    summary,
    source,
    payload,
    operator_id
  )
  values (
    p_device_id,
    'command_queued',
    'info',
    'Control Center command queued for operator app/device poll',
    'control_center',
    jsonb_build_object('command_id', v_command_id, 'command', p_command),
    v_uid
  );

  return jsonb_build_object(
    'id', v_command_id,
    'device_id', p_device_id,
    'command', p_command,
    'status', 'queued',
    'message', 'Queued - waiting for a connected operator app or device poll'
  );
end;
$$;

revoke all on function public.get_control_center_devices() from public, anon;
revoke all on function public.get_control_center_overview() from public, anon;
revoke all on function public.get_control_center_device_detail(uuid) from public, anon;
revoke all on function public.get_control_center_events(
  integer, uuid, text, text, timestamptz, timestamptz
) from public, anon;
revoke all on function public.control_center_supported_commands() from public, anon;
revoke all on function public.create_control_center_device_command(uuid, text, jsonb)
  from public, anon;

grant execute on function public.get_control_center_devices() to authenticated;
grant execute on function public.get_control_center_overview() to authenticated;
grant execute on function public.get_control_center_device_detail(uuid) to authenticated;
grant execute on function public.get_control_center_events(
  integer, uuid, text, text, timestamptz, timestamptz
) to authenticated;
grant execute on function public.control_center_supported_commands() to authenticated;
grant execute on function public.create_control_center_device_command(uuid, text, jsonb)
  to authenticated;

comment on function public.control_center_is_internal_admin()
  is 'DB-backed authorization gate for the MAGMA internal Control Center.';
comment on function public.control_center_device_health(
  timestamptz, text, text, integer, integer, interval
)
  is 'Central device health calculation for Control Center fleet views.';
comment on table public.ble_sessions
  is 'Observed BLE sessions reported by trusted backend/app flows; not a direct cloud online signal.';
comment on table public.device_commands
  is 'Asynchronous command queue. Devices receive commands only through app/device polling, not direct browser-to-BLE.';

notify pgrst, 'reload schema';
