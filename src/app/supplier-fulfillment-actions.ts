'use server';
import {createClient} from '@/lib/supabase/server';
import {revalidatePath} from 'next/cache';
export async function submitSupplierFulfillment(form:FormData){
 const db=await createClient();
 const {data:{user}}=await db.auth.getUser();
 if(!user)return {error:'Please sign in first'};
 const org=String(form.get('organization')||'');
 const order=String(form.get('order')||'');
 const status=String(form.get('status')||'');
 const tracking=String(form.get('tracking')||'').trim();
 const note=String(form.get('note')||'').trim();
 const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
 if(!uuid.test(org)||!uuid.test(order)||!['acknowledged','dispatched'].includes(status))return {error:'Invalid request'};
 if(tracking.length>120||note.length>1000)return {error:'Input too long'};
 const {error}=await db.rpc('submit_supplier_fulfillment',{p_org:org,p_order:order,p_status:status,p_tracking:tracking||null,p_note:note||null});
 if(error)return {error:error.message};
 revalidatePath('/supplier');
 return {success:true};
}
