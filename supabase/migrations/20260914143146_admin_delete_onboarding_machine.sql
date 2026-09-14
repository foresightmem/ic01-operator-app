create or replace function public.delete_onboarding_machine(
  p_machine_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_user_id uuid := auth.uid();
  v_role text;
  v_organization_id uuid;
  v_machine_organization_id uuid;
  v_machine_code text;
  v_ticket_count integer;
  v_refill_count integer;
  v_dispense_count integer;
  v_device_count integer;
  v_ble_session_count integer;
  v_device_event_count integer;
begin
  if v_user_id is null then
    raise exception 'Utente non autenticato';
  end if;

  select ctx.role, ctx.organization_id
    into v_role, v_organization_id
  from public.onboarding_actor_context() as ctx;

  if v_role <> 'admin' then
    raise exception 'Non autorizzato a eliminare questa macchina';
  end if;

  select m.organization_id, m.code
    into v_machine_organization_id, v_machine_code
  from public.machines as m
  where m.id = p_machine_id;

  if v_machine_code is null
     or v_machine_organization_id is distinct from v_organization_id then
    raise exception 'Macchina non trovata';
  end if;

  select count(*) into v_ticket_count
  from public.tickets as t
  where t.machine_id = p_machine_id;

  select count(*) into v_refill_count
  from public.refills as r
  where r.machine_id = p_machine_id;

  select count(*) into v_dispense_count
  from public.dispense_events as d
  where d.machine_id = p_machine_id;

  select count(*) into v_device_count
  from public.devices as d
  where d.machine_id = p_machine_id;

  select count(*) into v_ble_session_count
  from public.ble_sessions as s
  where s.machine_id = p_machine_id;

  select count(*) into v_device_event_count
  from public.device_events as e
  where e.machine_id = p_machine_id;

  if v_ticket_count > 0
     or v_refill_count > 0
     or v_dispense_count > 0
     or v_device_count > 0
     or v_ble_session_count > 0
     or v_device_event_count > 0 then
    raise exception 'Macchina non cancellabile: contiene ticket, refill, erogazioni, device o telemetria';
  end if;

  delete from public.machines as m
  where m.id = p_machine_id
    and m.organization_id = v_organization_id;

  return jsonb_build_object(
    'machine_id', p_machine_id,
    'machine_code', v_machine_code
  );
end;
$$;

revoke all on function public.delete_onboarding_machine(uuid) from public, anon;
grant execute on function public.delete_onboarding_machine(uuid) to authenticated;

comment on function public.delete_onboarding_machine(uuid)
  is 'Safely deletes an admin-managed machine only when it has no operational history or linked device.';

notify pgrst, 'reload schema';
