# StockFlow Pro — MFA enrollment upgrade

This upgrade adds `/dashboard/security` with Supabase TOTP enrollment, QR/manual key, code verification, listing and unenrollment. It does **not** implement mandatory MFA sign-in challenge or custom permission enforcement; those are separate security requirements. Do not market the app as MFA-enforced until the login flow checks `supabase.auth.mfa.getAuthenticatorAssuranceLevel()` and challenges verified factors when `currentLevel` is `aal1` and `nextLevel` is `aal2`.

## Install

Copy the changed files into your current project (preserve `.env.local`, `node_modules`, and any newer local changes). No SQL migration is needed for Supabase Auth MFA enrollment. In Supabase Dashboard, enable TOTP MFA under Authentication > Multi-Factor Authentication (setting labels may vary). Run `npm run typecheck`, `npm run build`, then test enrollment, verification and removal with a test user before deploying. Supabase may require an AAL2 session to unenroll a verified factor.

## Security cautions

- The TOTP secret is sensitive; don't log it or send it to analytics.
- HTTPS is required in production.
- Full MFA enforcement requires a login challenge page and auth guards across protected routes and sensitive server actions.
- This package has not been tested against your deployed Supabase project.
