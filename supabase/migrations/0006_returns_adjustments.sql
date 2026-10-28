-- Run after 0005_product_images.sql. Stock adjustments and sales returns.
create table public.sales_returns (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id),
 sale_id uuid not null,
 reason text not null default '',
 total_refund numeric(14,2) not null default 0 check(total_refund>=0),
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 unique(organization_id,id),
 foreign key(organization_id,sale_id) references public.sales(organization_id,id)
);
create table public.sales_return_items (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null,
 return_id uuid not null,
 sale_item_id uuid not null references public.sale_items(id),
 quantity integer not null check(quantity>0),
 unit_price numeric(14,2) not null check(unit_price>=0),
 foreign key(organization_id,return_id) references public.sales_returns(organization_id,id)
);
create index on public.sales_returns(organization_id,created_at desc);
create index on public.sales_return_items(organization_id,sale_item_id);
alter table public.sales_returns enable row level security;
alter table public.sales_return_items enable row level security;
create policy returns_read on public.sales_returns for select to authenticated using(public.is_org_member(organization_id));
create policy return_items_read on public.sales_return_items for select to authenticated using(public.is_org_member(organization_id));

create function public.adjust_stock(p_org uuid,p_product uuid,p_delta integer,p_reason text)
returns bigint language plpgsql security definer set search_path='' as $$
declare v_stock integer; v_id bigint;
begin
 if not (public.has_org_role(p_org,array['owner','admin','manager']::public.organization_role[]) or public.has_org_permission(p_org,'inventory.write')) then raise exception 'Permission denied'; end if;
 if p_delta=0 or abs(p_delta)>1000000 or length(trim(p_reason))<3 then raise exception 'Invalid adjustment'; end if;
 select stock into v_stock from public.products where id=p_product and organization_id=p_org and active for update;
 if not found then raise exception 'Product not found'; end if;
 if v_stock+p_delta<0 then raise exception 'Insufficient stock'; end if;
 update public.products set stock=stock+p_delta where id=p_product and organization_id=p_org;
 insert into public.stock_movements(organization_id,product_id,delta,reason,actor_id)
 values(p_org,p_product,p_delta,'adjustment: '||left(trim(p_reason),200),auth.uid()) returning id into v_id;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id,metadata)
 values(p_org,auth.uid(),'stock.adjust','product',p_product::text,jsonb_build_object('delta',p_delta,'reason',left(trim(p_reason),200)));
 return v_id;
end $$;

create function public.return_sale(p_org uuid,p_sale uuid,p_items jsonb,p_reason text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_line record; v_qty integer; v_prior integer; v_refund numeric(14,2):=0; v_count integer:=0;
begin
 if not (public.has_org_role(p_org,array['owner','admin','manager']::public.organization_role[]) or public.has_org_permission(p_org,'sales.write')) then raise exception 'Permission denied'; end if;
 if not exists(select 1 from public.sales where organization_id=p_org and id=p_sale) then raise exception 'Sale not found'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 or jsonb_array_length(p_items)>100 then raise exception 'Invalid return items'; end if;
 if exists(select 1 from jsonb_array_elements(p_items) j where jsonb_typeof(j->'quantity')<>'number' or (j->>'quantity')::numeric<=0 or (j->>'quantity')::numeric<>trunc((j->>'quantity')::numeric)) then raise exception 'Invalid return quantity'; end if;
 -- Lock sale line rows in stable order, preventing concurrent over-returns.
 for v_line in select si.* from public.sale_items si where si.organization_id=p_org and si.sale_id=p_sale order by si.id for update loop
   select coalesce(sum((j->>'quantity')::integer),0) into v_qty from jsonb_array_elements(p_items) j where (j->>'sale_item_id')::uuid=v_line.id;
   if v_qty>0 then
     select coalesce(sum(quantity),0) into v_prior from public.sales_return_items where organization_id=p_org and sale_item_id=v_line.id;
     if v_qty+v_prior>v_line.quantity then raise exception 'Return exceeds sold quantity'; end if;
     v_refund:=v_refund+v_qty*v_line.unit_price;
     v_count:=v_count+1;
   end if;
 end loop;
 if v_count=0 or v_count<>(select count(distinct j->>'sale_item_id') from jsonb_array_elements(p_items) j) then raise exception 'Invalid sale item'; end if;
 insert into public.sales_returns(organization_id,sale_id,reason,total_refund,created_by)
 values(p_org,p_sale,left(trim(coalesce(p_reason,'')),500),v_refund,auth.uid()) returning id into v_id;
 for v_line in select si.* from public.sale_items si where si.organization_id=p_org and si.sale_id=p_sale order by si.id loop
   select coalesce(sum((j->>'quantity')::integer),0) into v_qty from jsonb_array_elements(p_items) j where (j->>'sale_item_id')::uuid=v_line.id;
   if v_qty>0 then
     insert into public.sales_return_items(organization_id,return_id,sale_item_id,quantity,unit_price)
     values(p_org,v_id,v_line.id,v_qty,v_line.unit_price);
     update public.products set stock=stock+v_qty where organization_id=p_org and id=v_line.product_id;
     insert into public.stock_movements(organization_id,product_id,delta,reason,reference_id,actor_id)
     values(p_org,v_line.product_id,v_qty,'sales_return',v_id,auth.uid());
   end if;
 end loop;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id,metadata)
 values(p_org,auth.uid(),'sale.return','sale',p_sale::text,jsonb_build_object('return_id',v_id,'refund',v_refund));
 return v_id;
end $$;
revoke all on function public.adjust_stock(uuid,uuid,integer,text) from public;
revoke all on function public.return_sale(uuid,uuid,jsonb,text) from public;
grant execute on function public.adjust_stock(uuid,uuid,integer,text) to authenticated;
grant execute on function public.return_sale(uuid,uuid,jsonb,text) to authenticated;
