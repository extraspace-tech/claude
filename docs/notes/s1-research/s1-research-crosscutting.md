# S1 research — cross-cutting (admin pages, RBAC, crons, notifications, S0 carry-overs, CMS as-built)

Researcher: read-only, 2026-10-14. Paths: `SPEC` = `../Backend Demo/backend/.claude/backend-spec/`, `DEMO` = `../Backend Demo/backend/`, `CMS` = `../CMS/`, `CTX` = `Claude/`.
Tags: **[DOC]** = documented, cited file:line. **[INF]** = my inference / recommendation, not stated anywhere.

Demo freshness [DOC]: `DEMO/.git/FETCH_HEAD` fetched 2026-10-14 10:08; `git log 6be4474..origin/main` is empty, so the demo still sits at the sync-log baseline `6be4474` (`CTX/docs/notes/demo-backend/sync-log.md`). No new demo commits to diff before the S1 spec.

---

## 1. How the demo admin UI works (what "identical" has to reproduce)

### 1.1 Engine [DOC]
- Routes (`DEMO/admin-ui/src/App.tsx`): `/login`, `/` Dashboard, `/r/:resourceKey` (ResourceListPage), `/r/:resourceKey/:id` (ResourceEditPage; `id = "new"` = create), `/bizplus/*` (5 custom pages), `/cowork/:view?` (CoworkApp). Router basename `/admin`.
- Fully config-driven: nav, list tables, search, filters and forms come from `GET /admin/api/meta/resources` (44 registry entries in `DEMO/src/services/admin/resource-registry.ts`; spec `SPEC/features/12-admin-console.md:22-28`, shape `:172-216`, full content Appendix A `:925-1685`). One generic CRUD API `/admin/api/resources/:resource[/:id]` (`12:218-299`).
- Reads of every generic resource need only a session, no permission (`12:220`, `12:550-552`, edge case `12:737-738`). Writes need `def.permission`; missing → **401** `Missing permission: <code>` (`12:272-273`, `12:733-734`). Role named literally `Super Admin` bypasses all checks (`DEMO/src/services/admin/auth.service.ts:49`).
- **List page** (`DEMO/admin-ui/src/pages/ResourceListPage.tsx`):
  - page size **20** (`:19`), server paging; `Pagination` shows `{start}–{end} of {total}` (`components/Pagination.tsx:22`);
  - search box only when `searchFields` non-empty, placeholder `Search <label lowercased>…` (`:89`); server does `ILIKE %term%` OR over searchFields (`12:236-238`);
  - one `<Select>` per `filterable` field, using `filterOptions` or default All/Yes/No (`:99-118`);
  - "New" button (Plus icon) only when `canWrite` (`:123`);
  - columns = `listFields`, header = titleCase of the first dot-segment (`site.name` → "Site") (`:23-25`);
  - row click → edit page; trash icon per row when `canWrite`, confirm dialog `Delete <label minus last char>?` / "This action can't be undone." (`:156`, `:164`, `:194`);
  - empty state `No <label lowercased> yet` (`:135`).
  - Cell rendering heuristics (`components/ResourceCell.tsx`): null/"" → grey "—"; boolean → Yes/No badge (success/neutral); leaf key `status|type|source|provider|tier|billingFrequency` → badge; ISO datetime → `formatDate` (`en-SG`, `dd MMM yyyy`); number → `toLocaleString()` tabular.
  - Sort: fixed per resource (`orderBy` or `createdAt desc`), no client-chosen sort (`12:239-242`).
- **Edit page** (`DEMO/admin-ui/src/pages/ResourceEditPage.tsx`): "← Back to <label>" link; one Card `max-w-2xl`; every registry field in registry order; title `New <label minus trailing s>` / `<label minus s>`; field widgets by type: string/email/number/date/password → `<Input>`, `text` → Textarea, `enum` → Select with `— select —` + raw enum values, `relation` → `RelationSelect` (loads target list `?pageSize=200`, shows `labelField`), boolean → Checkbox; required → red `*`; `readOnlyField` → label + plain value; buttons "Create" / "Save changes" / "Cancel"; when not writable: "This record is read-only." Save = `POST` (then navigate to the list) or `PUT` with all non-readOnly fields.
- **Shell** (`components/layout/Sidebar.tsx`, `Topbar.tsx`, `lib/workspace.ts`): w-64 sidebar; brand block "ExtraSpace / Self Storage" (a workspace switcher "ExtraSpace · Self Storage | BizPlus" appears only with credit/cowork permissions); "Dashboard" first; then one section per registry `group` in first-appearance order, items sorted **alphabetically by label** within a group, icon from registry `icon` (lucide name). Topbar: page title, Light/Dark/System theme switch, user menu with logout.
- Stack: React 18, react-router 6, Tailwind 3, own `components/ui/*` (not shadcn), lucide, **recharts 2** (`DEMO/admin-ui/package.json`). Money formatting `formatCurrency(amount, currency = "SGD")`, `en-SG`, 0 decimals (`admin-ui/src/lib/utils.ts:16-20`).

