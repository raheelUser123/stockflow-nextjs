# Upgrade 0016 — Stripe Billing Checkout (beta)

1. Back up Supabase, then run `supabase/migrations/0016_stripe_billing.sql` in SQL Editor.
2. Install dependencies with `npm install` (adds Stripe SDK).
3. In Stripe create **monthly recurring prices in PKR** matching approved amounts, and set `STRIPE_PRICE_STARTER`, `STRIPE_PRICE_PROFESSIONAL`. Confirm Stripe supports your account, country, and PKR subscription settlement before selling.
4. Add `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `SUPABASE_SERVICE_ROLE_KEY`, and `NEXT_PUBLIC_SITE_URL` to Vercel server environment variables. Never prefix secret keys with NEXT_PUBLIC_.
5. Configure Stripe webhook to `https://YOUR_DOMAIN/api/billing/webhook` for `checkout.session.completed`, `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted`.
6. Test checkout, webhook delivery, duplicate webhooks, failed payments and cancellation on staging before production. `npm run typecheck && npm run build`.

**Limitations:** This is a billing integration foundation, not a complete subscription billing system. No customer portal, invoices, metered usage, plan-limit enforcement, dunning, refunds, proration or guaranteed event ordering. Webhooks are signed and event IDs idempotent, but out-of-order subscription events need hardening. Only Stripe Checkout plans starter/professional are offered. Existing subscriptions cannot purchase again. Stripe may not be available to businesses in all countries. No live payments were tested.
