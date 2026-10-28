# StockFlow Pro — Phase 1

A Next.js + Supabase multi-tenant SaaS starter for inventory management. **Phase 1 foundation only**: inventory, POS, invitations, role editing, MFA enrollment and analytics are **not yet implemented**. Placeholder pages say so explicitly.

## Prerequisites
- Node.js 20+ (22 recommended)
- npm
- A Supabase project

## Quick start
1. `npm install`
2. Copy `.env.example` to `.env.local` and set `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` from Supabase project settings. **Never put service_role keys in NEXT_PUBLIC variables.**
3. In Supabase SQL Editor, execute `supabase/migrations/0001_foundation.sql` once against a fresh project. For production use Supabase CLI migrations instead.
4. In Supabase Authentication > URL Configuration, set Site URL to `http://localhost:3000` and add `http://localhost:3000/auth/callback` to allowed redirect URLs. Configure production URL too before deploying.
5. In Supabase Authentication > Providers > Email, enable email confirmation. Configure SMTP for production.
6. `npm run dev`, open http://localhost:3000, register, confirm email, then create a company.
7. `npm run typecheck`, `npm run lint`, `npm run build`.

## Included
- Light theme responsive landing page, authentication pages, dashboard shell and navigation
- Supabase SSR auth with cookie refresh middleware
- Email/password registration, login, reset and logout
- Company onboarding via atomic Postgres RPC
- Company switcher for memberships
- PKR default, light theme default, branch creation on onboarding
- RLS tenant boundaries, role helper, invitation schema, audit-log schema

## Important boundaries
- Navigation for POS, inventory, suppliers, reports, team and roles is placeholder only.
- The database has role definitions, but invitation acceptance and role assignment RPCs are a future milestone.
- Do not use this starter to process real sales before transaction logic, tests, and a production security review.
- RLS protects the tables but requires additional tests and permission-scoped RPCs as modules grow.
- Organization creation is rate-limited only by Supabase's general auth/project limits; add quotas and abuse controls before public SaaS launch.
- A deployment requires real Supabase credentials; they are not bundled.

## Phase 2 backlog
Products/variants/categories, warehouses and stock movement ledger, suppliers, purchase orders, receiving and adjustments. Later: POS, receipts, payments, returns and analytics.

## No-login demo (new)

Start with `npm install && npm run dev`, then open **http://localhost:3000/demo**.
This route does not require Supabase credentials or registration. You can try products,
suppliers and warehouse CRUD, a simulated POS checkout, sales, analytics, CSV exports,
settings and activity history. Demo data persists **only in the current browser's localStorage**.
It is **not secure**, does not sync across users/devices, and is not suitable for real business data.
The authenticated Supabase-backed Phase 1 foundation remains available at `/login` and `/dashboard`.

**Not implemented yet:** production multi-tenant inventory/stock ledger, real POS payment processing,
refunds, supplier portal, full RBAC management, real-time sync, comprehensive reports and production audit trails.
These require additional migrations, server-side business logic and tests.

## Operational MVP upgrade (migration 0002)
Run `supabase/migrations/0002_operations.sql` **after** migration 0001. This adds live Supabase-backed product CRUD (archive instead of destructive delete), supplier CRUD, basic POS checkout with stock validation and atomic inventory deduction, sales history, basic analytics, and activity logs. These routes are available under `/dashboard/products`, `/dashboard/suppliers`, `/dashboard/pos`, `/dashboard/sales`, `/dashboard/analytics`, and `/dashboard/audit`.

**Scope limits:** This is an operational MVP, **not a finished enterprise POS**. Card payments are marked as externally collected and no gateway is connected. Taxes, refunds, purchase orders, full warehouse management, supplier portal, invitations, advanced RBAC, MFA enrollment, stock counting, subscriptions, advanced reporting, and receipts/printing are not yet implemented. Do not process production financial transactions until testing and security review. Default company selection is the first membership for module routes; multi-company module routing still needs a persistent organization context.

## Extended MVP (migration 0003)

Apply `supabase/migrations/0003_extended.sql` **after** 0001 and 0002. This adds warehouses, customers, categories, purchase orders, purchase receiving, warehouse stock schema, stock transfer schema, sales return schema, team role updates, and company settings RPCs.

Pages: `/dashboard/warehouses`, `/dashboard/customers`, `/dashboard/categories`, `/dashboard/purchases`, `/dashboard/team`, `/dashboard/roles`, `/dashboard/settings`.

### Limitations (read before production use)

This is an extended development MVP, **not a finished production POS/ERP**. Warehouse stock allocation and transfers, returns, invoicing/receipt printing, multi-line purchase order UI, supplier self-service, user invitation acceptance, billing/subscriptions, MFA enrollment, per-branch POS registers, configurable taxes, accounting integration, and automated end-to-end tests are not implemented. POS records externally collected payments; it does not charge cards. The `products.stock` value remains the aggregate source for POS; warehouse_stock is schema-only until warehouse allocation workflows are implemented. Supplier records are company-scoped, but suppliers do not yet have a separate access-controlled portal. Role changes only work for existing members. Never use live financial data before testing and hardening all workflows.

### Setup