### 1.2 Dashboard [DOC]
- UI (`DEMO/admin-ui/src/pages/DashboardPage.tsx`): 6 StatCards — Customers (+N this week), Active Leases ("currently occupied"), Active Reservations ("pending / held"), Occupancy Rate % ("across all sites"), Revenue Recorded (`formatCurrency`, "succeeded transactions"), Leads (+N this week) (`:55-60`); cards "Activity — last 14 days" TrendChart of `signups` + `leads` only (revenue not plotted) (`:65-67`); "Leads by status" donut (`:72-77`); "Occupancy by site" bar chart (`:85-90`); "Payments by provider" donut (`:96-101`); "Recent leads" list (`:107-122`); "Recent transactions" table (`:129-155`). Charts: `components/charts/{TrendChart,DonutChart,OccupancyBarChart}.tsx`.
- API `GET /admin/api/dashboard`, no permission (`12:301-319`); every metric's query `12:603-631`. Every input is S1 data (Customer, Lease, Reservation, Unit, Transaction, Lead, Site) → **the dashboard is an S1 page** [INF].
- Demo defects to not copy (`12:614-631`, `12:755-757`): UTC day buckets (not SGT/site TZ); `revenue` sums all currencies raw (breaks with SGD+MYR); `transactionsByProvider` counts all statuses; per-site total includes soft-deleted units while the global rate excludes them; floats.

### 1.3 S0 decision vs "identical" [DOC + INF]
- S0 spec §8 (`CTX/docs/superpowers/specs/2026-10-09-s0-foundation-design.md:333`): "**No generic CRUD engine.** … explicit admin endpoints per feature, plus shared components (`<PageShell>`, `<DataTable>`, `<RecordForm>`, `<ConfirmDialog>`) configured per page." Owner 2026-10-13 (`CTX/.claude/memory/feedback_match_demo_screens_and_logic.md`): pages identical to the demo, same logic, QOL additions allowed, listed in the spec.
- [INF] These fit together: the *look* is reproducible with two shared React components (`ResourceListPage`-like list + `RecordForm`-like edit page) fed a **static per-page config in the UI code** (columns, search, filters, fields), while each feature exposes its own typed endpoints (list with `page/pageSize/search/<filter>`, get, create, PATCH+version, DELETE?version). No `/meta/resources` endpoint and no dynamic table access are needed. `<RecordForm>` is named in the S0 spec but **was not built** (CMS has `FormField`, `NativeSelect`, `PageShell`, `DataTable`, `ConfirmDialog` only — `CMS/admin-ui/src/components/`).
- Visual deltas between our S0-5 shell and the demo [DOC from code]: our nav is a flat list (`CMS/admin-ui/src/app/nav.ts`), no group sections; edits are dialogs (`features/staff/StaffDialog.tsx`), demo uses full edit pages at `/r/<key>/<id>`; our `DataTable` has no paging/sorting (`components/DataTable.tsx:5`, paging hand-rolled in `features/audit/AuditPage.tsx:53-96`); Recharts not installed (`CMS/admin-ui/package.json`; S0-5 plan `:3261` "Recharts is 'from S1'"). Our shell already has the theme switch and sign-out (`app/Shell.tsx:41-47`).
- Open [INF]: does "identical" also mean re-skinning the S0 Staff/Roles/Audit screens into the demo's "Access Control" group (Roles, Permissions, Admin Users, Audit Log as generic pages)? Our S0 screens are functionally richer (owner rules, version, permission editor). Recommend: keep ours, place them under an "Access Control" nav section with the demo's labels. Owner to confirm.

---

## 2. S1 admin page inventory

All generic pages share the two demo source files `pages/ResourceListPage.tsx` + `pages/ResourceEditPage.tsx`; the per-page definition is the registry entry (cited by line in `DEMO/src/services/admin/resource-registry.ts` and spec Appendix A). [DOC] unless marked.

