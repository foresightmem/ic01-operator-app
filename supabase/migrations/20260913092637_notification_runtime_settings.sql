-- Store branch/prod runtime-only notification settings outside migrations.
-- Secrets must be inserted operationally per environment, never committed.

create schema if not exists private;

revoke all on schema private from public, anon, authenticated;

create table if not exists private.app_runtime_settings (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);

revoke all on table private.app_runtime_settings from public, anon, authenticated;

create or replace function private.set_app_runtime_setting(
  p_key text,
  p_value text
)
returns void
language sql
security definer
set search_path = private, pg_catalog
as $$
  insert into private.app_runtime_settings as settings (key, value, updated_at)
  values (p_key, p_value, now())
  on conflict (key) do update
  set value = excluded.value,
      updated_at = excluded.updated_at;
$$;

revoke all on function private.set_app_runtime_setting(text, text)
  from public, anon, authenticated;

create or replace function public.notify_outbox_immediate()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  v_url text := nullif(current_setting('app.settings.send_notifications_url', true), '');
  v_secret text := nullif(current_setting('app.settings.notifications_internal_secret', true), '');
  v_response json;
begin
  if v_url is null then
    select nullif(value, '')
    into v_url
    from private.app_runtime_settings
    where key = 'send_notifications_url';
  end if;

  if v_secret is null then
    select nullif(value, '')
    into v_secret
    from private.app_runtime_settings
    where key = 'notifications_internal_secret';
  end if;

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

alter function public.notify_outbox_immediate()
  set search_path = public, private, pg_catalog;

revoke all on function public.notify_outbox_immediate()
  from public, anon, authenticated;
