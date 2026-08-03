-- Remove default-argument ambiguity between the legacy 3-argument onboarding
-- RPCs and the newer 4-argument variants that include site city.

drop function if exists public.create_client_with_primary_site(
  text,
  text,
  text,
  text
);

drop function if exists public.add_site_to_client(
  uuid,
  text,
  text,
  text
);

create or replace function public.create_client_with_primary_site(
  p_client_name text,
  p_site_address text,
  p_site_name text,
  p_site_city text
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
  v_site_city text := nullif(trim(coalesce(p_site_city, '')), '');
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

  insert into public.sites (
    client_id,
    name,
    address,
    city,
    created_by,
    organization_id
  )
  values (
    v_client_id,
    coalesce(v_site_name, 'Sede principale'),
    v_site_address,
    v_site_city,
    v_uid,
    v_organization_id
  )
  returning id into v_site_id;

  return jsonb_build_object(
    'client_id', v_client_id,
    'client_name', v_client_name,
    'site_id', v_site_id,
    'site_name', coalesce(v_site_name, 'Sede principale'),
    'site_city', v_site_city,
    'role', v_role,
    'organization_id', v_organization_id
  );
end;
$$;

create or replace function public.add_site_to_client(
  p_client_id uuid,
  p_site_address text,
  p_site_name text,
  p_site_city text
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
  v_site_city text := nullif(trim(coalesce(p_site_city, '')), '');
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
    city,
    created_by,
    organization_id
  )
  values (
    p_client_id,
    coalesce(v_site_name, 'Sede'),
    v_site_address,
    v_site_city,
    v_uid,
    v_organization_id
  )
  returning id into v_site_id;

  return jsonb_build_object(
    'site_id', v_site_id,
    'site_name', coalesce(v_site_name, 'Sede'),
    'site_city', v_site_city,
    'client_id', p_client_id,
    'client_name', v_client_name,
    'organization_id', v_organization_id
  );
end;
$$;

revoke all on function public.create_client_with_primary_site(text, text, text, text)
  from public, anon;
grant execute on function public.create_client_with_primary_site(text, text, text, text)
  to authenticated;

revoke all on function public.add_site_to_client(uuid, text, text, text)
  from public, anon;
grant execute on function public.add_site_to_client(uuid, text, text, text)
  to authenticated;

comment on function public.create_client_with_primary_site(text, text, text, text)
  is 'Creates a client and first site atomically, including parsed city when provided.';

comment on function public.add_site_to_client(uuid, text, text, text)
  is 'Adds a site to an existing client, including parsed city when provided.';

notify pgrst, 'reload schema';
