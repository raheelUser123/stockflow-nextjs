-- Phase 0017: enforce quantitative plan limits in the database.
-- Run only after migration 0016. Back up and test on staging first.
-- This limits inserts (and tenant reassignment) for products, warehouses, and members.
-- It does not suspend companies on trial expiry or enforce feature entitlements.
create or replace function public.enforce_subscription_quantity_limit()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
 v_org uuid;
 v_plan text;
 v_max integer;
 v_count bigint;
begin
 v_org := new.organization_id;
 if tg_op = 'UPDATE' and new.organization_id = old.organization_id then return new; end if;
 -- Serialize concurrent inserts for the same organization.
 perform 1 from public.organizations where id=v_org for update;
 select s.plan_code into v_plan from public.organization_subscriptions s where s.organization_id=v_org;
 if v_plan is null then raise exception 'Organization subscription missing'; end if;
 if tg_table_name='products' then
  select max_products into v_max from public.subscription_plans where code=v_plan;
  select count(*) into v_count from public.products where organization_id=v_org;
 elsif tg_table_name='warehouses' then
  select max_warehouses into v_max from public.subscription_plans where code=v_plan;
  select count(*) into v_count from public.warehouses where organization_id=v_org;
 elsif tg_table_name='organization_members' then
  select max_users into v_max from public.subscription_plans where code=v_plan;
  select count(*) into v_count from public.organization_members where organization_id=v_org;
 else raise exception 'Unsupported limit target'; end if;
 if v_max is not null and v_count >= v_max then
  raise exception 'Plan limit reached for % (% allowed)',tg_table_name,v_max using errcode='P0001';
 end if;
 return new;
end $$;
revoke all on function public.enforce_subscription_quantity_limit() from public,anon,authenticated;
drop trigger if exists trg_product_plan_limit on public.products;
create trigger trg_product_plan_limit before insert or update of organization_id on public.products
for each row execute function public.enforce_subscription_quantity_limit();
drop trigger if exists trg_warehouse_plan_limit on public.warehouses;
create trigger trg_warehouse_plan_limit before insert or update of organization_id on public.warehouses
for each row execute function public.enforce_subscription_quantity_limit();
drop trigger if exists trg_member_plan_limit on public.organization_members;
create trigger trg_member_plan_limit before insert or update of organization_id on public.organization_members
for each row execute function public.enforce_subscription_quantity_limit();
