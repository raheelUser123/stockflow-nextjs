-- StockFlow Pro: enforce custom role permissions for core business mutations.
-- Apply AFTER 0012. Keep a database backup before running on production.
-- A custom role is additive to the member's built-in role. Owner/admin always retain access.

create or replace function public.has_org_permission(p_org uuid,p_permission text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists (
  select 1 from public.organization_members m
  where m.organization_id=p_org and m.user_id=(select auth.uid())
    and (
      m.role in ('owner','admin')
      or (m.role='manager' and p_permission = any(array[
        'products.read','products.write','suppliers.read','suppliers.write',
        'inventory.read','inventory.write','purchases.read','purchases.write',
        'sales.read','sales.write','reports.read','team.read','settings.read']))
      or (m.role='cashier' and p_permission = any(array['products.read','inventory.read','sales.read','sales.write']))
      or (m.role='viewer' and p_permission = any(array['products.read','suppliers.read','inventory.read','purchases.read','sales.read','reports.read']))
      or exists (
        select 1 from public.member_custom_roles mr
        join public.custom_roles cr on cr.organization_id=mr.organization_id and cr.id=mr.custom_role_id
        where mr.organization_id=m.organization_id and mr.user_id=m.user_id
          and p_permission=any(cr.permissions)
      )
    )
 );
$$;
revoke all on function public.has_org_permission(uuid,text) from public;
grant execute on function public.has_org_permission(uuid,text) to authenticated;

-- Replace only the exact authorization guards in the existing database functions.
-- This preserves previously deployed business logic rather than copying stale definitions.
do $$
declare
  entry record;
  original text;
  modified text;
  guard text;
  target text;
begin
  for entry in select * from (values
    ('public.manage_record(uuid,text,text,uuid,jsonb)'::text,'products.write'::text,'record'::text),
    ('public.manage_extended(uuid,text,text,uuid,jsonb)','products.write','extended'),
    ('public.checkout(uuid,jsonb,text)','sales.write','sales'),
    ('public.create_purchase(uuid,uuid,text,jsonb)','purchases.write','purchase'),
    ('public.receive_purchase(uuid,uuid)','purchases.write','purchase'),
    ('public.transfer_warehouse_stock(uuid,uuid,uuid,uuid,integer)','inventory.write','inventory'),
    ('public.allocate_warehouse_stock(uuid,uuid,uuid,integer)','inventory.write','inventory')
  ) as x(signature,permission,category)
  loop
    select pg_get_functiondef(to_regprocedure(entry.signature)) into original;
    if original is null then raise exception 'Missing function: %',entry.signature; end if;
    modified:=original;
    -- All core business RPCs previously used a built-in role check.
    guard:='public.has_org_role(p_org,array[''owner'',''admin'',''manager'']::public.organization_role[])';
    if entry.category='sales' then
      guard:='public.has_org_role(p_org,array[''owner'',''admin'',''manager'',''cashier'']::public.organization_role[])';
    elsif entry.signature like '%allocate_warehouse_stock%' then
      guard:='public.has_org_role(p_org,array[''owner'',''admin'']::public.organization_role[])';
    end if;
    target:='public.has_org_permission(p_org,'''||entry.permission||''')';
    if position(guard in modified)=0 then
      raise exception 'Expected authorization guard missing in %. Migration stopped; inspect function before applying.',entry.signature;
    end if;
    modified:=replace(modified,guard,target);
    -- Different entity types need different permissions.
    if entry.category='record' then
      modified:=replace(modified,'public.has_org_permission(p_org,''products.write'')',
        'public.has_org_permission(p_org,case when p_kind=''supplier'' then ''suppliers.write'' else ''products.write'' end)');
    elsif entry.category='extended' then
      modified:=replace(modified,'public.has_org_permission(p_org,''products.write'')',
        'public.has_org_permission(p_org,case when p_kind=''warehouse'' then ''inventory.write'' when p_kind=''customer'' then ''sales.write'' else ''products.write'' end)');
    end if;
    execute modified;
  end loop;
end $$;

-- Company administrators can inspect permission assignments.
-- This function provides a single authoritative permission check for UI gating.
create or replace function public.my_org_permissions(p_org uuid)
returns table(permission text) language sql stable security definer set search_path='' as $$
 select p.permission
 from unnest(array[
 'products.read','products.write','suppliers.read','suppliers.write',
 'inventory.read','inventory.write','purchases.read','purchases.write',
 'sales.read','sales.write','reports.read','team.read','settings.read'
 ]) as p(permission)
 where public.has_org_permission(p_org,p.permission);
$$;
revoke all on function public.my_org_permissions(uuid) from public;
grant execute on function public.my_org_permissions(uuid) to authenticated;