1. Keep your own `.env.local` with `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `NEXT_PUBLIC_SITE_URL`.
2. Run migrations in order (0001, 0002, 0003) in the Supabase SQL Editor. Do not rerun already applied migrations.
3. `npm install`, `npm run typecheck`, `npm run build`, `npm run dev`.
4. Configure Supabase Auth site URL and allowed redirect URLs for localhost and your deployment.
5. Test with at least two organizations and two users to validate tenant isolation before any public launch.

**Verification:** Dependency installation could not finish in the artifact environment, so TypeScript/build/runtime and database migration execution have not been verified. Resolve any local errors before deploying.

## Team and custom role extension (migration 0004)

After 0001, 0002, and 0003, run `supabase/migrations/0004_team_roles.sql` once. Open `/dashboard/team` or `/dashboard/roles`.

- Add a **previously registered, email-confirmed** user to the current company by email, using a built-in role. This does **not** send email invitations or create auth accounts.
- Create, edit, delete custom permission sets; assign or remove a custom role from a company member.
- Change built-in roles and remove members, with protected owner membership.
- All mutation functions check authenticated owner/admin role and write audit entries.

**Important**: custom permission definitions are stored and `has_org_permission` is available for future RPCs. Existing operational RPCs still authorize via built-in roles; custom permissions do not automatically override them. This is not full custom RBAC enforcement. Supplier self-service, MFA enrollment, invite emails, subscription billing, refunds, warehouse transfers and full accounting remain unimplemented. Do not use for production until reviewed and tested.

## Migration 0005 — Product images

Run `supabase/migrations/0005_product_images.sql` **once**, after 0001–0004. It creates a private Supabase Storage bucket (`product-images`), adds `products.image_path`, and protects image uploads/deletes with organization role checks. Products page now supports image upload (JPG/PNG/WebP, max 5MB); POS and product table show signed images. No service-role key is needed in the browser.

The upload and product save are separate requests. If save fails, the UI attempts to remove the uploaded image; orphaned images from interrupted requests may require a periodic cleanup job. The current image is replaced when editing with a new upload; old files are not automatically garbage-collected. This is a development release, not a fully audited production deployment.

## Migration 0006: Stock adjustments and sales returns

Run `supabase/migrations/0006_returns_adjustments.sql` after migrations 0001–0005. The dashboard includes **Stock Adjustments** and **Sales Returns**. Both use SECURITY DEFINER RPCs with role checks and audit logs. Returns restock items and record the calculated refund *liability*, but **do not actually refund money** via a payment gateway. Existing sales totals remain gross; calculate net sales by subtracting returns. This migration is not a warehouse transfer system.

### Current limitations / production blockers

This repository is an evolving MVP, **not a finished enterprise SaaS**. There is no real subscription billing, supplier self-service portal, transactional email invitations, end-to-end custom-permission enforcement across legacy RPCs, full warehouse stock accounting, integrated card gateway, cash reconciliation, or verified production build. Product photos require migration 0005 and Supabase Storage. Before live business use, run `npm install`, `npm run typecheck`, `npm run build`, and tenant-isolation/stock-concurrency tests against a staging Supabase project. Apply migrations to a backed-up database; test with a fresh company and a second account. Never place Supabase service-role credentials in `NEXT_PUBLIC_*` environment variables.

## 0008 reporting / receipt upgrade
- `/dashboard/sales` now links each receipt to `/dashboard/sales/[id]`.
- Receipt detail includes server-side tenant membership checks, line items, and browser print / Save PDF.
- `/dashboard/analytics` includes an interactive daily revenue chart with 7/14/30 day filters.
- This release requires **no new SQL migration**. It uses the existing `sales`, `sale_items`, `products`, `organizations` tables.
- Printing uses the browser print dialog, not a server-generated PDF or thermal-printer driver.
- No card gateway, supplier portal, subscription billing, or full integration tests are included in this increment.

## Upgrade 0008 — secure team invitations

Run `supabase/migrations/0008_invitations.sql` **once** in Supabase SQL Editor after 0007. In Team, generate an invitation link and share it securely with the specified email address. The recipient registers/verifies their email (if needed), signs in, opens the link and accepts. Invitations expire after 7 days, are single-use and are matched to the authenticated verified email. Email delivery is **not** integrated; links are shared manually. Do not paste invitation links into public channels.

This release does not implement supplier self-service, SaaS billing or end-to-end custom permission enforcement. Test migrations on staging before deploying to production.

## Migration 0009 — Supplier Portal

Run `supabase/migrations/0009_supplier_portal.sql` in Supabase SQL Editor **once** after migration 0008. This adds supplier-account links, a supplier-scoped read-only purchase-order portal, audit-logged linking/unlinking, and tightens broad read policies so supplier-only accounts cannot read general company records.

1. In **Team**, invite the supplier's email with role **Supplier**. Share the invitation link securely; email delivery is not automated.
2. Create the matching supplier record under **Suppliers** (if not already present).
3. Visit **Supplier Access** and link the supplier-role member to the supplier record.
4. Supplier signs in and visits `/supplier`. They can see their own purchase-order summaries.

**Scope:** This upgrade provides read-only supplier order summaries and administrator-managed supplier links. Delivery confirmations, supplier invoice uploads, automated email delivery, full custom-role enforcement, subscription billing, and production integration tests are **not** included. Do not treat it as a final enterprise release. Back up the production database and test on staging before applying the migration.
