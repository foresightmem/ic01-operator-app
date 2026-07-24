-- Corrective RLS pass after introducing public maintenance tickets.
-- Goals:
-- 1) keep the public form outside direct table access;
-- 2) make admin reads explicit across the operational tables used by /admin;
-- 3) avoid endless UI loading by ensuring profile role lookup can succeed.

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

grant select on public.profiles to authenticated;
grant select on public.clients to authenticated;
grant select on public.sites to authenticated;
grant select on public.machines to authenticated;
grant select, insert, update on public.tickets to authenticated;

do $$
begin
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
    where conname = 'tickets_status_check_v2'
      and conrelid = 'public.tickets'::regclass
  ) then
    alter table public.tickets
      add constraint tickets_status_check_v2
      check (status in ('open', 'assigned', 'in_progress', 'resolved', 'cancelled', 'closed'))
      not valid;
  end if;
end $$;

do $$
begin
  if to_regclass('public.refills') is not null then
    execute 'grant select on public.refills to authenticated';

    execute 'drop policy if exists refills_select_admin_or_own on public.refills';
    execute $policy$
      create policy refills_select_admin_or_own
        on public.refills
        for select
        to authenticated
        using (
          operator_id = (select auth.uid())
          or public.current_app_role() = 'admin'
        )
    $policy$;
  end if;

  if to_regclass('public.visits') is not null then
    execute 'grant select, insert on public.visits to authenticated';

    execute 'drop policy if exists visits_select_admin_or_own on public.visits';
    execute $policy$
      create policy visits_select_admin_or_own
        on public.visits
        for select
        to authenticated
        using (
          operator_id = (select auth.uid())
          or public.current_app_role() = 'admin'
        )
    $policy$;

    execute 'drop policy if exists visits_insert_admin_or_own on public.visits';
    execute $policy$
      create policy visits_insert_admin_or_own
        on public.visits
        for insert
        to authenticated
        with check (
          operator_id = (select auth.uid())
          or public.current_app_role() = 'admin'
        )
    $policy$;
  end if;
end $$;

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

revoke all on public.machines from anon;
revoke all on public.clients from anon;
revoke all on public.sites from anon;
revoke all on public.tickets from anon;
