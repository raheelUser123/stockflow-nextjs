-- StockFlow Pro 0019: enforce subscription entitlement on business writes.
-- Test on staging and back up production before applying.
-- No automatic charges, account deletions or plan changes occur here.
create or replace function public.subscription_write_allowed(p_org uuid)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare s public.organization_subscriptions%rowtype;
begin
  if p_org is null then return false; end if;
  select * into s from public.organization_subscriptions where organization_id=p_org;
  if not found then return false; end if;
  if s.plan_code = 'free' and s.status in ('active','trialing') then return true; end if;
  if s.status = 'trialing' then
    return s.trial_ends_at is not null and s.trial_ends_at > now();
  end if;
  if s.status = 'active' then
    return s.current_period_ends_at is null or s.current_period_ends_at > now();
  end if;
  -- A canceled subscription may retain access through its paid period.
  if s.status = 'canceled' and s.current_period_ends_at is not null then
    return s.current_period_ends_at > now();
  end if;
  return false;
end $$;
revoke all on function public.subscription_write_allowed(uuid) from public,anon;
grant execute on function public.subscription_write_allowed(uuid) to authenticated,service_role;

create or replace function public.enforce_subscription_business_write()
returns trigger language plpgsql security definer set search_path = '' as $$
declare org uuid;
begin
  -- Administrative migrations and verified Stripe service operations are not blocked.
  if auth.role() = 'service_role' then return coalesce(new,old); end if;
  if tg_op = 'DELETE' then org := old.organization_id;
  else org := new.organization_id; end if;
  if tg_op = 'UPDATE' and new.organization_id is distinct from old.organization_id then
    raise exception 'Organization cannot be changed';
  end if;
  if not public.subscription_write_allowed(org) then
    raise exception 'Subscription inactive or trial expired. Update billing to continue.' using errcode='P0001';
  end if;
  return coalesce(new,old);
end $$;

-- This is intentionally limited to core business tables. Billing, authentication,
-- membership, invoice review and organization settings remain accessible for recovery.
do $$
declare t text;
begin
 foreach t in array array['products','suppliers','customers','categories','warehouses',
   'purchase_orders','purchase_items','sales','sale_items','stock_movements',
   'warehouse_stock','stock_transfers','sales_returns'] loop
   execute format('drop trigger if exists trg_subscription_write on public.%I',t);
   execute format('create trigger trg_subscription_write before insert or update or delete on public.%I for each row execute function public.enforce_subscription_business_write()',t);
 end loop;
end $$;
