import {notFound,redirect} from 'next/navigation';
import Link from 'next/link';
import {createClient} from '@/lib/supabase/server';
import {PrintReceipt} from '@/components/print-receipt';
export default async function ReceiptPage({params,searchParams}:{params:Promise<{id:string}>,searchParams:Promise<{organization?:string}>}){
 const {id}=await params;const {organization}=await searchParams;
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)redirect('/login');
 const {data:members}=await db.from('organization_members').select('organization_id').eq('user_id',user.id);
 if(!members?.length)redirect('/onboarding');
 const org=members.find(x=>x.organization_id===organization)?.organization_id||members[0].organization_id;
 const [{data:sale,error},{data:lines},{data:company}]=await Promise.all([
  db.from('sales').select('id,receipt_number,total,payment_method,created_at').eq('organization_id',org).eq('id',id).maybeSingle(),
  db.from('sale_items').select('id,product_id,quantity,unit_price').eq('organization_id',org).eq('sale_id',id),
  db.from('organizations').select('name').eq('id',org).maybeSingle()
 ]);
 if(error||!sale)notFound();
 const productIds=[...new Set((lines||[]).map(l=>l.product_id))];
 const {data:products}=productIds.length?await db.from('products').select('id,name,sku').eq('organization_id',org).in('id',productIds):{data:[]};
 const productNames=new Map((products||[]).map(p=>[p.id,p.name]));
 const money=(n:number)=>`PKR ${n.toLocaleString('en-PK',{minimumFractionDigits:2,maximumFractionDigits:2})}`;
 return <div className="max-w-3xl mx-auto space-y-5"><div className="flex items-center justify-between gap-3 print:hidden"><Link className="text-indigo-600" href="/dashboard/sales">← Sales history</Link><PrintReceipt/></div><section className="bg-white rounded-2xl border border-slate-200 p-6 md:p-10 print:border-0 print:p-0"><div className="flex justify-between gap-4 border-b pb-6"><div><h1 className="text-2xl font-bold">{company?.name||'StockFlow Pro'}</h1><p className="text-slate-500 text-sm">Sales receipt</p></div><div className="text-right"><b>#{sale.receipt_number}</b><p className="text-sm text-slate-500">{new Date(sale.created_at).toLocaleString('en-PK')}</p></div></div><table className="w-full text-sm mt-7"><thead><tr className="border-b text-left"><th className="py-3">Item</th><th className="py-3 text-right">Qty</th><th className="py-3 text-right">Unit</th><th className="py-3 text-right">Total</th></tr></thead><tbody>{(lines||[]).map(l=><tr key={l.id} className="border-b"><td className="py-4">{productNames.get(l.product_id)||'Product'}</td><td className="text-right">{l.quantity}</td><td className="text-right">{money(Number(l.unit_price))}</td><td className="text-right">{money(l.quantity*Number(l.unit_price))}</td></tr>)}</tbody></table><div className="flex justify-between mt-7 font-bold text-xl"><span>Total</span><span>{money(Number(sale.total))}</span></div><p className="text-right mt-2 text-sm text-slate-500">Payment: {sale.payment_method.toUpperCase()}</p><p className="mt-12 pt-5 border-t text-center text-slate-500 text-sm">Thank you for your business.</p></section></div>;
}
