import {WarehouseTransferWorkspace} from '@/components/warehouse-transfer-workspace';
import {StockWorkspace} from '@/components/stock-workspace';
import {notFound,redirect} from 'next/navigation';import {createClient} from '@/lib/supabase/server';import {OperationsWorkspace} from '@/components/operations-workspace';
import {ExtendedWorkspace} from '@/components/extended-workspace';
import {TeamRolesWorkspace} from '@/components/team-roles-workspace';
const names:Record<string,string>={customers:'Customers',categories:'Categories',purchases:'Purchase Orders',products:'Products',warehouses:'Warehouses',suppliers:'Suppliers',pos:'Point of Sale',sales:'Sales',analytics:'Analytics',team:'Team Management',roles:'Roles & Permissions',audit:'Activity Logs',settings:'Settings',adjustments:'Stock Adjustments',returns:'Sales Returns','stock-transfers':'Warehouse Transfers'};
export default async function Page({params,searchParams}:{params:Promise<{module:string}>,searchParams:Promise<{organization?:string}>}){
 const {module}=await params;if(!names[module])notFound();const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)redirect('/login');const {data:members}=await db.from('organization_members').select('organization_id,role').eq('user_id',user.id);if(!members?.length)redirect('/onboarding');const query=await searchParams;const org=members.find(m=>m.organization_id===query.organization)?.organization_id||members[0].organization_id;
 if(module==='stock-transfers'){
  const [{data:warehouses,error:wErr},{data:products,error:pErr},{data:balances,error:bErr}]=await Promise.all([
   db.from('warehouses').select('id,name').eq('organization_id',org).order('name'),
   db.from('products').select('id,name,stock').eq('organization_id',org).eq('active',true).order('name'),
   db.from('warehouse_stock').select('warehouse_id,product_id,quantity').eq('organization_id',org)
  ]);
  if(wErr||pErr||bErr)return <div className="panel p-8">{wErr?.message||pErr?.message||bErr?.message}</div>;
  return <WarehouseTransferWorkspace org={org} warehouses={warehouses||[]} products={products||[]} balances={balances||[]}/>;
 }
 if(['adjustments','returns'].includes(module)){
  const [{data:products,error:pErr},{data:sales,error:sErr},{data:lines,error:lErr}]=await Promise.all([
   db.from('products').select('id,name,sku,stock').eq('organization_id',org).eq('active',true).order('name'),
   db.from('sales').select('id,receipt_number,total,created_at').eq('organization_id',org).order('created_at',{ascending:false}).limit(100),
   db.from('sale_items').select('id,sale_id,quantity,unit_price,product_id').eq('organization_id',org).limit(1000)
  ]);
  if(pErr||sErr||lErr)return <div className="panel p-8">{pErr?.message||sErr?.message||lErr?.message}</div>;
  return <StockWorkspace kind={module as 'adjustments'|'returns'} org={org} products={products||[]} sales={sales||[]} lines={lines||[]}/>;
 }
 if(['team','roles'].includes(module)){
  const [{data:members,error:memberError},{data:roles,error:roleError},{data:assignments,error:assignmentError}]=await Promise.all([
    db.from('organization_members').select('user_id,role').eq('organization_id',org),
    db.from('custom_roles').select('id,name,permissions').eq('organization_id',org),
    db.from('member_custom_roles').select('user_id,custom_role_id').eq('organization_id',org)
  ]);
  if(memberError||roleError||assignmentError)return <div className="panel p-8">Run migration 0004_team_roles.sql first: {memberError?.message||roleError?.message||assignmentError?.message}</div>;
  return <TeamRolesWorkspace org={org} members={members||[]} roles={roles||[]} assignments={assignments||[]} />;
 }
 if(['warehouses','customers','categories','purchases','settings'].includes(module)){
  const table=module==='purchases'?'purchase_orders':module==='team'||module==='roles'?'organization_members':module==='settings'?'organization_settings':module;
  const [{data:rows,error}, {data:products},{data:suppliers},{data:members},{data:settings}]=await Promise.all([
   db.from(table).select('*').eq('organization_id',org).limit(200),
   db.from('products').select('id,name,cost').eq('organization_id',org).eq('active',true),
   db.from('suppliers').select('id,name').eq('organization_id',org),
   db.from('organization_members').select('user_id,role').eq('organization_id',org),
   db.from('organization_settings').select('theme,timezone').eq('organization_id',org).maybeSingle()
  ]);
  if(error)return <div className="panel p-8">Database migration 0003_extended.sql may be required: {error.message}</div>;
  return <ExtendedWorkspace kind={module} org={org} rows={rows||[]} products={products||[]} suppliers={suppliers||[]} members={members||[]} settings={settings}/>;
 }
 if(['products','suppliers','pos'].includes(module)){const [{data:products,error:pError},{data:suppliers,error:sError}]=await Promise.all([db.from('products').select('id,name,sku,price,cost,stock,min_stock,active,image_path').eq('organization_id',org).eq('active',true).order('created_at',{ascending:false}),db.from('suppliers').select('id,name,email,phone').eq('organization_id',org).order('created_at',{ascending:false})]);if(pError||sError)return <div className="panel p-8">Please run the 0002_operations.sql migration in Supabase SQL Editor. {pError?.message||sError?.message}</div>;const imageProducts=await Promise.all((products||[]).map(async p=>({...p,image_url:p.image_path?(await db.storage.from('product-images').createSignedUrl(p.image_path,3600)).data?.signedUrl||null:null})));return <OperationsWorkspace kind={module} org={org} products={imageProducts} suppliers={suppliers||[]}/>}
 if(module==='sales'){const {data,error}=await db.from('sales').select('id,receipt_number,total,payment_method,created_at').eq('organization_id',org).order('created_at',{ascending:false}).limit(100);return <div className="space-y-5"><h1 className="text-3xl font-bold">Sales History</h1>{error?<p>{error.message}</p>:<div className="panel overflow-x-auto"><table className="w-full text-left text-sm"><thead><tr>{['Receipt','Date','Total','Payment'].map(x=><th key={x} className="p-4">{x}</th>)}</tr></thead><tbody>{data?.map(s=><tr className="border-t" key={s.id}><td className="p-4">#{s.receipt_number}</td><td className="p-4">{new Date(s.created_at).toLocaleString()}</td><td className="p-4">PKR {Number(s.total).toLocaleString()}</td><td className="p-4 capitalize">{s.payment_method}</td></tr>)}</tbody></table></div>}</div>}
 if(module==='audit'){const {data,error}=await db.from('audit_logs').select('id,action,entity_type,entity_id,created_at').eq('organization_id',org).order('created_at',{ascending:false}).limit(100);return <div className="space-y-5"><h1 className="text-3xl font-bold">Audit Logs</h1>{error?<p>Audit logs require owner/admin permission.</p>:<div className="panel p-5 space-y-3">{data?.map(a=><div className="border-b pb-3 flex justify-between gap-3" key={a.id}><div><b>{a.action}</b><p className="text-xs text-slate-500">{a.entity_type} · {a.entity_id}</p></div><span className="text-xs text-slate-500">{new Date(a.created_at).toLocaleString()}</span></div>)}</div>}</div>}
 if(module==='analytics'){const [{data:products},{data:sales}]=await Promise.all([db.from('products').select('stock,cost,min_stock').eq('organization_id',org).eq('active',true),db.from('sales').select('total,created_at').eq('organization_id',org)]);const total=(sales||[]).reduce((a,s)=>a+Number(s.total),0);return <div className="space-y-6"><h1 className="text-3xl font-bold">Analytics</h1><div className="grid sm:grid-cols-3 gap-5">{[['Sales revenue',`PKR ${total.toLocaleString()}`],['Stock value',`PKR ${(products||[]).reduce((a,p)=>a+p.stock*Number(p.cost),0).toLocaleString()}`],['Low stock',(products||[]).filter(p=>p.stock<=p.min_stock).length]].map(([a,b])=><div className="panel p-7" key={a}><p className="text-slate-500">{a}</p><h2 className="text-3xl font-bold mt-3">{b}</h2></div>)}</div><p className="text-slate-500">These totals are live database calculations. Advanced period comparisons and charts are planned.</p></div>}
 return <div className="space-y-5"><h1 className="text-3xl font-bold">{names[module]}</h1><div className="panel p-8"><p className="font-semibold">This module is not implemented yet.</p><p className="text-slate-500 mt-2">The authenticated foundation is ready, but this feature needs additional database migrations and secure workflows.</p></div></div>;
}
