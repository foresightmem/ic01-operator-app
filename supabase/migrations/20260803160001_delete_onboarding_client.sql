create or replace function public.delete_onboarding_client(
  p_client_id uuid
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
  v_client_organization_id uuid;
  v_client_created_by uuid;
  v_client_name text;
  v_site_count integer;
  v_machine_count integer;
  v_ticket_count integer;
  v_visit_count integer;
begin
  if v_user_id is null then
    raise exception 'Utente non autenticato';
  end if;

  select ctx.role, ctx.organization_id
    into v_role, v_organization_id
  from public.onboarding_actor_context() as ctx;

  select c.organization_id, c.created_by, c.name
    into v_client_organization_id, v_client_created_by, v_client_name
  from public.clients as c
  where c.id = p_client_id;

  if v_client_name is null or v_client_organization_id is distinct from v_organization_id then
    raise exception 'Cliente non trovato';
  end if;

  if v_role <> 'admin'
     and (v_role <> 'refill_operator' or v_client_created_by is distinct from v_user_id) then
    raise exception 'Non autorizzato a eliminare questo cliente';
  end if;

  select count(*)
    into v_machine_count
  from public.sites as s
  join public.machines as m on m.site_id = s.id
  where s.client_id = p_client_id;

  select count(*)
    into v_ticket_count
  from public.tickets as t
  where t.client_id = p_client_id;

  select count(*)
    into v_visit_count
  from public.visits as v
  where v.client_id = p_client_id;

  if v_machine_count > 0 or v_ticket_count > 0 or v_visit_count > 0 then
    raise exception 'Cliente non cancellabile: contiene macchine, ticket o visite';
  end if;

  select count(*)
    into v_site_count
  from public.sites as s
  where s.client_id = p_client_id;

  delete from public.sites as s
  where s.client_id = p_client_id;

  delete from public.clients as c
  where c.id = p_client_id;

  return jsonb_build_object(
    'client_id', p_client_id,
    'client_name', v_client_name,
    'deleted_sites', v_site_count
  );
end;
$$;

revoke all on function public.delete_onboarding_client(uuid) from public, anon;
grant execute on function public.delete_onboarding_client(uuid) to authenticated;

comment on function public.delete_onboarding_client(uuid)
  is 'Safely deletes an onboarding client only when it has no machines, tickets, or visits.';

notify pgrst, 'reload schema';
