-- Run after 0004_team_roles.sql, once only.
alter table public.products add column if not exists image_path text;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('product-images','product-images',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=false,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'];
-- Folder name must equal an organization UUID. Private bucket: images served using short-lived signed URLs.
create policy "product_images_read" on storage.objects for select to authenticated
using (bucket_id='product-images' and public.is_org_member((storage.foldername(name))[1]::uuid));
create policy "product_images_upload" on storage.objects for insert to authenticated
with check (bucket_id='product-images' and public.has_org_role((storage.foldername(name))[1]::uuid,array['owner','admin','manager']::public.organization_role[]) and lower(storage.extension(name)) in ('jpg','png','webp'));
create policy "product_images_remove" on storage.objects for delete to authenticated
using (bucket_id='product-images' and public.has_org_role((storage.foldername(name))[1]::uuid,array['owner','admin','manager']::public.organization_role[]));
-- Preserve original product/supplier CRUD function and extend product image handling.
alter function public.manage_record(uuid,text,text,uuid,jsonb) rename to manage_record_core;
create function public.manage_record(p_org uuid,p_kind text,p_action text,p_id uuid,p_payload jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_path text;
begin
 if p_kind='product' and p_payload ? 'image_path' and p_action in ('create','update') then
   if not public.has_org_role(p_org,array['owner','admin','manager']::public.organization_role[]) then raise exception 'Permission denied'; end if;
   v_path:=p_payload->>'image_path';
   if v_path is null or left(v_path,length(p_org::text)+1)<>p_org::text||'/' or
      not exists(select 1 from storage.objects where bucket_id='product-images' and name=v_path) then
      raise exception 'Invalid product image';
   end if;
 end if;
 v_id:=public.manage_record_core(p_org,p_kind,p_action,p_id,p_payload - 'image_path');
 if p_kind='product' and p_action in ('create','update') and p_payload ? 'image_path' then
   update public.products set image_path=v_path where organization_id=p_org and id=v_id;
 end if;
 return v_id;
end $$;
revoke all on function public.manage_record_core(uuid,text,text,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.manage_record(uuid,text,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.manage_record(uuid,text,text,uuid,jsonb) to authenticated;
