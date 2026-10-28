'use server';
import {createClient} from '@/lib/supabase/server';
import {revalidatePath} from 'next/cache';
export async function changeSupplierLink(form:FormData){
 const db=await createClient();
 const {data:{user}}=await db.auth.getUser();if(!user)return {error:'Sign in required'};
 const org=String(form.get('org')||'');const supplier=String(form.get('supplier')||'');const member=String(form.get('member')||'');
 const action=String(form.get('action')||'link');
 if(!/^[0-9a-f-]{36}$/i.test(org)||!/^[0-9a-f-]{36}$/i.test(supplier)||!/^[0-9a-f-]{36}$/i.test(member))return {error:'Select valid records'};
 const {error}=await db.rpc(action==='unlink'?'unlink_supplier_account':'link_supplier_account',{p_org:org,p_supplier:supplier,p_user:member});
 if(error)return {error:error.message};
 revalidatePath('/dashboard/supplier-access');return {success:true};
}