| # | Nav (group › label, icon) | Registry key / line | List columns (listFields) | Search | Filters | Default sort | Form fields (registry order) | Write perm (demo) | Owning S1 doc |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Dashboard (LayoutDashboard) | — `pages/DashboardPage.tsx` | see §1.2 | — | — | — | — | none | 12 (+data of 03/04/05/06) |
| 1 | Platform › Sites (MapPin) | `sites` :57; spec `12:985` | locationCode, name, facilityType, city, country, active | name, locationCode, city | — | createdAt desc | locationCode*, siteLinkCorpCode*, facilityType enum SELF_STORAGE/WORKSPACE, name*, displayName, description(text), heroImageUrl, address1, city, region, postalCode, country, phone, latitude, longitude, timezone, taxPercentage "Tax % (GST)", active | `sites.write` | 03 |
| 2 | Platform › Storage Types (Grid3x3) | `storageTypes` :94; `12:1010` | key, name, active, sortOrder | key, name | — | createdAt desc | key*, name*, displayName, iconPath, imagePath, sortOrder, active, siteId→sites | `units.write` | 03 |
| 3 | Platform › Unit Sizes (Maximize) | `unitSizes` :115; `12:1025` | key, label, unitGroup, sortOrder | key, label | — | createdAt desc | key*, label*, displayName, description, unitGroup, imagePath, minAreaSqft, maxAreaSqft, sortOrder, storageTypeId→storageTypes | `units.write` | 03 |
| 4 | Platform › Units (Box) — **read-only** | `units` :138 (readOnly :157); `12:1042` | unitName, site.name, storageType.name, unitSize.label, standardRate, available, rented | unitName, description | `available` (All statuses / Available / Unavailable) | unitName asc | all readOnlyField: unitName, site, storageType, unitSize, width, length, areaSqft, floor, climate, standardRate, webRate, rented, available, lastSyncedAt | `units.write` (never writable) | 02/03 |
| 5 | Tenants › Customers (User) | `customers` :205; `12:1063` | email, firstName, lastName, phone, city | email, firstName, lastName | — | createdAt desc | email*, firstName, lastName, phone, address1, address2, city, country, postalCode, businessName, uenNumber | `tenants.write` | 01/04 (Identity owns `customer`) |
| 6 | Tenants › Leases (FileText) | `leases` :295; `12:1122` | customer.email, unit.unitName, status, monthlyRent, startDate | none (no search box) | — | createdAt desc | customerId*→customers, unitId*→units, siteId*→sites, reservationId→reservations, siteLinkLedgerId*, siteLinkLeaseNum, startDate*, endDate, monthlyRent*, billingFrequency, status ACTIVE/ENDED, movedInAt, movedOutAt | `reservations.write` | 04 |
| 7 | Tenants › Reservations (Bookmark) | `reservations` :259; `12:1099` | customer.email, unit.unitName, status, grandTotal, currency, createdAt | paymentReference | — | createdAt desc | customerId*, unitId*, siteId*, siteLinkWaitingId, status PENDING/HELD/CONVERTED/CANCELLED/EXPIRED, quotedRate, dateNeeded*, expiresAt, reserveCharge, securityDeposit, gst, grandTotal, currency, paymentProvider, paymentReference, paymentStatus | `reservations.write` | 04 |
| 8 | Tenants › Viewing Appointments (Calendar) | `viewingAppointments` :323; `12:1142` | customerEmail, scheduledDate, timeSlot, status | customerEmail | — | scheduledDate desc | customerId, customerEmail*, customerPhone, siteId*, unitId, scheduledDate*, timeSlot*, status SCHEDULED/RESCHEDULED/CANCELLED/COMPLETED, notes | `reservations.write` | 06 |
| 9 | Leads › Leads (TrendingUp) | `leads` :229; `12:1081` | name, email, status, source, createdAt | name, email | — | createdAt desc | name*, email*, phone, siteId, unitId, interestType, durationMonths, rentalAmount, status NEW/CONTACTED/CONVERTED/CLOSED, source, notes | `leads.write` | 06 |
| 10 | Payments › Transactions (CreditCard) | `transactions` :831 (perm :841); `12:1388` | provider, amount, currency, status, createdAt | providerReference | — | createdAt desc | customerId, reservationId, leaseId, siteId, provider* STRIPE/PAYUP/SITELINK_CASH/SITELINK_OTHER, providerReference, amount*, currency, status PENDING/SUCCEEDED/FAILED/REFUNDED, siteLinkReceiptId | `payments.write` | 05 |
| 11? | Payments › Promotions (Tag) | `promotions` :797 (perm :805); `12:1365` | name, source, amountType, active | name | — | createdAt desc | siteId, source SITELINK/INTERNAL, siteLinkConcessionId, name*, description, amountType FIXED/PERCENT/FIXED_RATE, fixedDiscount, percentDiscount, fixedRate, maxAmountOff, neverExpires, expiresMonths, requiresPrepay, active, startsAt, endsAt | `promotions.write` (**never seeded**) | 11 (stub; "No runtime code reads it", `11:161-193`) |

