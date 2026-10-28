'use client';
import {useEffect,useState} from 'react';
import {createClient} from '@/lib/supabase/client';

type Factor={id:string;friendly_name?:string;status:string};
export function MfaSettings(){
 const [factors,setFactors]=useState<Factor[]>([]);
 const [factorId,setFactorId]=useState('');
 const [qr,setQr]=useState('');
 const [secret,setSecret]=useState('');
 const [code,setCode]=useState('');
 const [busy,setBusy]=useState(false);
 const [message,setMessage]=useState('');
 const supabase=createClient();
 async function refresh(){const {data,error}=await supabase.auth.mfa.listFactors();if(error){setMessage(error.message);return;}setFactors((data?.totp||[]) as Factor[]);}
 useEffect(()=>{void refresh();},[]);
 async function enroll(){setBusy(true);setMessage('');try{const {data,error}=await supabase.auth.mfa.enroll({factorType:'totp',friendlyName:'Authenticator'});if(error)throw error;setFactorId(data.id);setQr(data.totp.qr_code);setSecret(data.totp.secret);}catch(e){setMessage(e instanceof Error?e.message:'Unable to start enrollment');}finally{setBusy(false);}}
 async function verify(){if(!/^\d{6}$/.test(code)){setMessage('Enter the 6-digit code.');return;}setBusy(true);setMessage('');try{const {data,error}=await supabase.auth.mfa.challenge({factorId});if(error)throw error;const result=await supabase.auth.mfa.verify({factorId,challengeId:data.id,code});if(result.error)throw result.error;setQr('');setSecret('');setFactorId('');setCode('');setMessage('Authenticator enabled successfully.');await refresh();}catch(e){setMessage(e instanceof Error?e.message:'Verification failed');}finally{setBusy(false);}}
 async function remove(id:string){if(!confirm('Remove this authenticator? Your account security will be reduced.'))return;setBusy(true);setMessage('');try{const {error}=await supabase.auth.mfa.unenroll({factorId:id});if(error)throw error;setMessage('Authenticator removed.');await refresh();}catch(e){setMessage(e instanceof Error?e.message:'Unable to remove factor. You may need to sign in with MFA first.');}finally{setBusy(false);}}
 return <section className="rounded-2xl border border-slate-200 bg-white p-6 space-y-5"><div><h2 className="text-lg font-semibold">Two-factor authentication</h2><p className="text-sm text-slate-500">Use Google Authenticator, Microsoft Authenticator or another TOTP app.</p></div>
 {factors.length>0&&<div className="space-y-2">{factors.map(f=><div key={f.id} className="flex items-center justify-between gap-3 rounded-xl bg-slate-50 p-3"><div><div className="font-medium">{f.friendly_name||'Authenticator'}</div><div className="text-xs text-slate-500">{f.status}</div></div><button disabled={busy} onClick={()=>void remove(f.id)} className="text-sm text-red-600 disabled:opacity-50">Remove</button></div>)}</div>}
 {!factorId?<button type="button" disabled={busy} onClick={()=>void enroll()} className="rounded-xl bg-indigo-600 px-4 py-2 text-sm font-medium text-white disabled:opacity-50">Add authenticator</button>:<div className="space-y-4"><p className="text-sm">Scan this QR code in your authenticator app, then enter the 6-digit code.</p>{qr&&<img src={qr} alt="Authenticator enrollment QR code" className="h-48 w-48 rounded-lg border p-2"/>}<div className="text-xs text-slate-500 break-all">Manual setup key: <code>{secret}</code></div><label className="block text-sm font-medium">Verification code<input inputMode="numeric" autoComplete="one-time-code" maxLength={6} value={code} onChange={e=>setCode(e.target.value.replace(/\D/g,''))} className="mt-2 block w-full max-w-xs rounded-lg border border-slate-300 p-3" placeholder="000000"/></label><div className="flex gap-3"><button disabled={busy} onClick={()=>void verify()} className="rounded-xl bg-indigo-600 px-4 py-2 text-sm text-white disabled:opacity-50">Verify & enable</button><button onClick={()=>{setFactorId('');setQr('');setSecret('');setCode('');}} className="text-sm text-slate-600">Cancel</button></div></div>}
 {message&&<p role="status" className="text-sm text-slate-700">{message}</p>}
 <p className="text-xs text-amber-700">Enrollment alone does not enforce MFA at sign-in. The sign-in challenge flow must be enabled before MFA is mandatory.</p></section>;
}
