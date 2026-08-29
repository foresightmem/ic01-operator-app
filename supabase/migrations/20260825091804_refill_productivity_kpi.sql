-- Refill productivity KPI for the Admin Dashboard.
--
-- The refill event is stored in public.refills because it already represents
-- the historical operational log. New consumable-based refills freeze the dose
-- snapshot before the machine state is reset.

alter table public.refills
  add column if not exists consumable_type public.consumable_type,
  add column if not exists previous_units integer,
  add column if not exists capacity_units integer,
  add column if not exists refilled_units integer,
  add column if not exists snapshot_metadata jsonb not null default '{}'::jsonb;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'refills_units_snapshot_nonnegative'
      and conrelid = 'public.refills'::regclass
  ) then
    alter table public.refills
      add constraint refills_units_snapshot_nonnegative
      check (
        (previous_units is null or previous_units >= 0)
        and (capacity_units is null or capacity_units >= 0)
        and (refilled_units is null or refilled_units >= 0)
      );
  end if;
end $$;

create index if not exists refills_productivity_created_operator_idx
  on public.refills (created_at, operator_id)
  where undone_at is null;

create index if not exists refills_productivity_machine_created_idx
  on public.refills (machine_id, created_at desc)
  where undone_at is null;

create or replace function public.perform_refill_consumable(
  p_machine_id uuid,
  p_type public.consumable_type
)
returns json
language plpgsql
security definer
set search_path = ''
set row_security = off
as $$
declare
  v_uid uuid := auth.uid();
  v_allowed boolean;
  v_prev integer;
  v_cap integer;
  v_refilled integer;
  v_previous_percent numeric;
  v_refill_id uuid;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  select exists (
    select 1
    from public.machines m
    where m.id = p_machine_id
      and m.organization_id = public.current_app_organization_id()
      and (
        m.assigned_operator_id = v_uid
        or exists (
          select 1
          from public.temp_machine_assignments t
          where t.machine_id = m.id
            and t.status = 'confirmed'
            and current_date between t.start_date and t.end_date
            and t.new_operator_id = v_uid
        )
      )
  ) into v_allowed;

  if not v_allowed then
    raise exception 'Not allowed for this machine';
  end if;

  select mc.current_units, mc.capacity_units
  into v_prev, v_cap
  from public.machine_consumables mc
  where mc.machine_id = p_machine_id
    and mc.type = p_type
    and mc.is_enabled = true
  for update;

  if v_cap is null then
    raise exception 'Consumable disabled or not found';
  end if;

  v_refilled := greatest(v_cap - v_prev, 0);
  v_previous_percent := case
    when v_cap > 0 then round(v_prev::numeric / v_cap::numeric * 100, 2)
    else 0
  end;

  update public.machine_consumables
  set current_units = capacity_units,
      updated_at = now()
  where machine_id = p_machine_id
    and type = p_type
    and is_enabled = true;

  if v_refilled > 0 then
    insert into public.refills (
      machine_id,
      operator_id,
      previous_fill_percent,
      new_fill_percent,
      consumable_type,
      previous_units,
      capacity_units,
      refilled_units,
      snapshot_metadata
    )
    values (
      p_machine_id,
      v_uid,
      v_previous_percent,
      100,
      p_type,
      v_prev,
      v_cap,
      v_refilled,
      jsonb_build_object(
        'source', 'perform_refill_consumable',
        'snapshot', 'before_refill',
        'observed_refill_window_timezone', 'Europe/Rome'
      )
    )
    returning id into v_refill_id;
  end if;

  return json_build_object(
    'ok', true,
    'machine_id', p_machine_id,
    'type', p_type::text,
    'previous_units', v_prev,
    'capacity_units', v_cap,
    'new_units', v_cap,
    'refilled_units', v_refilled,
    'refill_id', v_refill_id,
    'event_recorded', v_refill_id is not null
  );
end;
$$;

revoke all on function public.perform_refill_consumable(
  uuid,
  public.consumable_type
) from public, anon;
grant execute on function public.perform_refill_consumable(
  uuid,
  public.consumable_type
) to authenticated;

