-- Close residual broad table grants on machines. Admin creation continues to
-- go through the reviewed onboarding RPCs; direct client writes stay narrow.

do $$
begin
  if to_regclass('public.machines') is not null then
    revoke insert, delete, truncate, references, trigger on table public.machines
      from authenticated;
    grant select on table public.machines to authenticated;
    grant update (temperature_mode, updated_at) on table public.machines to authenticated;
  end if;
end $$;
