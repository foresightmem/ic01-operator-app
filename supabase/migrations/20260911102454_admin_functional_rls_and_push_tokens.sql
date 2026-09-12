-- Remediation for SEC-008 and SEC-012.

do $$
begin
  if to_regclass('public.machines') is not null then
    revoke update on table public.machines from authenticated;
    grant select on table public.machines to authenticated;
    grant update (temperature_mode, updated_at) on table public.machines to authenticated;

    drop policy if exists machines_update_by_operator_or_admin on public.machines;
    drop policy if exists machines_update_if_effective_operator on public.machines;
    drop policy if exists machines_update_admin_config on public.machines;
    create policy machines_update_admin_config
      on public.machines
      for update
      to authenticated
      using (
        organization_id = public.current_app_organization_id()
        and public.current_app_role() = 'admin'
      )
      with check (
        organization_id = public.current_app_organization_id()
        and public.current_app_role() = 'admin'
      );
  end if;

  if to_regclass('public.machine_consumables') is not null then
    revoke all on table public.machine_consumables from anon;
    revoke delete, truncate, references, trigger on table public.machine_consumables from authenticated;
    grant select, insert, update on table public.machine_consumables to authenticated;

    drop policy if exists machine_consumables_insert_admin on public.machine_consumables;
    create policy machine_consumables_insert_admin
      on public.machine_consumables
      for insert
      to authenticated
      with check (
        public.current_app_role() = 'admin'
        and exists (
          select 1
          from public.machines m
          where m.id = machine_id
            and m.organization_id = public.current_app_organization_id()
        )
      );

    drop policy if exists machine_consumables_update_admin on public.machine_consumables;
    create policy machine_consumables_update_admin
      on public.machine_consumables
      for update
      to authenticated
      using (
        public.current_app_role() = 'admin'
        and exists (
          select 1
          from public.machines m
          where m.id = machine_id
            and m.organization_id = public.current_app_organization_id()
        )
      )
      with check (
        public.current_app_role() = 'admin'
        and exists (
          select 1
          from public.machines m
          where m.id = machine_id
            and m.organization_id = public.current_app_organization_id()
        )
      );
  end if;

  if to_regclass('public.operator_unavailability') is not null then
    revoke all on table public.operator_unavailability from anon;
    revoke delete, truncate, references, trigger on table public.operator_unavailability from authenticated;
    grant select, insert, update on table public.operator_unavailability to authenticated;

    drop policy if exists admin_all_operator_unavailability on public.operator_unavailability;
    create policy admin_manage_operator_unavailability_by_org
      on public.operator_unavailability
      for all
      to authenticated
      using (
        public.current_app_role() = 'admin'
        and exists (
          select 1
          from public.profiles p
          where p.id = operator_id
            and p.organization_id = public.current_app_organization_id()
        )
      )
      with check (
        public.current_app_role() = 'admin'
        and exists (
          select 1
          from public.profiles p
          where p.id = operator_id
            and p.organization_id = public.current_app_organization_id()
        )
      );
  end if;

  if to_regclass('public.temp_machine_assignments') is not null then
    revoke all on table public.temp_machine_assignments from anon;
    revoke delete, truncate, references, trigger on table public.temp_machine_assignments from authenticated;
    grant select, insert, update on table public.temp_machine_assignments to authenticated;

    drop policy if exists admin_all_temp_machine_assignments on public.temp_machine_assignments;
    create policy admin_manage_temp_machine_assignments_by_org
      on public.temp_machine_assignments
      for all
      to authenticated
      using (
        public.current_app_role() = 'admin'
        and exists (
          select 1
          from public.machines m
          join public.profiles original_operator on original_operator.id = original_operator_id
          join public.profiles new_operator on new_operator.id = new_operator_id
          where m.id = machine_id
            and m.organization_id = public.current_app_organization_id()
            and original_operator.organization_id = public.current_app_organization_id()
            and new_operator.organization_id = public.current_app_organization_id()
        )
      )
      with check (
        public.current_app_role() = 'admin'
        and exists (
          select 1
          from public.machines m
          join public.profiles original_operator on original_operator.id = original_operator_id
          join public.profiles new_operator on new_operator.id = new_operator_id
          where m.id = machine_id
            and m.organization_id = public.current_app_organization_id()
            and original_operator.organization_id = public.current_app_organization_id()
            and new_operator.organization_id = public.current_app_organization_id()
        )
      );
  end if;

  if to_regclass('public.push_tokens') is not null then
    revoke all on table public.push_tokens from anon;
    revoke delete, truncate, references, trigger on table public.push_tokens from authenticated;
    grant select, insert, update on table public.push_tokens to authenticated;

    create unique index if not exists push_tokens_user_device_platform_key
      on public.push_tokens (user_id, device_id, platform);
  end if;
end $$;
