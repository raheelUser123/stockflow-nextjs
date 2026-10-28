# StockFlow Pro — Warehouse-aware POS (0021)

## What changed
- POS now requires warehouse selection when company warehouses exist.
- New `checkout_from_warehouse` RPC atomically decreases both global product stock and selected warehouse stock.
- Existing sales, sale items, stock movements and audit records are preserved.
- The old `checkout` RPC remains for companies with no warehouse configured and for backward compatibility.

## Apply
1. Back up Supabase and deploy to staging first.
2. Run `supabase/migrations/0021_warehouse_pos.sql` once in Supabase SQL Editor.
3. Replace project source, preserving `.env.local` and `node_modules`.
4. Run `npm run typecheck`, `npm run build`, then test a sale from a selected warehouse.
5. Use Warehouse Transfers to allocate existing unallocated stock before POS sales.

## Caveats
- Purchase receiving, returns and manual adjustments still require warehouse-ledger integration.
- Existing global-only stock must be allocated to warehouses before checkout.
- Old RPC is retained for compatibility, so a future migration must close that path once all operations are warehouse-aware.
- Test RLS, subscription triggers, concurrent checkouts and rollback on insufficient stock in staging.
- This is not a verified production build; no live Supabase access was available.
