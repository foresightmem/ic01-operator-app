-- IC-01 Operator App
-- Schema DB per notifiche push (Supabase Postgres)
-- NOTE:
-- 1) Esegui questo file nel SQL Editor di Supabase quando vuoi applicare lo schema.
-- 2) Richiede pg_cron (opzionale) se vuoi schedulare l'invio lato DB.
-- 3) Le policy RLS qui sotto sono minime e possono essere raffinate in seguito.

-- ===============================================================
-- Tabella: push_tokens
-- Salva i token per device (FCM/APNs/Web).
-- ===============================================================
create table if not exists public.push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  device_id text not null,
  platform text not null check (platform in ('android', 'ios', 'web')),
  token text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (device_id, platform)
);

create index if not exists push_tokens_user_id_idx on public.push_tokens (user_id);
create index if not exists push_tokens_platform_idx on public.push_tokens (platform);

-- Aggiorna updated_at automaticamente
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists push_tokens_touch_updated_at on public.push_tokens;
create trigger push_tokens_touch_updated_at
before update on public.push_tokens
for each row execute procedure public.touch_updated_at();

-- ===============================================================
-- Tabella: notification_settings
-- Impostazioni per orario notifiche giornaliere.
-- ===============================================================
create table if not exists public.notification_settings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  enabled boolean not null default true,
  hour smallint not null check (hour between 0 and 23),
  minute smallint not null check (minute between 0 and 59),
  timezone text not null default 'Europe/Rome',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists notification_settings_touch_updated_at
  on public.notification_settings;
create trigger notification_settings_touch_updated_at
before update on public.notification_settings
for each row execute procedure public.touch_updated_at();

-- ===============================================================
-- Tabella: notification_outbox
-- Coda di notifiche da inviare (auditing + retry).
-- ===============================================================
create table if not exists public.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text not null,
  data jsonb not null default '{}'::jsonb,
  status text not null default 'pending'
    check (status in ('pending', 'sent', 'failed')),
  attempts int not null default 0,
  last_error text,
  scheduled_for timestamptz not null,
  sent_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists notification_outbox_status_idx
  on public.notification_outbox (status);
create index if not exists notification_outbox_scheduled_idx
  on public.notification_outbox (scheduled_for);

-- ===============================================================
-- RLS
-- ===============================================================
alter table public.push_tokens enable row level security;
alter table public.notification_settings enable row level security;
alter table public.notification_outbox enable row level security;

-- Token: ogni utente legge/scrive solo i propri token
drop policy if exists "push_tokens_select_own" on public.push_tokens;
create policy "push_tokens_select_own"
  on public.push_tokens for select
  using (auth.uid() = user_id);

drop policy if exists "push_tokens_upsert_own" on public.push_tokens;
create policy "push_tokens_upsert_own"
  on public.push_tokens for insert
  with check (auth.uid() = user_id);

drop policy if exists "push_tokens_update_own" on public.push_tokens;
create policy "push_tokens_update_own"
  on public.push_tokens for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Settings: ogni utente legge/scrive solo le proprie impostazioni
drop policy if exists "notification_settings_select_own"
  on public.notification_settings;
create policy "notification_settings_select_own"
  on public.notification_settings for select
  using (auth.uid() = user_id);

drop policy if exists "notification_settings_upsert_own"
  on public.notification_settings;
create policy "notification_settings_upsert_own"
  on public.notification_settings for insert
  with check (auth.uid() = user_id);

drop policy if exists "notification_settings_update_own"
  on public.notification_settings;
create policy "notification_settings_update_own"
  on public.notification_settings for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Outbox: lettura solo propria (scrittura gestita da backend)
drop policy if exists "notification_outbox_select_own"
  on public.notification_outbox;
create policy "notification_outbox_select_own"
  on public.notification_outbox for select
  using (auth.uid() = user_id);

-- ===============================================================
-- (Opzionale) Cron job lato DB
-- Richiede estensione pg_cron abilitata dal progetto Supabase.
-- L'idea è: ogni minuto chiami un'edge function che invia le notifiche pendenti.
--
-- Esempio (da adattare con URL e API key del progetto):
-- select cron.schedule(
--   'ic01_send_notifications',
--   '* * * * *',
--   $$
--   select
--     net.http_post(
--       url := 'https://<project>.supabase.co/functions/v1/send-notifications',
--       headers := '{"Authorization":"Bearer <service_role_key>"}'::jsonb
--     );
--   $$
-- );
-- ===============================================================

-- ===============================================================
-- Trigger immediato su INSERT (solo se scheduled_for <= now())
-- Richiede estensione pg_net (HTTP dal DB).
-- ===============================================================

-- Abilita pg_net (se non già presente)
create extension if not exists pg_net;

create or replace function public.notify_outbox_immediate()
returns trigger language plpgsql as $$
declare
  resp json;
  url text;
  secret text;
begin
  if (new.scheduled_for <= now()) then
    -- URL della edge function send_notifications (da sostituire)
    url := 'https://<project>.supabase.co/functions/v1/send-notifications';
    -- Segreto cron (da sostituire, stesso di NOTIFICATION_CRON_SECRET)
    secret := '<NOTIFICATION_CRON_SECRET>';

    select net.http_post(
      url := url,
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || secret,
        'Content-Type', 'application/json'
      ),
      body := '{}'::jsonb
    ) into resp;
  end if;

  return new;
end;
$$;

drop trigger if exists notification_outbox_immediate_trigger
  on public.notification_outbox;
create trigger notification_outbox_immediate_trigger
after insert on public.notification_outbox
for each row execute procedure public.notify_outbox_immediate();

