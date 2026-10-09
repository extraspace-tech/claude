# Demo backend inventory (`Backend Demo/backend`)

Written 2026-10-09 from a read-only scan of `/Users/waiyanmin/Projects/Extra Space/Backend Demo/backend`
(git `extraspace-tech/backend`, HEAD `6be4474`, 2026-10-08). All paths below are relative to that
folder unless they start with `/`. "Spec" means `.claude/backend-spec/` inside it. "Inferred" marks
anything I concluded but did not see stated or run. Nothing was installed, run or checked out.
No secret values are copied here; env vars are named only.

---

## 1. Shape and maturity

### 1.1 Size per folder (tracked files only)

| Folder | Files | Lines | What it is |
|---|---|---|---|
| `src/` | 276 | 30,922 | Express 5 API. Services 18.6k lines, controllers 5.6k (178 route files), hand-written OpenAPI 2.6k, tests 2.7k |
| `admin-ui/src/` | 77 | 16,325 | React admin SPA. 11.4k of it is the Cowork Manager pages, 2.7k the BizPlus pages, ~2.2k the generic CRUD shell |
| `web-app/src/` | 42 | 2,906 | React "mobile app look-alike" prototype |
| `prisma/` | 22 | 5,688 | `schema.prisma` (1,998 lines, 69 models), 13 migrations (2,253 SQL lines), seeds |
| `docs/` | 6 | 4,225 | Design/plan docs: `facility-booking/DESIGN.md`, `bizplus-credits/PLAN.md` (+TEST-SCENARIOS), `cowork-manager/PLAN.md` |
| `.claude/` | 27 | 27,647 | The handover spec (`backend-spec/`, 27.6k lines) + a skill |
| `.agents/` | 47 | 5,680 | Vendor skills only (neon, upstash) — no app code |
| `api/` | 1 | 16 | Vercel serverless entry that wraps the Express app |
| `public/` | 5 | — | `facility-images/bizplus/*` static photos |

Total: 541 tracked files.

### 1.2 Git history

```
2026-10-08 ExtraSpace Tech Add backend handover spec for C# re-implementation       (22 files, +27,637)
2026-10-08 ExtraSpace Tech Cowork Manager: mobile app API, layout conversions, ...   (46 files, +3,358 / -240)
2026-10-06 ExtraSpace Tech Initial import of platform-backend                        (500 files, +79,340)
```

- 3 commits, 1 author (`ExtraSpace Tech <tech@extraspaceasia.com>`), 1 branch (`main`).
- The first commit is an **import**: the code was built elsewhere, inside a larger workspace that
  also holds the Flutter app and 8 older MongoDB services (`CLAUDE.md` mentions `../CLAUDE.md`,
  `extracted/backend_services/`, `extracted/frontend/...`, `sitelink-connector-service`). The real
  history is not in this repo.
- The real timeline comes from the migration names and the dated plan sections:

| Date | What landed | Evidence |
|---|---|---|
| 2026-09-16 | Init schema: storage units, quotes, reservations, leases, leads, admin | `prisma/migrations/20260916160742_init` |
| 2026-09-17 → 09-24 | Live SiteLink verification against the `LSETUP` sandbox; SETUP2 workspace site | `README.md` "Known simplifications" |
| 2026-09-21 | Rewards catalog | migration `..._add_reward_catalog_and_redemptions` |
| 2026-09-28 | Facility booking (meeting rooms) | migration + `docs/facility-booking/DESIGN.md` status |
| 2026-09-30 → 10-02 | BizPlus credit wallet, deployed to prod 10-01 | `docs/bizplus-credits/PLAN.md` §7.1–7.16 |
| 2026-10-05 → 10-08 | Cowork Manager (port of a Claude artifact), deployed 10-05, more on 10-06/07/08 | `docs/cowork-manager/PLAN.md` §7–9, last 5 migrations |
| 2026-10-08 | Handover spec for a C# rebuild | last commit |

