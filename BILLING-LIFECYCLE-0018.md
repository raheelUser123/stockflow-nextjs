# StockFlow Pro — Billing lifecycle upgrade 0018

This update adds Stripe event signature verification (existing), canonical subscription retrieval, event-id deduplication, timestamp ordering, customer/subscription identity checks, and records cancel-at-period-end plus current billing period end.

## Apply
1. Back up production database and application. Test on staging first.
2. Run `supabase/migrations/0018_billing_lifecycle.sql` once in Supabase SQL Editor.
3. Deploy updated `src/app/api/billing/webhook/route.ts` with existing server-only `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `SUPABASE_SERVICE_ROLE_KEY` and `NEXT_PUBLIC_SUPABASE_URL`.
4. Configure Stripe webhook to send `checkout.session.completed`, `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted`, `invoice.paid`, and `invoice.payment_failed`.
5. Run `npm run typecheck && npm run build` and use Stripe CLI/test mode to exercise event replays, cancellation, failed payments, and renewal.

## Limitations / important behavior
- A failed payment updates the local status only after Stripe changes the canonical subscription status (which can remain `active` during retries). Do not treat invoice failure alone as a definitive suspension.
- This does **not** implement trial-expiry access gating or a full subscription entitlement middleware.
- Existing subscription associations are not automatically replaced: migration intentionally rejects attempts to attach a different Stripe subscription to an organization. Manual, audited reconciliation is required when replacing subscriptions.
- Stripe event ordering is handled by the database timestamp guard; events with the same timestamp still depend on the latest fetched Stripe state.
- If your Stripe API version differs, verify `invoice.parent.subscription_details.subscription` exists; invoice events without it are ignored.
- Test against a staging Supabase project; the code has not been verified against a live Stripe account.
