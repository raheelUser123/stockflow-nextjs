# MFA challenge upgrade (0013 application-only)

Adds `/mfa-challenge` and enforces an AAL2 session for accounts with an enrolled verified TOTP factor on the dashboard, onboarding and supplier page. Users without an enrolled factor can still sign in; this is **step-up enforcement**, not a company-wide mandatory enrollment policy.

## Setup
1. Preserve `.env.local`, `node_modules` and any deployment-specific changes.
2. Enable TOTP MFA in Supabase Auth settings.
3. No new SQL migration. Existing MFA enrollment UI remains at `/dashboard/security`.
4. Run `npm install`, `npm run typecheck`, `npm run build`.
5. Test sign-in with enrolled and unenrolled users, incorrect and correct TOTP, supplier portal, and sign-out.

## Security follow-up
This guards page entry, but sensitive server actions and RPCs must also enforce AAL2 and fine-grained RBAC. Do not describe this as full mandatory MFA for all users or comprehensive permission enforcement.
