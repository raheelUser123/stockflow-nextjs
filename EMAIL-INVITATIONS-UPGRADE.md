# StockFlow Pro — Automatic Email Invitations Upgrade

This update replaces the manual-only invitation form with email delivery using Resend's HTTPS API. It uses the existing `create_team_invitation` SQL RPC from migration `0008_invitations.sql`, so **no new SQL migration** is needed.

## Setup

1. Create a Resend account and verify a domain you control.
2. Set `RESEND_API_KEY` and `INVITATION_FROM_EMAIL` in your Vercel environment (and optionally `.env.local`). The sender must be verified by Resend.
3. Set `NEXT_PUBLIC_SITE_URL` to your deployed app's **actual HTTPS origin**, e.g. `https://inventory.example.com`. Do not include a trailing slash or a path.
4. Redeploy the app.
5. From the Team page, invite a verified-email user. Verify delivery and acceptance with a fresh test account.

Without the two email variables, the form still creates an invitation and shows a one-time link to share manually. Failed provider responses also return the link rather than falsely claiming success.

## Security notes

- Never expose `RESEND_API_KEY` to the browser or commit it to Git.
- The database RPC enforces owner/admin access and hashes invitation tokens. Invitations are single-use, expire in seven days, and are bound to the invited verified email.
- The email provider accepting a message does not guarantee inbox delivery. Check Resend delivery logs if needed.
- Rate limiting, invitation resend/revoke UX, abuse monitoring, and email delivery webhooks are recommended before public SaaS launch.

## Verification

Run `npm install`, `npm run typecheck`, `npm run build`. Test a manual invitation with no Resend keys, then email sending with a verified domain, and acceptance using the invited account. Run these tests in staging before production deployment.
