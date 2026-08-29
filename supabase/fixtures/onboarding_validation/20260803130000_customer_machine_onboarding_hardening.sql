-- Hardening for customer/site/machine onboarding:
-- - introduce explicit organization/tenant scope
-- - validate assigned operators in the same organization
-- - avoid permanent access based only on created_by
-- - scope direct machine_consumables access by machine organization

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

insert into public.organizations (id, name)
values ('00000000-0000-0000-0000-000000000001', 'Default organization')
on conflict (id) do nothing;

alter table public.profiles
  add column if not exists organization_id uuid references public.organizations(id);

alter table public.clients
  add column if not exists organization_id uuid references public.organizations(id);

alter table public.sites
  add column if not exists organization_id uuid references public.organizations(id);

alter table public.machines
  add column if not exists organization_id uuid references public.organizations(id);

update public.profiles
set organization_id = '00000000-0000-0000-0000-000000000001'
where organization_id is null;

update public.clients
set organization_id = '00000000-0000-0000-0000-000000000001'
where organization_id is null;

update public.sites s
set organization_id = c.organization_id
from public.clients c
where s.client_id = c.id
  and s.organization_id is null;

update public.machines m
set organization_id = s.organization_id
from public.sites s
where m.site_id = s.id
  and m.organization_id is null;

alter table public.profiles
  alter column organization_id set not null;

alter table public.clients
  alter column organization_id set not null;

alter table public.sites
  alter column organization_id set not null;

alter table public.machines
  alter column organization_id set not null;

create index if not exists profiles_organization_id_idx
  on public.profiles (organization_id);
create index if not exists clients_organization_id_idx
  on public.clients (organization_id);
create index if not exists sites_organization_id_idx
  on public.sites (organization_id);
create index if not exists machines_organization_id_idx
  on public.machines (organization_id);

create or replace function public.current_app_organization_id()
returns uuid
language plpgsql
stable
security definer
set search_path = public
set row_security = off
as $$
declare
  v_organization_id uuid;
begin
  select p.organization_id
  into v_organization_id
  from public.profiles p
  where p.id = auth.uid()
  limit 1;

  return v_organization_id;
end;
$$;

revoke all on function public.current_app_organization_id() from public, anon;
grant execute on function public.current_app_organization_id() to authenticated;

create or replace function public.onboarding_actor_context(
  out role text,
  out organization_id uuid
)
language plpgsql
stable
security definer
set search_path = public
set row_security = off
as $$
begin
  select p.role, p.organization_id
  into role, organization_id
  from public.profiles p
  where p.id = auth.uid()
  limit 1;

  if role not in ('admin', 'refill_operator') then
    raise exception 'Ruolo non autorizzato per onboarding';
  end if;

  if organization_id is null then
    raise exception 'Profilo senza organizzazione';
  end if;
end;
$$;

revoke all on function public.onboarding_actor_context() from public, anon;
grant execute on function public.onboarding_actor_context() to authenticated;