Count [INF]: **11 S1 resources** (10 firm + Promotions undecided) → 1 dashboard + 11 list screens + 11 detail screens ≈ **23 screens, 12 nav entries**, built from ~3 page components (Dashboard, list template, form template). Nav sections in S1: Platform, Tenants, Leads, Payments (+ Access Control from S0).

Not S1 [DOC: group/doc ownership]: Facility Booking group (13 resources, doc 07 → S2 deferred), Credit (doc 08 → S2), Cowork (09/10 → S3), Rewards / Content / Tools (`sizeEstimatorRules`, `recommendationLogs`) (doc 11 → S4 Extras), BizPlus + Cowork custom pages. Note `sizeEstimatorRules` relation → `unitSizes` and recommendations read `Unit` (doc 11 `:195-203`), so S4 depends on S1's unit tables [INF].

### 2.1 Where copying "identical" collides with our rules (each needs a line in the S1 spec) [INF unless cited]
1. **Unguarded reads** (`12:737`): any admin reads customers, transactions, audit. Our S0 model guards reads (`audit.read`). Recommend a read permission per area or reuse `*.manage` for read+write; decide.
2. **401 vs 403** for missing permission (`12:733`): keep our 403 (wire contract of S0).
3. **Units list triggers a live SiteLink sync of every active site on each page load** (`DEMO/src/controllers/admin-api/resources/methods/[resource]/index.get.ts:30-38`, marked TEMPORARY; `02:425-429`; `12:747-748`). Do not copy; QOL: "Sync now" button per site / all sites (client artifact has "Refresh this site / Refresh all sites", `CTX/docs/notes/client-artifacts/03-es-admin.md:30-36`), plus `lastSyncedAt` shown.
4. **Leases / Reservations / Transactions are freely editable and creatable by hand** (generic CRUD; `payments.write` can create a SUCCEEDED transaction or change `amount`). That fabricates money records and desyncs from SiteLink/Stripe. Recommend Transactions read-only (refund/notes actions only if specced), Leases read-only (SiteLink-derived), Reservations limited to status actions. Owner decision; list as a deliberate difference.
5. **Customers**: demo edits `email` freely; ours `email` is the sign-in identity and SiteLink link key (artifact open Q7, `03-es-admin.md:325-326`). Our `customer` table has only `email, first_name, last_name, phone` (`CMS/src/ExtraSpace.Api/Features/Identity/Customer.cs`); the demo form also has address1/2, city, country, postalCode, businessName, uenNumber → S1 must add columns (Identity owns the table; another feature only uses `Features/Identity/Contracts/`, house rule 10). Identity's Contracts today hold only `CustomerPrincipal.cs`, `LoginCodes.cs`: S1 needs a customer read/update contract.
6. **Deletes**: demo hard-deletes any row, FK RESTRICT → 500 (`12:294-299`). Ours: FK violation → 409 `CONFLICT` already (built-so-far `:79`). Decide which S1 resources allow delete at all (deleting a Lease/Transaction row should not be possible).
7. **Dates and money**: demo writes `datetime-local` as server UTC and formats `en-SG` (`12:578`, `12:762`); ours shows instants in the browser zone (`CMS/admin-ui/src/lib/time.ts`), business dates must be in the site zone. Money: demo floats + SGD default; ours `decimal` per currency (MY = MYR) — `formatCurrency` must take the row's currency.
8. **Edit semantics**: demo PUTs all fields; ours PATCH with dirty fields + `version` (xmin) and 409 reload (built-so-far `:79`, `:106`). Keep ours (invisible to the user).
9. **Boolean coercion / enum validation / required-on-update** quirks (`12:739-746`) → ours validates (400 `VALIDATION_FAILED`).
10. **Edit as full page vs dialog**: to look identical, S1 pages use full-page edit routes like `/r/<key>/<id>` (or `/sites/<id>`); route segments must not contain a dot (built-so-far `:95`).

---

## 3. RBAC permissions S1 must add

