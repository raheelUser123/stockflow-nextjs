# StockFlow Pro — Reconciliation Report (Upgrade 0020)

This upgrade adds a read-only `/dashboard/reconciliation` page and a sidebar link.

## Setup

No new SQL migration is required. Copy the updated project files over your existing project (preserve `.env.local`, `node_modules`, and local customizations). Run `npm run typecheck` and `npm run build` before deploying.

## How to use

Sign in as an owner, admin, or manager and open **Reconciliation** in the sidebar. Select the company if you have multiple memberships. The report compares each product's `products.stock` with the sum of its `warehouse_stock.quantity` allocations.

- **Balanced**: global quantity equals allocated quantity.
- **Unallocated**: global quantity exceeds allocations; this may be intentional.
- **Over-allocated**: warehouse allocations exceed global stock; investigate before further stock transactions.

The report is read-only and does not fix balances. It does not verify the stock movement ledger, sales/purchase atomicity, or the accuracy of the underlying inventory quantities. Result caps are 5,000 products and 10,000 allocations; a warning appears if reached. The report is for operational review, not financial audit certification.

## Security and rollout

The page checks authenticated organization membership and restricts its view to owner/admin/manager roles. Queries are tenant-scoped and existing RLS must remain enabled. Take a backup and deploy to staging first. No migration should be rerun. Verify the report using a test product with known warehouse allocations.
