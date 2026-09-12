-- Remove remaining policy references to caller-supplied helper functions and
-- avoid PUBLIC-scoped push token policies.

do $$
begin
  if to_regclass('public.machine_consumables') is not null then
    drop policy if exists machine_consumables_select_by_machine_access
      on public.machine_consumables;
    create policy machine_consumables_select_by_machine_access
      on public.machine_consumables
      for select
      to authenticated
      using (
        exists (
          select 1
          from public.machines m
          where m.id = machine_id
            and m.organization_id = public.current_app_organization_id()
            and (
              public.current_app_role() in ('admin', 'technician')
              or public.current_user_has_machine_access(m.id)
            )
        )
      );
  end if;

  if to_regclass('public.push_tokens') is not null then
    drop policy if exists push_tokens_select_own on public.push_tokens;
    drop policy if exists push_tokens_upsert_own on public.push_tokens;
    drop policy if exists push_tokens_update_own on public.push_tokens;

    create policy push_tokens_select_own
      on public.push_tokens
      for select
      to authenticated
      using ((select auth.uid()) = user_id);

    create policy push_tokens_upsert_own
      on public.push_tokens
      for insert
      to authenticated
      with check ((select auth.uid()) = user_id);

    create policy push_tokens_update_own
      on public.push_tokens
      for update
      to authenticated
      using ((select auth.uid()) = user_id)
      with check ((select auth.uid()) = user_id);
  end if;
end $$;