### 3.1 Demo codes that gate S1 resources [DOC `12:409-421`, seed `11:650-660`]
| Demo code | Seeded label | Gates (S1 part) |
|---|---|---|
| `sites.write` | Manage sites | Sites |
| `units.write` | Manage unit taxonomy & cache | Storage Types, Unit Sizes (Units read-only) |
| `tenants.write` | Manage tenants | Customers |
| `reservations.write` | Manage reservations & leases | Reservations, Leases, Viewing Appointments |
| `payments.write` | Manage promotions & transactions | Transactions (label says promotions too, but…) |
| `leads.write` | Manage leads | Leads |
| `promotions.write` | **not seeded** | Promotions (registry `:805`) — only Super Admin can edit; spec 12 §4.3 wrongly says `payments.write` gates promotions; spec 11 `:732-735` flags it |
Seeded roles: `Super Admin` (bypass by name), `Content Editor` (`content.write`, `payments.write`), `Ops Manager` (`tenants.write`, `reservations.write`, `leads.write`, `units.write`, + cowork) (`12:694-718`). Dashboard: no permission.

### 3.2 Ours today [DOC]
- Catalogue: `staff.manage`, `roles.manage`, `audit.read`, `jobs.manage` (`CMS/src/ExtraSpace.Api/Features/Admin/AdminPermissions.cs`). System role **Owner** holds every name (built-so-far `:71`, `:74`); no name-based "Super Admin".
- Mechanism: a feature calls `services.AddPermissions(new Permission(name, description))` (`Features/Admin/Contracts/Permissions.cs`) and guards with `.RequireAuthorization("<name>")`; UI menu item in `admin-ui/src/app/nav.ts` with `permission`, page wrapped `guarded('<perm>', Page)` (`app/routes.tsx:39-41`). Stored names that leave the catalogue are ignored.
- Naming convention so far `<area>.<verb>` with verbs `manage` / `read`.

### 3.3 Proposal [INF]
Keep the demo's split of areas, our verb style, and add read gates: `sites.manage`, `units.manage` (taxonomy + unit sync trigger), `customers.read` / `customers.manage` (demo `tenants.write`), `leases.read` / `reservations.manage` (reservations + leases + viewings, as demo), `leads.manage`, `payments.read` (transactions; read-only if §2.1-4 accepted), `promotions.manage` (if Promotions is S1), `dashboard.read` (or leave the dashboard open like the demo). Alternative: copy the demo codes verbatim (`sites.write` …) so the PM recognises them. Owner picks naming. Also: create default roles "Ops Manager" / "Content Editor" as data? Our S0 has no seeded roles except Owner; a migration seed would be reference data (S0 spec `:200` "reference data in migrations").

---

## 4. Background jobs (crons) relevant to S1

### 4.1 Demo jobs [DOC `11:575-627`, `00:259-272`]
| Job | Schedule | Lock | What | Idempotency | Sub-project |
|---|---|---|---|---|---|
| **Unit sync from SiteLink** `runUnitSyncOnce` (`DEMO/src/schedulers/unitSync.scheduler.ts:18,45`) | `*/15 * * * *` in-process (`UNIT_SYNC_CRON`, `UNIT_SYNC_ENABLED`); Vercel `0 3 * * *` daily | Redis `scheduler:unit-sync`, 600 s | For every `Site.active = true` (all facility types, incl. WORKSPACE) sequentially `syncSiteUnits(site.id, locationCode)`; per-site error logged and skipped; returns `ranSites` | Upserts keyed `(siteId, siteLinkUnitId)`; incremental cursor advances only when the whole site sync succeeds (`02:412-429`, `03:845-866`) | **S1** |
| Facility lifecycle | every minute | `scheduler:facility-lifecycle` 120 s | expire holds, complete bookings, expire Stripe sessions | — | S2 (deferred) |
| Credit upkeep | 00:05 SGT | 900 s | rollover + expiry | — | S2 |
| Cowork automations | 00:30 SGT | 900 s | reminders/house-rules to outbox | — | S3 |
- Also a per-unit lock `unit-reserve-lock:{unitId}` 15 s in `reservation.service.ts:53` (request-time, not a job) — S1 reservation flow; in our stack a PostgreSQL advisory lock `unit-reserve:<unitId>` (namespaced per checklist §1d) [INF].
- HTTP cron triggers `GET /api/cron/*` with `CRON_SECRET` (`11:602-619`): Vercel-only plumbing → not needed with Hangfire [INF]; a staff "Run now" exists in our Hangfire dashboard `/admin/jobs`.
- **Absent in the demo** [DOC]: no reservation-expiry job (`04:757-760`, EXPIRED unused); nothing marks viewings COMPLETED or expires leads (`06:435-437`); no reconciliation of PENDING My Bills transactions, no retry of failed SiteLink postings, no Stripe polling for missed webhooks (`05:559-565`).

