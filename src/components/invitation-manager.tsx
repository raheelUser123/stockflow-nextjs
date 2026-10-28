'use client';
import { useState, useTransition } from 'react';
import { inviteMemberWithEmail } from '@/app/invitation-email-actions';

export function InvitationManager({org}:{org:string}) {
  const [email,setEmail] = useState('');
  const [role,setRole] = useState('viewer');
  const [link,setLink] = useState('');
  const [message,setMessage] = useState('');
  const [error,setError] = useState('');
  const [busy,start] = useTransition();
  return <section className="panel p-6 space-y-4">
    <h2 className="text-lg font-bold">Invite a team member</h2>
    <p className="text-sm text-slate-500">Invite users by email. Invitations expire after 7 days and require a verified account with the invited email.</p>
    <form className="flex flex-col md:flex-row gap-3" onSubmit={e=>{
      e.preventDefault(); setError('');setLink('');setMessage('');
      start(async()=>{
        const result=await inviteMemberWithEmail(org,email,role);
        if(result.error) setError(result.error);
        else if(result.status==='sent') {setMessage('Invitation email accepted by the email provider.');setEmail('');}
        else {setMessage(result.warning||'Share the invitation link manually.');setLink(result.link||'');}
      });
    }}>
      <input className="input flex-1" type="email" required placeholder="team@example.com" value={email} onChange={e=>setEmail(e.target.value)}/>
      <select className="input" value={role} onChange={e=>setRole(e.target.value)}>
        {['admin','manager','cashier','supplier','viewer'].map(r=><option key={r} value={r}>{r}</option>)}
      </select>
      <button className="btn" disabled={busy}>{busy?'Sending…':'Send invitation'}</button>
    </form>
    {error&&<p role="alert" className="text-sm text-red-600">{error}</p>}
    {message&&<p role="status" className="text-sm text-slate-700">{message}</p>}
    {link&&<div className="rounded-xl bg-indigo-50 p-4 space-y-2">
      <p className="text-sm font-medium">Manual invitation link (shown once)</p>
      <input className="input w-full" readOnly value={link} aria-label="Invitation link"/>
      <button className="btn" type="button" onClick={()=>navigator.clipboard.writeText(link)}>Copy link</button>
    </div>}
  </section>;
}
