# 0019 — Subscription entitlement enforcement

## Apply safely
1. Back up the Supabase database and deploy to staging first.
2. Run `supabase/migrations/0019_subscription_entitlements.sql` in Supabase SQL Editor.
3. Deploy the updated Next.js source, preserving `.env.local` and secrets.
4. Run `npm run typecheck && npm run build` locally and test all workflows.

## Expected behavior
- Trialing companies may write business records until `trial_ends_at`.
- Active subscriptions may write until `current_period_ends_at` when present.
- Canceled subscriptions retain access only through the remaining paid period.
- Past-due/expired subscriptions are read-only for core business tables.
- Free plans in active/trialing status retain write access within existing plan limits.
- Existing data is not deleted. Billing management remains available.

## Essential test matrix
1. Trialing (future expiry): create product, supplier, checkout sale.
2. Trialing (past expiry): writes blocked; dashboard/billing reads allowed.
3. Active subscription: writes allowed; past-due: writes blocked.
4. Canceled before period end: writes allowed; after period end: blocked.
5. Organization A cannot modify organization B's data (RLS still applies).
6. Confirm stock receiving, sales returns, transfers, POS, and invoices.
7. Verify Stripe webhook events still update subscription status.

## Limitations
This is not a certified production release. The full application has not been built or tested against live Supabase/Stripe in this environment. The prior warehouse/POS reconciliation issue and comprehensive authorization audit still need validation. Payment gateway availability and actual subscription events depend on your Stripe account configuration.

## Rollback (staging only; assess impact first)
Remove `trg_subscription_write` triggers from the 13 tables listed in migration 0019. This removes subscription write gating; it does not change billing status or data.