### 4.2 What S1 needs on our side [INF, grounded in S0 docs]
- `UnitSync` recurring job via `services.AddRecurringJob<TJob>(name, cron)` with `Jobs:UnitSync:Enabled` (built-so-far `:32-37`). Hangfire recurring jobs can start a new run while the previous one still runs → add `[DisableConcurrentExecution]` or an advisory lock `unit-sync` (unverified how `Hangfire.PostgreSql` 1.21.1 handles it). Note: `RecurringJobs` uses a **fixed** `Asia/Singapore` zone (`CMS/src/ExtraSpace.Api/Platform/Jobs/RecurringJobs.cs:33`) — fine for `*/15`, but any per-day S1 job touching MY sites must compute the day per site zone.
- The **payment side-effect outbox job** (Stripe paid → `PaymentSimpleCashWithSource` → receipt) — required by S0 §13 (`spec :442`), not in the demo.
- Optional QOL: reservation-expiry sweep, PENDING-transaction reconciliation (demo gap above) — spec decides.
- S0-6 carry-overs for the first long job: stop timeout, Hangfire heartbeat / queue-age alarm (§6).

---

## 5. Notifications / email / push

- [DOC] The demo has **no email, SMS or push sender at all**: grep of `DEMO/src` and `package.json` for nodemailer / SES / resend / sendgrid / postmark / firebase / fcm / twilio finds nothing. The only "email" concept is the Cowork outbox (`DEMO/src/controllers/admin-api/cowork/methods/outbox/*`), a staff queue with "mark sent" (S3).
- S1 docs: leads/viewings "No … email" (`06:340`, `06:446-448`); 02–05 send none (05's receipts are Stripe's own) [DOC by grep of `features/02..06`].
- S0 scope: push notifications out ("not in the demo", S0 spec `:31`); email = SES + Hangfire `EmailJob`, template `login-code` only (built-so-far `:38-46`).
- [INF] Any S1 email (payment receipt, reservation confirmation, viewing confirmation, staff alert on a new lead) is a **QOL addition** to list in the S1 spec; S0 §13 already names "send the receipt" as an example post-payment side effect. Each new template goes under `Integrations/Email/Templates/`; staging is limited by `Email:AllowedRecipients`.

---

## 6. S0 carry-overs addressed to S1 (verbatim, with source)

From `CTX/docs/superpowers/plans/2026-10-12-s0-plan-index.md`:
- `:77-83` (Carry-overs from S0-3, **S1**):
  - "Add `customerId` to the summary line when binding fails. Today the endpoint filter sets it only once the handler stage is reached. Test it with the first signed-in POST."
  - "Outbox for the login-code email (a queuing failure after commit gives a 500 today)."
  - "Per-IP limits in Valkey, if the per-task count proves too loose."
  - "Optionally, move the per-email limit from a fixed window to a rolling one."
  - "Make `default(Money)` safe and use the invariant culture in `Money.ToString` once Money reaches EF or a DTO."
  - "Use `.HasConversion<string>()` for every enum property."
- `:117-124` (Carry-overs from S0-5, **S1**):
  - "Playwright smoke for the admin (sign-in, one edit)."
  - "A menu for narrow screens (below 768 px the sidebar is hidden and nothing replaces it), or an owner ruling that the admin is desktop-only." (Demo sidebar is also `hidden … md:flex`, `Sidebar.tsx` aside class — same gap.)
  - "Refetch `me` on window focus (two tabs keep an old name and menu until a call fails)."
  - "Server field errors show no trace id; a route error page replaces the whole shell; a 200 with a non-JSON body surfaces as a raw `SyntaxError`."
  - "Every new audited table adds a line to the audit screen's record types; every new admin page adds its menu item with a permission." (`admin-ui/src/features/audit/AuditPage.tsx:16-19`, `app/nav.ts`)
  - "A new `[Required]` nested request DTO or nullable enum is covered by `RequiredNotNullOpenApi`; re-check its tests after any `Microsoft.AspNetCore.OpenApi` upgrade."
  - "`admin-ui/src/main.tsx` must import `@/lib/zod-config` first (no test guards it); a lazy route chunk needs the same. Cheapest guard: both dialogs import `z` from one wrapper that sets the config."
- `:136` (Carry-overs from S0-6, **S1**; same text in `2026-10-13-s0-6-delivery.md:3262`): "scope the firewall's 8 KB body rule before any webhook or upload route; a Hangfire heartbeat or queue-age alarm; a stop timeout with the first long job; access logs once S3 exists."
- `2026-10-13-s0-3-customer-identity.md:69` (decision 3): per-IP limits in memory per task; "S1 may move these limits to Valkey." `:93` (decision 16): "No circuit breaker in S0: S1 adds `Microsoft.Extensions.Http.Resilience` for the outside calls."
- `2026-10-13-s0-5-admin-ui-shell.md:70`: "Playwright still starts in S1." `:3261`: "Recharts is 'from S1' and is not installed."

