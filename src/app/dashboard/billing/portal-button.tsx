'use client';
import {useState} from 'react';
export function PortalButton({organizationId}:{organizationId:string}){
 const [busy,setBusy]=useState(false);const [error,setError]=useState('');
 async function openPortal(){setBusy(true);setError('');try{
  const response=await fetch('/api/billing/portal',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({organization_id:organizationId})});
  const payload=await response.json();if(!response.ok||!payload.url)throw new Error(payload.error||'Could not open billing portal');
  window.location.assign(payload.url);
 }catch(e){setError(e instanceof Error?e.message:'Something went wrong');setBusy(false);}}
 return <div className="space-y-2"><button type="button" disabled={busy} onClick={openPortal} className="rounded-xl bg-indigo-600 px-5 py-3 text-white font-semibold disabled:opacity-60">{busy?'Opening…':'Manage subscription & payment methods'}</button>{error&&<p role="alert" className="text-sm text-red-700">{error}</p>}</div>;
}
