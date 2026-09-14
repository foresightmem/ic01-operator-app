-- Allow the admin coverage page to regenerate suggested coverage plans.
--
-- The UI first deletes previous `suggested` rows for the selected operator/date
-- range, then inserts a new suggestion plan. A previous hardening migration
-- created an admin-scoped DELETE policy but revoked the table DELETE privilege,
-- so PostgREST returned "permission denied for table temp_machine_assignments".
--
-- Keep the grant narrow through RLS: authenticated users receive the table
-- DELETE privilege, but only admins can delete same-organization rows and only
-- while they are still suggestions.

do $$
begin
  if to_regclass('public.temp_machine_assignments') is not null then
    revoke delete on table public.temp_machine_assignments from anon;
    grant delete on table public.temp_machine_assignments to authenticated;

    drop policy if exists temp_machine_assignments_delete_admin_by_org
      on public.temp_machine_assignments;

    create policy temp_machine_assignments_delete_admin_by_org
      on public.temp_machine_assignments
      for delete
      to authenticated
      using (
        status = 'suggested'
        and (select public.current_app_role()) = 'admin'
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
