-- Remediation for SEC-007 and SEC-009.
-- Role and tenant membership are authorization data. They must not be mutable
-- through public clients.

do $$
begin
  if to_regclass('public.profiles') is not null then
    revoke all on table public.profiles from anon;
    revoke insert, update, delete, truncate, references, trigger on table public.profiles from authenticated;
    grant select on table public.profiles to authenticated;

    drop policy if exists profiles_insert_self on public.profiles;
    drop policy if exists profiles_update_self on public.profiles;
    drop policy if exists profiles_update_own on public.profiles;
    drop policy if exists profiles_delete_self on public.profiles;
  end if;
end $$;

create or replace function public.ticket_resource_scope_is_valid(
  p_machine_id uuid,
  p_client_id uuid,
  p_site_id uuid
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
    join public.sites s on s.id = m.site_id
    join public.clients c on c.id = s.client_id
    where m.id = p_machine_id
      and c.id = p_client_id
      and (p_site_id is null or s.id = p_site_id)
      and m.organization_id = public.current_app_organization_id()
      and s.organization_id = public.current_app_organization_id()
      and c.organization_id = public.current_app_organization_id()
  );
$$;

revoke all on function public.ticket_resource_scope_is_valid(uuid, uuid, uuid) from public, anon, authenticated;

create or replace function public.enforce_ticket_protected_columns()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_role text := public.current_app_role();
  v_uid uuid := auth.uid();
  v_resource_changed boolean;
  v_assignment_changed boolean;
begin
  v_resource_changed :=
    new.machine_id is distinct from old.machine_id
    or new.client_id is distinct from old.client_id
    or new.site_id is distinct from old.site_id
    or new.source is distinct from old.source
    or new.machine_code_snapshot is distinct from old.machine_code_snapshot;

  v_assignment_changed :=
    new.assigned_operator_id is distinct from old.assigned_operator_id
    or new.assigned_technician_id is distinct from old.assigned_technician_id;

  if v_role = 'admin' then
    if (v_resource_changed or v_assignment_changed)
      and not public.ticket_resource_scope_is_valid(new.machine_id, new.client_id, new.site_id) then
      raise exception 'ticket resource scope is invalid'
        using errcode = '42501';
    end if;

    return new;
  end if;

  if v_resource_changed or new.assigned_operator_id is distinct from old.assigned_operator_id then
    raise exception 'ticket resource columns are immutable for this role'
      using errcode = '42501';
  end if;

  if new.assigned_technician_id is distinct from old.assigned_technician_id
    and new.assigned_technician_id is distinct from v_uid then
    raise exception 'ticket technician assignment can only be claimed by the caller'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_ticket_protected_columns() from public, anon, authenticated;

do $$
begin
  if to_regclass('public.tickets') is not null then
    drop trigger if exists enforce_ticket_protected_columns on public.tickets;
    create trigger enforce_ticket_protected_columns
      before update on public.tickets
      for each row
      execute function public.enforce_ticket_protected_columns();
  end if;
end $$;

do $$
begin
  if to_regclass('public.tickets') is not null then
    revoke all on table public.tickets from anon;
    revoke delete, truncate, references, trigger on table public.tickets from authenticated;
    grant select, insert, update on table public.tickets to authenticated;
  end if;
end $$;
