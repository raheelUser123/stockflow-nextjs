-- Apply once after 0008. Supplier accounts are linked explicitly to a supplier record.
create table public.supplier_accounts (
 organization_id uuid not null,
 supplier_id uuid not null,
 user_id uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key(organization_id,supplier_id,user_id),
 foreign key(organization_id,supplier_id) references public.suppliers(organization_id,id) on delete cascade,
 foreign key(organization_id,user_id) references public.organization_members(organization_id,user_id) on delete cascade
);
create index supplier_accounts_user_idx on public.supplier_accounts(user_id,organization_id);
alter table public.supplier_accounts enable row level security;
create policy supplier_accounts_read on public.supplier_accounts for select to authenticated using (
 user_id=(select auth.uid()) or public.has_org_role(organization_id,array['owner','admin','manager']::public.organization_role[])
);
-- Suppliers may only see purchase orders belonging to their explicitly linked supplier record.
create or replace function public.supplier_portal_orders(p_org uuid)
returns table(id uuid,reference text,status text,total numeric,created_at timestamptz,supplier_name text)
language sql stable security definer set search_path='' as $$
 select po.id,po.reference,po.status,po.total,po.created_at,s.name
 from public.purchase_orders po
 join public.suppliers s on s.id=po.supplier_id and s.organization_id=po.organization_id
 where po.organization_id=p_org and exists (
   select 1 from public.supplier_accounts sa
   join public.organization_members om on om.organization_id=sa.organization_id and om.user_id=sa.user_id
   where sa.organization_id=po.organization_id and sa.supplier_id=po.supplier_id
   and sa.user_id=(select auth.uid()) and om.role='supplier'
 )
 order by po.created_at desc limit 250
$$;
create or replace function public.supplier_portal_order_items(p_org uuid,p_order uuid)
returns table(product_name text,quantity integer,unit_cost numeric)
language plpgsql stable security definer set search_path='' as $$
begin
 if not exists (
  select 1 from public.purchase_orders po
  join public.supplier_accounts sa on sa.organization_id=po.organization_id and sa.supplier_id=po.supplier_id
  join public.organization_members om on om.organization_id=sa.organization_id and om.user_id=sa.user_id
  where po.organization_id=p_org and po.id=p_order and sa.user_id=auth.uid() and om.role='supplier'
 ) then raise exception 'Order not accessible'; end if;
 return query select p.name,pi.quantity,pi.unit_cost from public.purchase_items pi
 join public.products p on p.organization_id=pi.organization_id and p.id=pi.product_id
 where pi.organization_id=p_org and pi.order_id=p_order;
end $$;
create or replace function public.link_supplier_account(p_org uuid,p_supplier uuid,p_user uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.has_org_role(p_org,array['owner','admin']::public.organization_role[]) then raise exception 'Permission denied'; end if;
 if not exists(select 1 from public.organization_members where organization_id=p_org and user_id=p_user and role='supplier') then raise exception 'User must be a supplier-role company member'; end if;
 if not exists(select 1 from public.suppliers where organization_id=p_org and id=p_supplier) then raise exception 'Supplier not found'; end if;
 insert into public.supplier_accounts(organization_id,supplier_id,user_id) values(p_org,p_supplier,p_user)
 on conflict do nothing;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id)
 values(p_org,auth.uid(),'supplier.account.link','supplier',p_supplier::text);
end $$;
create or replace function public.unlink_supplier_account(p_org uuid,p_supplier uuid,p_user uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.has_org_role(p_org,array['owner','admin']::public.organization_role[]) then raise exception 'Permission denied'; end if;
 delete from public.supplier_accounts where organization_id=p_org and supplier_id=p_supplier and user_id=p_user;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id)
 values(p_org,auth.uid(),'supplier.account.unlink','supplier',p_supplier::text);
end $$;
revoke all on function public.supplier_portal_orders(uuid) from public;
revoke all on function public.supplier_portal_order_items(uuid,uuid) from public;
revoke all on function public.link_supplier_account(uuid,uuid,uuid) from public;
revoke all on function public.unlink_supplier_account(uuid,uuid,uuid) from public;
grant execute on function public.supplier_portal_orders(uuid) to authenticated;
grant execute on function public.supplier_portal_order_items(uuid,uuid) to authenticated;
grant execute on function public.link_supplier_account(uuid,uuid,uuid) to authenticated;
grant execute on function public.unlink_supplier_account(uuid,uuid,uuid) to authenticated;
-- Prevent supplier-only memberships from reading company-wide financial/stock data.
-- Company operators retain access; supplier orders are exposed solely through scoped RPCs.
drop policy if exists supplier_select on public.suppliers;
create policy supplier_select on public.suppliers for select to authenticated using (
 public.has_org_role(organization_id,array['owner','admin','manager','cashier','viewer']::public.organization_role[])
);
drop policy if exists product_select on public.products;
create policy product_select on public.products for select to authenticated using (
 public.has_org_role(organization_id,array['owner','admin','manager','cashier','viewer']::public.organization_role[])
);
drop policy if exists sales_select on public.sales;
create policy sales_select on public.sales for select to authenticated using (
 public.has_org_role(organization_id,array['owner','admin','manager','cashier','viewer']::public.organization_role[])
);
drop policy if exists sale_items_select on public.sale_items;
create policy sale_items_select on public.sale_items for select to authenticated using (
 public.has_org_role(organization_id,array['owner','admin','manager','cashier','viewer']::public.organization_role[])
);
drop policy if exists movement_select on public.stock_movements;
create policy movement_select on public.stock_movements for select to authenticated using (
 public.has_org_role(organization_id,array['owner','admin','manager','cashier','viewer']::public.organization_role[])
);
do $$ declare t text;begin
 foreach t in array array['warehouses','customers','categories','purchase_orders','purchase_items','stock_transfers','warehouse_stock','sales_returns'] loop
  execute format('drop policy if exists tenant_read on public.%I',t);
  execute format('create policy tenant_read on public.%I for select to authenticated using(public.has_org_role(organization_id,array[''owner'',''admin'',''manager'',''cashier'',''viewer'']::public.organization_role[]))',t);
 end loop;
end $$;
