'use client';
import {useState} from 'react';
export function CheckoutButton({organizationId,plan}:{organizationId:string;plan:'starter'|'professional'}){
 const [busy,setBusy]=useState(false),[error,setError]=useState('');
 return <div><button disabled={busy} className="rounded-lg bg-indigo-600 px-4 py-2 text-white disabled:opacity-50" onClick={async()=>{setBusy(true);setError('');try{const r=await fetch('/api/billing/checkout',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({organization_id:organizationId,plan_code:plan})});const j=await r.json();if(!r.ok||!j.url)throw new Error(j.error||'Checkout failed');window.location.assign(j.url)}catch(e){setError(e instanceof Error?e.message:'Checkout failed');setBusy(false)}}}>{busy?'Redirecting…':'Subscribe securely'}</button>{error&&<p role="alert" className="text-sm text-red-600 mt-2">{error}</p>}</div>;
}
