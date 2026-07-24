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