create or replace function public.get_refill_productivity_kpi(
  p_period_days integer default 30,
  p_timezone text default 'Europe/Rome',
  p_theoretical_work_hours_per_day numeric default 6
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set row_security = off
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_organization_id uuid;
  v_period_days integer := greatest(1, least(coalesce(p_period_days, 30), 366));
  v_timezone text := coalesce(nullif(trim(p_timezone), ''), 'Europe/Rome');
  v_theoretical_hours numeric :=
    greatest(coalesce(p_theoretical_work_hours_per_day, 6), 0);
  v_period_end timestamptz := now();
  v_period_start timestamptz;
  v_previous_start timestamptz;
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  perform now() at time zone v_timezone;

  select p.role, p.organization_id
  into v_role, v_organization_id
  from public.profiles p
  where p.id = v_uid
  limit 1;

  if v_role <> 'admin' or v_organization_id is null then
    raise exception 'Admin role required' using errcode = '42501';
  end if;

  if v_theoretical_hours <= 0 then
    raise exception 'Theoretical work hours per day must be positive';
  end if;

  v_period_start := v_period_end - make_interval(days => v_period_days);
  v_previous_start := v_period_start - make_interval(days => v_period_days);

  with period_ranges as (
    select
      'current'::text as bucket,
      v_period_start as starts_at,
      v_period_end as ends_at
    union all
    select
      'previous'::text as bucket,
      v_previous_start as starts_at,
      v_period_start as ends_at
  ),
  all_refills as (
    select
      pr.bucket,
      r.id,
      r.machine_id,
      r.operator_id,
      coalesce(nullif(trim(p.full_name), ''), 'Operatore') as operator_name,
      r.created_at,
      (r.created_at at time zone v_timezone)::date as operational_day,
      r.refilled_units,
      case
        when r.refilled_units is not null and r.refilled_units > 0
          then r.refilled_units::numeric
        else null
      end as refilled_doses,
      (r.refilled_units is not null and r.refilled_units <= 0) as invalid_quantity
    from public.refills r
    join period_ranges pr
      on r.created_at >= pr.starts_at
     and r.created_at < pr.ends_at
    join public.machines m on m.id = r.machine_id
    join public.profiles p on p.id = r.operator_id
    where r.created_at is not null
      and r.machine_id is not null
      and r.operator_id is not null
      and r.undone_at is null
      and m.organization_id = v_organization_id
  ),
  valid_refills as (
    select *
    from all_refills
    where invalid_quantity = false
  ),
  excluded_refills as (
    select
      bucket,
      count(*)::integer as invalid_quantity_count
    from all_refills
    where invalid_quantity = true
    group by bucket
  ),
  daily as (
    select
      bucket,
      operator_id,
      max(operator_name) as operator_name,
      operational_day,
      count(*)::integer as refill_count,
      count(distinct machine_id)::integer as unique_machine_count,
      coalesce(sum(refilled_doses), 0)::numeric as total_refilled_doses,
      count(refilled_doses)::integer as refill_with_quantity_count,
      count(*) filter (where refilled_units is null)::integer
        as legacy_without_quantity_count,
      min(created_at) as first_refill_at,
      max(created_at) as last_refill_at
    from valid_refills
    group by bucket, operator_id, operational_day
  ),
  daily_enriched as (
    select
      *,
      (
        refill_count >= 2
        and last_refill_at > first_refill_at
      ) as has_observed_window,
      case
        when refill_count >= 2 and last_refill_at > first_refill_at
          then extract(epoch from (last_refill_at - first_refill_at)) / 3600.0
        else null
      end as observed_refill_hours
    from daily
  ),
  operator_base as (
    select
      bucket,
      operator_id,
      max(operator_name) as operator_name,
      count(*)::integer as refill_count,
      count(distinct machine_id)::integer as unique_machine_count,
      coalesce(sum(refilled_doses), 0)::numeric as total_refilled_doses,
      count(refilled_doses)::integer as refill_with_quantity_count,
      count(*) filter (where refilled_units is null)::integer
        as legacy_without_quantity_count
    from valid_refills
    group by bucket, operator_id
  ),
  operator_daily as (
    select
      bucket,
      operator_id,
      count(*)::integer as active_refill_days,
      count(*) filter (where has_observed_window)::integer as observable_days,
      coalesce(sum(observed_refill_hours) filter (where has_observed_window), 0)
        ::numeric as observed_refill_hours,
      coalesce(sum(total_refilled_doses) filter (where has_observed_window), 0)
        ::numeric as doses_for_observed_rate
    from daily_enriched
    group by bucket, operator_id
  ),
  operator_metrics as (
    select
      ob.bucket,
      ob.operator_id,
      ob.operator_name,
      ob.total_refilled_doses,
      ob.refill_count,
      ob.unique_machine_count,
      coalesce(od.active_refill_days, 0)::integer as active_refill_days,
      (coalesce(od.active_refill_days, 0) * v_theoretical_hours)::numeric
        as theoretical_hours,
      coalesce(od.observable_days, 0)::integer as observable_days,
      coalesce(od.observed_refill_hours, 0)::numeric as observed_refill_hours,
      coalesce(od.doses_for_observed_rate, 0)::numeric
        as doses_for_observed_rate,
      case
        when ob.refill_with_quantity_count > 0
          and coalesce(od.active_refill_days, 0) > 0
          then ob.total_refilled_doses
            / nullif(coalesce(od.active_refill_days, 0) * v_theoretical_hours, 0)
        else null
      end as doses_per_theoretical_hour,
      case
        when coalesce(od.observed_refill_hours, 0) > 0
          and coalesce(od.doses_for_observed_rate, 0) > 0
          then od.doses_for_observed_rate / od.observed_refill_hours
        else null
      end as doses_per_observed_hour,
      case
        when coalesce(od.observable_days, 0) > 0
          then od.observed_refill_hours
            / nullif(coalesce(od.observable_days, 0) * v_theoretical_hours, 0)
        else null
      end as observed_window_utilization,
      greatest(
        (coalesce(od.observable_days, 0) * v_theoretical_hours)
          - coalesce(od.observed_refill_hours, 0),
        0
      )::numeric as theoretical_residual_capacity_hours,
      ob.refill_with_quantity_count,
      ob.legacy_without_quantity_count
    from operator_base ob
    left join operator_daily od
      on od.bucket = ob.bucket
     and od.operator_id = ob.operator_id
  ),
  summary_base as (
    select
      bucket,
      count(*)::integer as refill_count,
      count(distinct machine_id)::integer as unique_machine_count,
      coalesce(sum(refilled_doses), 0)::numeric as total_refilled_doses,
      count(refilled_doses)::integer as refill_with_quantity_count,
      count(*) filter (where refilled_units is null)::integer
        as legacy_without_quantity_count
    from valid_refills
    group by bucket
  ),
  summary_daily as (
    select
      bucket,
      count(*)::integer as active_refill_days,
      count(*) filter (where has_observed_window)::integer as observable_days,
      coalesce(sum(observed_refill_hours) filter (where has_observed_window), 0)
        ::numeric as observed_refill_hours,
      coalesce(sum(total_refilled_doses) filter (where has_observed_window), 0)
        ::numeric as doses_for_observed_rate
    from daily_enriched
    group by bucket
  ),
  summary_metrics as (
    select
      pr.bucket,
      coalesce(sb.total_refilled_doses, 0)::numeric as total_refilled_doses,
      coalesce(sb.refill_count, 0)::integer as refill_count,
      coalesce(sb.unique_machine_count, 0)::integer as unique_machine_count,
      coalesce(sd.active_refill_days, 0)::integer as active_refill_days,
      (coalesce(sd.active_refill_days, 0) * v_theoretical_hours)::numeric
        as theoretical_hours,
      coalesce(sd.observable_days, 0)::integer as observable_days,
      coalesce(sd.observed_refill_hours, 0)::numeric as observed_refill_hours,
      coalesce(sd.doses_for_observed_rate, 0)::numeric
        as doses_for_observed_rate,
      case
        when coalesce(sb.refill_with_quantity_count, 0) > 0
          and coalesce(sd.active_refill_days, 0) > 0
          then sb.total_refilled_doses
            / nullif(coalesce(sd.active_refill_days, 0) * v_theoretical_hours, 0)
        else null
      end as doses_per_theoretical_hour,
      case
        when coalesce(sd.observed_refill_hours, 0) > 0
          and coalesce(sd.doses_for_observed_rate, 0) > 0
          then sd.doses_for_observed_rate / sd.observed_refill_hours
        else null
      end as doses_per_observed_hour,
      case
        when coalesce(sd.observable_days, 0) > 0
          then sd.observed_refill_hours
            / nullif(coalesce(sd.observable_days, 0) * v_theoretical_hours, 0)
        else null
      end as observed_window_utilization,
      greatest(
        (coalesce(sd.observable_days, 0) * v_theoretical_hours)
          - coalesce(sd.observed_refill_hours, 0),
        0
      )::numeric as theoretical_residual_capacity_hours,
      coalesce(sb.refill_with_quantity_count, 0)::integer
        as refill_with_quantity_count,
      coalesce(sb.legacy_without_quantity_count, 0)::integer
        as legacy_without_quantity_count,
      coalesce(er.invalid_quantity_count, 0)::integer
        as invalid_quantity_count
    from period_ranges pr
    left join summary_base sb on sb.bucket = pr.bucket
    left join summary_daily sd on sd.bucket = pr.bucket
    left join excluded_refills er on er.bucket = pr.bucket
  ),
  current_summary as (
    select * from summary_metrics where bucket = 'current'
  ),
  previous_summary as (
    select * from summary_metrics where bucket = 'previous'
  ),
  current_operators as (
    select
      c.*,
      case
        when p.doses_per_theoretical_hour is null
          or p.doses_per_theoretical_hour = 0
          or c.doses_per_theoretical_hour is null
          then null
        else ((c.doses_per_theoretical_hour - p.doses_per_theoretical_hour)
          / p.doses_per_theoretical_hour) * 100
      end as productivity_delta_percent
    from operator_metrics c
    left join operator_metrics p
      on p.bucket = 'previous'
     and p.operator_id = c.operator_id
    where c.bucket = 'current'
  ),
  operators_json as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'operator_id', operator_id,
          'operator_name', operator_name,
          'total_refilled_doses', total_refilled_doses,
          'refill_count', refill_count,
          'unique_machine_count', unique_machine_count,
          'active_refill_days', active_refill_days,
          'theoretical_hours', theoretical_hours,
          'observable_days', observable_days,
          'observed_refill_hours', observed_refill_hours,
          'doses_for_observed_rate', doses_for_observed_rate,
          'doses_per_theoretical_hour', doses_per_theoretical_hour,
          'doses_per_observed_hour', doses_per_observed_hour,
          'observed_window_utilization', observed_window_utilization,
          'theoretical_residual_capacity_hours',
            theoretical_residual_capacity_hours,
          'refill_with_quantity_count', refill_with_quantity_count,
          'legacy_without_quantity_count', legacy_without_quantity_count,
          'productivity_delta_percent', productivity_delta_percent
        )
        order by doses_per_theoretical_hour desc nulls last, operator_name
      ),
      '[]'::jsonb
    ) as payload
    from current_operators
  )
  select jsonb_build_object(
    'period', jsonb_build_object(
      'start', v_period_start,
      'end', v_period_end,
      'days', v_period_days,
      'timezone', v_timezone,
      'theoretical_work_hours_per_day', v_theoretical_hours
    ),
    'previous_period', jsonb_build_object(
      'start', v_previous_start,
      'end', v_period_start,
      'days', v_period_days,
      'timezone', v_timezone
    ),
    'summary', (
      select to_jsonb(cs) - 'bucket'
      from current_summary cs
    ),
    'previous_summary', (
      select to_jsonb(ps) - 'bucket'
      from previous_summary ps
    ),
    'comparison', (
      select jsonb_build_object(
        'doses_delta_percent',
          case
            when ps.total_refilled_doses = 0 then null
            else ((cs.total_refilled_doses - ps.total_refilled_doses)
              / ps.total_refilled_doses) * 100
          end,
        'refill_delta_percent',
          case
            when ps.refill_count = 0 then null
            else ((cs.refill_count - ps.refill_count)::numeric
              / ps.refill_count::numeric) * 100
          end,
        'theoretical_productivity_delta_percent',
          case
            when ps.doses_per_theoretical_hour is null
              or ps.doses_per_theoretical_hour = 0
              or cs.doses_per_theoretical_hour is null
              then null
            else ((cs.doses_per_theoretical_hour
              - ps.doses_per_theoretical_hour)
              / ps.doses_per_theoretical_hour) * 100
          end,
        'observed_productivity_delta_percent',
          case
            when ps.doses_per_observed_hour is null
              or ps.doses_per_observed_hour = 0
              or cs.doses_per_observed_hour is null
              then null
            else ((cs.doses_per_observed_hour - ps.doses_per_observed_hour)
              / ps.doses_per_observed_hour) * 100
          end
      )
      from current_summary cs
      cross join previous_summary ps
    ),
    'operators', (select payload from operators_json)
  )
  into v_result;

  return v_result;
end;
$$;

revoke all on function public.get_refill_productivity_kpi(
  integer,
  text,
  numeric
) from public, anon;
grant execute on function public.get_refill_productivity_kpi(
  integer,
  text,
  numeric
) to authenticated;

comment on function public.get_refill_productivity_kpi(integer, text, numeric)
  is 'Admin-only refill productivity KPI. Uses active refill days and daily observed refill windows in the requested timezone.';

comment on column public.refills.refilled_units
  is 'Immutable snapshot of doses refilled at confirmation time. For full refill flows this is capacity_units - previous_units before reset.';

notify pgrst, 'reload schema';
