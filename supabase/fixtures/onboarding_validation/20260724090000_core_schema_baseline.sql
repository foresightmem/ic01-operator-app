-- Core schema baseline for local/disposable database validation.
-- Historical migrations in this repository start from public maintenance
-- changes and assume the operational tables already exist. This idempotent
-- baseline captures the pre-existing core schema so a fresh local database can
-- apply the full migration history in order.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role text not null check (role in ('refill_operator', 'technician', 'admin')),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  vat_number text,
  notes text,
  created_at timestamptz default now()
);

create table if not exists public.sites (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  name text not null,
  address text,
  city text,
  lat double precision,
  lon double precision,
  created_at timestamptz default now()
);

create table if not exists public.machines (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  site_id uuid not null references public.sites(id) on delete cascade,
  assigned_operator_id uuid not null references public.profiles(id),
  capacity_water_ml integer,
  current_fill_percent numeric not null default 100,
  yearly_shots integer not null default 0,
  hw_serial text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  water_tank_enabled boolean not null default false,
  temperature_mode text not null default 'hot'
    check (temperature_mode in ('hot', 'cold'))
);

do $$
begin
  if not exists (select 1 from pg_type where typname = 'consumable_type') then
    create type public.consumable_type as enum (
      'hot',
      'cold',
      'coffee',
      'milk',
      'powder',
      'water'
    );
  end if;
end $$;

create table if not exists public.machine_consumables (
  id uuid primary key default gen_random_uuid(),
  machine_id uuid not null references public.machines(id) on delete cascade,
  type public.consumable_type not null,
  capacity_units integer not null default 0,
  current_units integer not null default 0,
  is_enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  unique (machine_id, type),
  constraint machine_consumables_nonneg
    check (
      capacity_units >= 0
      and current_units >= 0
      and current_units <= capacity_units
    )
);

create table if not exists public.refills (
  id uuid primary key default gen_random_uuid(),
  machine_id uuid not null references public.machines(id) on delete cascade,
  operator_id uuid not null references public.profiles(id),
  created_at timestamptz default now(),
  previous_fill_percent numeric,
  new_fill_percent numeric not null default 100,
  undone_at timestamptz,
  undone_by uuid references public.profiles(id),
  note text
);

