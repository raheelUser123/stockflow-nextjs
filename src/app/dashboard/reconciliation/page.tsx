import Link from 'next/link';
import {redirect} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';

type Product={id:string;name:string;sku:string;stock:number};
type Allocation={product_id:string;quantity:number};
export default async function Reconciliation({searchParams}:{searchParams:Promise<{organization?:string}>}){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)redirect('/login');
 const {data:members,error:membershipError}=await db.from('organization_members').select('organization_id,role,organizations(name)').eq('user_id',user.id);
 if(membershipError)return <p className="panel p-6">Unable to verify company access: {membershipError.message}</p>;
 const eligible=(members||[]).filter(m=>['owner','admin','manager'].includes(m.role));
 if(!eligible.length)return <p className="panel p-6">Only company owners, admins and managers can view stock reconciliation.</p>;
 const params=await searchParams;const member=eligible.find(m=>m.organization_id===params.organization)||eligible[0];const orgId=member.organization_id;
 const [productsResult,allocationResult]=await Promise.all([
  db.from('products').select('id,name,sku,stock').eq('organization_id',orgId).order('name').limit(5000),
  db.from('warehouse_stock').select('product_id,quantity').eq('organization_id',orgId).limit(10000)
 ]);
 const issue=productsResult.error||allocationResult.error;
 if(issue)return <p className="panel p-6">Could not load reconciliation: {issue.message}</p>;
 const totals=new Map<string,number>();for(const a of (allocationResult.data||[]) as Allocation[])totals.set(a.product_id,(totals.get(a.product_id)||0)+a.quantity);
 const rows=((productsResult.data||[]) as Product[]).map(p=>({...p,allocated:totals.get(p.id)||0,difference:p.stock-(totals.get(p.id)||0)}));
 const flagged=rows.filter(r=>r.difference!==0);const over=rows.filter(r=>r.difference<0);
 const limited=(productsResult.data||[]).length===5000||(allocationResult.data||[]).length===10000;
 return <div className="space-y-6"><div><p className="text-indigo-600 text-sm font-semibold">INVENTORY CONTROL</p><h1 className="text-3xl font-bold">Stock Reconciliation</h1><p className="text-slate-500 mt-2">Read-only comparison of product stock versus warehouse allocations. This report does not modify inventory.</p></div>
 <div className="panel p-4 flex flex-wrap gap-2">{eligible.map(m=><Link key={m.organization_id} href={'/dashboard/reconciliation?organization='+m.organization_id} className={'rounded-lg px-3 py-2 text-sm '+(orgId===m.organization_id?'bg-indigo-600 text-white':'bg-slate-100')}>{(m.organizations as unknown as {name:string})?.name||'Company'}</Link>)}</div>
 {limited&&<div className="panel p-4 text-amber-800 bg-amber-50">Result limit reached. This report is incomplete for large datasets; do not use it as a final stock audit.</div>}
 <div className="grid sm:grid-cols-3 gap-4">{[['Products reviewed',rows.length],['Unallocated / mismatched',flagged.length],['Over-allocated products',over.length]].map(([label,value])=><div key={label} className="panel p-5"><p className="text-sm text-slate-500">{label}</p><p className="text-3xl font-bold mt-2">{value}</p></div>)}</div>
 <div className="panel overflow-x-auto"><table className="w-full text-sm text-left"><thead className="bg-slate-50"><tr>{['Product','SKU','Global stock','Allocated','Difference','Status'].map(h=><th key={h} className="px-4 py-3">{h}</th>)}</tr></thead><tbody>{rows.map(r=><tr key={r.id} className="border-t border-slate-100"><td className="px-4 py-3 font-medium">{r.name}</td><td className="px-4 py-3">{r.sku}</td><td className="px-4 py-3">{r.stock}</td><td className="px-4 py-3">{r.allocated}</td><td className="px-4 py-3">{r.difference}</td><td className="px-4 py-3">{r.difference<0?'Over-allocated':r.difference>0?'Unallocated':'Balanced'}</td></tr>)}</tbody></table>{!rows.length&&<p className="p-6 text-slate-500">No products found for this company.</p>}</div><p className="text-sm text-slate-500">A positive difference can represent stock not yet allocated to a warehouse. A negative difference indicates an inconsistency. This report compares balances only; it does not certify movement-ledger accuracy.</p></div>;
}
