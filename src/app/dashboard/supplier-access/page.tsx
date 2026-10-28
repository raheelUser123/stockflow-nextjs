import {redirect} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';
import {SupplierAccessManager} from '@/components/supplier-access-manager';
export default async function SupplierAccess({searchParams}:{searchParams:Promise<{organization?:string}>}){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)redirect('/login');
 const {data:memberships}=await db.from('organization_members').select('organization_id,role').eq('user_id',user.id).in('role',['owner','admin']);
 if(!memberships?.length)redirect('/supplier');const q=await searchParams;const org=memberships.find(m=>m.organization_id===q.organization)?.organization_id||memberships[0].organization_id;
 const [{data:suppliers,error:a},{data:members,error:b},{data:links,error:c}]=await Promise.all([
 db.from('suppliers').select('id,name,email').eq('organization_id',org).order('name'),
 db.from('organization_members').select('user_id,role').eq('organization_id',org).eq('role','supplier'),
 db.from('supplier_accounts').select('supplier_id,user_id').eq('organization_id',org)
 ]);
 return <div className="space-y-5"><h1 className="text-3xl font-bold">Supplier Access</h1><p className="text-slate-500">Connect supplier-role team members to their supplier records. Linked users can see only their assigned purchase orders.</p>{a||b||c?<div className="panel p-6 text-red-600">{a?.message||b?.message||c?.message} — check migration 0009.</div>:<SupplierAccessManager org={org} suppliers={suppliers||[]} members={members||[]} links={links||[]}/>}</div>;
}
