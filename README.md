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
