"use client";
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';

export function MfaChallenge() {
 const router = useRouter();
 const [factorId, setFactorId] = useState('');
 const [code, setCode] = useState('');
 const [error, setError] = useState('');
 const [loading, setLoading] = useState(false);
 const [ready, setReady] = useState(false);
 useEffect(() => {
  let alive = true;
  const supabase = createClient();
  (async () => {
   const { data: { user } } = await supabase.auth.getUser();
   if (!alive) return;
   if (!user) { router.replace('/login'); return; }
   const assurance = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
   if (!alive) return;
   if (assurance.data?.currentLevel === 'aal2') { router.replace('/dashboard'); return; }
   if (assurance.error) { setError(assurance.error.message); setReady(true); return; }
   const factors = await supabase.auth.mfa.listFactors();
   if (!alive) return;
   if (factors.error) setError(factors.error.message);
   else if (factors.data?.totp?.length) setFactorId(factors.data.totp[0].id);
   else setError('No verified authenticator found. Contact your administrator.');
   setReady(true);
  })();
  return () => { alive = false; };
 }, [router]);
 async function verify(event: React.FormEvent) {
  event.preventDefault();
  if (!factorId || !/^\d{6}$/.test(code)) return;
  setLoading(true); setError('');
  const supabase = createClient();
  const challenge = await supabase.auth.mfa.challenge({ factorId });
  if (challenge.error || !challenge.data) { setError(challenge.error?.message ?? 'Challenge failed'); setLoading(false); return; }
  const result = await supabase.auth.mfa.verify({ factorId, challengeId: challenge.data.id, code });
  if (result.error) { setError(result.error.message); setLoading(false); return; }
  router.replace('/dashboard'); router.refresh();
 }
 async function signOut() { await createClient().auth.signOut(); router.replace('/login'); router.refresh(); }
 return <main className="min-h-screen grid place-items-center p-5 bg-slate-50"><section className="panel w-full max-w-md p-9 space-y-5"><div className="text-indigo-600 font-bold">STOCKFLOW PRO</div><h1 className="text-2xl font-bold">Two-factor verification</h1><p className="text-slate-600 text-sm">Enter the six-digit code from your authenticator app to continue.</p><form onSubmit={verify} className="space-y-4"><label className="block text-sm font-medium">Authenticator code<input className="input mt-2" inputMode="numeric" autoComplete="one-time-code" maxLength={6} pattern="[0-9]{6}" value={code} onChange={e=>setCode(e.target.value.replace(/\D/g,''))} required /></label><button className="btn w-full" disabled={!ready || !factorId || loading || code.length!==6}>{loading?'Verifying...':'Verify and continue'}</button></form>{error&&<p role="alert" className="text-sm text-red-700">{error}</p>}<button type="button" onClick={signOut} className="text-sm text-indigo-600">Sign out / use another account</button></section></main>;
}
