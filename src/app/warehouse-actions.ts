'use server';
import {createClient} from '@/lib/supabase/server';
import {revalidatePath} from 'next/cache';
export async function warehouseAction(org:string,mode:'allocate'|'transfer',product:string,from:string,to:string,quantity:number){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)return {error:'Sign in required'};
 if(!Number.isSafeInteger(quantity)||quantity<1)return {error:'Invalid quantity'};
 const {error}=mode==='allocate'?await db.rpc('allocate_warehouse_stock',{p_org:org,p_product:product,p_warehouse:to,p_quantity:quantity}):await db.rpc('transfer_warehouse_stock',{p_org:org,p_product:product,p_from:from,p_to:to,p_quantity:quantity});
 if(error)return {error:error.message};revalidatePath('/dashboard/stock-transfers');return {success:true};
}
