-- Run once after 0010_supplier_fulfillment.sql.
create table public.supplier_invoices (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null,
 order_id uuid not null,
 supplier_id uuid not null,
 uploaded_by uuid not null references auth.users(id),
 invoice_number text not null check (length(invoice_number) between 1 and 100),
 file_path text not null unique,
 file_name text not null,
 created_at timestamptz not null default now(),
 foreign key (organization_id,order_id) references public.purchase_orders(organization_id,id),
 foreign key (organization_id,supplier_id) references public.suppliers(organization_id,id)
);
create index supplier_invoices_order_idx on public.supplier_invoices(organization_id,order_id,created_at desc);
alter table public.supplier_invoices enable row level security;

create or replace function public.can_access_supplier_order(p_org uuid,p_order uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists (
 select 1 from public.purchase_orders po
 where po.organization_id=p_org and po.id=p_order
 and (public.has_org_role(p_org,array['owner','admin','manager']::public.organization_role[])
 or exists (select 1 from public.supplier_accounts sa
 join public.organization_members m on m.organization_id=sa.organization_id and m.user_id=sa.user_id
 where sa.organization_id=po.organization_id and sa.supplier_id=po.supplier_id
 and sa.user_id=(select auth.uid()) and m.role='supplier')))
$$;
revoke all on function public.can_access_supplier_order(uuid,uuid) from public;
grant execute on function public.can_access_supplier_order(uuid,uuid) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('supplier-invoices','supplier-invoices',false,10485760,array['application/pdf','image/jpeg','image/png'])
on conflict(id) do update set public=false,file_size_limit=10485760,allowed_mime_types=array['application/pdf','image/jpeg','image/png'];
-- Path format: org_uuid/order_uuid/user_uuid/random_uuid.ext
create policy supplier_invoice_storage_insert on storage.objects for insert to authenticated
with check (bucket_id='supplier-invoices'
 and (storage.foldername(name))[3]=(select auth.uid())::text
 and public.can_access_supplier_order(((storage.foldername(name))[1])::uuid,((storage.foldername(name))[2])::uuid)
 and lower(storage.extension(name)) in ('pdf','jpg','jpeg','png'));
create policy supplier_invoice_storage_select on storage.objects for select to authenticated
using (bucket_id='supplier-invoices'
 and public.can_access_supplier_order(((storage.foldername(name))[1])::uuid,((storage.foldername(name))[2])::uuid));
-- No direct deletion: retain audit trail; cleanup requires controlled admin process.

create or replace function public.register_supplier_invoice(p_org uuid,p_order uuid,p_number text,p_path text,p_filename text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_supplier uuid;
begin
 if not public.can_access_supplier_order(p_org,p_order) then raise exception 'Access denied'; end if;
 if length(trim(coalesce(p_number,''))) not between 1 and 100 or length(coalesce(p_filename,''))>255 then raise exception 'Invalid invoice details'; end if;
 if split_part(p_path,'/',1)<>p_org::text or split_part(p_path,'/',2)<>p_order::text or split_part(p_path,'/',3)<>auth.uid()::text then raise exception 'Invalid upload path'; end if;
 if not exists(select 1 from storage.objects where bucket_id='supplier-invoices' and name=p_path and owner_id=auth.uid()::text) then raise exception 'Upload missing'; end if;
 select supplier_id into v_supplier from public.purchase_orders where organization_id=p_org and id=p_order;
 insert into public.supplier_invoices(organization_id,order_id,supplier_id,uploaded_by,invoice_number,file_path,file_name)
 values(p_org,p_order,v_supplier,auth.uid(),trim(p_number),p_path,p_filename) returning id into v_id;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id,metadata)
 values(p_org,auth.uid(),'supplier.invoice.uploaded','purchase_order',p_order::text,jsonb_build_object('invoice_id',v_id,'invoice_number',trim(p_number)));
 return v_id;
end $$;
revoke all on function public.register_supplier_invoice(uuid,uuid,text,text,text) from public;
grant execute on function public.register_supplier_invoice(uuid,uuid,text,text,text) to authenticated;

create or replace function public.list_supplier_invoices(p_org uuid)
returns table(id uuid,order_id uuid,invoice_number text,file_path text,file_name text,created_at timestamptz)
language sql stable security definer set search_path='' as $$
 select si.id,si.order_id,si.invoice_number,si.file_path,si.file_name,si.created_at
 from public.supplier_invoices si where si.organization_id=p_org
 and public.can_access_supplier_order(p_org,si.order_id)
 order by si.created_at desc limit 500
$$;
revoke all on function public.list_supplier_invoices(uuid) from public;
grant execute on function public.list_supplier_invoices(uuid) to authenticated;
