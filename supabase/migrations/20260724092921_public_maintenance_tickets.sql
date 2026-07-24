-- Public maintenance ticket flow for IC01/GEDA.
-- Existing domain table `tickets` is extended instead of introducing a duplicate
-- ticket table. The public web form calls only the Edge Function, which then
-- invokes create_public_maintenance_ticket with the service role.

create extension if not exists pgcrypto;

create or replace function public.normalize_machine_code(input text)
returns text
language sql
immutable
as $$
  select regexp_replace(upper(trim(coalesce(input, ''))), '[[:space:]-]+', '', 'g');
$$;

create or replace function public.current_app_role()
returns text
language plpgsql
stable
security definer
set search_path = public
set row_security = off
as $$
declare
  v_role text;
begin
  select p.role
  into v_role
  from public.profiles p
  where p.id = auth.uid()
  limit 1;

  return v_role;
end;
$$;

revoke all on function public.current_app_role() from public, anon;
grant execute on function public.current_app_role() to authenticated;

alter table if exists public.tickets
  add column if not exists reason text,
  add column if not exists source text not null default 'operator_app',
  add column if not exists machine_code_snapshot text,
  add column if not exists assigned_operator_id uuid references public.profiles(id),
  add column if not exists resolved_at timestamptz,
  add column if not exists resolution_time_seconds bigint,
  add column if not exists duplicate_report_count integer not null default 0,
  add column if not exists updated_at timestamptz not null default now();

do $$
begin
  if to_regclass('public.tickets') is not null then
    if exists (
      select 1
      from pg_constraint
      where conname = 'tickets_status_check'
        and conrelid = 'public.tickets'::regclass
    ) then
      alter table public.tickets drop constraint tickets_status_check;
    end if;

    if not exists (
      select 1
      from pg_constraint
      where conname = 'tickets_reason_check'
        and conrelid = 'public.tickets'::regclass
    ) then
      alter table public.tickets
        add constraint tickets_reason_check
        check (reason is null or reason in ('out_of_stock', 'malfunction'))
        not valid;
    end if;

    if not exists (
      select 1
      from pg_constraint
      where conname = 'tickets_status_check_v2'
        and conrelid = 'public.tickets'::regclass
    ) then
      alter table public.tickets
        add constraint tickets_status_check_v2
        check (status in ('open', 'assigned', 'in_progress', 'resolved', 'cancelled', 'closed'))
        not valid;
    end if;

    if not exists (
      select 1
      from pg_constraint
      where conname = 'tickets_source_check'
        and conrelid = 'public.tickets'::regclass
    ) then
      alter table public.tickets
        add constraint tickets_source_check
        check (source in ('operator_app', 'admin_app', 'public_web'))
        not valid;
    end if;
  end if;
end $$;