From the S0 spec `CTX/docs/superpowers/specs/2026-10-09-s0-foundation-design.md`:
- `:11` "S1 adds the per-country pieces (Stripe account, tax, SiteLink sites)."
- `:27-30` Out of S0 → S1: "SiteLink client and the linking of SiteLink tenants at sign-in (S1)", "Stripe (S1)", "the ElastiCache decision (S1)".
- `:44,47` folders "(S1+: Storage/ Payments/ Leads/ Bookings/ …)", "(S1+: SiteLink/ Stripe/ Files/)".
- `:122` `correlationId` "Carried into every Hangfire job … and into the outbox rows of S1".
- `:132` log props "when known: `siteId`, `country`".
- `:139` every outside call logs `integration, operation (WSDL op name), elapsedMs, outcome (ok/error/timeout/circuit-open), httpStatus, attempt`; "Whether staging may log redacted SOAP bodies is decided in S1."
- `:178-182` Money half-away-from-zero to 2 places only where a feature spec names it; "Conversion to Stripe integer cents happens only in the Stripe integration (S1)"; "S1 adds `site.time_zone`, an IANA name, default `Asia/Singapore`; Malaysian sites use `Asia/Kuala_Lumpur` … code never assumes [UTC+8]".
- `:206` "`customer` … S1 adds the SiteLink tenant links in its own table".
- `:222` "S1 adds 'link SiteLink tenants by this verified email' at this point" (inside `/auth/code/verify`).
- `:229` "Public routes (S1 browsing) are `[AllowAnonymous]` and rate-limited per IP. There is no app API key."
- `:239` "S1's outbox can remove this gap" (email queued after commit).
- `:330` "Charts | Recharts (from S1)"; `:333` no generic CRUD engine; `:353`, `:411` Playwright starts in S1.
- `:368` NAT fixed IPs "in case SiteLink or a vendor allowlists IPs; to confirm in S1".
- `:372` "ElastiCache Valkey … is budgeted; S1 decides what it caches (SiteLink unit and price data, rate limits). S0 does not create it."
- `:399` tests: "SiteLink and Stripe from S1, with recorded responses."
- `:435` open item 7 "In-app account deletion … Design it in S1".
- `:440-443` §13 "S1 outside-call rules (owner, 2026-10-09)": timeout + limited retry with backoff for safe reads only + circuit breaker on every outside call (`Microsoft.Extensions.Http.Resilience`; SiteLink SOAP binding gets the same limits); every post-payment side effect is an idempotent job whose trigger is saved in the payment's transaction — "an outbox row in our own table that a Hangfire job picks up, or Hangfire enlisted in that transaction; S1 picks one after checking what `Hangfire.PostgreSql` supports (not verified yet) … The S1 spec names the idempotency key per step and what staff see when the retries run out." "S1 adds: SiteLink tenant linking inside 'check the code' (only for the verified email, matched case-insensitively), `site.time_zone` and currency per site, the SiteLink cache decision (in-memory vs ElastiCache), Stripe, S3 if needed." Plus: every later spec checks the demo sync log and the client-artifact notes.

From `CTX/.claude/rules/cross-repo.md` §4 open decisions touching S1 [DOC]: 6 (account deletion, S1), 7 (SiteLink IP allowlist, confirm in S1), 10 (Stripe Connect model — ask PM before the S1 spec), 8 (artifact vs demo conflicts: insurance table, lease status "Active only when signed", "Add customer from SiteLink", refresh buttons, country filter), 2 (MY data hosted in SG — PDPA), 12 (staff sign-in hardening before production).

---

## 7. What already exists in ../CMS that S1 builds on [DOC, `CMS` at branch `s0-6-oidc-subject`, HEAD `a985ecb`, clean tree]

