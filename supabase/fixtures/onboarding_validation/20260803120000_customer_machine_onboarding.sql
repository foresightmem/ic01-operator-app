-- Customer, site, and machine onboarding.
-- The project already models customer locations as public.sites and installs
-- machines through machines.site_id, so this migration adds only the missing
-- transactional entry points and minimal audit/access support.

create extension if not exists pgcrypto;

alter table public.clients
  add column if not exists created_by uuid references public.profiles(id),
  add column if not exists updated_at timestamptz not null default now();

alter table public.sites
  add column if not exists created_by uuid references public.profiles(id),
  add column if not exists updated_at timestamptz not null default now();

alter table public.machines
  add column if not exists created_by uuid references public.profiles(id);

create index if not exists clients_created_by_idx
  on public.clients (created_by)
  where created_by is not null;

create index if not exists sites_client_id_idx
  on public.sites (client_id);

create index if not exists sites_created_by_idx
  on public.sites (created_by)
  where created_by is not null;

create index if not exists machines_created_by_idx
  on public.machines (created_by)
  where created_by is not null;

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

drop trigger if exists set_timestamp_on_clients on public.clients;
create trigger set_timestamp_on_clients
before update on public.clients
for each row execute function public.set_current_timestamp_updated_at();

drop trigger if exists set_timestamp_on_sites on public.sites;
create trigger set_timestamp_on_sites
before update on public.sites
for each row execute function public.set_current_timestamp_updated_at();

drop trigger if exists set_timestamp_on_machines on public.machines;
create trigger set_timestamp_on_machines
before update on public.machines
for each row execute function public.set_current_timestamp_updated_at();

create or replace function public.onboarding_actor_role()
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

  if v_role not in ('admin', 'refill_operator') then
    raise exception 'Ruolo non autorizzato per onboarding';
  end if;

  return v_role;
end;
$$;

revoke all on function public.onboarding_actor_role() from public, anon;
grant execute on function public.onboarding_actor_role() to authenticated;

