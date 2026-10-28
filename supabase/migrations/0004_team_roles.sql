-- Apply after 0003. Existing registered users can be added by email.
-- A brand-new user must first register and confirm their email.
create table public.custom_roles (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 name text not null check(length(trim(name)) between 2 and 60),
 permissions text[] not null default '{}',
 created_at timestamptz not null default now(),
 unique(organization_id,name), unique(organization_id,id)
);
create table public.member_custom_roles (
 organization_id uuid not null,
 user_id uuid not null,
 custom_role_id uuid not null,
 primary key(organization_id,user_id),
 foreign key(organization_id,user_id) references public.organization_members(organization_id,user_id) on delete cascade,
 foreign key(organization_id,custom_role_id) references public.custom_roles(organization_id,id) on delete cascade
);
alter table public.custom_roles enable row level security;
alter table public.member_custom_roles enable row level security;
create policy custom_roles_read on public.custom_roles for select to authenticated using(public.is_org_member(organization_id));
create policy custom_roles_members_read on public.member_custom_roles for select to authenticated using(public.is_org_member(organization_id));
create or replace function public.add_registered_member(p_org uuid,p_email text,p_role public.organization_role)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_user uuid;
begin
 if not public.has_org_role(p_org,array['owner','admin']::public.organization_role[]) then raise exception 'Permission denied'; end if;
 if p_role='owner' then raise exception 'Cannot assign owner'; end if;
 if length(trim(p_email))>254 or position('@' in p_email)=0 then raise exception 'Invalid email'; end if;
 select id into v_user from auth.users where lower(email)=lower(trim(p_email)) and email_confirmed_at is not null limit 1;
 if v_user is null then raise exception 'User must register and confirm their email first'; end if;
 insert into public.organization_members(organization_id,user_id,role) values(p_org,v_user,p_role)
 on conflict(organization_id,user_id) do nothing;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id) values(p_org,auth.uid(),'team.add','member',v_user::text);
 return v_user;
end $$;
create or replace function public.manage_custom_role(p_org uuid,p_action text,p_id uuid,p_name text,p_permissions text[])
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_allowed text[]:=array['products.read','products.write','suppliers.read','suppliers.write','inventory.read','inventory.write','purchases.read','purchases.write','sales.read','sales.write','reports.read','team.read','settings.read'];
begin
 if not public.has_org_role(p_org,array['owner','admin']::public.organization_role[]) then raise exception 'Permission denied'; end if;
 if p_action in ('create','update') then
  if length(trim(p_name)) not between 2 and 60 or p_permissions is null or not (p_permissions <@ v_allowed) then raise exception 'Invalid role name or permissions'; end if;
 end if;
 if p_action='create' then
  insert into public.custom_roles(organization_id,name,permissions) values(p_org,trim(p_name),p_permissions) returning id into v_id;
 elsif p_action='update' then
  update public.custom_roles set name=trim(p_name),permissions=p_permissions where id=p_id and organization_id=p_org returning id into v_id;
 elsif p_action='delete' then
  delete from public.custom_roles where id=p_id and organization_id=p_org returning id into v_id;
 else raise exception 'Invalid action'; end if;
 if v_id is null then raise exception 'Role not found'; end if;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id) values(p_org,auth.uid(),'custom_role.'||p_action,'custom_role',v_id::text);
 return v_id;
end $$;
create or replace function public.assign_custom_role(p_org uuid,p_user uuid,p_role_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.has_org_role(p_org,array['owner','admin']::public.organization_role[]) then raise exception 'Permission denied'; end if;
 if not exists(select 1 from public.organization_members where organization_id=p_org and user_id=p_user and role<>'owner') then raise exception 'Member not found or protected'; end if;
 if p_role_id is null then
  delete from public.member_custom_roles where organization_id=p_org and user_id=p_user;
 else
  if not exists(select 1 from public.custom_roles where organization_id=p_org and id=p_role_id) then raise exception 'Invalid role'; end if;
  insert into public.member_custom_roles(organization_id,user_id,custom_role_id) values(p_org,p_user,p_role_id)
  on conflict(organization_id,user_id) do update set custom_role_id=excluded.custom_role_id;
 end if;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id) values(p_org,auth.uid(),'custom_role.assign','member',p_user::text);
end $$;
-- Explicit permissions helper for future module RPCs. Existing RPCs still use built-in role checks.
create or replace function public.has_org_permission(p_org uuid,p_permission text)
returns boolean language sql stable security definer set search_path='' as $$
 select public.has_org_role(p_org,array['owner','admin']::public.organization_role[])
 or exists(select 1 from public.member_custom_roles m join public.custom_roles r on r.id=m.custom_role_id and r.organization_id=m.organization_id
 where m.organization_id=p_org and m.user_id=auth.uid() and p_permission=any(r.permissions));
$$;
revoke all on function public.add_registered_member(uuid,text,public.organization_role) from public;
revoke all on function public.manage_custom_role(uuid,text,uuid,text,text[]) from public;
revoke all on function public.assign_custom_role(uuid,uuid,uuid) from public;
revoke all on function public.has_org_permission(uuid,text) from public;
grant execute on function public.add_registered_member(uuid,text,public.organization_role) to authenticated;
grant execute on function public.manage_custom_role(uuid,text,uuid,text,text[]) to authenticated;
grant execute on function public.assign_custom_role(uuid,uuid,uuid) to authenticated;
grant execute on function public.has_org_permission(uuid,text) to authenticated;