create table if not exists public.ticket_events (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.tickets(id) on delete cascade,
  event_type text not null check (
    event_type in (
      'created',
      'duplicate_reported',
      'assigned',
      'status_changed',
      'resolved',
      'reopened'
    )
  ),
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists ticket_events_ticket_id_created_at_idx
  on public.ticket_events (ticket_id, created_at desc);

create table if not exists public.public_ticket_request_log (
  id uuid primary key default gen_random_uuid(),
  ip_hash text not null,
  machine_code_hash text,
  accepted boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists public_ticket_request_log_ip_created_at_idx
  on public.public_ticket_request_log (ip_hash, created_at desc);

create table if not exists public.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text not null,
  data jsonb not null default '{}'::jsonb,
  status text not null default 'pending'
    check (status in ('pending', 'sent', 'failed')),
  attempts int not null default 0,
  last_error text,
  scheduled_for timestamptz not null default now(),
  sent_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists notification_outbox_status_scheduled_idx
  on public.notification_outbox (status, scheduled_for);
create index if not exists notification_outbox_user_created_at_idx
  on public.notification_outbox (user_id, created_at desc);

create index if not exists tickets_machine_id_idx
  on public.tickets (machine_id);
create index if not exists tickets_status_idx
  on public.tickets (status);
create index if not exists tickets_created_at_idx
  on public.tickets (created_at desc);
create index if not exists tickets_resolved_at_idx
  on public.tickets (resolved_at desc)
  where resolved_at is not null;
create index if not exists tickets_assigned_technician_id_idx
  on public.tickets (assigned_technician_id)
  where assigned_technician_id is not null;
create index if not exists tickets_assigned_operator_id_idx
  on public.tickets (assigned_operator_id)
  where assigned_operator_id is not null;
create index if not exists tickets_client_id_idx
  on public.tickets (client_id);
create index if not exists tickets_reason_idx
  on public.tickets (reason)
  where reason is not null;
create index if not exists machines_code_normalized_idx
  on public.machines (public.normalize_machine_code(code));

do $$
begin
  if not exists (
    select 1
    from (
      select public.normalize_machine_code(code) as normalized_code
      from public.machines
      where code is not null and trim(code) <> ''
      group by public.normalize_machine_code(code)
      having count(*) > 1
    ) dupes
  ) then
    create unique index if not exists machines_code_normalized_unique_idx
      on public.machines (public.normalize_machine_code(code))
      where code is not null and trim(code) <> '';
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from (
      select machine_id, reason
      from public.tickets
      where reason is not null
        and status in ('open', 'assigned', 'in_progress')
      group by machine_id, reason
      having count(*) > 1
    ) dupes
  ) then
    create unique index if not exists tickets_open_machine_reason_unique_idx
      on public.tickets (machine_id, reason)
      where reason is not null and status in ('open', 'assigned', 'in_progress');
  end if;
end $$;

create or replace function public.touch_ticket_lifecycle()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();

  if new.status in ('resolved', 'closed') then
    new.resolved_at = coalesce(new.resolved_at, new.closed_at, now());
    new.closed_at = coalesce(new.closed_at, new.resolved_at);
    new.resolution_time_seconds =
      greatest(0, floor(extract(epoch from (new.resolved_at - new.created_at)))::bigint);
  elsif tg_op = 'UPDATE'
    and old.status in ('resolved', 'closed')
    and new.status not in ('resolved', 'closed') then
    new.resolved_at = null;
    new.closed_at = null;
    new.resolution_time_seconds = null;
  end if;

  return new;
end;
$$;

drop trigger if exists tickets_touch_lifecycle on public.tickets;
create trigger tickets_touch_lifecycle
before insert or update on public.tickets
for each row execute function public.touch_ticket_lifecycle();

create or replace function public.record_ticket_lifecycle_event()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.ticket_events (ticket_id, event_type, metadata)
    values (
      new.id,
      'created',
      jsonb_build_object('status', new.status, 'reason', new.reason, 'source', new.source)
    );
    return new;
  end if;

  if old.status is distinct from new.status then
    insert into public.ticket_events (ticket_id, event_type, metadata)
    values (
      new.id,
      case
        when new.status in ('resolved', 'closed') then 'resolved'
        when old.status in ('resolved', 'closed') and new.status not in ('resolved', 'closed') then 'reopened'
        when new.status = 'assigned' then 'assigned'
        else 'status_changed'
      end,
      jsonb_build_object('from', old.status, 'to', new.status)
    );
  end if;

  return new;
end;
$$;

drop trigger if exists tickets_record_lifecycle_event on public.tickets;
create trigger tickets_record_lifecycle_event
after insert or update of status on public.tickets
for each row execute function public.record_ticket_lifecycle_event();

create or replace function public.create_public_maintenance_ticket(
  p_machine_code text,
  p_reason text,
  p_reporter_hash text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_normalized_code text;
  v_machine_id uuid;
  v_machine_code text;
  v_machine_json jsonb;
  v_site_id uuid;
  v_client_id uuid;
  v_client_name text;
  v_assigned_operator_id uuid;
  v_existing_ticket_id uuid;
  v_ticket_id uuid;
  v_dupe_count integer;
begin
  v_normalized_code := public.normalize_machine_code(p_machine_code);

  if v_normalized_code = '' then
    return jsonb_build_object('ok', false, 'code', 'missing_machine_code');
  end if;

  if p_reason not in ('out_of_stock', 'malfunction') then
    return jsonb_build_object('ok', false, 'code', 'invalid_reason');
  end if;

  select
    m.id,
    m.code,
    to_jsonb(m),
    m.site_id,
    s.client_id,
    c.name,
    m.assigned_operator_id
  into
    v_machine_id,
    v_machine_code,
    v_machine_json,
    v_site_id,
    v_client_id,
    v_client_name,
    v_assigned_operator_id
  from public.machines m
  left join public.sites s on s.id = m.site_id
  left join public.clients c on c.id = s.client_id
  where public.normalize_machine_code(m.code) = v_normalized_code
  order by m.created_at desc nulls last
  limit 1;

  if v_machine_id is null then
    return jsonb_build_object('ok', false, 'code', 'machine_not_found');
  end if;

  if (v_machine_json ? 'is_active')
    and lower(v_machine_json ->> 'is_active') in ('false', 'f', '0', 'no') then
    return jsonb_build_object('ok', false, 'code', 'machine_inactive');
  end if;

  if (v_machine_json ? 'active')
    and lower(v_machine_json ->> 'active') in ('false', 'f', '0', 'no') then
    return jsonb_build_object('ok', false, 'code', 'machine_inactive');
  end if;

  if (v_machine_json ? 'status')
    and lower(v_machine_json ->> 'status') in ('inactive', 'disabled', 'archived', 'decommissioned') then
    return jsonb_build_object('ok', false, 'code', 'machine_inactive');
  end if;

  select id, duplicate_report_count
  into v_existing_ticket_id, v_dupe_count
  from public.tickets
  where machine_id = v_machine_id
    and reason = p_reason
    and status in ('open', 'assigned', 'in_progress')
  order by created_at asc
  limit 1
  for update;

  if v_existing_ticket_id is not null then
    update public.tickets
    set duplicate_report_count = coalesce(duplicate_report_count, 0) + 1
    where id = v_existing_ticket_id;

    insert into public.ticket_events (ticket_id, event_type, metadata)
    values (
      v_existing_ticket_id,
      'duplicate_reported',
      jsonb_build_object(
        'reason', p_reason,
        'source', 'public_web',
        'reporter_hash', p_reporter_hash
      )
    );

    return jsonb_build_object(
      'ok', true,
      'duplicate', true,
      'ticket_id', v_existing_ticket_id,
      'message', 'La segnalazione risulta già aperta ed è stata presa in carico.'
    );
  end if;

  insert into public.tickets (
    machine_id,
    client_id,
    site_id,
    status,
    reason,
    source,
    description,
    machine_code_snapshot,
    assigned_operator_id
  )
  values (
    v_machine_id,
    v_client_id,
    v_site_id,
    'open',
    p_reason,
    'public_web',
    case
      when p_reason = 'out_of_stock' then 'Segnalazione pubblica: scorte finite'
      when p_reason = 'malfunction' then 'Segnalazione pubblica: malfunzionamento'
    end,
    v_machine_code,
    v_assigned_operator_id
  )
  returning id into v_ticket_id;

  if v_assigned_operator_id is not null then
    insert into public.notification_outbox (
      user_id,
      title,
      body,
      data,
      scheduled_for
    )
    values (
      v_assigned_operator_id,
      'Nuova segnalazione manutenzione',
      concat(
        'Macchina ', v_machine_code,
        ' • ',
        case
          when p_reason = 'out_of_stock' then 'Scorte finite'
          else 'Malfunzionamento'
        end,
        coalesce(' • Cliente ' || v_client_name, '')
      ),
      jsonb_build_object(
        'route', '/maintenance/' || v_ticket_id::text,
        'ticket_id', v_ticket_id,
        'machine_code', v_machine_code,
        'reason', p_reason,
        'client_name', v_client_name,
        'created_at', now()
      ),
      now()
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'duplicate', false,
    'ticket_id', v_ticket_id,
    'message', 'Segnalazione inviata correttamente.'
  );
exception
  when unique_violation then
    select id
    into v_existing_ticket_id
    from public.tickets
    where machine_id = v_machine_id
      and reason = p_reason
      and status in ('open', 'assigned', 'in_progress')
    order by created_at asc
    limit 1;

    if v_existing_ticket_id is not null then
      return jsonb_build_object(
        'ok', true,
        'duplicate', true,
        'ticket_id', v_existing_ticket_id,
        'message', 'La segnalazione risulta già aperta ed è stata presa in carico.'
      );
    end if;

    raise;
end;
$$;

revoke all on function public.create_public_maintenance_ticket(text, text, text)
  from public, anon, authenticated;
grant execute on function public.create_public_maintenance_ticket(text, text, text)
  to service_role;

drop view if exists public.ticket_list;
create view public.ticket_list
with (security_invoker = true)
as
select
  t.id as ticket_id,
  t.status,
  t.reason,
  t.source,
  t.description,
  t.created_at,
  t.updated_at,
  t.assigned_technician_id,
  tech.full_name as assigned_technician_name,
  t.assigned_operator_id,
  op.full_name as assigned_operator_name,
  t.assigned_at,
  t.closed_at,
  t.resolved_at,
  t.resolution_time_seconds,
  t.duplicate_report_count,
  t.machine_id,
  coalesce(t.machine_code_snapshot, m.code) as machine_code,
  t.client_id,
  c.name as client_name,
  t.site_id,
  s.name as site_name,
  s.address as site_address,
  s.city as site_city
from public.tickets t
join public.machines m on m.id = t.machine_id
left join public.sites s on s.id = t.site_id
left join public.clients c on c.id = t.client_id
left join public.profiles tech on tech.id = t.assigned_technician_id
left join public.profiles op on op.id = t.assigned_operator_id;

grant select on public.ticket_list to authenticated;
revoke all on public.ticket_list from anon;

grant select on public.profiles to authenticated;
grant select on public.clients to authenticated;
grant select on public.sites to authenticated;
grant select on public.machines to authenticated;
grant select, insert, update on public.tickets to authenticated;
grant select on public.ticket_events to authenticated;
grant select on public.notification_outbox to authenticated;

alter table public.tickets enable row level security;
alter table public.ticket_events enable row level security;
alter table public.public_ticket_request_log enable row level security;
alter table public.notification_outbox enable row level security;
alter table public.profiles enable row level security;
alter table public.clients enable row level security;
alter table public.sites enable row level security;
alter table public.machines enable row level security;

drop policy if exists profiles_select_self_or_admin on public.profiles;
drop policy if exists profiles_select_own_or_admin on public.profiles;
create policy profiles_select_own_or_admin
  on public.profiles
  for select
  to authenticated
  using (
    id = (select auth.uid())
    or public.current_app_role() = 'admin'
  );

drop policy if exists clients_select_by_role on public.clients;
create policy clients_select_by_role
  on public.clients
  for select
  to authenticated
  using (
    public.current_app_role() in ('admin', 'technician')
    or exists (
      select 1
      from public.sites s
      join public.machines m on m.site_id = s.id
      where s.client_id = clients.id
        and m.assigned_operator_id = (select auth.uid())
    )
  );

drop policy if exists sites_select_by_role on public.sites;
create policy sites_select_by_role
  on public.sites
  for select
  to authenticated
  using (
    public.current_app_role() in ('admin', 'technician')
    or exists (
      select 1
      from public.machines m
      where m.site_id = sites.id
        and m.assigned_operator_id = (select auth.uid())
    )
  );

drop policy if exists machines_select_by_role on public.machines;
create policy machines_select_by_role
  on public.machines
  for select
  to authenticated
  using (
    assigned_operator_id = (select auth.uid())
    or public.current_app_role() in ('admin', 'technician')
  );

drop policy if exists tickets_select_by_role on public.tickets;
create policy tickets_select_by_role
  on public.tickets
  for select
  to authenticated
  using (
    assigned_technician_id = (select auth.uid())
    or assigned_operator_id = (select auth.uid())
    or public.current_app_role() in ('admin', 'technician')
  );

drop policy if exists tickets_insert_admin_or_technician on public.tickets;
create policy tickets_insert_admin_or_technician
  on public.tickets
  for insert
  to authenticated
  with check (
    public.current_app_role() in ('admin', 'technician')
  );

drop policy if exists tickets_update_admin_or_technician on public.tickets;
create policy tickets_update_admin_or_technician
  on public.tickets
  for update
  to authenticated
  using (
    public.current_app_role() in ('admin', 'technician')
  )
  with check (
    public.current_app_role() in ('admin', 'technician')
  );

drop policy if exists ticket_events_select_by_ticket_access on public.ticket_events;
create policy ticket_events_select_by_ticket_access
  on public.ticket_events
  for select
  to authenticated
  using (
    exists (
      select 1 from public.tickets t
      where t.id = ticket_events.ticket_id
        and (
          t.assigned_technician_id = (select auth.uid())
          or t.assigned_operator_id = (select auth.uid())
          or public.current_app_role() in ('admin', 'technician')
        )
    )
  );

drop policy if exists notification_outbox_select_own on public.notification_outbox;
create policy notification_outbox_select_own
  on public.notification_outbox
  for select
  to authenticated
  using (user_id = (select auth.uid()));

revoke all on public.public_ticket_request_log from anon, authenticated;
revoke all on public.ticket_events from anon;
revoke all on public.tickets from anon;
revoke all on public.machines from anon;
revoke all on public.clients from anon;
revoke all on public.sites from anon;