create table if not exists public.tickets (
  id uuid primary key default gen_random_uuid(),
  machine_id uuid not null references public.machines(id) on delete cascade,
  client_id uuid not null references public.clients(id) on delete cascade,
  site_id uuid references public.sites(id) on delete set null,
  status text not null default 'open'
    check (status in ('open', 'assigned', 'in_progress', 'closed')),
  requester_name text,
  requester_contact text,
  description text,
  assigned_technician_id uuid references public.profiles(id) on delete set null,
  assigned_at timestamptz,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.visits (
  id uuid primary key default gen_random_uuid(),
  operator_id uuid not null references public.profiles(id) on delete restrict,
  client_id uuid not null references public.clients(id) on delete cascade,
  site_id uuid references public.sites(id) on delete set null,
  visit_type text not null check (visit_type in ('refill', 'maintenance')),
  ticket_id uuid references public.tickets(id) on delete set null,
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.operator_unavailability (
  id uuid primary key default gen_random_uuid(),
  operator_id uuid not null references public.profiles(id),
  start_date date not null,
  end_date date not null,
  reason text,
  created_at timestamptz not null default now(),
  check (end_date >= start_date)
);

create table if not exists public.temp_machine_assignments (
  id uuid primary key default gen_random_uuid(),
  machine_id uuid not null references public.machines(id) on delete cascade,
  original_operator_id uuid not null references public.profiles(id),
  new_operator_id uuid not null references public.profiles(id),
  start_date date not null,
  end_date date not null,
  status text not null default 'pending'
    check (status in ('pending', 'confirmed', 'cancelled')),
  created_at timestamptz not null default now(),
  check (end_date >= start_date)
);

create index if not exists machines_site_id_idx on public.machines(site_id);
create index if not exists machines_assigned_operator_id_idx
  on public.machines(assigned_operator_id);
create index if not exists machine_consumables_machine_id_idx
  on public.machine_consumables(machine_id);
create index if not exists temp_machine_assignments_machine_status_idx
  on public.temp_machine_assignments(machine_id, status);

create or replace function public.set_current_timestamp_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.fill_percent_to_state(p numeric)
returns text
language sql
immutable
as $$
  select case
    when p <= 10 then 'black'
    when p <= 20 then 'red'
    when p <= 40 then 'yellow'
    else 'green'
  end;
$$;

create or replace function public.sync_machine_current_fill_percent()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_mode text;
  v_active_type public.consumable_type;
  v_percent numeric;
begin
  select temperature_mode into v_mode
  from public.machines
  where id = new.machine_id;

  v_active_type := case v_mode
    when 'cold' then 'cold'::public.consumable_type
    else 'hot'::public.consumable_type
  end;

  if new.type <> v_active_type or new.is_enabled is not true then
    return new;
  end if;

  v_percent := case
    when new.capacity_units > 0 then
      round(new.current_units::numeric / new.capacity_units::numeric * 100, 2)
    else 0
  end;

  update public.machines
  set current_fill_percent = v_percent,
      updated_at = now()
  where id = new.machine_id;

  return new;
end;
$$;

drop trigger if exists trg_sync_machine_current_fill_percent
  on public.machine_consumables;
create trigger trg_sync_machine_current_fill_percent
after insert or update on public.machine_consumables
for each row execute function public.sync_machine_current_fill_percent();

create or replace function public.apply_refill()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  update public.machines
  set current_fill_percent = new.new_fill_percent,
      updated_at = now()
  where id = new.machine_id;
  return new;
end;
$$;

drop trigger if exists on_refill_insert on public.refills;
create trigger on_refill_insert
after insert on public.refills
for each row execute function public.apply_refill();

create or replace function public.perform_refill_consumable(
  p_machine_id uuid,
  p_type public.consumable_type
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_allowed boolean;
  v_prev integer;
  v_cap integer;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  select exists (
    select 1
    from public.machines m
    where m.id = p_machine_id
      and (
        m.assigned_operator_id = v_uid
        or exists (
          select 1
          from public.temp_machine_assignments t
          where t.machine_id = m.id
            and t.status = 'confirmed'
            and current_date between t.start_date and t.end_date
            and t.new_operator_id = v_uid
        )
      )
  ) into v_allowed;

  if not v_allowed then
    raise exception 'Not allowed for this machine';
  end if;

  select mc.current_units, mc.capacity_units
  into v_prev, v_cap
  from public.machine_consumables mc
  where mc.machine_id = p_machine_id
    and mc.type = p_type
    and mc.is_enabled = true;

  if v_cap is null then
    raise exception 'Consumable disabled or not found';
  end if;

  update public.machine_consumables
  set current_units = capacity_units,
      updated_at = now()
  where machine_id = p_machine_id
    and type = p_type
    and is_enabled = true;

  return json_build_object(
    'ok', true,
    'machine_id', p_machine_id,
    'type', p_type::text,
    'previous_units', v_prev,
    'capacity_units', v_cap,
    'new_units', v_cap
  );
end;
$$;

revoke all on function public.perform_refill_consumable(
  uuid,
  public.consumable_type
) from public, anon;
grant execute on function public.perform_refill_consumable(
  uuid,
  public.consumable_type
) to authenticated;

drop view if exists public.machine_effective_consumables;
drop view if exists public.client_states_effective;
drop view if exists public.machine_effective_assignment;
drop view if exists public.client_machines;
drop view if exists public.client_states;
drop view if exists public.machine_states;

create view public.machine_states
with (security_invoker = true)
as
with effective_assignment as (
  select
    m.id,
    m.code,
    m.site_id,
    coalesce(t.new_operator_id, m.assigned_operator_id) as assigned_operator_id,
    m.yearly_shots,
    m.created_at,
    m.updated_at
  from public.machines m
  left join lateral (
    select tma.new_operator_id
    from public.temp_machine_assignments tma
    where tma.machine_id = m.id
      and tma.status = 'confirmed'
      and current_date >= tma.start_date
      and current_date <= tma.end_date
    order by tma.start_date desc
    limit 1
  ) t on true
),
worst as (
  select
    mc.machine_id,
    min(mc.current_units::numeric / nullif(mc.capacity_units, 0)::numeric * 100)::numeric(5, 2)
      as current_fill_percent
  from public.machine_consumables mc
  where mc.is_enabled = true
    and mc.capacity_units > 0
  group by mc.machine_id
)
select
  ea.id as machine_id,
  ea.code,
  ea.site_id,
  ea.assigned_operator_id,
  coalesce(w.current_fill_percent, 0::numeric)::numeric(5, 2)
    as current_fill_percent,
  public.fill_percent_to_state(
    coalesce(w.current_fill_percent, 0::numeric)::numeric(5, 2)
  ) as state,
  ea.yearly_shots,
  ea.created_at,
  ea.updated_at
from effective_assignment ea
left join worst w on w.machine_id = ea.id;

create view public.machine_effective_assignment
with (security_invoker = true)
as
with eff as (
  select
    m.id as machine_id,
    m.code as machine_code,
    m.site_id,
    coalesce(t.new_operator_id, m.assigned_operator_id) as effective_operator_id
  from public.machines m
  left join lateral (
    select tma.new_operator_id
    from public.temp_machine_assignments tma
    where tma.machine_id = m.id
      and tma.status = 'confirmed'
      and current_date >= tma.start_date
      and current_date <= tma.end_date
    order by tma.start_date desc
    limit 1
  ) t on true
)
select
  eff.machine_id,
  eff.machine_code,
  eff.site_id,
  eff.effective_operator_id,
  s.name as site_name,
  s.city as site_city,
  c.id as client_id,
  c.name as client_name,
  ms.current_fill_percent,
  ms.state
from eff
join public.sites s on s.id = eff.site_id
join public.clients c on c.id = s.client_id
join public.machine_states ms on ms.machine_id = eff.machine_id;

create view public.client_states_effective
with (security_invoker = true)
as
select
  effective_operator_id as assigned_operator_id,
  client_id,
  client_name as name,
  count(distinct machine_id) as total_machines,
  count(*) filter (where current_fill_percent < 20) as machines_to_refill,
  max(
    case state
      when 'black' then 4
      when 'red' then 3
      when 'yellow' then 2
      else 1
    end
  ) as worst_state_rank
from public.machine_effective_assignment
group by effective_operator_id, client_id, client_name;

create view public.machine_effective_consumables
with (security_invoker = true)
as
select
  mea.machine_id,
  mea.machine_code,
  mea.effective_operator_id,
  mea.client_id,
  mea.client_name,
  mea.site_name,
  mea.site_city,
  mc.type,
  mc.capacity_units,
  mc.current_units,
  case
    when mc.capacity_units > 0 then
      round(mc.current_units::numeric / mc.capacity_units::numeric * 100, 2)
    else 0::numeric
  end as fill_percent
from public.machine_effective_assignment mea
join public.machine_consumables mc on mc.machine_id = mea.machine_id
where mc.is_enabled = true;

create view public.client_states
with (security_invoker = true)
as
select
  assigned_operator_id,
  client_id,
  name,
  total_machines,
  machines_to_refill,
  case worst_state_rank
    when 4 then 'black'
    when 3 then 'red'
    when 2 then 'yellow'
    else 'green'
  end as worst_state
from public.client_states_effective;

create view public.client_machines
with (security_invoker = true)
as
select
  mea.effective_operator_id as assigned_operator_id,
  mea.client_id,
  mea.client_name,
  mea.machine_id,
  mea.machine_code,
  mea.site_name,
  mea.site_city,
  mea.current_fill_percent,
  mea.state
from public.machine_effective_assignment mea;

grant select on public.machine_states to authenticated;
grant select on public.machine_effective_assignment to authenticated;
grant select on public.client_states_effective to authenticated;
grant select on public.machine_effective_consumables to authenticated;
grant select on public.client_states to authenticated;
grant select on public.client_machines to authenticated;

alter table public.profiles enable row level security;
alter table public.clients enable row level security;
alter table public.sites enable row level security;
alter table public.machines enable row level security;
alter table public.refills enable row level security;
alter table public.visits enable row level security;
