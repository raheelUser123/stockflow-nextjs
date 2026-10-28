# StockFlow Pro — Permission enforcement upgrade (0013)

## Scope
This migration makes custom-role permissions effective in the core mutation RPCs for products, suppliers, categories/customers/warehouses, POS checkout, purchasing and warehouse transfers. It preserves existing SQL function bodies and changes their authorization guards in place. It also adds `my_org_permissions` for the UI to read the current user's effective permission list.

## Install
1. Back up your Supabase database and test on a staging project first.
2. Ensure migrations `0001` through `0012` have been applied.
3. Run `supabase/migrations/0013_permission_enforcement.sql` in Supabase SQL Editor.
4. Test each role in a separate browser/session before production rollout.

## Permission behavior
- Owner and admin: full permissions.
- Manager: current built-in operational permissions.
- Cashier: sales write and limited read permissions.
- Viewer: read-only permissions.
- Supplier: no general operational permissions; supplier portal access remains separate.
- Custom roles: **additive** to built-in permissions. Assign a low-privilege `viewer` base role if you want a narrowly scoped custom role. Do not assume custom roles can remove built-in permissions.

## Tests to perform
- Viewer attempts checkout -> denied.
- Cashier checkout -> allowed.
- Viewer with custom `products.write` can edit product, but not checkout.
- Supplier cannot edit another company's products or purchase orders.
- User from company A cannot operate on company B, even when they have permissions in A.
- Owner/admin retains access.

## Limitations
This is a targeted authorization upgrade, **not** complete end-to-end RBAC enforcement. It does not rewrite every SELECT RLS policy, storage policy, invoice approval, team management, supplier workflow, or client-side navigation gate. Existing manager permissions remain additive. Review these areas before calling the product production-ready.
