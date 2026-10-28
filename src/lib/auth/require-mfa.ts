import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';

/** Enforce step-up when a verified authenticator is enrolled. */
export async function requireMfa() {
  const supabase = await createClient();
  const { data: { user }, error: userError } = await supabase.auth.getUser();
  if (userError || !user) redirect('/login');
  const { data, error } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  if (error || !data) throw new Error('Unable to verify account security. Try again.');
  if (data.nextLevel === 'aal2' && data.currentLevel !== 'aal2') redirect('/mfa-challenge');
  return { supabase, user };
}
