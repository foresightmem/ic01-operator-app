-- Harden mutable search_path warnings reported by Supabase advisors.
-- Also remove hard-coded notification endpoint credentials from the trigger
-- helper so cloned branches cannot call production functions by accident.

create or replace function public.notify_outbox_immediate()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_url text := nullif(current_setting('app.settings.send_notifications_url', true), '');
  v_secret text := nullif(current_setting('app.settings.notifications_internal_secret', true), '');
  v_response json;
begin
  if new.scheduled_for <= now()
    and v_url is not null
    and v_secret is not null then
    select net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || v_secret,
        'Content-Type', 'application/json'
      ),
      body := '{}'::jsonb
    ) into v_response;
  end if;

  return new;
end;
$$;

alter function public.apply_refill() set search_path = public, pg_catalog;
alter function public.control_center_device_health(timestamp with time zone, text, text, integer, integer, interval)
  set search_path = public, pg_catalog;
alter function public.fill_percent_to_state(numeric) set search_path = public, pg_catalog;
alter function public.normalize_machine_code(text) set search_path = public, pg_catalog;
alter function public.notify_outbox_immediate() set search_path = public, pg_catalog;
alter function public.state_severity(text) set search_path = public, pg_catalog;
alter function public.touch_ticket_lifecycle() set search_path = public, pg_catalog;
alter function public.touch_updated_at() set search_path = public, pg_catalog;
alter function public.whoami() set search_path = public, pg_catalog;
