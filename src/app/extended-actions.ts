'use server';
import {createClient} from '@/lib/supabase/server';
import {revalidatePath} from 'next/cache';
async function rpc(name:string,args:Record<string,unknown>){const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)return {error:'Sign in required'};const {data,error}=await db.rpc(name,args);if(!error)revalidatePath('/dashboard',{type:'layout'});return error?{error:error.message}:{success:true,data};}
export async function extendedRecord(org:string,kind:string,action:string,id:string|null,payload:Record<string,string>){return rpc('manage_extended',{p_org:org,p_kind:kind,p_action:action,p_id:id,p_payload:payload});}
export async function createPurchase(org:string,supplier:string,reference:string,items:{product_id:string;quantity:number;unit_cost:number}[]){return rpc('create_purchase',{p_org:org,p_supplier:supplier,p_reference:reference,p_items:items});}
export async function receivePurchase(org:string,order:string){return rpc('receive_purchase',{p_org:org,p_order:order});}
export async function changeTeam(org:string,user:string,role:string,action:string){return rpc('manage_team',{p_org:org,p_user:user,p_role:role,p_action:action});}
export async function saveSettings(org:string,theme:string,timezone:string){return rpc('update_company_settings',{p_org:org,p_theme:theme,p_timezone:timezone});}
export async function addRegisteredMember(org:string,email:string,role:string){return rpc('add_registered_member',{p_org:org,p_email:email,p_role:role});}
export async function manageCustomRole(org:string,action:string,id:string|null,name:string,permissions:string[]){return rpc('manage_custom_role',{p_org:org,p_action:action,p_id:id,p_name:name,p_permissions:permissions});}
export async function assignCustomRole(org:string,user:string,role:string|null){return rpc('assign_custom_role',{p_org:org,p_user:user,p_role_id:role});}
