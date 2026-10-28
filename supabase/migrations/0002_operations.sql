-- Run after 0001_foundation.sql. All writes are permission-checked RPCs.
create table public.suppliers(id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),name text not null, email text,phone text,created_at timestamptz default now(),unique(organization_id,id));
create table public.products(id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),name text not null,sku text not null,price numeric(14,2) not null default 0 check(price>=0),cost numeric(14,2) not null default 0 check(cost>=0),stock integer not null default 0 check(stock>=0),min_stock integer not null default 5 check(min_stock>=0),active boolean not null default true,created_at timestamptz default now(),unique(organization_id,sku),unique(organization_id,id));
create table public.sales(id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),receipt_number bigint generated always as identity,total numeric(14,2) not null check(total>=0),payment_method text not null check(payment_method in ('cash','card','other')),created_by uuid not null references auth.users(id),created_at timestamptz default now(),unique(organization_id,id));
create table public.sale_items(id uuid primary key default gen_random_uuid(),organization_id uuid not null, sale_id uuid not null,product_id uuid not null,quantity integer not null check(quantity>0),unit_price numeric(14,2) not null check(unit_price>=0),foreign key(organization_id,sale_id) references public.sales(organization_id,id),foreign key(organization_id,product_id) references public.products(organization_id,id));
create table public.stock_movements(id bigint generated always as identity primary key,organization_id uuid not null,product_id uuid not null,delta integer not null,reason text not null,reference_id uuid,actor_id uuid references auth.users(id),created_at timestamptz default now(),foreign key(organization_id,product_id) references public.products(organization_id,id));
create index on public.products(organization_id);create index on public.suppliers(organization_id);create index on public.sales(organization_id,created_at desc);create index on public.stock_movements(organization_id,created_at desc);
alter table public.suppliers enable row level security;alter table public.products enable row level security;alter table public.sales enable row level security;alter table public.sale_items enable row level security;alter table public.stock_movements enable row level security;
create policy supplier_select on public.suppliers for select to authenticated using(public.is_org_member(organization_id));
create policy product_select on public.products for select to authenticated using(public.is_org_member(organization_id));
create policy sales_select on public.sales for select to authenticated using(public.is_org_member(organization_id));
create policy sale_items_select on public.sale_items for select to authenticated using(public.is_org_member(organization_id));
create policy movement_select on public.stock_movements for select to authenticated using(public.is_org_member(organization_id));
create function public.manage_record(p_org uuid,p_kind text,p_action text,p_id uuid,p_payload jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_old integer;v_new integer;
begin
 if not public.has_org_role(p_org,array['owner','admin','manager']::public.organization_role[]) then raise exception 'Permission denied';end if;
 if p_kind='product' then
  if p_action='create' then
   v_id:=gen_random_uuid();v_new:=coalesce((p_payload->>'stock')::integer,0);
   insert into public.products(id,organization_id,name,sku,price,cost,stock,min_stock) values(v_id,p_org,p_payload->>'name',p_payload->>'sku',coalesce((p_payload->>'price')::numeric,0),coalesce((p_payload->>'cost')::numeric,0),v_new,coalesce((p_payload->>'min_stock')::integer,5));
   if v_new<>0 then insert into public.stock_movements(organization_id,product_id,delta,reason,actor_id) values(p_org,v_id,v_new,'opening',auth.uid());end if;
  elsif p_action='update' then
   select stock into v_old from public.products where id=p_id and organization_id=p_org for update;
   if not found then raise exception 'Product not found';end if;
   v_new:=coalesce((p_payload->>'stock')::integer,v_old);
   update public.products set name=coalesce(p_payload->>'name',name),sku=coalesce(p_payload->>'sku',sku),price=coalesce((p_payload->>'price')::numeric,price),cost=coalesce((p_payload->>'cost')::numeric,cost),stock=v_new,min_stock=coalesce((p_payload->>'min_stock')::integer,min_stock) where id=p_id and organization_id=p_org;
   if v_new<>v_old then insert into public.stock_movements(organization_id,product_id,delta,reason,actor_id) values(p_org,p_id,v_new-v_old,'adjustment',auth.uid());end if;
   v_id:=p_id;
  elsif p_action='delete' then
   update public.products set active=false where id=p_id and organization_id=p_org;v_id:=p_id;
  else raise exception 'Invalid action';end if;
 elsif p_kind='supplier' then
  if p_action='create' then insert into public.suppliers(organization_id,name,email,phone) values(p_org,p_payload->>'name',p_payload->>'email',p_payload->>'phone') returning id into v_id;
  elsif p_action='update' then update public.suppliers set name=coalesce(p_payload->>'name',name),email=coalesce(p_payload->>'email',email),phone=coalesce(p_payload->>'phone',phone) where id=p_id and organization_id=p_org returning id into v_id;
  elsif p_action='delete' then delete from public.suppliers where id=p_id and organization_id=p_org returning id into v_id;
  else raise exception 'Invalid action';end if;
 else raise exception 'Invalid entity type';end if;
 if v_id is null then raise exception 'Record not found';end if;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),p_action,p_kind,v_id::text,jsonb_build_object('payload',case when p_action='delete' then '{}'::jsonb else p_payload end));
 return v_id;
