-- PM-008 closure: authenticated SECURITY DEFINER surface is an audited
-- allowlist. The Flutter refill flow uses perform_refill_consumable(...);
-- perform_refill(uuid) is legacy and should not be directly callable by app
-- users unless a future client compatibility review explicitly re-approves it.

do $$
declare
  v_perform_refill regprocedure := to_regprocedure('public.perform_refill(uuid)');
begin
  if v_perform_refill is not null then
    execute format(
      'revoke all on function %s from public, anon, authenticated',
      v_perform_refill
    );
    execute format('grant execute on function %s to service_role', v_perform_refill);
  end if;
end $$;

comment on function public.perform_refill(uuid)
  is 'Legacy generic refill RPC. PM-008: service-role only; operator app uses perform_refill_consumable(uuid, consumable_type).';

comment on function public.perform_refill_consumable(uuid, public.consumable_type)
  is 'Operator app refill RPC. SECURITY DEFINER allowlisted by PM-008; requires auth.uid(), same organization, and effective machine assignment.';