create or replace function public.client_has_no_machines(p_client_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select not exists (
    select 1
    from public.sites s
    join public.machines m on m.site_id = s.id
    where s.client_id = p_client_id
  );
$$;

create or replace function public.client_has_operator_access(
  p_client_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select exists (
    select 1
    from public.sites s
    join public.machines m on m.site_id = s.id
    where s.client_id = p_client_id
      and m.assigned_operator_id = p_user_id
  )
  or exists (
    select 1
    from public.sites s
    join public.machines m on m.site_id = s.id
    join public.temp_machine_assignments t on t.machine_id = m.id
    where s.client_id = p_client_id
      and t.status = 'confirmed'
      and current_date between t.start_date and t.end_date
      and t.new_operator_id = p_user_id
  );
$$;

create or replace function public.site_has_no_machines(p_site_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select not exists (
    select 1
    from public.machines m
    where m.site_id = p_site_id
  );
$$;

create or replace function public.site_has_operator_access(
  p_site_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select exists (
    select 1
    from public.machines m
    where m.site_id = p_site_id
      and m.assigned_operator_id = p_user_id
  )
  or exists (
    select 1
    from public.machines m
    join public.temp_machine_assignments t on t.machine_id = m.id
    where m.site_id = p_site_id
      and t.status = 'confirmed'
      and current_date between t.start_date and t.end_date
      and t.new_operator_id = p_user_id
  );
$$;

create or replace function public.machine_has_operator_access(
  p_machine_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select exists (
    select 1
    from public.machines m
    where m.id = p_machine_id
      and m.assigned_operator_id = p_user_id
  )
  or exists (
    select 1
    from public.temp_machine_assignments t
    where t.machine_id = p_machine_id
      and t.status = 'confirmed'
      and current_date between t.start_date and t.end_date
      and t.new_operator_id = p_user_id
  );
$$;

revoke all on function public.client_has_no_machines(uuid) from public, anon;
grant execute on function public.client_has_no_machines(uuid) to authenticated;

revoke all on function public.client_has_operator_access(uuid, uuid)
  from public, anon;
grant execute on function public.client_has_operator_access(uuid, uuid)
  to authenticated;

revoke all on function public.site_has_no_machines(uuid) from public, anon;
grant execute on function public.site_has_no_machines(uuid) to authenticated;

revoke all on function public.site_has_operator_access(uuid, uuid)
  from public, anon;
grant execute on function public.site_has_operator_access(uuid, uuid)
  to authenticated;

revoke all on function public.machine_has_operator_access(uuid, uuid)
  from public, anon;
grant execute on function public.machine_has_operator_access(uuid, uuid)
  to authenticated;

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
  v_organization_id uuid;
  v_client_name text := trim(coalesce(p_client_name, ''));
  v_site_address text := trim(coalesce(p_site_address, ''));
  v_site_name text := nullif(trim(coalesce(p_site_name, '')), '');
  v_client_id uuid;
  v_site_id uuid;
begin
  if v_uid is null then
    raise exception 'Utente non autenticato';
  end if;

  select ctx.role, ctx.organization_id
  into v_role, v_organization_id
  from public.onboarding_actor_context() ctx;

  if v_client_name = '' then
    raise exception 'Il nome cliente è obbligatorio';
  end if;

  if v_site_address = '' then
    raise exception 'L''indirizzo della sede principale è obbligatorio';
  end if;

  insert into public.clients (name, created_by, organization_id)
  values (v_client_name, v_uid, v_organization_id)
  returning id into v_client_id;

  insert into public.sites (client_id, name, address, created_by, organization_id)
  values (
    v_client_id,
    coalesce(v_site_name, 'Sede principale'),
    v_site_address,
    v_uid,
    v_organization_id
  )
  returning id into v_site_id;

  return jsonb_build_object(
    'client_id', v_client_id,
    'client_name', v_client_name,
    'site_id', v_site_id,
    'site_name', coalesce(v_site_name, 'Sede principale'),
    'role', v_role,
    'organization_id', v_organization_id
  );
end;
$$;

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
  v_organization_id uuid;
  v_site_address text := trim(coalesce(p_site_address, ''));
  v_site_name text := nullif(trim(coalesce(p_site_name, '')), '');
  v_client_name text;
  v_allowed boolean;
  v_site_id uuid;
begin
  if v_uid is null then
    raise exception 'Utente non autenticato';
  end if;

  select ctx.role, ctx.organization_id
  into v_role, v_organization_id
  from public.onboarding_actor_context() ctx;

  if p_client_id is null then
    raise exception 'Cliente obbligatorio';
  end if;

  if v_site_address = '' then
    raise exception 'L''indirizzo della sede è obbligatorio';
  end if;

  select c.name
  into v_client_name
  from public.clients c
  where c.id = p_client_id
    and c.organization_id = v_organization_id;

  if v_client_name is null then
    raise exception 'Cliente non trovato';
  end if;

  select (
    v_role = 'admin'
    or exists (
      select 1
      from public.clients c
      where c.id = p_client_id
        and c.organization_id = v_organization_id
        and c.created_by = v_uid
        and public.client_has_no_machines(c.id)
    )
    or public.client_has_operator_access(p_client_id, v_uid)
  ) into v_allowed;

  if not v_allowed then
    raise exception 'Non autorizzato per questo cliente';
  end if;

  insert into public.sites (
    client_id,
    name,
    address,
    created_by,
    organization_id
  )
  values (
    p_client_id,
    coalesce(v_site_name, 'Sede'),
    v_site_address,
    v_uid,
    v_organization_id
  )
  returning id into v_site_id;

  return jsonb_build_object(
    'site_id', v_site_id,
    'site_name', coalesce(v_site_name, 'Sede'),
    'client_id', p_client_id,
    'client_name', v_client_name,
    'organization_id', v_organization_id
  );
end;
$$;

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
  v_organization_id uuid;
  v_code text := upper(trim(coalesce(p_code, '')));
  v_normalized_code text;
  v_temperature_mode text := lower(trim(coalesce(p_temperature_mode, '')));
  v_hw_serial text := nullif(trim(coalesce(p_hw_serial, '')), '');
  v_assigned_operator_id uuid;
  v_operator_role text;
  v_operator_org uuid;
  v_site_matches boolean;
  v_allowed boolean;
  v_machine_id uuid;
begin
  if v_uid is null then
    raise exception 'Utente non autenticato';
  end if;

  select ctx.role, ctx.organization_id
  into v_role, v_organization_id
  from public.onboarding_actor_context() ctx;

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
    raise exception 'La capacità dosi deve essere un intero positivo';
  end if;

  select exists (
    select 1
    from public.sites s
    join public.clients c on c.id = s.client_id
    where s.id = p_site_id
      and s.client_id = p_client_id
      and s.organization_id = v_organization_id
      and c.organization_id = v_organization_id
  ) into v_site_matches;

  if not v_site_matches then
    raise exception 'La sede selezionata non appartiene al cliente';
  end if;

  select (
    v_role = 'admin'
    or exists (
      select 1
      from public.clients c
      where c.id = p_client_id
        and c.organization_id = v_organization_id
        and c.created_by = v_uid
        and public.client_has_no_machines(c.id)
    )
    or public.client_has_operator_access(p_client_id, v_uid)
  ) into v_allowed;

  if not v_allowed then
    raise exception 'Non autorizzato per questo cliente';
  end if;

  if v_role = 'admin' then
    if p_assigned_operator_id is null then
      raise exception 'Seleziona un operatore assegnatario';
    end if;
    v_assigned_operator_id := p_assigned_operator_id;
  else
    v_assigned_operator_id := v_uid;
  end if;

  select p.role, p.organization_id
  into v_operator_role, v_operator_org
  from public.profiles p
  where p.id = v_assigned_operator_id;

  if v_operator_role is distinct from 'refill_operator'
    or v_operator_org is distinct from v_organization_id then
    raise exception 'L''assegnatario deve essere un operatore refill della stessa organizzazione';
  end if;

  insert into public.machines (
    code,
    site_id,
    assigned_operator_id,
    current_fill_percent,
    yearly_shots,
    hw_serial,
    temperature_mode,
    created_by,
    organization_id
  )
  values (
    v_code,
    p_site_id,
    v_assigned_operator_id,
    100,
    0,
    v_hw_serial,
    v_temperature_mode,
    v_uid,
    v_organization_id
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
    'assigned_operator_id', v_assigned_operator_id,
    'organization_id', v_organization_id
  );
exception
  when unique_violation then
    raise exception 'Il codice macchina è già in uso';
end;
$$;

revoke all on function public.create_client_with_primary_site(text, text, text)
  from public, anon;
grant execute on function public.create_client_with_primary_site(text, text, text)
  to authenticated;

revoke all on function public.add_site_to_client(uuid, text, text)
  from public, anon;
grant execute on function public.add_site_to_client(uuid, text, text)
  to authenticated;

revoke all on function public.create_machine_for_site(
  uuid, uuid, text, text, integer, uuid, text
) from public, anon;
grant execute on function public.create_machine_for_site(
  uuid, uuid, text, text, integer, uuid, text
) to authenticated;

drop policy if exists profiles_select_self_or_admin on public.profiles;
drop policy if exists profiles_select_own_or_admin on public.profiles;
create policy profiles_select_own_or_admin
  on public.profiles
  for select
  to authenticated
  using (
    id = (select auth.uid())
    or (
      public.current_app_role() = 'admin'
      and organization_id = public.current_app_organization_id()
    )
  );

drop policy if exists clients_select_by_role on public.clients;
drop policy if exists clients_select_created_by_user on public.clients;
drop policy if exists clients_select_by_effective_assignment on public.clients;
create policy clients_select_by_scope
  on public.clients
  for select
  to authenticated
  using (
    organization_id = public.current_app_organization_id()
    and (
      public.current_app_role() in ('admin', 'technician')
      or (
        created_by = (select auth.uid())
        and public.client_has_no_machines(clients.id)
      )
      or public.client_has_operator_access(clients.id, (select auth.uid()))
    )
  );

drop policy if exists sites_select_by_role on public.sites;
drop policy if exists sites_select_created_or_client_created_by_user
  on public.sites;
drop policy if exists sites_select_by_effective_assignment on public.sites;
create policy sites_select_by_scope
  on public.sites
  for select
  to authenticated
  using (
    organization_id = public.current_app_organization_id()
    and (
      public.current_app_role() in ('admin', 'technician')
      or (
        created_by = (select auth.uid())
        and public.site_has_no_machines(sites.id)
      )
      or exists (
        select 1
        from public.clients c
        where c.id = sites.client_id
          and c.created_by = (select auth.uid())
          and public.client_has_no_machines(c.id)
      )
      or public.site_has_operator_access(sites.id, (select auth.uid()))
    )
  );

drop policy if exists machines_select_by_operator_or_admin on public.machines;
drop policy if exists machines_select_by_role on public.machines;
create policy machines_select_by_scope
  on public.machines
  for select
  to authenticated
  using (
    organization_id = public.current_app_organization_id()
    and (
      public.current_app_role() in ('admin', 'technician')
      or public.machine_has_operator_access(machines.id, (select auth.uid()))
    )
  );

drop policy if exists machine_consumables_select_by_machine_access
  on public.machine_consumables;
create policy machine_consumables_select_by_machine_access
  on public.machine_consumables
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.machines m
      where m.id = machine_consumables.machine_id
        and m.organization_id = public.current_app_organization_id()
        and (
          public.current_app_role() in ('admin', 'technician')
          or public.machine_has_operator_access(m.id, (select auth.uid()))
        )
    )
  );

drop policy if exists machine_consumables_insert_admin
  on public.machine_consumables;
create policy machine_consumables_insert_admin
  on public.machine_consumables
  for insert
  to authenticated
  with check (
    public.current_app_role() = 'admin'
    and exists (
      select 1
      from public.machines m
      where m.id = machine_consumables.machine_id
        and m.organization_id = public.current_app_organization_id()
    )
  );

drop policy if exists machine_consumables_update_admin
  on public.machine_consumables;
create policy machine_consumables_update_admin
  on public.machine_consumables
  for update
  to authenticated
  using (
    public.current_app_role() = 'admin'
    and exists (
      select 1
      from public.machines m
      where m.id = machine_consumables.machine_id
        and m.organization_id = public.current_app_organization_id()
    )
  )
  with check (
    public.current_app_role() = 'admin'
    and exists (
      select 1
      from public.machines m
      where m.id = machine_consumables.machine_id
        and m.organization_id = public.current_app_organization_id()
    )
  );

comment on column public.machine_consumables.capacity_units
  is 'Per-consumable maximum units/doses for the enabled monitored factor; onboarding sets this for the selected hot/cold factor, not as total machine capacity.';
