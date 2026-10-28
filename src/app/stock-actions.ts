'use server';
import {createClient} from '@/lib/supabase/server';
import {revalidatePath} from 'next/cache';
export async function adjustStock(org:string,product:string,delta:number,reason:string){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)return {error:'Authentication required'};
 const {error}=await db.rpc('adjust_stock',{p_org:org,p_product:product,p_delta:delta,p_reason:reason});
 if(error)return {error:error.message};revalidatePath('/dashboard','layout');return {success:true};
}
export async function returnSale(org:string,sale:string,items:{sale_item_id:string;quantity:number}[],reason:string){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)return {error:'Authentication required'};
 const {error}=await db.rpc('return_sale',{p_org:org,p_sale:sale,p_items:items,p_reason:reason});
 if(error)return {error:error.message};revalidatePath('/dashboard','layout');return {success:true};
}
