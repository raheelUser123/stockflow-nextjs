-- Billing audit/history foundation. No charges are initiated by this migration.
create table if not exists public.subscription_events (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 event_type text not null check (event_type in ('trial_started','trial_ended','plan_changed','invoice_issued','payment_succeeded','payment_failed','subscription_canceled','subscription_renewed')),
 external_event_id text unique,
 description text not null default '',
 amount_pkr numeric(14,2) check (amount_pkr is null or amount_pkr >= 0),
 currency text not null default 'PKR' check (currency = 'PKR'),
 occurred_at timestamptz not null default now(),
 metadata jsonb not null default '{}'::jsonb
);
create index if not exists subscription_events_org_date_idx on public.subscription_events(organization_id,occurred_at desc);
alter table public.subscription_events enable row level security;
-- Only owner/admin can read billing events; no browser-facing writes.
create policy subscription_events_owner_admin_read on public.subscription_events
 for select to authenticated using (
  exists (select 1 from public.organization_members m
   where m.organization_id=subscription_events.organization_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin'))
 );
-- Backfill a single non-financial trial-start event for organizations with trials.
insert into public.subscription_events(organization_id,event_type,description,occurred_at)
select s.organization_id,'trial_started','Initial trial started',coalesce(o.created_at,now())
from public.organization_subscriptions s join public.organizations o on o.id=s.organization_id
where s.trial_ends_at is not null
and not exists(select 1 from public.subscription_events e where e.organization_id=s.organization_id and e.event_type='trial_started');
-- Automatically log future trial creation; this is not a payment receipt.
create or replace function public.log_subscription_trial_start() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
 if new.status='trialing' then
  insert into public.subscription_events(organization_id,event_type,description)
  values(new.organization_id,'trial_started','Initial trial started');
 end if;
 return new;
end $$;
drop trigger if exists trg_log_subscription_trial_start on public.organization_subscriptions;
create trigger trg_log_subscription_trial_start after insert on public.organization_subscriptions
for each row execute function public.log_subscription_trial_start();
-- This ledger is append-only from trusted backend functions / future verified webhooks.
revoke all on public.subscription_events from anon,authenticated;
grant select on public.subscription_events to authenticated;