create or replace function public.create_client_with_primary_site(
  p_client_name text,
  p_site_address text,
  p_site_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_client_name text := trim(coalesce(p_client_name, ''));
  v_site_address text := trim(coalesce(p_site_address, ''));
  v_site_name text := nullif(trim(coalesce(p_site_name, '')), '');
  v_client_id uuid;
  v_site_id uuid;
begin
  if v_uid is null then
    raise exception 'Utente non autenticato';
  end if;

  v_role := public.onboarding_actor_role();

  if v_client_name = '' then
    raise exception 'Il nome cliente è obbligatorio';
  end if;

  if v_site_address = '' then
    raise exception 'L''indirizzo della sede principale è obbligatorio';
  end if;

  insert into public.clients (name, created_by)
  values (v_client_name, v_uid)
  returning id into v_client_id;

  insert into public.sites (client_id, name, address, created_by)
  values (
    v_client_id,
    coalesce(v_site_name, 'Sede principale'),
    v_site_address,
    v_uid
  )
  returning id into v_site_id;

  return jsonb_build_object(
    'client_id', v_client_id,
    'client_name', v_client_name,
    'site_id', v_site_id,
    'site_name', coalesce(v_site_name, 'Sede principale'),
    'role', v_role
  );
end;
$$;

revoke all on function public.create_client_with_primary_site(text, text, text)
  from public, anon;
grant execute on function public.create_client_with_primary_site(text, text, text)
  to authenticated;

create or replace function public.add_site_to_client(
  p_client_id uuid,
  p_site_address text,
  p_site_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_site_address text := trim(coalesce(p_site_address, ''));
  v_site_name text := nullif(trim(coalesce(p_site_name, '')), '');
  v_client_name text;
  v_allowed boolean;
  v_site_id uuid;
begin
  if v_uid is null then
    raise exception 'Utente non autenticato';
  end if;

  v_role := public.onboarding_actor_role();

  if p_client_id is null then
    raise exception 'Cliente obbligatorio';
  end if;

  if v_site_address = '' then
    raise exception 'L''indirizzo della sede è obbligatorio';
  end if;

  select c.name
  into v_client_name
  from public.clients c
  where c.id = p_client_id;

  if v_client_name is null then
    raise exception 'Cliente non trovato';
  end if;

  select (
    v_role = 'admin'
    or exists (
      select 1
      from public.clients c
      where c.id = p_client_id
        and c.created_by = v_uid
    )
    or exists (
      select 1
      from public.sites s
      join public.machines m on m.site_id = s.id
      where s.client_id = p_client_id
        and m.assigned_operator_id = v_uid
    )
    or exists (
      select 1
      from public.sites s
      join public.machines m on m.site_id = s.id
      join public.temp_machine_assignments t on t.machine_id = m.id
      where s.client_id = p_client_id
        and t.status = 'confirmed'
        and current_date between t.start_date and t.end_date
        and t.new_operator_id = v_uid
    )
  ) into v_allowed;

  if not v_allowed then
    raise exception 'Non autorizzato per questo cliente';
  end if;

  insert into public.sites (client_id, name, address, created_by)
  values (p_client_id, coalesce(v_site_name, 'Sede'), v_site_address, v_uid)
  returning id into v_site_id;

  return jsonb_build_object(
    'site_id', v_site_id,
    'site_name', coalesce(v_site_name, 'Sede'),
    'client_id', p_client_id,
    'client_name', v_client_name
  );
end;
$$;

revoke all on function public.add_site_to_client(uuid, text, text)
  from public, anon;
grant execute on function public.add_site_to_client(uuid, text, text)
  to authenticated;

create or replace function public.create_machine_for_site(
  p_client_id uuid,
  p_site_id uuid,
  p_code text,
  p_temperature_mode text,
  p_capacity_units integer,
  p_assigned_operator_id uuid default null,
  p_hw_serial text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_code text := upper(trim(coalesce(p_code, '')));
  v_normalized_code text;
  v_temperature_mode text := lower(trim(coalesce(p_temperature_mode, '')));
  v_hw_serial text := nullif(trim(coalesce(p_hw_serial, '')), '');
  v_assigned_operator_id uuid;
  v_operator_role text;
  v_site_matches boolean;
  v_machine_id uuid;
begin
  if v_uid is null then
    raise exception 'Utente non autenticato';
  end if;

  v_role := public.onboarding_actor_role();

  if p_client_id is null or p_site_id is null then
    raise exception 'Cliente e sede sono obbligatori';
  end if;

  if v_code = '' then
    raise exception 'Il codice macchina è obbligatorio';
  end if;

  v_normalized_code := public.normalize_machine_code(v_code);
  if v_normalized_code = '' then
    raise exception 'Il codice macchina non è valido';
  end if;

  if v_temperature_mode not in ('hot', 'cold') then
    raise exception 'Tipo macchina non valido';
  end if;

  if p_capacity_units is null or p_capacity_units <= 0 then
    raise exception 'La capacità massima deve essere un intero positivo';
  end if;

  select exists (
    select 1
    from public.sites s
    where s.id = p_site_id
      and s.client_id = p_client_id
  ) into v_site_matches;

  if not v_site_matches then
    raise exception 'La sede selezionata non appartiene al cliente';
  end if;

  if v_role = 'admin' then
    if p_assigned_operator_id is null then
      raise exception 'Seleziona un operatore assegnatario';
    end if;
    v_assigned_operator_id := p_assigned_operator_id;
  else
    v_assigned_operator_id := v_uid;
  end if;

  select p.role
  into v_operator_role
  from public.profiles p
  where p.id = v_assigned_operator_id;

  if v_operator_role is distinct from 'refill_operator' then
    raise exception 'L''assegnatario deve essere un operatore refill';
  end if;

  insert into public.machines (
    code,
    site_id,
    assigned_operator_id,
    current_fill_percent,
    yearly_shots,
    hw_serial,
    temperature_mode,
    created_by
  )
  values (
    v_code,
    p_site_id,
    v_assigned_operator_id,
    100,
    0,
    v_hw_serial,
    v_temperature_mode,
    v_uid
  )
  returning id into v_machine_id;

  insert into public.machine_consumables (
    machine_id,
    type,
    capacity_units,
    current_units,
    is_enabled,
    updated_at
  )
  values (
    v_machine_id,
    v_temperature_mode::public.consumable_type,
    p_capacity_units,
    p_capacity_units,
    true,
    now()
  );

  return jsonb_build_object(
    'machine_id', v_machine_id,
    'machine_code', v_code,
    'client_id', p_client_id,
    'site_id', p_site_id,
    'temperature_mode', v_temperature_mode,
    'capacity_units', p_capacity_units,
    'assigned_operator_id', v_assigned_operator_id
  );
exception
  when unique_violation then
    raise exception 'Il codice macchina è già in uso';
end;
$$;

revoke all on function public.create_machine_for_site(
  uuid, uuid, text, text, integer, uuid, text
) from public, anon;
grant execute on function public.create_machine_for_site(
  uuid, uuid, text, text, integer, uuid, text
) to authenticated;

drop policy if exists clients_select_created_by_user on public.clients;
create policy clients_select_created_by_user
  on public.clients
  for select
  to authenticated
  using (created_by = (select auth.uid()));

drop policy if exists sites_select_created_or_client_created_by_user
  on public.sites;
create policy sites_select_created_or_client_created_by_user
  on public.sites
  for select
  to authenticated
  using (
    created_by = (select auth.uid())
    or exists (
      select 1
      from public.clients c
      where c.id = sites.client_id
        and c.created_by = (select auth.uid())
    )
  );

drop policy if exists clients_select_by_effective_assignment
  on public.clients;
create policy clients_select_by_effective_assignment
  on public.clients
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.sites s
      join public.machines m on m.site_id = s.id
      join public.temp_machine_assignments t on t.machine_id = m.id
      where s.client_id = clients.id
        and t.status = 'confirmed'
        and current_date between t.start_date and t.end_date
        and t.new_operator_id = (select auth.uid())
    )
  );

drop policy if exists sites_select_by_effective_assignment
  on public.sites;
create policy sites_select_by_effective_assignment
  on public.sites
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.machines m
      join public.temp_machine_assignments t on t.machine_id = m.id
      where m.site_id = sites.id
        and t.status = 'confirmed'
        and current_date between t.start_date and t.end_date
        and t.new_operator_id = (select auth.uid())
    )
  );

