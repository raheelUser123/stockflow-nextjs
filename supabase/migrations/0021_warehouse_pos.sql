-- 0021: Optional warehouse-aware POS checkout. Existing checkout remains unchanged.
-- Run after 0019. Requires a warehouse allocation for each item sold.
create or replace function public.checkout_from_warehouse(
 p_org uuid, p_warehouse uuid, p_items jsonb, p_payment text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
 v_sale uuid; v_total numeric(14,2):=0; v_item record; v_product public.products%rowtype;
 v_qty integer; v_available integer; v_count integer:=0;
begin
 if auth.uid() is null or not public.has_org_permission(p_org,'sales.write') then
   raise exception 'Permission denied';
 end if;
 if p_payment not in ('cash','card','other') then raise exception 'Invalid payment method'; end if;
 if not exists(select 1 from public.warehouses where organization_id=p_org and id=p_warehouse) then
   raise exception 'Invalid warehouse';
 end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 100 then
   raise exception 'Invalid cart';
 end if;
 -- Serialize all writers participating in warehouse allocations/transfers per product.
 -- Validate input before acquiring product locks.
 for v_item in
   select (j->>'product_id')::uuid as product_id,
          sum((j->>'quantity')::integer)::bigint as qty
   from jsonb_array_elements(p_items) j
   group by (j->>'product_id')::uuid order by (j->>'product_id')::uuid
 loop
   if v_item.qty is null or v_item.qty<1 or v_item.qty>1000000 then raise exception 'Invalid quantity'; end if;
   perform pg_advisory_xact_lock(hashtextextended(p_org::text||v_item.product_id::text,0));
 end loop;
 -- Lock all product rows in stable order. No stock changes until every item is validated.
 for v_item in
   select (j->>'product_id')::uuid as product_id,
          sum((j->>'quantity')::integer)::integer as qty
   from jsonb_array_elements(p_items) j
   group by (j->>'product_id')::uuid order by (j->>'product_id')::uuid
 loop
   select * into v_product from public.products
     where organization_id=p_org and id=v_item.product_id for update;
   if not found or not v_product.active then raise exception 'Product missing or inactive'; end if;
   select quantity into v_available from public.warehouse_stock
     where organization_id=p_org and warehouse_id=p_warehouse and product_id=v_item.product_id for update;
   if v_product.stock<v_item.qty or coalesce(v_available,0)<v_item.qty then
     raise exception 'Insufficient stock in selected warehouse for %',v_product.name;
   end if;
   v_total:=v_total+v_item.qty*v_product.price;
   v_count:=v_count+1;
 end loop;
 if v_count=0 then raise exception 'Empty cart'; end if;
 insert into public.sales(organization_id,total,payment_method,created_by)
 values(p_org,v_total,p_payment,auth.uid()) returning id into v_sale;
 for v_item in
   select (j->>'product_id')::uuid as product_id,
          sum((j->>'quantity')::integer)::integer as qty
   from jsonb_array_elements(p_items) j
   group by (j->>'product_id')::uuid order by (j->>'product_id')::uuid
 loop
   select price into v_product.price from public.products where organization_id=p_org and id=v_item.product_id;
   insert into public.sale_items(organization_id,sale_id,product_id,quantity,unit_price)
   values(p_org,v_sale,v_item.product_id,v_item.qty,v_product.price);
   update public.products set stock=stock-v_item.qty
     where organization_id=p_org and id=v_item.product_id;
   update public.warehouse_stock set quantity=quantity-v_item.qty
     where organization_id=p_org and warehouse_id=p_warehouse and product_id=v_item.product_id;
   insert into public.stock_movements(organization_id,product_id,delta,reason,reference_id,actor_id)
   values(p_org,v_item.product_id,-v_item.qty,'warehouse_sale',v_sale,auth.uid());
 end loop;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id,metadata)
 values(p_org,auth.uid(),'checkout_warehouse','sale',v_sale::text,
        jsonb_build_object('warehouse_id',p_warehouse,'total',v_total,'payment',p_payment));
 return v_sale;
end $$;
revoke all on function public.checkout_from_warehouse(uuid,uuid,jsonb,text) from public;
grant execute on function public.checkout_from_warehouse(uuid,uuid,jsonb,text) to authenticated;
