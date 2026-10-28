-- Apply after 0006. Warehouse transfer ledger and atomic movement.
create index if not exists warehouse_stock_lookup on public.warehouse_stock(organization_id,product_id);
create or replace function public.transfer_warehouse_stock(p_org uuid,p_product uuid,p_from uuid,p_to uuid,p_quantity integer)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_current integer;
begin
 if not public.has_org_role(p_org,array['owner','admin','manager']::public.organization_role[]) then raise exception 'Permission denied'; end if;
 if p_quantity is null or p_quantity<1 or p_quantity>1000000 or p_from=p_to then raise exception 'Invalid transfer'; end if;
 if not exists(select 1 from public.products where organization_id=p_org and id=p_product and active=true) then raise exception 'Invalid product'; end if;
 if (select count(*) from public.warehouses where organization_id=p_org and id in(p_from,p_to))<>2 then raise exception 'Invalid warehouses'; end if;
 -- Serialize transfer writers per tenant/product to avoid races and deadlocks.
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||p_product::text,0));
 select quantity into v_current from public.warehouse_stock where organization_id=p_org and warehouse_id=p_from and product_id=p_product for update;
 if coalesce(v_current,0)<p_quantity then raise exception 'Insufficient warehouse stock. Allocate opening warehouse stock before transferring.'; end if;
 update public.warehouse_stock set quantity=quantity-p_quantity where organization_id=p_org and warehouse_id=p_from and product_id=p_product;
 insert into public.warehouse_stock(organization_id,warehouse_id,product_id,quantity) values(p_org,p_to,p_product,p_quantity)
 on conflict(organization_id,warehouse_id,product_id) do update set quantity=public.warehouse_stock.quantity+excluded.quantity;
 insert into public.stock_transfers(organization_id,from_warehouse,to_warehouse,product_id,quantity) values(p_org,p_from,p_to,p_product,p_quantity) returning id into v_id;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'transfer','warehouse_stock',v_id::text,jsonb_build_object('product',p_product,'from',p_from,'to',p_to,'quantity',p_quantity));
 return v_id;
end $$;
revoke all on function public.transfer_warehouse_stock(uuid,uuid,uuid,uuid,integer) from public;
grant execute on function public.transfer_warehouse_stock(uuid,uuid,uuid,uuid,integer) to authenticated;
-- Safe allocation of existing unallocated stock to a warehouse. Does not alter global product stock.
create or replace function public.allocate_warehouse_stock(p_org uuid,p_product uuid,p_warehouse uuid,p_quantity integer)
returns void language plpgsql security definer set search_path='' as $$
declare v_total integer; v_allocated bigint;
begin
 if not public.has_org_role(p_org,array['owner','admin']::public.organization_role[]) then raise exception 'Permission denied'; end if;
 if p_quantity is null or p_quantity<1 then raise exception 'Quantity must be positive'; end if;
 if not exists(select 1 from public.warehouses where id=p_warehouse and organization_id=p_org) then raise exception 'Warehouse not found'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||p_product::text,0));
 select stock into v_total from public.products where id=p_product and organization_id=p_org for update;
 if v_total is null then raise exception 'Product not found'; end if;
 select coalesce(sum(quantity),0) into v_allocated from public.warehouse_stock where organization_id=p_org and product_id=p_product;
 if v_allocated+p_quantity>v_total then raise exception 'Allocation exceeds unallocated stock'; end if;
 insert into public.warehouse_stock(organization_id,warehouse_id,product_id,quantity) values(p_org,p_warehouse,p_product,p_quantity)
 on conflict(organization_id,warehouse_id,product_id) do update set quantity=public.warehouse_stock.quantity+excluded.quantity;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'allocate','warehouse_stock',p_product::text,jsonb_build_object('warehouse',p_warehouse,'quantity',p_quantity));
end $$;
revoke all on function public.allocate_warehouse_stock(uuid,uuid,uuid,integer) from public;
grant execute on function public.allocate_warehouse_stock(uuid,uuid,uuid,integer) to authenticated;
