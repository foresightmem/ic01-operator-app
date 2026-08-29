create or replace function public.current_app_role()
returns text
language plpgsql
stable
security definer
set search_path = public
set row_security = off
as $$
declare
  v_role text;
begin
  select p.role
  into v_role
  from public.profiles p
  where p.id = auth.uid()
  limit 1;

  return v_role;
end;
$$;

revoke all on function public.current_app_role() from public, anon;
grant execute on function public.current_app_role() to authenticated;

drop policy if exists profiles_select_self_or_admin on public.profiles;
drop policy if exists profiles_select_own_or_admin on public.profiles;
create policy profiles_select_own_or_admin
  on public.profiles
  for select
  to authenticated
  using (
    id = (select auth.uid())
    or public.current_app_role() = 'admin'
  );
