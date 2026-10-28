'use client';
import {useState,useTransition} from 'react';
import {submitSupplierFulfillment} from '@/app/supplier-fulfillment-actions';
export default function SupplierFulfillmentForm({organization,order,step}:{organization:string;order:string;step:'acknowledged'|'dispatched'}){
 const [pending,start]=useTransition();const [message,setMessage]=useState('');
 return <form className="mt-3 flex flex-col sm:flex-row gap-2 items-start" action={form=>start(async()=>{
  const result=await submitSupplierFulfillment(form);setMessage(result.error||'Saved successfully');
 })}>
 <input type="hidden" name="organization" value={organization}/><input type="hidden" name="order" value={order}/><input type="hidden" name="status" value={step}/>
 {step==='dispatched'&&<input name="tracking" className="input" maxLength={120} placeholder="Tracking reference (optional)"/>}
 <input name="note" className="input" maxLength={1000} placeholder="Note (optional)"/>
 <button disabled={pending} className="btn" type="submit">{pending?'Saving…':step==='acknowledged'?'Acknowledge order':'Mark dispatched'}</button>
 {message&&<span role="status" className="text-sm text-slate-600">{message}</span>}
 </form>;
}