alter table public.machine_consumables enable row level security;

revoke all on public.machine_consumables from anon;
grant select, insert, update on public.machine_consumables to authenticated;

drop policy if exists machine_consumables_select_by_machine_access
  on public.machine_consumables;
create policy machine_consumables_select_by_machine_access
  on public.machine_consumables
  for select
  to authenticated
  using (
    public.current_app_role() in ('admin', 'technician')
    or exists (
      select 1
      from public.machines m
      where m.id = machine_consumables.machine_id
        and m.assigned_operator_id = (select auth.uid())
    )
    or exists (
      select 1
      from public.temp_machine_assignments t
      where t.machine_id = machine_consumables.machine_id
        and t.status = 'confirmed'
        and current_date between t.start_date and t.end_date
        and t.new_operator_id = (select auth.uid())
    )
  );

drop policy if exists machine_consumables_insert_admin
  on public.machine_consumables;
create policy machine_consumables_insert_admin
  on public.machine_consumables
  for insert
  to authenticated
  with check (public.current_app_role() = 'admin');

drop policy if exists machine_consumables_update_admin
  on public.machine_consumables;
create policy machine_consumables_update_admin
  on public.machine_consumables
  for update
  to authenticated
  using (public.current_app_role() = 'admin')
  with check (public.current_app_role() = 'admin');

comment on function public.create_client_with_primary_site(text, text, text)
  is 'Creates a client and its first site atomically for admin/refill_operator onboarding.';

comment on function public.add_site_to_client(uuid, text, text)
  is 'Adds a site to an existing client after validating admin/refill_operator access.';

comment on function public.create_machine_for_site(uuid, uuid, text, text, integer, uuid, text)
  is 'Creates a machine at a site and initializes the active hot/cold consumable capacity atomically.';

comment on column public.machine_consumables.capacity_units
  is 'Maximum nominal units/doses for the enabled monitored factor of a machine; onboarding treats this as maximum loadable product count.';
