-- Subscription tracking and trial management. No payment collection in this migration.
create table if not exists public.subscription_plans (
 code text primary key check(code ~ '^[a-z_]+$'), name text not null,
 monthly_price_pkr numeric(12,2) not null check(monthly_price_pkr>=0),
 max_users integer, max_products integer, max_warehouses integer,
 features jsonb not null default '{}'::jsonb, active boolean not null default true
);
insert into public.subscription_plans(code,name,monthly_price_pkr,max_users,max_products,max_warehouses,features) values
('free','Free',0,2,100,1,'{"pos":true,"analytics":"basic"}'),
('starter','Starter',2999,5,1000,2,'{"pos":true,"analytics":"basic"}'),
('professional','Professional',7999,25,10000,10,'{"pos":true,"analytics":"advanced"}'),
('enterprise','Enterprise',0,null,null,null,'{"pos":true,"analytics":"advanced","custom_pricing":true}')
on conflict(code) do nothing;
create table if not exists public.organization_subscriptions (
 organization_id uuid primary key references public.organizations(id) on delete cascade,
 plan_code text not null references public.subscription_plans(code) default 'professional',
 status text not null default 'trialing' check(status in ('trialing','active','past_due','canceled','expired')),
 trial_ends_at timestamptz, current_period_ends_at timestamptz,
 cancel_at_period_end boolean not null default false,
 updated_at timestamptz not null default now(),
 updated_by uuid references auth.users(id)
);
insert into public.organization_subscriptions(organization_id,plan_code,status,trial_ends_at)
select id,'professional','trialing',created_at + interval '14 days' from public.organizations
on conflict(organization_id) do nothing;
create or replace function public.init_subscription_for_organization() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 insert into public.organization_subscriptions(organization_id,plan_code,status,trial_ends_at)
 values(new.id,'professional','trialing',now()+interval '14 days')
 on conflict(organization_id) do nothing;
 return new;
end $$;
drop trigger if exists trg_init_subscription on public.organizations;
create trigger trg_init_subscription after insert on public.organizations
for each row execute function public.init_subscription_for_organization();
alter table public.subscription_plans enable row level security;
alter table public.organization_subscriptions enable row level security;
create policy plans_public_read on public.subscription_plans for select to authenticated using(active);
create policy subscription_member_read on public.organization_subscriptions for select to authenticated using(public.is_org_member(organization_id));
create or replace function public.subscription_overview(p_org uuid)
returns table(plan_code text,plan_name text,status text,trial_ends_at timestamptz,current_period_ends_at timestamptz,max_users integer,max_products integer,max_warehouses integer,member_count bigint,product_count bigint,warehouse_count bigint)
language plpgsql stable security definer set search_path='' as $$
begin
 if not public.is_org_member(p_org) then raise exception 'Not authorized';end if;
 return query select s.plan_code,p.name,s.status,s.trial_ends_at,s.current_period_ends_at,
 p.max_users,p.max_products,p.max_warehouses,
 (select count(*) from public.organization_members m where m.organization_id=p_org),
 (select count(*) from public.products pr where pr.organization_id=p_org),
 (select count(*) from public.warehouses w where w.organization_id=p_org)
 from public.organization_subscriptions s join public.subscription_plans p on p.code=s.plan_code
 where s.organization_id=p_org;
end $$;
revoke all on function public.subscription_overview(uuid) from public;
grant execute on function public.subscription_overview(uuid) to authenticated;
-- Plan changes and billing status are intentionally not exposed to ordinary users.
-- A verified billing webhook or trusted platform admin workflow must update subscriptions.
