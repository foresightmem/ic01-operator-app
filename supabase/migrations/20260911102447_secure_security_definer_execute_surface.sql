-- Remediation for SEC-004 and SEC-005.
-- SECURITY DEFINER functions remain only where required, and direct RPC grants
-- are narrowed to the intended caller surface.

do $$
declare
  v_function regprocedure;
begin
  for v_function in
    select p.oid::regprocedure
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
  loop
    execute format('revoke all on function %s from public, anon', v_function);
  end loop;
end $$;

do $$
declare
  v_signature text;
  v_function regprocedure;
begin
  foreach v_signature in array array[
    'public.add_site_to_client(uuid,text,text)',
    'public.add_site_to_client(uuid,text,text,text)',
    'public.add_site_to_client(uuid,text,text,text,double precision,double precision)',
    'public.client_has_no_machines(uuid)',
    'public.control_center_is_internal_admin()',
    'public.control_center_supported_commands()',
    'public.create_client_with_primary_site(text,text,text)',
    'public.create_client_with_primary_site(text,text,text,text)',
    'public.create_client_with_primary_site(text,text,text,text,double precision,double precision)',
    'public.create_control_center_device_command(uuid,text,jsonb)',
    'public.create_machine_for_site(uuid,uuid,text,text,integer,uuid,text)',
    'public.current_app_organization_id()',
    'public.current_app_role()',
    'public.delete_onboarding_client(uuid)',
    'public.get_control_center_device_detail(uuid)',
    'public.get_control_center_devices()',
    'public.get_control_center_events(integer,uuid,text,text,timestamp with time zone,timestamp with time zone)',
    'public.get_control_center_overview()',
    'public.get_refill_productivity_kpi(integer,text,numeric)',
    'public.onboarding_actor_context()',
    'public.perform_refill(uuid)',
    'public.perform_refill_consumable(uuid,public.consumable_type)',
    'public.site_has_no_machines(uuid)'
  ]
  loop
    v_function := to_regprocedure(v_signature);
    if v_function is not null then
      execute format('grant execute on function %s to authenticated', v_function);
    end if;
  end loop;
end $$;

create or replace function public.current_user_has_machine_access(p_machine_id uuid)
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
      and m.assigned_operator_id = auth.uid()
  )
  or exists (
    select 1
    from public.temp_machine_assignments t
    where t.machine_id = p_machine_id
      and t.status = 'confirmed'
      and current_date between t.start_date and t.end_date
      and t.new_operator_id = auth.uid()
  );
$$;

create or replace function public.current_user_has_site_access(p_site_id uuid)
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
      and public.current_user_has_machine_access(m.id)
  );
$$;

create or replace function public.current_user_has_client_access(p_client_id uuid)
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
    where s.client_id = p_client_id
      and public.current_user_has_site_access(s.id)
  );
$$;

revoke all on function public.current_user_has_machine_access(uuid) from public, anon;
revoke all on function public.current_user_has_site_access(uuid) from public, anon;
revoke all on function public.current_user_has_client_access(uuid) from public, anon;
grant execute on function public.current_user_has_machine_access(uuid) to authenticated;
grant execute on function public.current_user_has_site_access(uuid) to authenticated;
grant execute on function public.current_user_has_client_access(uuid) to authenticated;

do $$
begin
  if to_regclass('public.clients') is not null then
    drop policy if exists clients_select_by_scope on public.clients;
    create policy clients_select_by_scope
      on public.clients
      for select
      to authenticated
      using (
        organization_id = public.current_app_organization_id()
        and (
          public.current_app_role() in ('admin', 'technician')
          or public.current_user_has_client_access(id)
        )
      );
  end if;

  if to_regclass('public.sites') is not null then
    drop policy if exists sites_select_by_scope on public.sites;
    create policy sites_select_by_scope
      on public.sites
      for select
      to authenticated
      using (
        organization_id = public.current_app_organization_id()
        and (
          public.current_app_role() in ('admin', 'technician')
          or public.current_user_has_site_access(id)
        )
      );
  end if;

  if to_regclass('public.machines') is not null then
    drop policy if exists machines_select_by_scope on public.machines;
    create policy machines_select_by_scope
      on public.machines
      for select
      to authenticated
      using (
        organization_id = public.current_app_organization_id()
        and (
          public.current_app_role() in ('admin', 'technician')
          or public.current_user_has_machine_access(id)
        )
      );
  end if;
end $$;

do $$
declare
  v_function regprocedure;
begin
  foreach v_function in array array[
    to_regprocedure('public.client_has_operator_access(uuid,uuid)'),
    to_regprocedure('public.site_has_operator_access(uuid,uuid)'),
    to_regprocedure('public.machine_has_operator_access(uuid,uuid)')
  ]
  loop
    if v_function is not null then
      execute format('revoke all on function %s from public, anon, authenticated', v_function);
    end if;
  end loop;
end $$;

-- The public/device dispense/refill RPCs are not authenticated by function body.
-- Keep them service-role only until a device authentication scheme is formalized.
do $$
declare
  v_register_dispense regprocedure := to_regprocedure('public.register_dispense(uuid,public.beverage_type,bigint,text)');
  v_perform_refill regprocedure := to_regprocedure('public.perform_refill(uuid)');
begin
  if v_register_dispense is not null then
    execute format('revoke all on function %s from public, anon, authenticated', v_register_dispense);
    execute format('grant execute on function %s to service_role', v_register_dispense);
  end if;

  if v_perform_refill is not null then
    execute format('revoke all on function %s from public, anon', v_perform_refill);
    execute format('grant execute on function %s to authenticated', v_perform_refill);
  end if;
end $$;

-- Internal helpers are required by policies and RPC bodies, but should never be
-- callable before sign-in.
revoke all on function public.current_app_role() from public, anon;
revoke all on function public.current_app_organization_id() from public, anon;
revoke all on function public.control_center_is_internal_admin() from public, anon;
grant execute on function public.current_app_role() to authenticated;
grant execute on function public.current_app_organization_id() to authenticated;
grant execute on function public.control_center_is_internal_admin() to authenticated;
