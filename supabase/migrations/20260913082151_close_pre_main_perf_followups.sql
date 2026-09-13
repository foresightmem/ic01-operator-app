-- Close pre-main performance follow-ups that are safe to apply before main.
--
-- PM-013: remove RLS initplan and duplicate permissive policy warnings by
-- wrapping auth/helper calls in scalar subqueries and consolidating overlapping
-- SELECT/INSERT policies without changing the intended app access model.
--
-- PM-014: remove exact duplicate indexes reported by the performance advisor.

do $$
begin
  if to_regclass('public.notification_settings') is not null then
    drop policy if exists notification_settings_select_own
      on public.notification_settings;
    drop policy if exists notification_settings_upsert_own
      on public.notification_settings;
    drop policy if exists notification_settings_update_own
      on public.notification_settings;

    create policy notification_settings_select_own
      on public.notification_settings
      for select
      to authenticated
      using ((select auth.uid()) = user_id);

    create policy notification_settings_upsert_own
      on public.notification_settings
      for insert
      to authenticated
      with check ((select auth.uid()) = user_id);

    create policy notification_settings_update_own
      on public.notification_settings
      for update
      to authenticated
      using ((select auth.uid()) = user_id)
      with check ((select auth.uid()) = user_id);
  end if;
end $$;

do $$
begin
  if to_regclass('public.refills') is not null then
    drop policy if exists refills_select_admin_or_own
      on public.refills;
    drop policy if exists refills_select_by_operator_or_admin
      on public.refills;
    drop policy if exists refills_insert_by_operator
      on public.refills;
    drop policy if exists refills_insert_if_effective_operator
      on public.refills;

    create policy refills_select_by_operator_or_admin
      on public.refills
      for select
      to authenticated
      using (
        operator_id = (select auth.uid())
        or (select public.current_app_role()) = 'admin'
      );

    create policy refills_insert_by_operator
      on public.refills
      for insert
      to authenticated
      with check (operator_id = (select auth.uid()));
  end if;
end $$;

do $$
begin
  if to_regclass('public.temp_machine_assignments') is not null then
    drop policy if exists admin_manage_temp_machine_assignments_by_org
      on public.temp_machine_assignments;
    drop policy if exists read_confirmed_assignments_for_me
      on public.temp_machine_assignments;

    create policy temp_machine_assignments_select_by_scope
      on public.temp_machine_assignments
      for select
      to authenticated
      using (
        (
          status = 'confirmed'
          and (
            new_operator_id = (select auth.uid())
            or original_operator_id = (select auth.uid())
          )
        )
        or (
          (select public.current_app_role()) = 'admin'
          and exists (
            select 1
            from public.machines m
            join public.profiles original_operator
              on original_operator.id = original_operator_id
            join public.profiles new_operator
              on new_operator.id = new_operator_id
            where m.id = machine_id
              and m.organization_id = (select public.current_app_organization_id())
              and original_operator.organization_id =
                (select public.current_app_organization_id())
              and new_operator.organization_id =
                (select public.current_app_organization_id())
          )
        )
      );

    create policy temp_machine_assignments_insert_admin_by_org
      on public.temp_machine_assignments
      for insert
      to authenticated
      with check (
        (select public.current_app_role()) = 'admin'
        and exists (
          select 1
          from public.machines m
          join public.profiles original_operator
            on original_operator.id = original_operator_id
          join public.profiles new_operator
            on new_operator.id = new_operator_id
          where m.id = machine_id
            and m.organization_id = (select public.current_app_organization_id())
            and original_operator.organization_id =
              (select public.current_app_organization_id())
            and new_operator.organization_id =
              (select public.current_app_organization_id())
        )
      );

    create policy temp_machine_assignments_update_admin_by_org
      on public.temp_machine_assignments
      for update
      to authenticated
      using (
        (select public.current_app_role()) = 'admin'
        and exists (
          select 1
          from public.machines m
          join public.profiles original_operator
            on original_operator.id = original_operator_id
          join public.profiles new_operator
            on new_operator.id = new_operator_id
          where m.id = machine_id
            and m.organization_id = (select public.current_app_organization_id())
            and original_operator.organization_id =
              (select public.current_app_organization_id())
            and new_operator.organization_id =
              (select public.current_app_organization_id())
        )
      )
      with check (
        (select public.current_app_role()) = 'admin'
        and exists (
          select 1
          from public.machines m
          join public.profiles original_operator
            on original_operator.id = original_operator_id
          join public.profiles new_operator
            on new_operator.id = new_operator_id
          where m.id = machine_id
            and m.organization_id = (select public.current_app_organization_id())
            and original_operator.organization_id =
              (select public.current_app_organization_id())
            and new_operator.organization_id =
              (select public.current_app_organization_id())
        )
      );

    create policy temp_machine_assignments_delete_admin_by_org
      on public.temp_machine_assignments
      for delete
      to authenticated
      using (
        (select public.current_app_role()) = 'admin'
        and exists (
          select 1
          from public.machines m
          join public.profiles original_operator
            on original_operator.id = original_operator_id
          join public.profiles new_operator
            on new_operator.id = new_operator_id
          where m.id = machine_id
            and m.organization_id = (select public.current_app_organization_id())
            and original_operator.organization_id =
              (select public.current_app_organization_id())
            and new_operator.organization_id =
              (select public.current_app_organization_id())
        )
      );
  end if;
end $$;

drop index if exists public.idx_commands_device_status;
drop index if exists public.tickets_machine_idx;
