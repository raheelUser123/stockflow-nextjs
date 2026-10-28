import {redirect} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';
import {InvoiceReviewList} from '@/components/invoice-review-list';
export default async function InvoiceReviewPage({searchParams}:{searchParams:Promise<{organization?:string}>}){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)redirect('/login');
 const {data:members,error:memberError}=await db.from('organization_members').select('organization_id,role').eq('user_id',user.id).in('role',['owner','admin','manager']);
 if(memberError||!members?.length)return <p>Company owner, admin or manager access required.</p>;
 const {organization}=await searchParams;const chosen=members.find(m=>m.organization_id===organization)||members[0];
 const {data,error}=await db.rpc('company_supplier_invoices',{p_org:chosen.organization_id});
 if(error)return <div className="panel p-6">{error.message}. Apply migration 0012_invoice_review.sql.</div>;
 const invoices=await Promise.all((data||[]).map(async(i:{file_path:string;[key:string]:unknown})=>{
  const {data:signed}=await db.storage.from('supplier-invoices').createSignedUrl(i.file_path,300);
  return {...i,file_url:signed?.signedUrl||null};
 }));
 return <div className="space-y-6"><div><h1 className="text-3xl font-bold">Supplier Invoice Review</h1><p className="text-slate-500 mt-2">Approve or reject submitted supplier invoices. Review does not trigger payment or goods receipt.</p></div><InvoiceReviewList org={chosen.organization_id} invoices={invoices as Parameters<typeof InvoiceReviewList>[0]['invoices']}/></div>;
}
