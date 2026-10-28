# StockFlow Pro — Billing History Upgrade (0015)

This upgrade introduces an append-only billing event ledger and billing activity UI. It records trial starts, and prepares an auditable history for future verified billing webhooks. **No payment gateway, paid subscription activation, webhook processing, or plan-limit enforcement is included.**

## Install
1. Back up Supabase and test on staging.
2. Run `supabase/migrations/0015_billing_history.sql` after 0014.
3. Update project source, preserving `.env.local` and `node_modules`.
4. Run `npm run typecheck && npm run build`, then deploy.
5. Open `/dashboard/billing` as owner/admin.

## Security
The browser can only read its own organization's billing events if the user is owner/admin. No authenticated client can insert/update/delete events. Future payment integrations must verify webhook signatures, deduplicate external_event_id, and atomically update subscription state and event history from a trusted backend. Do not treat trial-start events as payment evidence.
