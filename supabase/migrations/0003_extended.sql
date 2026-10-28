-- StockFlow Pro extension. Run once after 0001 and 0002.
create table public.warehouses(id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),name text not null,location text default '',created_at timestamptz default now(),unique(organization_id,id));
create table public.customers(id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),name text not null,email text,phone text,address text default '',created_at timestamptz default now(),unique(organization_id,id));
create table public.categories(id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),name text not null,description text default '',created_at timestamptz default now(),unique(organization_id,id));
create table public.purchase_orders(id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),supplier_id uuid not null,reference text not null,status text not null default 'draft' check(status in ('draft','received','cancelled')),total numeric(14,2) not null default 0,created_at timestamptz default now(),unique(organization_id,id),foreign key(organization_id,supplier_id) references public.suppliers(organization_id,id));
create table public.purchase_items(id uuid primary key default gen_random_uuid(),organization_id uuid not null,order_id uuid not null,product_id uuid not null,quantity integer not null check(quantity>0),unit_cost numeric(14,2) not null check(unit_cost>=0),foreign key(organization_id,order_id) references public.purchase_orders(organization_id,id),foreign key(organization_id,product_id) references public.products(organization_id,id));
create table public.stock_transfers(id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),from_warehouse uuid not null,to_warehouse uuid not null,product_id uuid not null,quantity integer not null check(quantity>0),created_at timestamptz default now(),foreign key(organization_id,from_warehouse) references public.warehouses(organization_id,id),foreign key(organization_id,to_warehouse) references public.warehouses(organization_id,id),foreign key(organization_id,product_id) references public.products(organization_id,id),check(from_warehouse<>to_warehouse));
create table public.warehouse_stock(organization_id uuid not null,warehouse_id uuid not null,product_id uuid not null,quantity integer not null default 0 check(quantity>=0),primary key(organization_id,warehouse_id,product_id),foreign key(organization_id,warehouse_id) references public.warehouses(organization_id,id),foreign key(organization_id,product_id) references public.products(organization_id,id));
create table public.sales_returns(id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),sale_id uuid not null,reason text not null default '',created_at timestamptz default now(),foreign key(organization_id,sale_id) references public.sales(organization_id,id),unique(organization_id,sale_id));
create index on public.purchase_orders(organization_id,created_at desc);create index on public.customers(organization_id);create index on public.warehouses(organization_id);create index on public.categories(organization_id);
do $$ declare t text;begin foreach t in array array['warehouses','customers','categories','purchase_orders','purchase_items','stock_transfers','warehouse_stock','sales_returns'] loop execute format('alter table public.%I enable row level security',t);execute format('create policy tenant_read on public.%I for select to authenticated using(public.is_org_member(organization_id))',t);end loop;end $$;
-- All mutations use authenticated SECURITY DEFINER RPCs, no direct client writes.
create function public.manage_extended(p_org uuid,p_kind text,p_action text,p_id uuid,p_payload jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_table text;v_fields text[];v_field text;v_pairs text:='';v_cols text:='organization_id';v_vals text:='$1';v_idx integer:=2;v_sql text;v_data text[]:=array[]::text[];
begin
 if not public.has_org_role(p_org,array['owner','admin','manager']::public.organization_role[]) then raise exception 'Permission denied';end if;
 case p_kind
 when 'warehouses' then v_table:='warehouses';v_fields:=array['name','location'];
 when 'customers' then v_table:='customers';v_fields:=array['name','email','phone','address'];
 when 'categories' then v_table:='categories';v_fields:=array['name','description'];
 else raise exception 'Unsupported entity';end case;
 if p_action='create' then
  if length(trim(coalesce(p_payload->>'name','')))<1 then raise exception 'Name required';end if;
  v_id:=gen_random_uuid();
  insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id) values(p_org,auth.uid(),'create',p_kind,v_id::text);
  if p_kind='warehouses' then insert into public.warehouses(id,organization_id,name,location) values(v_id,p_org,p_payload->>'name',coalesce(p_payload->>'location',''));
  elsif p_kind='customers' then insert into public.customers(id,organization_id,name,email,phone,address) values(v_id,p_org,p_payload->>'name',p_payload->>'email',p_payload->>'phone',coalesce(p_payload->>'address',''));
  else insert into public.categories(id,organization_id,name,description) values(v_id,p_org,p_payload->>'name',coalesce(p_payload->>'description',''));end if;
 elsif p_action='update' then
  if p_kind='warehouses' then update public.warehouses set name=coalesce(p_payload->>'name',name),location=coalesce(p_payload->>'location',location) where id=p_id and organization_id=p_org returning id into v_id;
  elsif p_kind='customers' then update public.customers set name=coalesce(p_payload->>'name',name),email=coalesce(p_payload->>'email',email),phone=coalesce(p_payload->>'phone',phone),address=coalesce(p_payload->>'address',address) where id=p_id and organization_id=p_org returning id into v_id;
  else update public.categories set name=coalesce(p_payload->>'name',name),description=coalesce(p_payload->>'description',description) where id=p_id and organization_id=p_org returning id into v_id;end if;
 elsif p_action='delete' then
  if p_kind='warehouses' then delete from public.warehouses where id=p_id and organization_id=p_org returning id into v_id;
  elsif p_kind='customers' then delete from public.customers where id=p_id and organization_id=p_org returning id into v_id;
  else delete from public.categories where id=p_id and organization_id=p_org returning id into v_id;end if;
 else raise exception 'Invalid action';end if;
 if v_id is null then raise exception 'Record not found';end if;
 if p_action<>'create' then insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),p_action,p_kind,v_id::text,case when p_action='delete' then '{}'::jsonb else p_payload end);end if;
 return v_id;
