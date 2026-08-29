-- Allow the refill operator assigned to a public ticket to take it in charge
-- and move its workflow forward. Public tickets are linked to the machine's
-- assigned_operator_id, while the previous update policy allowed only admins
-- and technicians.

grant update on public.tickets to authenticated;

drop policy if exists tickets_update_admin_or_technician on public.tickets;
drop policy if exists tickets_update_by_role_or_assignment on public.tickets;

create policy tickets_update_by_role_or_assignment
  on public.tickets
  for update
  to authenticated
  using (
    public.current_app_role() in ('admin', 'technician')
    or assigned_technician_id = (select auth.uid())
    or assigned_operator_id = (select auth.uid())
  )
  with check (
    public.current_app_role() in ('admin', 'technician')
    or assigned_technician_id = (select auth.uid())
    or assigned_operator_id = (select auth.uid())
  );
