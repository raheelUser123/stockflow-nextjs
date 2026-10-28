-- Billing lifecycle: trusted Stripe webhook updates only.
-- Take a backup and test in staging before applying.
alter table public.organization_subscriptions
 add column if not exists stripe_last_event_created bigint not null default 0,
 add column if not exists stripe_last_event_id text;

create or replace function public.apply_stripe_lifecycle_event(
 p_event_id text,p_event_created bigint,p_org uuid,p_plan text,p_status text,
 p_customer text,p_subscription text,p_event_type text,p_period_end timestamptz default null,
 p_cancel_at_period_end boolean default false
) returns text language plpgsql security definer set search_path = '' as $$
declare s public.organization_subscriptions%rowtype;
begin
 if auth.role() <> 'service_role' then raise exception 'Service role only'; end if;
 if p_event_id is null or length(p_event_id)<5 or p_event_created is null or p_event_created<=0
    or p_org is null or p_subscription is null then raise exception 'Invalid event'; end if;
 if p_plan not in ('starter','professional') or p_status not in ('trialing','active','past_due','canceled','expired') then raise exception 'Invalid plan/status'; end if;
 select * into s from public.organization_subscriptions where organization_id=p_org for update;
 if not found then raise exception 'Subscription not found'; end if;
 if exists(select 1 from public.subscription_events where external_event_id=p_event_id) then return 'duplicate'; end if;
 -- Never let a different subscription overwrite an already linked subscription.
 if s.stripe_subscription_id is not null and s.stripe_subscription_id<>p_subscription then
   raise exception 'Subscription mismatch';
 end if;
 if s.stripe_customer_id is not null and p_customer is not null and s.stripe_customer_id<>p_customer then
   raise exception 'Customer mismatch';
 end if;
 if p_event_created < s.stripe_last_event_created then return 'stale'; end if;
 update public.organization_subscriptions set plan_code=p_plan,status=p_status,
   stripe_customer_id=coalesce(p_customer,stripe_customer_id),stripe_subscription_id=p_subscription,
   current_period_ends_at=coalesce(p_period_end,current_period_ends_at),
   cancel_at_period_end=p_cancel_at_period_end,
   stripe_last_event_created=p_event_created,stripe_last_event_id=p_event_id,updated_at=now()
 where organization_id=p_org;
 insert into public.subscription_events(organization_id,event_type,external_event_id,description,metadata)
 values(p_org,'plan_changed',p_event_id,p_event_type,
 jsonb_build_object('stripe_subscription_id',p_subscription,'status',p_status,'stripe_created',p_event_created));
 return 'applied';
end $$;
revoke all on function public.apply_stripe_lifecycle_event(text,bigint,uuid,text,text,text,text,text,timestamptz,boolean) from public,anon,authenticated;
grant execute on function public.apply_stripe_lifecycle_event(text,bigint,uuid,text,text,text,text,text,timestamptz,boolean) to service_role;