So the whole thing was built in **about 3 weeks**, at a very fast pace. The plan docs show it was
built with Claude Code (e.g. `docs/cowork-manager/PLAN.md` §7.8: "the auto-mode classifier blocks
Claude from production actions").

### 1.3 Verdict: production-shaped prototype, not a clickable mock

It is much more than a click-through demo:

- Real SiteLink SOAP integration (18 operations), request fields checked against the live WSDL,
  full tenant → reserve → move-in → ledger flow verified live on the `LSETUP` sandbox
  (`README.md` lines 144–157).
- Real Stripe hosted Checkout + one signature-verified webhook for 5 payment flows.
- It **is deployed**: Vercel serverless + Neon Postgres + Upstash Redis, called "production" in the
  docs (`vercel.json`, spec `00` §12, `docs/bizplus-credits/PLAN.md` §7.13,
  `docs/cowork-manager/PLAN.md` §7.8). Real Cowork data was imported into that production DB on
  2026-10-05: 97 units, 53 tenants, 135 licences.

But it is **not production-grade**:

- No customer authentication. `POST /api/v1/me/login` issues a 30-day JWT for any email, with no
  password (spec `01` §3.1 and line 188 "effectively account takeover by email").
- No ownership checks on storage routes: `GET /api/v1/me/spaces?userId=<email>` reads any
  customer's data; reservations can be cancelled by id by anyone with the public anon key
  (spec `04` §7 item 1, spec `06` §7 item 1).
- Client-reported payments are trusted for storage reserve / move-in (spec `04` §7 item 2). The
  `web-app` prototype does a **real** SiteLink move-in with a fake `stripeSessionId`
  (`web-app/src/pages/MoveInPage.tsx` lines 76–97, 209).
- Tests cover only pure maths: 9 jest files, 189 test cases (`credit-engine`, `facility-pricing`,
  `booking-policy`, `cowork-engine`, `cowork-import`, `cowork-layout`, `cowork-mail`,
  `cowork-app-view`, one mapper). **No** tests for SiteLink, reservations/leases, the Stripe
  webhook, admin CRUD, or any DB or HTTP path. `admin-ui` and `web-app` have no tests.
- No CI config, no committed git hooks (`package.json` runs `husky` but there is no `.husky/`).
- Admin security gaps listed in spec `12` §7: permission failure returns 401 not 403, all reads
  unguarded, no session regeneration on login, cookie without `Secure`, CORS reflects any origin
  with credentials.
- Rate limit is in-memory per instance (`src/core/server.ts` line 97), so on Vercel it is per
  lambda (inferred).

### 1.4 Stable vs churning

| Area | State |
|---|---|
| Storage flow (sites, units, quotes, reservations, move-in, My Spaces), leads, viewings | Oldest (Sept 16–24). Stable, but has the security/trust gaps above. Not used by the real Flutter app in production (see §7). |
| CMS, rewards, size estimator, recommendations, promotions | Stubs. Stable because nobody works on them. |
| Admin generic CRUD + dashboard | Stable. |
| Facility booking | Built Sept 28 – Oct 2. Complete, unit-tested. |
| BizPlus credits | Built Sept 30 – Oct 2. Complete, unit-tested, deployed. |
| **Cowork Manager** (inventory, licences, billing, outbox, app Workspace API) | **Churning.** Built Oct 5–8, with new features on each of the last 4 days (UI parity, layout conversions, mobile Workspace, unit on every charge). Its biggest question (C1: does SiteLink already bill these suites?) is still open and could remove half of it. |

---

## 2. Feature list

Route counts come from `spec/reference/endpoints.md` (178 routes total; it matches the 178 route
files under `src/controllers/**/methods/`, so no code route is missing from the spec).

| # | Feature (spec doc) | What it does | Routes | Main tables | External | Code state |
|---|---|---|---|---|---|---|
| 01 | Auth & identity | Mobile auth: raw `Authorization` header holds either an anonymous API key (`MOBILE_API_KEY` / `WEB_ANON_API_KEY`) or an HS256 customer JWT. `POST /api/v1/me/login` creates or finds the `Customer` by email, searches every active site in SiteLink for an existing tenant, pulls their leases in, returns a 30-day JWT. Also the whole HTTP pipeline (helmet, CORS, request id, rate limit, error envelope). | 1 | `Customer`, `SiteLinkTenantLink` | SiteLink | Complete, **insecure by design** (email-only login) |
| 02 | SiteLink integration | SOAP 1.1 client for SiteLink CCWs 3.5, DataSet XML parsing, 18 operations (sites, units, pricing, discount plans, promotions, tenants, ledgers, waiting-list reservations, move-in, cash payment posting). Per-location corp logins. Never calls a card-carrying operation. | 0 | `UnitSyncCursor` (indirect) | SiteLink | Complete. Request names verified on live WSDL; response columns verified only for operations exercised live. |
| 03 | Units, sites, quotes | Site list, storage types, unit sizes, unit search/detail/availability, 1/3/6/12-month rental-plan quotes, reserve charge, workspace-type tabs. Local unit cache synced from SiteLink every 15 min (Redis-locked). | 9 | `Site`, `StorageType`, `UnitSize`, `Unit`, `UnitSyncCursor`, `RentalPlanQuote` | SiteLink, Redis | Complete. Admin Units page re-syncs all sites on every page load (spec `12` §7 item 8). |
| 04 | Reservations, leases, My Spaces | SiteLink waiting-list reservation (+ preview, cancel), move-in direct or from a reservation (+ preview), signed agreements, My Spaces (Storage tab object, Workspace tab bare list, live-synced from SiteLink). | 7 | `Reservation`, `Lease`, `SignedAgreement`, `Transaction` | SiteLink | Works live on sandbox. No ownership checks, trusts client money, no reservation expiry job, retry-on-`-95` workaround for fake seeded tenant ids. |
| 05 | Payments / Stripe | Stripe hosted Checkout + the one webhook, dispatching 5 `metadata.kind` flows: My Bills, facility booking, facility extension, credit package, cowork invoice. My Bills posts the paid amount to SiteLink as a cash payment. | 2 | `Transaction` (+ booking / purchase / checkout tables of other features) | Stripe, SiteLink | Complete for the 5 flows. TODO: My Bills reconciliation when SiteLink posting fails (`src/services/domain/payment.service.ts` line 220). No webhook event-id dedupe. |
| 06 | Leads & viewings | "I'm interested" enquiries (storage or cowork unit), viewing appointments with fixed 09:00–17:30 half-hour slots. | 7 | `Lead`, `ViewingAppointment` | — | **Thin.** No ownership checks, no double-booking guard, no opening hours, `customerId` never set (spec `06` §7). |
| 07 | Facility booking | Hourly booking of meeting rooms / event spaces / hot desks: catalogue, free slots, server-side pricing (promo codes, credits, member rate, after-hours surcharge, cleaning fees, deposit, same-day cutoff), slot hold (~33 min) with a Postgres EXCLUDE overlap guard, Stripe checkout, reschedule, extend, cancel/refund under two policies, lifecycle job. Replaces Lucy's `FacilityBookingService`. | 13 | `BookableFacilityType`, `BookableFacility`, `FacilityImage/Feature/Service/OperatingHours/Blackout`, `FacilityPromoCode(+Type)`, `FacilityAdditionalCharge`, `BookableFacilityTypeAmenity`, `FacilityBooking`, `…LineItem`, `…Invitee`, `…Adjustment` (15) | Stripe, Redis | Complete, complex, unit-tested (pricing + policy). |
| 08 | BizPlus credits | Credit wallet per (customer, site): buckets for monthly allowance with capped carry-forward, lump-sum contract, packages, complimentary, refund credits; spend soonest-expiring first; month-end rollover/expiry (lazy + nightly job); package purchase in app; admin BizPlus dashboard (enrol, adjust, grant, admin booking, deposits, month-end run). Single writer: `credit-wallet.service.ts`. | 27 (22 admin + 5 mobile) | `CreditAccount`, `CreditBucket`, `CreditLedgerEntry`, `FacilityBookingCreditDraw`, `CreditPackage`, `CreditPackagePurchase`, `CreditRolloverRun` | Stripe | Complete, unit-tested, deployed. |
| 09 | Cowork inventory & licences | Back office for the BizPlus co-working centre (SETUP2): suites / hot desks / fixed desks, split a suite into desks and revert, tenants + contacts, licences (move-in, end, renew), document links, notes, floor board, occupancy, whole-site snapshot, BizPlus room/credit actions, spreadsheet + artifact import. | 55 (admin) | `CoworkUnit`, `CoworkConversion`, `CoworkUnitGap`, `CoworkTenant`, `CoworkContact`, `CoworkLicence`, `CoworkDocument`, `CoworkTenantNote` | — (by design no SiteLink) | Complete for admin, newest code, still changing. |
| 10 | Cowork billing, outbox, app Workspace | Monthly billing runs with proration, invoices + numbering, tenant charges, price list, payments with allocation, bank-statement CSV import + matching, statements/aging, late fees, void with audit, email outbox (reminders, house rules) sent by the admin via `mailto:`, daily automation cron. Mobile: `GET /me/cowork`, pay cowork invoices by Stripe, guest list of workspace units. | 30 (26 admin + 4 mobile) | `Invoice`, `InvoiceLine`, `CoworkPayment`, `PaymentAllocation`, `TenantCharge`, `ChargeCatalogItem`, `CoworkBillingSettings`, `CoworkBillingRun`, `InvoiceNumberCounter`, `OutboxEmail`, `CoworkInvoiceCheckout` | Stripe | Built, but `autoBilling` is off until C1 is answered. No email sending at all. |
| 11 | Rewards, CMS, misc | Rewards points wallet + catalog + vouchers (only automatic credit: 2,000-point welcome bonus at first login), blog posts + FAQs (2 public reads), size estimator (keyword heuristic), recommendations (budget scoring), health, app-internal promotions (CRUD only, nothing reads them), cron routes, seeds. | 13 + 4 cron | `RewardAccount`, `RewardTransaction`, `Reward`, `RewardRedemption`, `BlogPost`, `Faq`, `SizeEstimatorRule`, `RecommendationLog`, `Promotion` | — | **Stubs** (README module table). |
| 12 | Admin console | Session-cookie login, RBAC (roles → permissions, "Super Admin" bypass by role name), audit log on every mutation, resource registry (44 resources) driving generic list/create/edit/delete, analytics dashboard. | 10 | `AdminUser`, `Role`, `Permission`, `RolePermission`, `AuditLog` | Redis (sessions) | Complete. No UI to assign permissions to roles; reads not permission-gated. |

Features in code but not in the spec: **none found** (route files = endpoint catalogue = 178).
Supporting scripts are covered inside docs 03 and 09: `src/scripts/resync-site-units.ts`,
`import-cowork.ts`, `cowork-tenant-profiles.ts`.

### 2.1 Spec claims I checked against the TS source

| Spec claim | Result |
|---|---|
| 178 routes (`endpoints.md`) | ✔ 178 route files under `src/controllers/**/methods/` |
| 69 models, 107 `DOUBLE PRECISION` money columns, 41 `@updatedAt`, 19 `@db.Date` (spec `00` §6) | ✔ all four counts match `prisma/schema.prisma` / `reference/schema.sql` |
| `reference/schema.prisma` is the data model | ✔ byte-identical to `prisma/schema.prisma` |
| 44 resource definitions (spec `12`) | ✔ 44 `key:` entries in `src/services/admin/resource-registry.ts` |
| Rate limit 300 / 60 s, JSON body 2 MB (spec `00` §2) | ✔ `src/core/server.ts` lines 97–99, 121 |
| Facility hold ~33 min (spec `07` §1.1) | ✔ `HOLD_TTL_MS = CHECKOUT_TTL_MS (31 min) + 2 min`, `facility-booking.service.ts` lines 38–41 |
| Credit tables have one writer (spec `08`) | ✔ only `credit-wallet.service.ts` calls create/update on `creditAccount/creditBucket/creditLedgerEntry` |
| Cron defaults (spec `00` §10) | ✔ `src/config/env.ts` lines 57–83 |
| Every admin mutation is audited (spec `00` §4) | ✔ mostly: 16 mutating route files have no audit call, but they are previews/quotes/login, or audit inside the service (e.g. `voidInvoice` → `cowork-billing.service.ts` line 556) |

Drift found:

- `reference/openapi.json` has 54 operations for 55 `/api/v1` routes: `GET /api/v1/me/rewards/history`
  (added in commit `2f96a7e`) is missing from it.
- `src/middlewares/mobile-auth.ts` comment and OpenAPI say "Core issues the session token". Not
  true: this service issues it (`src/controllers/v1/me/methods/login.post.ts`). The spec already
  flags this (spec `01` lines 39–41).
- `README.md` contradicts itself on reservation cancel (line 158 "cancels SiteLink's entry" vs
  line 257 "only cancels the local hold"). Code calls `ReservationUpdate_v4`. Spec `04` §7 item 14
  flags it.
- Vercel runs unit sync **once a day** (`vercel.json`: `/api/cron/sync-units` at `0 3 * * *`), not
  every 15 minutes. The 15-minute schedule only applies to the in-process scheduler (Docker/local).
  The spec states both (spec `00` §10), but anyone reading only "every 15 min" would be misled.
- The `Dockerfile` `admin-ui-build` stage copies only `admin-ui/`, but `admin-ui` imports
  `../src/services/domain/cowork-engine.ts` (alias `@engine`, `admin-ui/vite.config.ts`). So the
  Docker build of the admin UI most likely fails since the Cowork pages were added (inferred,
  not run). Vercel builds from the full repo, so it works there.

---

## 3. API surface

| Group | Prefix | Auth | Routes |
|---|---|---|---|
| Mobile / web REST | `/api/v1/*` | `mobileAuth`: raw `Authorization` header = anon key or customer JWT (no `Bearer`) | 54 + the webhook |
| Stripe webhook | `POST /api/v1/payments/webhook` | `Stripe-Signature` header, raw body | 1 |
| Admin API | `/admin/api/*` | session cookie `extraspace.admin.sid` (Redis store) + permission check inside the handler | 113 |
| Cron | `/api/cron/*` | `Authorization: Bearer $CRON_SECRET` | 4 (`sync-units`, `facility-bookings`, `credits`, `cowork`) |
| Public misc | `/api/cms/*` (3), `/api/health` (1) | none | 4 |
| Public misc, keyed | `/api/size-estimator/estimate`, `/api/recommendations/units` | `mobileAuth` | 2 |
| **Total** | | | **178** |

Admin API split: `cowork` 81, `bizplus` 22, generic `resources` 5, `auth` 3, `meta` 1, `dashboard` 1.
By method: 75 GET, 74 POST, 13 PATCH, 5 PUT, 11 DELETE.

Mobile routes by area: units/sites/quotes 9, reservations/leases/agreements/My Spaces 7, facility
booking 13, credits 5, cowork app 4, rewards 7, leads/viewings 7, login 1, My Bills checkout 1.

Other surfaces (no route files): static `/admin/*` (built SPA), `/facility-images/*`, Swagger UI at
`/api/docs` and `/api/docs/openapi.json`, `GET /` service banner (spec `00` §1–2).

Response style: success bodies are **not** wrapped; errors use one envelope
`{success:false, code, message, details, requestId}` (spec `00` §3). File-based routing
(`methods/<name>.<verb>.ts`), zod validation, Express 5.

---

## 4. Data model

- **69 tables, 39 PostgreSQL enums**, one Prisma schema, 13 migrations (2026-09-16 → 2026-10-08).
- Main aggregates:
  - Storage: `Site` → `Unit` (+ `StorageType`, `UnitSize`), `Customer` → `SiteLinkTenantLink`,
    `Reservation`, `Lease`, `Transaction`, `SignedAgreement`.
  - Sales: `Lead`, `ViewingAppointment`, `Promotion`.
  - Facility booking: `BookableFacilityType` → `BookableFacility` → `FacilityBooking` (+ line items,
    invitees, adjustments, promo codes).
  - Credits: `CreditAccount` (customer × site) → `CreditBucket` → `CreditLedgerEntry`, packages,
    purchases, rollover runs.
  - Cowork: `CoworkUnit`, `CoworkTenant` → `CoworkContact`, `CoworkLicence`, `Invoice` →
    `InvoiceLine`, `CoworkPayment` → `PaymentAllocation`, `TenantCharge`, `OutboxEmail`, settings.
  - Admin: `AdminUser`, `Role`, `Permission`, `RolePermission`, `AuditLog`.
  - Stubs: rewards (4 tables), CMS (2), tools (2).
- Conventions (spec `00` §6, checked in the schema):
  - ids are app-generated **cuid** strings (`@default(cuid())`, no DB default);
  - quoted PascalCase tables, camelCase columns;
  - money is **`DOUBLE PRECISION`** (107 columns), JS rounding rules;
  - timestamps `timestamp(3)` storing UTC; 19 `date` columns; business days in `Asia/Singapore`;
  - `updatedAt` set by the app (41 tables), no DB trigger;
  - 7 `jsonb` columns; hand-written CHECK and `EXCLUDE USING gist` constraints (`btree_gist`)
    for the booking overlap guard and credit bucket bounds.
- `Customer` has **no password or auth columns** — identity is email only.

### 4.1 Hooks for data from older systems

| Hook | Where | Older system it points to |
|---|---|---|
| `siteLink*Id` ints | `Site.siteLinkSiteId`, `Unit.siteLinkUnitId/UnitTypeId`, `SiteLinkTenantLink.siteLinkTenantId`, `Reservation.siteLinkWaitingId`, `Lease.siteLinkLedgerId`, `Promotion.siteLinkConcessionId`, `Transaction.siteLinkReceiptId`, `CoworkUnit.siteLinkUnitId` | SiteLink (live system of record, not a one-off import) |
| `POST /api/v1/me/login` sync | `tenant.service.ts#resolveCustomerByEmail` | Pulls an existing SiteLink tenant's current ledgers into `Lease` on first login. This is the only "migration" path for existing storage customers. |
| `legacyId` (unique) | `CoworkUnit`, `CoworkTenant`, `CoworkLicence`, `Invoice`, `CoworkPayment` | The **Claude artifact "Cowork Manager"** export (doc ids), via `npm run import:cowork` (`src/scripts/import-cowork.ts`) |
| `placeholder`, `imported`, `endAssumed`, `dataIssue` | `CoworkTenant`, `CoworkLicence` | Same artifact import |
| `bankImportRowHash` | `CoworkPayment` | Bank-statement CSV import (de-dupe) |
| `CreditBucketKind.LEGACY` | `CreditBucket` | The demo's own pre-bucket credit balance, not an external system |
| Lucy field names in comments | facility booking models (`schema.prisma` lines 953–1430) | Lucy/Iviva `FacilityBookingService` payload shapes the Flutter app used |

**There is no import from the old Codigo C# / MySQL system** and no mention of it by name.
Two code comments refer to an older .NET app: `src/services/sitelink/operations/payments.ts` line 3
("not guessed from the older .NET reference app") and `src/services/domain/payment.service.ts`
line 185 ("the legacy MakePayment2 flow"). That suggests the authors had the old .NET code as a
reference for SiteLink payments (inferred).

---

## 5. Admin UI (`admin-ui/`)

- **Stack**: React 18.3, Vite 6, TypeScript 5.7, `react-router-dom` 6.28, Tailwind 3.4 with
  hand-built shadcn-style components (`src/components/ui/*`), `lucide-react` icons, Recharts 2.15
  for charts, `read-excel-file` for spreadsheet imports. **No** state library (React context),
  **no** form library, **no** table library, **no** data-fetching library (a 42-line `fetch`
  wrapper, `src/lib/api.ts`). Light/dark theme (`ThemeContext.tsx`). No tests, no i18n.
- **How it is generated**: `AuthContext` loads the session user and `GET /admin/api/meta/resources`.
  The sidebar groups, list tables (search, boolean filters, pagination), and create/edit forms
  (`ResourceListPage.tsx`, `ResourceEditPage.tsx`, `RelationSelect.tsx`) are rendered from the
  registry in `src/services/admin/resource-registry.ts`. Field types: string, text, email, number,
  boolean, date, enum, relation, password.
- **Screens**:
  - Login, Dashboard (KPIs + Recharts trend/donut/occupancy).
  - Generic CRUD for 44 resources in 11 groups: Platform 4 (sites, storage types, unit sizes, units),
    Tenants 4 (customers, reservations, leases, viewings), Leads 1, Facility Booking 12, Payments 2
    (promotions, transactions), Rewards 4, Credit 6 (read-only), Tools 2, Content 2 (blogs, FAQs),
    Cowork 3 (units, tenants, price list), Access Control 4 (roles, permissions, admin users, audit log).
  - BizPlus (hand-built, `src/pages/bizplus/`): Overview, Accounts (+ add customer, manage credits,
    new booking), Account "view as", Month-end, Bookings & deposits.
  - Cowork Manager (hand-built, `src/cowork/`, a port of the Claude artifact's UI): Dashboard,
    Floor board, Room bookings, Tenants & members, Leases, Invoices, Tenant charges, Payments,
    Statements, Documents, Emails, Credits, Rooms & spaces, Locations, Settings — plus many
    drawers/modals (billing 1.7k lines, bookings, tenants, credits, leases, units, conversions,
    mail, docs, import).
- **Auth**: cookie session (`credentials: "include"`), `RequireAuth` route guard, permission flags
  from `/admin/api/auth/me`.
- **Build and serving**: `npm run build` → `../admin-ui-dist`, Vite `base: "/admin/"`. The backend
  serves it at `/admin` with an SPA fallback (`index.html` no-store, assets immutable). Dev server
  on :5173 proxies `/admin/api` to :4000. One ~1.4 MB JS bundle (`admin-ui/README.md`).
- **Reusable as-is in production?** Partly.
  - The generic CRUD shell and BizPlus pages talk only to `/admin/api/*`, so they can sit on top of a
    C# backend that keeps the same contracts.
  - The **Cowork pages are a problem for "reuse as-is"**: they load the whole site in one
    `GET /admin/api/cowork/snapshot` and compute almost every view in the browser using the
    backend's own TS file `src/services/domain/cowork-engine.ts` (alias `@engine`, imported in 10
    files: `admin-ui/src/cowork/model.ts`, `ui.tsx`, `modals/BillingModals.tsx`, ...). If the
    backend becomes C#, that TS file must be kept and kept in sync with a C# copy of the same
    billing maths, or the Cowork UI must be rewritten to use server-computed views.
  - Quality is fine for an internal tool built fast, but: no tests, permission errors arrive as 401,
    the generic forms coerce `"false"` to `true` and can null NOT NULL columns (spec `12` §7 items
    5–6), no role-permission editor.

---

## 6. web-app (`web-app/`)

- **Stack**: React 18.3, Vite 6, TypeScript, Tailwind 3.4, `react-router-dom` 6.28, `lucide-react`.
  2.9k lines, 42 files. No tests.
- **Purpose**: a **presentation prototype** that looks like the mobile app, shown inside a phone
  frame (`components/PhoneShell.tsx`). `CLAUDE.md` calls it "presentation prototype for the mobile
  app's unit-browsing/move-in/payment/My Spaces flow". It is not a customer web portal.
- **Screens** (`src/App.tsx`): sign-in email, sign-in password, sign-up, explore home, browse units,
  unit detail, move-in, confirmation, coming soon, cards, profile, My Spaces, lease detail,
  favourites.
- **How it calls the API**: `fetch` to `/api/v1/*` with the anonymous key in the `Authorization`
  header. Dev proxy to `localhost:4100` (Docker); on Vercel a rewrite to the deployed backend
  (`web-app/vercel.json`). Uses `GET /api/v1/sites`, `/units`, `/units/:id`, `/unit-sizes`,
  `POST /units/:id/rental-plans`, `POST /api/v1/leases`, `POST /api/v1/me/login`,
  `GET /api/v1/me/spaces?userId=<email>`.
- **Simulated parts**: login (email kept in `localStorage`, password never checked), sign-up (does
  nothing), saved cards (`lib/cardsStore.ts`, browser-only), autopay (`lib/autopayStore.ts`),
  payment (`stripeSessionId: demo_sim_<uuid>`). But confirming a move-in sends a **real** SiteLink
  move-in (`pages/MoveInPage.tsx` line 209 says so on screen).
- **Stale vs the backend**: it never stores or sends the JWT that `/me/login` now returns; it relies
  on the `userId` query param instead.
- 🔴 **Security note**: `web-app/src/lib/api.ts` line 6 hard-codes the anonymous mobile API key
  value in source (and therefore in git and in the public JS bundle). Value not copied here. It
  should be treated as public and rotated before any real launch.

---

## 7. Mobile app relationship

- The Flutter app is **not in this repo**. The demo's docs place it at
  `extracted/frontend/frontend-feature-pay_up_auto_payment/` in the client's wider workspace
  (spec `01` lines 42–60, `docs/bizplus-credits/PLAN.md` "Sources used").
- **What the app calls today** (`README.md` lines 335–338, spec `01` §1.2,
  `docs/facility-booking/DESIGN.md` lines 581–602):
  - **stag / prod builds**: the old **Lucy/Iviva gateway** (`Lucy/SelfStorage/*`, `Lucy/BookAView/*`,
    `Lucy/FacilityBookingService/*`, `Lucy/UserAuthentication/loginUser`, ...). Not this demo.
  - **dev / web builds only** (behind `MockConfig.useLucyMock` / `MockConfig.usePlatformBooking`):
    login via `/api/v1/me/login`, workspace browsing, facility booking, BizPlus credits, Workspace
    tab of My Spaces, Bills › Workspace pay. "Everything else, and stag/prod, still calls Lucy."
  - The storage reserve / move-in flow has **never** been called by Flutter: only `web-app` calls
    `/leases`. Spec `04` lines 219–223 notes Flutter's real request models would get **400** today
    (it sends `null`s and string agreements).
- `README.md` lines 340–377 map each Lucy path to its `/api/v1/*` replacement (36 rows).
  Verbs changed on purpose (some POST reads became GET, some GET writes became DELETE/PUT).
- "Core" in the demo docs means the older MongoDB services under `extracted/backend_services/`
  (e.g. `TenantManagementService`), which own real customer auth and PayUp/NicePay autopay.
- **`openapi.json` coverage**: 54 operations, all under `/api/v1/*`, covering 54 of the 55 mobile
  routes (missing `GET /api/v1/me/rewards/history`). It does not cover admin, cron, CMS, health,
  size estimator or recommendations.
- Consequence (inferred): the "Flutter must keep working unchanged on `/api/v1/*`" rule in our
  workspace is true only for the dev/web build and the workspace/booking/credits slice. Production
  Flutter still talks to Lucy, so most `/api/v1/*` shapes are not yet relied on by a live client.

---

## 8. The spec's own C# port plan (`spec/13-csharp-port-plan.md`)

- **Stack**: .NET 8 LTS (or 9), ASP.NET Core controllers, EF Core 8 + Npgsql **database-first**
  against the existing schema, FluentValidation, StackExchange.Redis, cookie auth with a Redis
  ticket store, BCrypt.Net-Next, Microsoft.IdentityModel JWT, hand-built SOAP envelopes with
  HttpClient + XDocument, Stripe.net, BackgroundService + Cronos (or Hangfire/Quartz), NodaTime,
  Serilog, Swashbuckle/NSwag, xUnit + FluentAssertions + Testcontainers.
  Note: our workspace `cms.md` says .NET 10; the spec says 8.
- **Layout**:
  ```
  ExtraSpace.Platform.sln
    src/ExtraSpace.Platform.Api/             controllers per feature, middleware, auth
    src/ExtraSpace.Platform.Domain/          pure engines (pricing, credit, cowork, booking policy)
    src/ExtraSpace.Platform.Application/     services per feature doc, DTOs, validators
    src/ExtraSpace.Platform.Infrastructure/  EF, Redis, SiteLink, Stripe, jobs
    tests/…Domain.Tests/  tests/…Api.Tests/
    wwwroot/admin/ (admin-ui-dist)  wwwroot/facility-images/
  ```
- **Phases** (each ends with a parity check): 1 skeleton/pipeline → 2 DB entities → 3 auth →
  4 admin console → 5 Redis + SiteLink → 6 units/quotes + sync → 7 leads/viewings →
  8 reservations/leases/My Spaces → 9 Stripe + webhook + My Bills → 10 facility booking →
  11 BizPlus credits → 12 cowork inventory → 13 cowork billing/outbox/app → 14 rewards/CMS/misc.
- **Parity method**: same DB copy for both services; port the jest tables as xUnit `[Theory]` first;
  golden-response diff of every GET (ignore `requestId` and timestamps); replay mutations on two DB
  copies and diff rows; contract-test against `openapi.json`; click through the admin UI; Flutter
  smoke on dev env; Stripe test events per `metadata.kind` incl. duplicates; cutover behind the
  same hostname, same env var names, switch the webhook URL, turn off Node schedulers first.
- **Frontend decision**: it makes one — **do not port the frontends**. `admin-ui` and `web-app` are
  "reuse as-is"; the C# app serves `admin-ui-dist` at `/admin` and keeps every `/admin/api/*`
  contract (spec `README.md` "Not in scope", spec `00` §13). It does not mention the `@engine`
  dependency described in §5 above.
- **Known open items it carries over**: SiteLink tenant provisioning (retry on `-95`), Cowork C1,
  BizPlus opening hours and GST on refunds, no automatic rewards earning, heuristic size
  estimator / recommendations.

---

## 9. What the demo explicitly does NOT cover

From `README.md`, `CLAUDE.md`, the spec "Edge cases" sections and code comments:

- **Customer accounts**: no password, OTP, sign-up, reset, profile editing or social login.
  "Core owns real auth" (`CLAUDE.md`, `src/middlewares/mobile-auth.ts`). `/me/login` is email-only.
- **Recurring payments / autopay** (PayUp/NicePay, `myspaceRecurringPaymentSubmission`): left to
  Core (`README.md` lines 385–387).
- **Card handling of any kind**, SiteLink card operations (`ReservationFeeAddWithSource_v2`,
  `PaymentSimpleWithSource_v3`): deliberately excluded.
- **Payment truth for storage reserve / move-in**: the app's own payment is trusted, not verified.
- **My Bills reconciliation** when SiteLink posting fails: TODO (`payment.service.ts` line 220).
- **Email, SMS, push notifications**: none. No mail/push library in `package.json`. The Cowork
  outbox only queues messages; staff send them through `mailto:` links
  (`cowork-outbox.service.ts` line 27, PLAN C8).
- **File uploads**: none. `CoworkDocument` stores a URL only; facility photos are static files in
  `public/facility-images/`.
- **Rewards earning**: none, apart from the 2,000-point welcome bonus (spec `11`).
- **Promotions engine**: the `Promotion` table is CRUD only; nothing reads it (spec `11`).
- **CMS**: no rich editor, no workflow, two public reads.
- **Size estimator / recommendations**: heuristics, not models.
- **Viewings**: fixed slots, no opening hours, no double-booking guard, no ownership checks.
- **Reservation expiry**: `EXPIRED` is never set; no job (spec `04` §7 item 6).
- **Cowork ↔ SiteLink**: no link; `CoworkUnit.siteLinkUnitId` is stored but unread (C1 open).
  Auto-billing off. No bank feed (CSV import only).
- **Workspace (BizPlus unit) rental from the app**: not wired (`README.md` lines 222–224).
- **StorageUnit media**: `imageList` / `specifications` / `tags` always empty (`README.md` line 260).
- **Role ↔ permission assignment UI**: none (spec `12` §7 item 4).
- **Migration from any older system**: no import from Lucy/Iviva, the MongoDB "Core" services or
  the old C# / MySQL system. Existing storage customers are picked up only from SiteLink at first
  login.
- **web-app**: login, sign-up, payment, saved cards and autopay are all simulated.
- **Infra**: no CI, no monitoring/alerting beyond logs, no WAF/CDN config (left to the infra team,
  `README.md` lines 39–41).

---

## 10. Open questions

1. **Which system is "production" for the Flutter app today?** The demo says stag/prod Flutter
   calls the Lucy/Iviva gateway. How does that relate to the old Codigo C# / MySQL system that
   agents A–C are scanning? Is the old C# system behind Lucy, beside it, or a different product
   (e.g. admin CMS only)?
2. **How frozen are the `/api/v1/*` shapes really?** Production Flutter does not call them yet.
   Only the dev/web build uses the workspace/booking/credits slice. If the owner wants "new logic",
   the storage flow contracts could still change at low cost. Our workspace `cross-repo.md` assumes
   they are fixed.
3. **What happens to the demo's production DB (Vercel + Neon)?** It holds real Cowork data
   (97 units, 53 tenants, 135 licences) and BizPlus setup since 2026-10-05. Does the C# app take
   over this DB as-is (frozen schema), or does it start on a new DB fed from the old MySQL system?
4. **Customer identity**: the demo has no real customer auth. Where do customer accounts and
   passwords live in the new system — the old MySQL users, Core/Lucy, or something new? Keeping
   the email-only `/me/login` in production is account takeover.
5. **Cowork C1**: does SiteLink already bill co-working rent? The answer decides whether half of
   docs 09/10 (billing, invoices, late fees) is needed.
6. **Admin UI Cowork pages depend on a TS file from the Node backend** (`cowork-engine.ts`). Keep a
   TS copy next to a C# copy (two implementations of billing maths), or rewrite those pages to use
   server-computed views?
7. **Money type**: the demo uses `double`; the old MySQL system probably uses `decimal` (not
   checked here). Which one wins for migrated data and for invoices? The Cowork plan itself warns
   about this (`docs/cowork-manager/PLAN.md` §8).
8. **.NET version**: spec says .NET 8; workspace `cms.md` says .NET 10.
9. **Is `web-app` needed at all?** It is a phone-frame sales prototype, stale vs the backend, and
   it performs real SiteLink move-ins with fake payments. Retire it, or keep it only for demos
   against a sandbox?
10. **Security fixes vs parity**: spec docs ask to keep bug-for-bug parity on ownership checks,
    trusted client payments, 401-instead-of-403, etc. Which of these does the owner want fixed in
    the C# build (each is a contract change for some client)?
11. **Features of the old system missing from the demo** (customer auth, autopay, notifications,
    file uploads, gate/access control?, reporting?) — to be answered by comparing with agents
    A–C's inventories.
