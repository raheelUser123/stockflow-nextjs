-- Apply once AFTER 0011_supplier_invoices.sql. Test on staging first.
alter table public.supplier_invoices
 add column review_status text not null default 'pending' check (review_status in ('pending','approved','rejected')),
 add column reviewed_by uuid references auth.users(id),
 add column reviewed_at timestamptz,
 add column review_note text not null default '' check (length(review_note)<=1000);
create index supplier_invoices_review_idx on public.supplier_invoices(organization_id,review_status,created_at desc);

-- Only a company operator can review. Supplier cannot approve their own invoice.
create or replace function public.review_supplier_invoice(p_org uuid,p_invoice uuid,p_status text,p_note text default '')
returns void language plpgsql security definer set search_path='' as $$
declare v_order uuid; v_old text;
begin
 if not public.has_org_role(p_org,array['owner','admin','manager']::public.organization_role[]) then raise exception 'Not authorized'; end if;
 if p_status not in ('approved','rejected') then raise exception 'Invalid review status'; end if;
 if length(coalesce(p_note,''))>1000 then raise exception 'Review note too long'; end if;
 select order_id,review_status into v_order,v_old from public.supplier_invoices
 where id=p_invoice and organization_id=p_org for update;
 if not found then raise exception 'Invoice not found'; end if;
 if v_old<>'pending' then raise exception 'Invoice already reviewed'; end if;
 update public.supplier_invoices set review_status=p_status,reviewed_by=auth.uid(),reviewed_at=now(),review_note=coalesce(p_note,'')
 where id=p_invoice and organization_id=p_org;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id,metadata)
 values(p_org,auth.uid(),'supplier.invoice.'||p_status,'supplier_invoice',p_invoice::text,jsonb_build_object('order_id',v_order,'note',coalesce(p_note,'')));
end $$;
revoke all on function public.review_supplier_invoice(uuid,uuid,text,text) from public;
grant execute on function public.review_supplier_invoice(uuid,uuid,text,text) to authenticated;

-- This RPC deliberately exposes only invoices to authorized company operators.
create or replace function public.company_supplier_invoices(p_org uuid)
returns table(id uuid,order_id uuid,invoice_number text,file_path text,file_name text,created_at timestamptz,review_status text,review_note text,reviewed_at timestamptz,supplier_name text,order_reference text)
language plpgsql stable security definer set search_path='' as $$
begin
 if not public.has_org_role(p_org,array['owner','admin','manager']::public.organization_role[]) then raise exception 'Not authorized'; end if;
 return query select si.id,si.order_id,si.invoice_number,si.file_path,si.file_name,si.created_at,si.review_status,si.review_note,si.reviewed_at,s.name,po.reference
 from public.supplier_invoices si
 join public.suppliers s on s.id=si.supplier_id and s.organization_id=si.organization_id
 join public.purchase_orders po on po.id=si.order_id and po.organization_id=si.organization_id
 where si.organization_id=p_org order by si.created_at desc limit 500;
end $$;
revoke all on function public.company_supplier_invoices(uuid) from public;
grant execute on function public.company_supplier_invoices(uuid) to authenticated;
