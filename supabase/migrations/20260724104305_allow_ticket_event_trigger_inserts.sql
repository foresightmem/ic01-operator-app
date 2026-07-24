-- Ticket lifecycle events are written by an internal trigger on tickets.
-- The triggering user may pass tickets RLS but still be blocked by
-- ticket_events RLS, so the trigger function needs to run with the owner's
-- privileges while remaining unavailable as a client-callable API.

create or replace function public.record_ticket_lifecycle_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.ticket_events (ticket_id, event_type, metadata)
    values (
      new.id,
      'created',
      jsonb_build_object(
        'status', new.status,
        'reason', new.reason,
        'source', new.source
      )
    );
    return new;
  end if;

  if old.status is distinct from new.status then
    insert into public.ticket_events (ticket_id, event_type, metadata)
    values (
      new.id,
      case
        when new.status in ('resolved', 'closed') then 'resolved'
        when old.status in ('resolved', 'closed')
          and new.status not in ('resolved', 'closed') then 'reopened'
        when new.status = 'assigned' then 'assigned'
        else 'status_changed'
      end,
      jsonb_build_object('from', old.status, 'to', new.status)
    );
  end if;

  return new;
end;
$$;

revoke all on function public.record_ticket_lifecycle_event()
  from public, anon, authenticated;
