-- Supplier fulfillment events. Does not receive inventory or change purchase order status.
create table public.supplier_fulfillments (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null,
 order_id uuid not null,
 supplier_id uuid not null,
 submitted_by uuid not null references auth.users(id),
 status text not null check(status in ('acknowledged','dispatched')),
 tracking_reference text,
 note text,
 created_at timestamptz not null default now(),
 foreign key(organization_id,order_id) references public.purchase_orders(organization_id,id),
 foreign key(organization_id,supplier_id) references public.suppliers(organization_id,id)
);
create index supplier_fulfillments_order_idx on public.supplier_fulfillments(organization_id,order_id,created_at desc);
alter table public.supplier_fulfillments enable row level security;
-- All reads use a scoped RPC; no direct table grants to supplier accounts.
create or replace function public.supplier_order_fulfillments(p_org uuid)
returns table(id uuid,order_id uuid,status text,tracking_reference text,note text,created_at timestamptz)
language sql stable security definer set search_path='' as $$
 select f.id,f.order_id,f.status,f.tracking_reference,f.note,f.created_at
 from public.supplier_fulfillments f
 where f.organization_id=p_org and (
  public.has_org_role(p_org,array['owner','admin','manager']::public.organization_role[])
  or exists (select 1 from public.supplier_accounts sa join public.organization_members m
    on m.organization_id=sa.organization_id and m.user_id=sa.user_id
    where sa.organization_id=f.organization_id and sa.supplier_id=f.supplier_id
    and sa.user_id=(select auth.uid()) and m.role='supplier')
 ) order by f.created_at desc limit 500
$$;
create or replace function public.submit_supplier_fulfillment(
 p_org uuid,p_order uuid,p_status text,p_tracking text default null,p_note text default null
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_supplier uuid;v_id uuid;v_last text;
begin
 if p_status not in ('acknowledged','dispatched') then raise exception 'Invalid fulfillment status'; end if;
 if length(coalesce(p_tracking,''))>120 or length(coalesce(p_note,''))>1000 then raise exception 'Input too long'; end if;
 select po.supplier_id into v_supplier from public.purchase_orders po
 where po.id=p_order and po.organization_id=p_org and po.status='draft' for update;
 if v_supplier is null then raise exception 'Open purchase order not found'; end if;
 if not exists(select 1 from public.supplier_accounts sa join public.organization_members m
 on m.organization_id=sa.organization_id and m.user_id=sa.user_id
 where sa.organization_id=p_org and sa.supplier_id=v_supplier and sa.user_id=auth.uid() and m.role='supplier')
 then raise exception 'Supplier access denied'; end if;
 select f.status into v_last from public.supplier_fulfillments f where f.organization_id=p_org and f.order_id=p_order order by f.created_at desc,f.id desc limit 1;
 if v_last='dispatched' then raise exception 'Order already dispatched'; end if;
 if p_status='acknowledged' and v_last is not null then raise exception 'Order already acknowledged'; end if;
 if p_status='dispatched' and v_last is distinct from 'acknowledged' then raise exception 'Acknowledge order first'; end if;
 insert into public.supplier_fulfillments(organization_id,order_id,supplier_id,submitted_by,status,tracking_reference,note)
 values(p_org,p_order,v_supplier,auth.uid(),p_status,nullif(trim(coalesce(p_tracking,'')),''),nullif(trim(coalesce(p_note,'')),'')) returning id into v_id;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id,metadata)
 values(p_org,auth.uid(),'supplier.order.'||p_status,'purchase_order',p_order::text,jsonb_build_object('fulfillment_id',v_id));
 return v_id;
end $$;
revoke all on function public.supplier_order_fulfillments(uuid) from public;
revoke all on function public.submit_supplier_fulfillment(uuid,uuid,text,text,text) from public;
grant execute on function public.supplier_order_fulfillments(uuid) to authenticated;
grant execute on function public.submit_supplier_fulfillment(uuid,uuid,text,text,text) to authenticated;