- **Features**: only `Features/Admin` and `Features/Identity`. Tables: `customer`, `login_code`, `customer_refresh_token`, `staff_user`, `role`, `audit_log` (+ `data_protection_keys`, `hangfire.*`). Migrations: `InitialPlatform`, `AddCustomerIdentity`, `AdminTables`, `StaffEmailCode`, `DropEntraObjectId` (`src/ExtraSpace.Api/Platform/Data/Migrations/`). Feature tables are read with `db.Set<T>()`, no `DbSet` on `AppDbContext` (built-so-far `:16`).
- **No `site` table, no site time-zone helper** anywhere: the only zone in code is the fixed `Asia/Singapore` for recurring jobs (`Platform/Jobs/RecurringJobs.cs:33`). No `Integrations/SiteLink`, no Stripe, no resilience package: `Directory.Packages.props` has no `Microsoft.Extensions.Http.Resilience`, `Stripe.net`, `System.ServiceModel.*` or Valkey/Redis client. `Integrations/` holds only `Email`.
- **Money** `src/ExtraSpace.Engines/Money.cs`: `record struct Money(decimal Amount, string Currency)`, `Money.Round(decimal)` = 2 places `AwayFromZero` (`:20`), operators check same currency, `ToString` uses current culture (`:32`, carry-over says make it invariant) and `default(Money)` has null Currency (carry-over).
- **Platform**: error envelope (`AppException`, ProblemDetails + `code` + `traceId`), FK/unique → 409 `CONFLICT`; `TimeProvider`; logging with `RequestLog.Add(ctx, "siteId", …)`; Hangfire jobs (`IRecurringJob`, `AddRecurringJob`, `Jobs:<name>:Enabled`, `JobTracingFilter` with `correlationId`); `IEmailSender.Enqueue` after commit; audit by `IAudited` + `AuditInterceptor` (same SaveChanges; `ExecuteUpdate` skips audit); `xmin` `Version` + PATCH/DELETE `version`; `.WithEnumGuard()`; strict JSON numbers; `RequiredNotNullOpenApi`; OpenAPI snapshot + `npm run gen:api` (built-so-far `:12-110`).
- **Customer auth**: `/api/v1` group `RequireCustomer()`; public browsing routes opt out with `.AllowAnonymous()` (needs per-IP rate limit policy — today only `auth-code`/`auth-verify` exist). `CustomerPrincipal` contract for the signed-in id.
- **Admin auth**: `/admin/api` group `RequireStaff()` (CSRF + audit context); permissions via `AddPermissions` + `.RequireAuthorization`; `HttpContext.StaffSession()`.
- **Admin UI** (`CMS/admin-ui/src`): `app/{App,Shell,ThemeSwitch,nav,routes}.tsx`, components `PageShell`, `DataTable` (TanStack Table 9, no paging/sorting), `ConfirmDialog`, `FormField`, `NativeSelect`, `ErrorNote`, shadcn `badge/button/dialog/input/label/sonner/table`; features `auth`, `dashboard` (placeholder "Reports arrive with the self-storage release."), `staff`, `roles`, `audit`; libs `forms.ts` (`applyServerErrors`, `dirtyValues`, `conflictMessage`), `time.ts` (browser zone), `query.ts`. React 19.3, react-router 8.4, TanStack Query 5, Tailwind 4, lucide 1.56. **Not present**: Recharts, Playwright, a textarea/checkbox/select-relation component, a pager component, grouped nav sections.

---

## 8. Design-relevant gaps / decisions to carry into the S1 spec [INF]
1. One list template + one form template in the UI, per-page static config, typed per-feature endpoints → "identical" without a generic CRUD engine. ~23 screens.
2. Read permissions vs demo's open reads; permission names (demo `*.write` vs our `*.manage`); Promotions = `promotions.write` never seeded.
3. Which demo-editable money/SiteLink records become read-only (Transactions, Leases) — deliberate difference, owner OK.
4. Customer profile columns (address, business, UEN) added to Identity's `customer` or a separate profile table; email immutable in admin?
5. `site` table owner (Storage/Sites feature) with `time_zone`, `currency`, `tax_percentage` (demo label "Tax % (GST)" → SST for MY), `country`; a site-zone date helper in Engines or Platform.
6. Units page: no live sync on load; "Sync now" QOL; UnitSync job with no-overlap guard.
7. Dashboard: site-zone (or SGT) day buckets, revenue per currency, consistent occupancy, decimal; Recharts install.
8. Outbox vs enlisted Hangfire for post-payment steps (also fixes the login-code-email 500 gap).
9. Resilience (timeouts, breaker, read-only retries) for SiteLink SOAP + Stripe; outside-call log line fields.
10. Before any webhook: the WAF 8 KB body rule scope.

Not checked: demo `admin-ui` Topbar/StatCard pixel details, `RelationSelect` behaviour beyond `pageSize=200`, the BizPlus/Cowork pages (out of S1), `Hangfire.PostgreSql` transaction enlistment (unverified, as S0 says), the client artifacts themselves (only their notes).
