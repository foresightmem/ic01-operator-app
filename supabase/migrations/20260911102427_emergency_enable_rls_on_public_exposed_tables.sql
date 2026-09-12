-- Emergency remediation for SEC-001.
-- These tables are in the exposed public schema. RLS must be enabled before
-- any Data API or GraphQL grant can be considered safe.

do $$
declare
  v_table regclass;
  v_table_name text;
begin
  foreach v_table_name in array array[
    'public.visits',
    'public.beverage_recipes',
    'public.beverage_recipe_items',
    'public.dispense_events',
    'public.firmware_versions'
  ]
  loop
    v_table := to_regclass(v_table_name);
    if v_table is not null then
      execute format('alter table %s enable row level security', v_table);
      execute format('alter table %s force row level security', v_table);
    end if;
  end loop;
end $$;

do $$
declare
  v_table regclass;
  v_table_name text;
begin
  foreach v_table_name in array array[
    'public.visits',
    'public.beverage_recipes',
    'public.beverage_recipe_items',
    'public.dispense_events',
    'public.firmware_versions'
  ]
  loop
    v_table := to_regclass(v_table_name);
    if v_table is not null then
      execute format('revoke all on table %s from anon', v_table);
    end if;
  end loop;

  -- Keep visits available only through its explicit authenticated policies.
  if to_regclass('public.visits') is not null then
    revoke all on table public.visits from authenticated;
    grant select, insert on table public.visits to authenticated;

    -- Existing visits policies are re-created because they were present but
    -- inert while RLS was disabled.
    drop policy if exists visits_select_admin_or_own on public.visits;
    create policy visits_select_admin_or_own
      on public.visits
      for select
      to authenticated
      using (
        operator_id = (select auth.uid())
        or public.current_app_role() = 'admin'
      );

    drop policy if exists visits_insert_admin_or_own on public.visits;
    create policy visits_insert_admin_or_own
      on public.visits
      for insert
      to authenticated
      with check (
        operator_id = (select auth.uid())
        or public.current_app_role() = 'admin'
      );
  end if;

  -- Recipe, dispense, and firmware tables are backend/device managed. They are
  -- not read directly by the Flutter app, so signed-in users get no direct grant.
  foreach v_table_name in array array[
    'public.beverage_recipes',
    'public.beverage_recipe_items',
    'public.dispense_events',
    'public.firmware_versions'
  ]
  loop
    v_table := to_regclass(v_table_name);
    if v_table is not null then
      execute format('revoke all on table %s from authenticated', v_table);
    end if;
  end loop;
end $$;
