'use client';
import {useState} from 'react';
import {createClient} from '@/lib/supabase/client';
export default function SupplierInvoiceUpload({organization,order}:{organization:string;order:string}){
 const [busy,setBusy]=useState(false);const [message,setMessage]=useState('');
 async function submit(e:React.FormEvent<HTMLFormElement>){
  e.preventDefault();setBusy(true);setMessage('');
  const form=new FormData(e.currentTarget);const file=form.get('file');const number=String(form.get('number')||'').trim();
  if(!(file instanceof File)||!file.size||file.size>10485760||!['application/pdf','image/jpeg','image/png'].includes(file.type)||!number){setMessage('Provide invoice number and a PDF/JPG/PNG up to 10 MB.');setBusy(false);return;}
  const db=createClient();const {data:{user}}=await db.auth.getUser();
  if(!user){setMessage('Please sign in.');setBusy(false);return;}
  const ext=file.type==='application/pdf'?'pdf':file.type==='image/png'?'png':'jpg';
  const path=`${organization}/${order}/${user.id}/${crypto.randomUUID()}.${ext}`;
  const {error:uploadError}=await db.storage.from('supplier-invoices').upload(path,file,{contentType:file.type,upsert:false});
  if(uploadError){setMessage(uploadError.message);setBusy(false);return;}
  const {error}=await db.rpc('register_supplier_invoice',{p_org:organization,p_order:order,p_number:number,p_path:path,p_filename:file.name.slice(0,255)});
  setMessage(error?`File uploaded but registration failed: ${error.message}`:'Invoice submitted successfully. Refresh to view it.');setBusy(false);
 }
 return <form onSubmit={submit} className="mt-3 flex flex-wrap gap-2 items-center"><input className="input" name="number" required maxLength={100} placeholder="Invoice number"/><input className="text-xs max-w-52" name="file" type="file" required accept=".pdf,.jpg,.jpeg,.png"/><button className="btn" disabled={busy}>{busy?'Uploading…':'Upload invoice'}</button>{message&&<span role="status" className="text-xs">{message}</span>}</form>;
}
