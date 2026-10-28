'use server';
import {createClient} from '@/lib/supabase/server';
import {revalidatePath} from 'next/cache';
export async function reviewInvoice(org:string,id:string,status:'approved'|'rejected',note:string){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();
 if(!user)return {error:'Please sign in'};
 if(!['approved','rejected'].includes(status)||note.length>1000)return {error:'Invalid review'};
 const {error}=await db.rpc('review_supplier_invoice',{p_org:org,p_invoice:id,p_status:status,p_note:note});
 if(error)return {error:error.message};
 revalidatePath('/dashboard/invoice-review');return {success:true};
}
