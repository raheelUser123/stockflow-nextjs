import { createClient } from '@/lib/supabase/server';
import { redirect } from 'next/navigation';
import { MfaSettings } from '@/components/mfa-settings';
export default async function SecurityPage(){
 const supabase=await createClient();
 const {data:{user}}=await supabase.auth.getUser();
 if(!user)redirect('/login');
 return <div className="max-w-3xl space-y-6"><div><h1 className="text-3xl font-bold text-slate-900">Account security</h1><p className="mt-2 text-slate-500">Protect your account using an authenticator app.</p></div><MfaSettings/></div>;
}
