# StockFlow Pro — Subscription Tracking (0014)

This upgrade adds subscription plan catalog, company trial records, usage dashboard, and tenant-safe read policies. **It does not charge cards, process subscriptions, enforce limits, or offer self-service plan upgrades.** The PKR prices are sample pricing and must be reviewed before publishing.

## Install
1. Back up production Supabase and test on staging.
2. Apply `supabase/migrations/0014_subscriptions.sql` in Supabase SQL Editor, after migrations 0001–0013.
3. Copy source changes without replacing `.env.local` or `node_modules`.
4. Run `npm run typecheck`, `npm run build`, then deploy.
5. Open `/dashboard/billing` as an owner or admin.

## Security and follow-up
- All subscriptions are read-only to authenticated company members through RLS. The UI restricts billing display to owners/admins.
- Subscription updates require trusted server-side billing integration, webhook signature validation, idempotency, and an event ledger.
- Existing organizations are assigned a 14-day trial measured from original creation time. This may already have expired for older companies; verify before enabling enforcement.
- No automatic suspension or usage limits are enforced. Add those atomically to mutation RPCs before selling plans.
- `subscription_overview` queries products and warehouses; migrations 0002 and 0003 are prerequisites.
