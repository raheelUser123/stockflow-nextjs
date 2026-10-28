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

# stockflow-nextjs
