-- Run once after 0007. Share invitation links manually; no email provider required.
create extension if not exists pgcrypto;
create table if not exists public.organization_invitations (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 email text not null check(length(email) between 3 and 254),
 role public.organization_role not null check(role <> 'owner'),
 token_hash text not null unique,
 invited_by uuid not null references auth.users(id),
 expires_at timestamptz not null default now() + interval '7 days',
 accepted_at timestamptz,
 revoked_at timestamptz,
 created_at timestamptz not null default now()
);
create index if not exists invitations_org_idx on public.organization_invitations(organization_id,created_at desc);
alter table public.organization_invitations enable row level security;
create policy invitation_admin_read on public.organization_invitations for select to authenticated
 using(public.has_org_role(organization_id,array['owner','admin']::public.organization_role[]));
create or replace function public.create_team_invitation(p_org uuid,p_email text,p_role public.organization_role)
returns text language plpgsql security definer set search_path='' as $$
declare v_token text; v_email text:=lower(trim(p_email));
begin
 if not public.has_org_role(p_org,array['owner','admin']::public.organization_role[]) then raise exception 'Permission denied'; end if;
 if p_role='owner' then raise exception 'Cannot invite owner'; end if;
 if length(v_email) not between 3 and 254 or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception 'Invalid email'; end if;
 if exists(select 1 from auth.users u join public.organization_members m on m.user_id=u.id where m.organization_id=p_org and lower(u.email)=v_email) then raise exception 'Already a member'; end if;
 update public.organization_invitations set revoked_at=now() where organization_id=p_org and email=v_email and accepted_at is null and revoked_at is null;
 v_token:=encode(extensions.gen_random_bytes(32),'hex');
 insert into public.organization_invitations(organization_id,email,role,token_hash,invited_by)
 values(p_org,v_email,p_role,encode(extensions.digest(v_token,'sha256'),'hex'),auth.uid());
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id)
 values(p_org,auth.uid(),'team.invite','invitation',v_email);
 return v_token;
end $$;
create or replace function public.accept_team_invitation(p_token text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_inv public.organization_invitations%rowtype; v_email text; 
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 select lower(email) into v_email from auth.users where id=auth.uid() and email_confirmed_at is not null;
 if v_email is null then raise exception 'Verify your email first'; end if;
 select * into v_inv from public.organization_invitations
 where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and accepted_at is null and revoked_at is null and expires_at>now() for update;
 if not found then raise exception 'Invitation invalid or expired'; end if;
 if v_inv.email<>v_email then raise exception 'Invitation belongs to another email'; end if;
 insert into public.organization_members(organization_id,user_id,role) values(v_inv.organization_id,auth.uid(),v_inv.role)
 on conflict(organization_id,user_id) do nothing;
 update public.organization_invitations set accepted_at=now() where id=v_inv.id;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id)
 values(v_inv.organization_id,auth.uid(),'team.accept_invite','member',auth.uid()::text);
 return v_inv.organization_id;
end $$;
revoke all on function public.create_team_invitation(uuid,text,public.organization_role) from public;
revoke all on function public.accept_team_invitation(text) from public;
grant execute on function public.create_team_invitation(uuid,text,public.organization_role) to authenticated;
grant execute on function public.accept_team_invitation(text) to authenticated;
