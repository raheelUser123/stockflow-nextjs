-- Run after 0015. Use Stripe webhook verified server only; do not expose service role key to browser.
alter table public.organization_subscriptions add column if not exists stripe_customer_id text;
alter table public.organization_subscriptions add column if not exists stripe_subscription_id text;
create unique index if not exists organization_subscriptions_stripe_customer_uidx on public.organization_subscriptions(stripe_customer_id) where stripe_customer_id is not null;
create unique index if not exists organization_subscriptions_stripe_sub_uidx on public.organization_subscriptions(stripe_subscription_id) where stripe_subscription_id is not null;
create or replace function public.apply_stripe_billing_event(p_event_id text,p_org uuid,p_plan text,p_status text,p_customer text,p_subscription text,p_event_type text,p_period_end timestamptz default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
 if auth.role() <> 'service_role' then raise exception 'Service role only';end if;
 if p_plan not in ('starter','professional') or p_status not in ('trialing','active','past_due','canceled','expired') or p_event_type not in ('payment_succeeded','plan_changed','subscription_canceled') then raise exception 'Invalid billing data';end if;
 if p_event_id is null or p_subscription is null then raise exception 'Missing Stripe identifiers';end if;
 -- Serialize per-organization updates, with idempotent event ledger.
 perform 1 from public.organization_subscriptions where organization_id=p_org for update;
 if exists(select 1 from public.subscription_events where external_event_id=p_event_id) then return;end if;
 update public.organization_subscriptions set plan_code=p_plan,status=p_status,stripe_customer_id=coalesce(p_customer,stripe_customer_id),stripe_subscription_id=p_subscription,current_period_ends_at=coalesce(p_period_end,current_period_ends_at),updated_at=now() where organization_id=p_org;
 if not found then raise exception 'Organization subscription not found';end if;
 insert into public.subscription_events(organization_id,event_type,external_event_id,description,metadata)
 values(p_org,p_event_type,p_event_id,'Stripe billing webhook',jsonb_build_object('stripe_subscription_id',p_subscription,'status',p_status));
end $$;
revoke all on function public.apply_stripe_billing_event(text,uuid,text,text,text,text,text,timestamptz) from public,anon,authenticated;
grant execute on function public.apply_stripe_billing_event(text,uuid,text,text,text,text,text,timestamptz) to service_role;
