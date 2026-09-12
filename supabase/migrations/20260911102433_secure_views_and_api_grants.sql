-- Remediation for SEC-002 and the view portion of SEC-003.
-- Public views should execute with the querying user's privileges so base table
-- RLS remains the enforcement layer.

do $$
declare
  v_view regclass;
  v_view_name text;
begin
  foreach v_view_name in array array[
    'public.client_machines',
    'public.machine_effective_assignment',
    'public.machine_effective_consumables',
    'public.operator_ranking',
    'public.client_states_effective',
    'public.client_states',
    'public.client_states_v2',
    'public.machine_states',
    'public.machine_states_v2',
    'public.ticket_list'
  ]
  loop
    v_view := to_regclass(v_view_name);
    if v_view is not null then
      execute format('alter view %s set (security_invoker = true)', v_view);
      execute format('revoke all on table %s from anon', v_view);
      execute format('revoke all on table %s from authenticated', v_view);
      execute format('grant select on table %s to authenticated', v_view);
    end if;
  end loop;
end $$;

-- Remove accidental anonymous GraphQL/Data API visibility for application data.
do $$
declare
  v_object regclass;
  v_object_name text;
begin
  foreach v_object_name in array array[
    'public.profiles',
    'public.clients',
    'public.sites',
    'public.machines',
    'public.refills',
    'public.tickets',
    'public.ticket_events',
    'public.notification_outbox',
    'public.notification_settings',
    'public.push_tokens',
    'public.operator_unavailability',
    'public.temp_machine_assignments'
  ]
  loop
    v_object := to_regclass(v_object_name);
    if v_object is not null then
      execute format('revoke all on table %s from anon', v_object);
    end if;
  end loop;
end $$;
