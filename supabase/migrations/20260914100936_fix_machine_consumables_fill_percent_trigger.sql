-- Let machine consumable admin edits update the derived machine fill percent.
--
-- `machine_consumables` writes fire this trigger to maintain
-- `machines.current_fill_percent`. After hardening direct machine updates to
-- only `temperature_mode` and `updated_at`, legitimate admin tank edits failed
-- because the trigger ran as the authenticated caller and could no longer write
-- the derived column. Keep the direct grant narrow and run only this trigger
-- helper with definer privileges.

create or replace function public.sync_machine_current_fill_percent()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_mode text;
  v_active_type public.consumable_type;
  v_percent numeric;
begin
  select temperature_mode
  into v_mode
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

revoke all on function public.sync_machine_current_fill_percent()
  from public, anon, authenticated;
