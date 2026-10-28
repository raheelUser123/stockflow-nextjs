# Upgrade 0017 — Stripe customer portal + plan quantity limits

1. Back up your Supabase database and test on staging.
2. Run only `supabase/migrations/0017_plan_limits.sql` after 0016.
3. In Stripe Dashboard enable the **Customer Portal**, and configure permitted cancellation, payment method, invoice, and subscription changes. Do not enable switching plans until webhook metadata and plan mapping support it.
4. Ensure Vercel has `STRIPE_SECRET_KEY` and `NEXT_PUBLIC_SITE_URL` set; never expose the Stripe secret in the browser.
5. Deploy the updated Next.js code. Owners/admins with a Stripe customer can click **Manage subscription & payment methods** on Billing & Plans.
6. Verify `npm run typecheck`, `npm run build`, portal access, cross-tenant denial, concurrent product creation at the limit, warehouse/member limits, and webhook cancellation on staging.

## Scope and limitations
- DB triggers enforce **new** products, warehouses, and organization members based on plan limits. Existing over-limit organizations are not automatically deleted or suspended.
- These triggers may reject a company's first warehouse/member if its current plan already meets its cap. Verify initial company onboarding behavior.
- Customer Portal manages payment methods/invoices/cancellation using Stripe's hosted interface. No in-app tax invoices, refunds, or dunning.
- Existing webhook processing still needs out-of-order event protection and thorough Stripe lifecycle tests. Plan changes initiated inside Stripe Customer Portal must remain disabled until supported.
- Trial expiration, feature entitlements, all RBAC coverage, and full production readiness remain separate work.
