'use server';

import { createClient } from '@/lib/supabase/server';
import { revalidatePath } from 'next/cache';

const allowedRoles = ['admin', 'manager', 'cashier', 'supplier', 'viewer'] as const;

/** Create an invitation under the caller's authenticated Supabase session.
 * The database RPC enforces organization membership and hashes the token.
 * Delivery failures return a manual link; they never claim an email was sent.
 */
export async function inviteMemberWithEmail(org: string, email: string, role: string): Promise<{
  error?: string;
  status?: 'sent' | 'manual';
  link?: string;
  warning?: string;
}> {
  if (!/^[0-9a-f-]{36}$/i.test(org)) return { error: 'Invalid organization' };
  const normalizedEmail = email.trim().toLowerCase();
  if (normalizedEmail.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalizedEmail)) return { error: 'Invalid email' };
  if (!allowedRoles.includes(role as typeof allowedRoles[number])) return { error: 'Invalid role' };

  const db = await createClient();
  const { data: { user }, error: authError } = await db.auth.getUser();
  if (authError || !user) return { error: 'Sign in required' };
  const { data: token, error } = await db.rpc('create_team_invitation', {
    p_org: org, p_email: normalizedEmail, p_role: role,
  });
  if (error) return { error: error.message };
  if (typeof token !== 'string') return { error: 'Invitation could not be created' };

  const base = process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/$/, '');
  if (!base || !/^https?:\/\//.test(base)) return { error: 'Configure NEXT_PUBLIC_SITE_URL to generate invitation links' };
  const link = `${base}/invite?token=${encodeURIComponent(token)}`;
  const apiKey = process.env.RESEND_API_KEY;
  const from = process.env.INVITATION_FROM_EMAIL;
  if (!apiKey || !from) return { status: 'manual', link, warning: 'Email provider not configured. Copy the invitation link and send it securely.' };

  try {
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from,
        to: [normalizedEmail],
        subject: 'You have been invited to StockFlow Pro',
        text: `You have been invited to join a company on StockFlow Pro as ${role}.\n\nAccept your invitation: ${link}\n\nThis link expires in 7 days and can be used only by the invited email address. If you were not expecting this, ignore this message.`,
      }),
      cache: 'no-store',
    });
    if (!response.ok) {
      return { status: 'manual', link, warning: `Email delivery failed (${response.status}). Share the link manually.` };
    }
    revalidatePath('/dashboard');
    return { status: 'sent' };
  } catch {
    return { status: 'manual', link, warning: 'Email delivery could not be confirmed. Share the link manually.' };
  }
}
