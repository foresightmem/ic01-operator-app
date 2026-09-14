-- Let the ticket protected-column trigger call its locked-down scope helper.
--
-- `ticket_resource_scope_is_valid(...)` is intentionally not executable by
-- app roles because it can otherwise become a relationship-enumeration helper.
-- The trigger that protects ticket resource columns still needs to call it
-- during legitimate ticket status/assignment updates. Run only the trigger
-- function with definer privileges and keep the helper private to the DB.

create or replace function public.enforce_ticket_protected_columns()
returns trigger
language plpgsql
security definer
set search_path = public, auth, pg_catalog
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
      and not public.ticket_resource_scope_is_valid(
        new.machine_id,
        new.client_id,
        new.site_id
      ) then
      raise exception 'ticket resource scope is invalid'
        using errcode = '42501';
    end if;

    return new;
  end if;

  if v_resource_changed
    or new.assigned_operator_id is distinct from old.assigned_operator_id then
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

revoke all on function public.enforce_ticket_protected_columns()
  from public, anon, authenticated;

revoke all on function public.ticket_resource_scope_is_valid(uuid, uuid, uuid)
  from public, anon, authenticated;