end $$;
create function public.create_purchase(p_org uuid,p_supplier uuid,p_reference text,p_items jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_item jsonb;v_cost numeric;v_qty integer;v_total numeric:=0;v_product uuid;
begin
 if not public.has_org_role(p_org,array['owner','admin','manager']::public.organization_role[]) then raise exception 'Permission denied';end if;
 if not exists(select 1 from public.suppliers where id=p_supplier and organization_id=p_org) then raise exception 'Supplier not found';end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 100 then raise exception 'Invalid items';end if;
 insert into public.purchase_orders(organization_id,supplier_id,reference) values(p_org,p_supplier,coalesce(nullif(trim(p_reference),''),'PO-'||substr(gen_random_uuid()::text,1,8))) returning id into v_id;
 for v_item in select value from jsonb_array_elements(p_items) loop
  v_product:=(v_item->>'product_id')::uuid;v_qty:=(v_item->>'quantity')::integer;v_cost:=(v_item->>'unit_cost')::numeric;
  if v_qty<=0 or v_cost<0 or not exists(select 1 from public.products where id=v_product and organization_id=p_org) then raise exception 'Invalid purchase item';end if;
  insert into public.purchase_items(organization_id,order_id,product_id,quantity,unit_cost) values(p_org,v_id,v_product,v_qty,v_cost);v_total:=v_total+v_qty*v_cost;
 end loop;
 update public.purchase_orders set total=v_total where id=v_id;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id) values(p_org,auth.uid(),'created','purchase_order',v_id::text);return v_id;
end $$;
create function public.receive_purchase(p_org uuid,p_order uuid) returns void language plpgsql security definer set search_path='' as $$
declare v_item record;
begin
 if not public.has_org_role(p_org,array['owner','admin','manager']::public.organization_role[]) then raise exception 'Permission denied';end if;
 perform 1 from public.purchase_orders where id=p_order and organization_id=p_org and status='draft' for update;
 if not found then raise exception 'Purchase order not in draft status';end if;
 for v_item in select product_id,quantity from public.purchase_items where order_id=p_order and organization_id=p_org order by product_id loop
  update public.products set stock=stock+v_item.quantity where id=v_item.product_id and organization_id=p_org;
  insert into public.stock_movements(organization_id,product_id,delta,reason,reference_id,actor_id) values(p_org,v_item.product_id,v_item.quantity,'purchase',p_order,auth.uid());
 end loop;
 update public.purchase_orders set status='received' where id=p_order and organization_id=p_org;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id) values(p_org,auth.uid(),'received','purchase_order',p_order::text);
end $$;
create function public.manage_team(p_org uuid,p_user uuid,p_role public.organization_role,p_action text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.has_org_role(p_org,array['owner','admin']::public.organization_role[]) then raise exception 'Permission denied';end if;
 if p_role='owner' then raise exception 'Owner assignment prohibited';end if;
 if p_action='update' then update public.organization_members set role=p_role where organization_id=p_org and user_id=p_user and role<>'owner';
 elsif p_action='remove' then delete from public.organization_members where organization_id=p_org and user_id=p_user and role<>'owner';
 else raise exception 'Invalid action';end if;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id) values(p_org,auth.uid(),p_action,'team',p_user::text);
end $$;
create function public.update_company_settings(p_org uuid,p_theme text,p_timezone text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.has_org_role(p_org,array['owner','admin']::public.organization_role[]) then raise exception 'Permission denied';end if;
 if p_theme not in ('light','dark','system') or length(p_timezone)>80 or length(p_timezone)<1 then raise exception 'Invalid settings';end if;
 update public.organization_settings set theme=p_theme,timezone=p_timezone,updated_at=now() where organization_id=p_org;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,metadata) values(p_org,auth.uid(),'update','settings',jsonb_build_object('theme',p_theme,'timezone',p_timezone));
end $$;
-- Harden function execution; default PUBLIC execution is removed.
do $$declare r record;begin for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('manage_extended','create_purchase','receive_purchase','manage_team','update_company_settings') loop execute 'revoke all on function '||r.sig||' from public';execute 'grant execute on function '||r.sig||' to authenticated';end loop;end $$;