end $$;
create function public.checkout(p_org uuid,p_items jsonb,p_payment text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_sale uuid;v_total numeric(14,2):=0;v_item jsonb;v_product public.products%rowtype;v_qty integer;v_count integer:=0;
begin
 if not public.has_org_role(p_org,array['owner','admin','manager','cashier']::public.organization_role[]) then raise exception 'Permission denied';end if;
 if p_payment not in ('cash','card','other') then raise exception 'Invalid payment';end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 or jsonb_array_length(p_items)>100 then raise exception 'Invalid cart';end if;
 -- Aggregate duplicate IDs and lock products in deterministic order to prevent races/deadlocks.
 for v_product in select p.* from public.products p join (select distinct (x->>'product_id')::uuid as id from jsonb_array_elements(p_items) x) z on z.id=p.id where p.organization_id=p_org order by p.id for update of p loop
  select sum((x->>'quantity')::integer)::integer into v_qty from jsonb_array_elements(p_items) x where (x->>'product_id')::uuid=v_product.id;
  if v_qty is null or v_qty<=0 or v_product.stock<v_qty or not v_product.active then raise exception 'Insufficient stock or invalid quantity for %',v_product.name;end if;
  v_total:=v_total+v_qty*v_product.price;v_count:=v_count+1;
 end loop;
 if v_count<>(select count(distinct x->>'product_id') from jsonb_array_elements(p_items) x) then raise exception 'Product missing';end if;
 insert into public.sales(organization_id,total,payment_method,created_by) values(p_org,v_total,p_payment,auth.uid()) returning id into v_sale;
 for v_item in select jsonb_build_object('product_id',p.id,'quantity',sum((x->>'quantity')::integer),'price',p.price) from jsonb_array_elements(p_items) x join public.products p on p.id=(x->>'product_id')::uuid and p.organization_id=p_org group by p.id,p.price loop
  v_qty:=(v_item->>'quantity')::integer;
  insert into public.sale_items(organization_id,sale_id,product_id,quantity,unit_price) values(p_org,v_sale,(v_item->>'product_id')::uuid,v_qty,(v_item->>'price')::numeric);
  update public.products set stock=stock-v_qty where id=(v_item->>'product_id')::uuid and organization_id=p_org;
  insert into public.stock_movements(organization_id,product_id,delta,reason,reference_id,actor_id) values(p_org,(v_item->>'product_id')::uuid,-v_qty,'sale',v_sale,auth.uid());
 end loop;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'checkout','sale',v_sale::text,jsonb_build_object('total',v_total,'payment',p_payment));
 return v_sale;
end $$;
revoke all on function public.manage_record(uuid,text,text,uuid,jsonb) from public;grant execute on function public.manage_record(uuid,text,text,uuid,jsonb) to authenticated;
revoke all on function public.checkout(uuid,jsonb,text) from public;grant execute on function public.checkout(uuid,jsonb,text) to authenticated;
