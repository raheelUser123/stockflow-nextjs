-- StockFlow Pro: multi-tenant SaaS foundation
create extension if not exists pgcrypto;
create table public.organizations (
 id uuid primary key default gen_random_uuid(), name text not null check(length(trim(name))>=2),
 slug text not null unique check(slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
 currency text not null default 'PKR' check(currency ~ '^[A-Z]{3}$'),
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now()
);
create type public.organization_role as enum ('owner','admin','manager','cashier','supplier','viewer');
create table public.organization_members (
 organization_id uuid not null references public.organizations(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 role public.organization_role not null default 'viewer',
 created_at timestamptz not null default now(),
 primary key(organization_id,user_id)
);
create index organization_members_user_idx on public.organization_members(user_id);
create table public.organization_settings (
 organization_id uuid primary key references public.organizations(id) on delete cascade,
 theme text not null default 'light' check(theme in ('light','dark','system')),
 timezone text not null default 'Asia/Karachi',
 updated_at timestamptz not null default now()
);
create table public.branches (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,
 name text not null,created_at timestamptz not null default now(),
 unique(organization_id,id)
);
create index branches_organization_idx on public.branches(organization_id);
create table public.audit_logs (
 id bigint generated always as identity primary key,
 organization_id uuid not null references public.organizations(id) on delete cascade,
 actor_id uuid references auth.users(id), action text not null,
 entity_type text not null, entity_id text, metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
create index audit_logs_org_created_idx on public.audit_logs(organization_id,created_at desc);
create table public.organization_invitations (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,
 email text not null,role public.organization_role not null default 'viewer',
 token_hash text not null unique,invited_by uuid not null references auth.users(id),
 expires_at timestamptz not null,accepted_at timestamptz,created_at timestamptz not null default now()
);
create index organization_invitations_org_idx on public.organization_invitations(organization_id);
-- SECURITY DEFINER helper avoids self-referential membership RLS recursion.
create function public.is_org_member(p_org uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organization_members m where m.organization_id=p_org and m.user_id=(select auth.uid()))
$$;
create function public.has_org_role(p_org uuid,p_roles public.organization_role[]) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organization_members m where m.organization_id=p_org and m.user_id=(select auth.uid()) and m.role=any(p_roles))
$$;
revoke all on function public.is_org_member(uuid) from public;
revoke all on function public.has_org_role(uuid,public.organization_role[]) from public;
grant execute on function public.is_org_member(uuid) to authenticated;
grant execute on function public.has_org_role(uuid,public.organization_role[]) to authenticated;
-- Atomic organization provisioning. Owner is derived from auth.uid(), never client input.
create function public.create_organization(p_name text,p_slug text) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_user uuid := auth.uid();
begin
 if v_user is null then raise exception 'Authentication required';end if;
 if length(trim(p_name))<2 or length(p_name)>120 or p_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or length(p_slug)>64 then raise exception 'Invalid company name or slug';end if;
 insert into public.organizations(name,slug,created_by) values(trim(p_name),p_slug,v_user) returning id into v_id;
 insert into public.organization_members(organization_id,user_id,role) values(v_id,v_user,'owner');
 insert into public.organization_settings(organization_id) values(v_id);
 insert into public.branches(organization_id,name) values(v_id,'Main Branch');
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id) values(v_id,v_user,'organization.created','organization',v_id::text);
 return v_id;
end $$;
revoke all on function public.create_organization(text,text) from public;
grant execute on function public.create_organization(text,text) to authenticated;
alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.organization_settings enable row level security;
alter table public.branches enable row level security;
alter table public.audit_logs enable row level security;
alter table public.organization_invitations enable row level security;
create policy org_read on public.organizations for select to authenticated using(public.is_org_member(id));
create policy member_read on public.organization_members for select to authenticated using(public.is_org_member(organization_id));
create policy settings_read on public.organization_settings for select to authenticated using(public.is_org_member(organization_id));
create policy branches_read on public.branches for select to authenticated using(public.is_org_member(organization_id));
create policy audit_read on public.audit_logs for select to authenticated using(public.has_org_role(organization_id,array['owner','admin']::public.organization_role[]));
create policy invitations_read on public.organization_invitations for select to authenticated using(public.has_org_role(organization_id,array['owner','admin']::public.organization_role[]));
-- No direct client write policies. Mutations must use carefully scoped server-side RPCs.
