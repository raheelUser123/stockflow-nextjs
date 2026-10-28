'use server';
import {createClient} from '@/lib/supabase/server';
import {revalidatePath} from 'next/cache';
export async function saveRecord(org:string,kind:'product'|'supplier',action:'create'|'update'|'delete',id:string|null,payload:Record<string,string|number>){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)return {error:'Please sign in'};
 const {error}=await db.rpc('manage_record',{p_org:org,p_kind:kind,p_action:action,p_id:id,p_payload:payload});
 if(error)return {error:error.message};revalidatePath('/dashboard');revalidatePath('/dashboard/'+(kind==='product'?'products':'suppliers'));return {success:true};
}
export async function completeSale(org:string,items:{product_id:string;quantity:number}[],payment:string){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)return {error:'Please sign in'};
 const {data,error}=await db.rpc('checkout',{p_org:org,p_items:items,p_payment:payment});
 if(error)return {error:error.message};revalidatePath('/dashboard');revalidatePath('/dashboard/products');revalidatePath('/dashboard/sales');return {success:true,id:data};
}
