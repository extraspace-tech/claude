# S1 research — payments / Stripe / My Bills (spec 05) + leads / viewings (spec 06)

Researcher: read-only Opus subagent, 2026-10-14. Demo at `6be4474` (local HEAD = baseline; I did NOT run
`git fetch`, so newer demo commits on origin/main were not checked).
Tags: **[DOC]** = documented, cite given. **[INF]** = my inference. **[STRIPE]** = Stripe docs via context7.
Paths: `SPEC` = `../Backend Demo/backend/.claude/backend-spec/`, `DEMO` = `../Backend Demo/backend/`,
`OLD` = `../../Extra Space old/extraspace-backend/` (secrets files not opened).

---

## 0. Top findings (design-relevant)

1. **The demo has only ONE real self-storage Stripe flow: My Bills** (`POST /api/v1/payments/checkout-session`).
   Reserve and move-in payments are NOT taken by the server: the app "collects money itself" and the
   server writes a `Transaction` row from the client's word [DOC SPEC/features/04:27-32, 04:526; DEMO/README.md:64-80].
   The demo web-app fakes it: `stripeSessionId: demo_sim_<uuid>`, `paymentStatus:"completed"`,
   in-app card form [DOC DEMO/web-app/src/pages/MoveInPage.tsx:76-97, 186-209]. Lease detail "Pay" is also
   "Simulated payment — no real charge" [DOC DEMO/web-app/src/pages/LeaseDetailPage.tsx:~188].
   → We must DESIGN move-in (and reservation-fee) payment from scratch: server-priced Checkout, SiteLink
   move-in only after `checkout.session.completed` (as a job). This is a new payment flow → business approval.
2. **Move-in pricing source of truth = SiteLink `MoveInCostRetrieveWithDiscount_v2`**; SiteLink rejects
   `MoveIn*` unless `dcPaymentAmount` equals the sum exactly (`-11 Payment amount does not match`) [DOC 04:~600].
   So the server must price the Checkout from that same call, and re-check at move-in time (price may move
   between checkout and webhook → late-payment / refund path needed). [INF]
3. **Old production already uses Stripe Connect with DIRECT charges per facility**: PaymentIntent created with
   `RequestOptions.StripeAccount = master_facility.stripe_account` for every non-default site; the default site
   (`SiteLink:SiteID`) charges on the platform; the PaymentMethod is cloned from the platform Customer onto the
   connected account [DOC OLD/ExtraSpaceAPI/mobile_api/DAL/PaymentDAL.cs:426-471 (yes-production), :434/:467 (mys)].
   Refunds use **the facility's own secret key** (`master_facility.stripe_secret_key`) not Connect
   [DOC PaymentDAL.cs:1011; notes 02-admin-cms.md:568]. SG and MY have **separate platform keys** (separate
   deployments) [DOC notes 03-core-data-infra.md:330,352]. Note: `01-mobile-api.md:464` says "no Connect account"
   — that line is wrong for payments (it is about saved cards); flag to fix the note.
4. **Connect webhook ≠ account webhook [STRIPE]**: events for direct charges live on the connected account and
   need a **Connect-scoped event destination** ("connected accounts scope delivers events for resources belonging
   to connected accounts, such as direct charges"); destination charges / platform charges need the
   **platform-scope** destination (https://docs.stripe.com/webhooks). Each destination has its own `whsec_`
   secret; the event carries `event.account` (https://docs.stripe.com/connect/payment-links).
   → "ONE signature-verified webhook" holds as ONE route, but with direct charges it must accept 2+ secrets
   (platform + Connect scope, × SG/MY platforms if two platforms). House-rule wording needs the owner's OK.
5. **Cross-border [STRIPE]**: self-serve cross-border payouts exist only for platforms in US/UK/EEA/CA/CH
   (https://docs.stripe.com/connect/cross-border-payouts); multi-currency settlement needs the connected
   account in the platform's region (https://docs.stripe.com/connect/multi-currency-settlement).
   → [INF] one SG platform paying MY connected accounts via destination charges / transfers is likely NOT
   self-serve. Simplest safe model = **one platform per country** (SG entity platform, MY entity platform),
   which is what the old system does. UNVERIFIED for direct charges cross-border — ask Stripe.
6. **My Bills money source**: amount cap = live SiteLink `chargeBalance` of the lease's ledger
   (`LedgersByTenantID`), `totalDue := chargeBalance` deliberately [DOC 04:396-398, 05:300-309]. Old system
   computes bills differently: sum of `dcBal > 0` charges from `ChargesAllByLedgerID`, **excluding Rent and
   Insurance charges with no invoice number yet** [DOC notes 01-mobile-api.md:438-442]. Rules differ → PM.
7. **Demo My Bills webhook can double-post to SiteLink** under concurrent duplicate deliveries (non-conditional
   update) and **silently swallows SiteLink failure** (SUCCEEDED + `siteLinkReceiptId NULL`, no retry/alert)
   [DOC 05:478, 05:416-418, 05:538]. Our outbox/job design fixes both.
8. **Currency is hard-coded `sgd`** in My Bills, credit package, cowork [DOC 05:546-552; payment.service.ts:106,138].
   We need per-site currency (SGD/MYR) + per-country Stripe account. `Transaction.amount` is `double` and stores
   the **unrounded client amount** [DOC 05:343, 05:664-666] → ours: `numeric(12,2)`, validated after rounding.
9. **Leads/viewings are thin and insecure**: anonymous key can do everything; no ownership; email from body;
   `customerId` never set; no server slot enforcement; no time zone; no emails; no SiteLink call; no cron
   [DOC 06:9-13, 06:413-433, 06:437-443]. Admin = generic CRUD only. SiteLink has a `LeadGeneration` op we could
   use (not used by the demo) [DOC docs/notes/sitelink/ccws-3.5-operations.md:79].
10. **Autopay / saved cards / e-wallets are client asks with no demo backing**: client app artifact shows a
    per-unit Recurring switch, saved cards, e-wallets (SG PayLah!, MY TNG/GrabPay/RazorPay) [DOC
    client-artifacts/02-es-app.md:64-65, 595, 650, 662-663]. Old system had a `RecurringPaymentJob`
    (off_session PaymentIntent on saved card) — **Disabled** [DOC notes 02-admin-cms.md:574-584, 636]. MY's
    `MakePayment2` is still live with 3DS [DOC 01-mobile-api.md:485-519, 773]. Any of these = new payment flow.

---

## 1. Payment flows in the demo (self-storage relevant)

### 1.1 Authorized Stripe flows (demo CLAUDE.md rule 4) [DOC 05:41-60]
1. My Bills (no `metadata.kind`) — **self-storage, S1**.
2. Facility booking `facility_booking` / extension `facility_extension` — BizPlus, deferred (S2).
3. Credit package `credit_package` — deferred (S2).
4. Cowork invoice `cowork_invoice` — deferred (S3).
Non-Stripe: reserve / move-in "app-reported" Transaction rows (PAYUP/STRIPE) [DOC 05:162-171].

### 1.2 My Bills checkout — `POST /api/v1/payments/checkout-session` [DOC 05:195-346]
- Auth: user JWT required; anon key → 401 "Sign in required to pay a bill".
- Body `{items:[{leaseId, amount>0}], successUrl, cancelUrl}`; redirect allowlist by `startsWith`
  (`https://extraspace-web-app.vercel.app/`, `http://localhost:5175/`, `http://localhost:4100/`,
  `esmobileapp://`, `extraspace://`) [DOC 05:274-290].
- Ownership: `Lease WHERE id IN … AND customerId = caller`, any status; count mismatch → 400 (also rejects dup ids).
- Price: client amount, server-capped: reject `amount <= 0 || amount > amountDue + 0.01`; `amountDue` =
  live SiteLink chargeBalance; balance unknown → 0 → reject. Partial payments allowed.
- Session: `mode=payment`, Customer (lazy `getOrCreateStripeCustomer`, no lock), one line per lease
  `"<site> — Unit <unit>"`, `sgd`, `Math.round(amount*100)`, `setup_future_usage=off_session`, metadata
  `{customerId, leaseIds}` (session only), **no kind, no payment_method_types, no expires_at (24 h), no
  idempotency key**.
- Then `Transaction.createMany` PENDING per lease, `providerReference = cs_…`, not in a tx with Stripe call.
- Response `{url}`.
- Defects [DOC 05:645-676]: double-tap → 2 sessions → overpay possible; delayed payment methods → rows FAILED and
  `async_payment_succeeded` ignored (money taken, no record); PI id not stored (no refunds); orphan session if
  insert fails; amount stored unrounded.

### 1.3 Webhook — `POST /api/v1/payments/webhook` [DOC 05:236-268, 361-421]
- Raw body; 500 `{"error":"webhook not configured"}` if no secret; 400 missing/invalid signature
  (`constructEvent`, 300 s tolerance); only `checkout.session.completed|expired` handled; everything else 200.
- Dispatch by `metadata.kind` (cowork → credit pkg → extension → facility → My Bills fallback).
- My Bills completed: `paid ? SUCCEEDED : FAILED`; select PENDING rows by session id; update (unguarded);
  for SUCCEEDED rows in parallel: `PaymentSimpleCashWithSource(locationCode, tenantId from SiteLinkTenantLink,
  unitId, amount, iSource=10)`; store `siteLinkReceiptId = iReceiptNum`; errors swallowed.
- Expired: PENDING → FAILED.
- Branch idempotency table [DOC 05:471-487]; no `event.id` table.
- C# notes: `EventUtility.ConstructEvent(..., throwOnApiVersionMismatch:false)` because Stripe.net checks API
  version and Node does not [DOC 05:764-765]; don't bind `[FromBody]`; exclude from auth/CSRF/body limits.
  API version pinned `2026-08-26.dahlia` [DOC 05:576, 585].
- SiteLink cash post: `iSource` must be 3 or 10 (5 → `-40`); no test-mode flag → real receipt even in Stripe
  test mode; use `LSETUP` sandbox corp [DOC 05:637-641, 791-793; DEMO/src/services/sitelink/operations/payments.ts:17-20].
- Note [INF]: `PaymentSimpleCashWithSource` posts per **unit** (`iUnitID`), not per ledger/charge; SiteLink
  allocates. Two leases on the same unit id across sites are disambiguated by location code.

### 1.4 Reservation (`POST /api/v1/reservations`) [DOC 04:480-526]
- `ReservationNewWithSource_v5` (waiting-list entry, no fee in SiteLink); `reserveCharge/securityDeposit/
  grandTotal` are **client-reported**, echoed and stored; optional Transaction from `paymentReference`.
  "No server-side check that the client-reported reserveCharge/grandTotal match GET /units/:id/reserve-charges".
- Server-side quote exists: `GET /api/v1/units/:unitId/reserve-charges` → `{reserveCharge, gst, securityDeposit,
  grandTotal}`, e.g. fee 10, tax 9 %, deposit 50 → 60.9 [DOC 03:527-530, 03:1030]; GST inconsistency between
  rental plans (fee excluded) and reserve-charges (included) [DOC 03:914].
- No ownership check on cancel [DOC 04:546, 788].

### 1.5 Move-in (`POST /api/v1/leases`) [DOC 04:549-603]
- `MoveInCostRetrieveWithDiscount_v2` → sum of `dcTotal` → `MoveInReservation_v6` / `MoveInWithDiscount_v7`
  with `iPayMethod=2` (cash), `paymentAmount = requiredPayment`, `testMode = SITELINK_TEST_MODE` (default
  "true"!). Client `grandTotal` only recorded. DB writes after SiteLink: DB failure → orphan SiteLink ledger.
- Anyone with the anon key can move in "as" any email [DOC 04:788].

### 1.6 Refunds
- None for self-storage in the demo (only facility R1–R4) [DOC 05:611-626]. My Bills refunds = manual in Stripe
  Dashboard + SiteLink.
- Old system: maker-checker refund (requestor flag → approver flag), Stripe refund with facility key, **SiteLink
  not touched** on refund (staff reverse by hand); no approver≠requestor check; double-click double refund
  possible [DOC notes 02-admin-cms.md:562-571].

### 1.7 Demo defects to never copy (payments)
- Storage payments on the client's word (reserve, move-in) — known defect list.
- Concurrent webhook double SiteLink post; swallowed SiteLink failure; no reconciliation job.
- No idempotency key on My Bills session; no expiry; delayed methods unhandled; PI id not stored.
- `Transaction` editable via generic admin CRUD (resource `transactions` is not `readOnly`; permission
  `payments.write`) [DOC DEMO/src/services/admin/resource-registry.ts:831-866] → staff can change amount/status.
- Dashboard `revenue` sums SUCCEEDED amounts across all currencies and by UTC day
  [DOC DEMO/src/services/domain/dashboard.service.ts:76, 107-130] → wrong once MYR exists.

---

## 2. My Bills (bills = SiteLink balances)

### 2.1 Demo [DOC 04:392-418, 686-743]
- Source: `GET /api/v1/me/spaces` (and `/me/login`) syncs leases from SiteLink `LedgersByTenantID` per
  (location, tenant) and attaches `balance: {chargeBalance, paidThruDate, totalDue}` per lease.
  `totalDue = chargeBalance` on purpose (SiteLink `dcTotalDue` is tenant-wide, repeated per row).
  `paidThruDate` = SiteLink `dPaidThru` verbatim (site-local, no offset).
- There is no separate "bills" endpoint; the app's Bills tab = leases with balance > 0.
- Lease sync side effect: zero current ledgers at a linked site ends ALL active leases there [DOC 04:714-721].

### 2.2 Old system [DOC notes 01-mobile-api.md:422-453]
- `GET /Payment/GetMyBills`: per unit, outstanding = Σ SiteLink charge `dcBal > 0`, **excluding Rent and
  Insurance charges with no invoice number yet**; due date = `dPaidThru + 1 day`; facility status "All Paid" /
  "Current" / "Overdue"; taxes from SiteLink (`dcTax1`, `dcTax2`); ops `LedgersByTenantID`,
  `ChargesAndPaymentsByLedgerID`, `ChargesAllByLedgerID`; Redis 1 min.
- Next bill date: `dPaidThru` in future → `dPaidThru + 1 day`; else `dAnniv` + 1 period (`UserBL.cs:641-656`).
- Receipts/invoices PDFs from SiteLink (`TenantInvoicesByTenantID`, Reporting `Receipts`, `PaymentsByLedgerID`);
  invoice list disabled by PM request.
- Min total ≥ 10 (S$/RM); per-unit ≤ 12 × monthly rent; `master_facility.allow_partial_payment` per facility
  [DOC 01-mobile-api.md:491-497; 03-core-data-infra.md:137].
- Points earned on successful payment (tier multiplier) — S4 rewards hook [DOC 01-mobile-api.md:516, 554-560].

### 2.3 Client artifact [DOC client-artifacts/02-es-app.md:146-177, 534-541, 655-669]
- Bills tab → facility list (status pill Overlocked > Overdue > Paid) → facility detail table
  Unit / Amt Due / Amt to Pay (editable, default = due) → "Pay Selected Units".
- Overdue banner on Home + routing R27. Overlocked status (not in demo/SiteLink fields we read).
- Prototype marks unit fully paid regardless of typed amount (prototype bug; demo server-caps).
- Storage tab only outside SG (Workspace tab SG only).

### 2.4 Rules to decide (PM) [INF]
- Which balance: ledger `chargeBalance` (demo) vs invoiced-only charges (old) — they give different "amount due"
  before the invoice date. Old rule hides rent not yet invoiced.
- Partial payments allowed? Old: per facility flag; demo: always; artifact: editable amount.
- Minimum payment (old: 10). Overpayment tolerance (demo +0.01 — drop it: we validate rounded decimal).
- Overdue definition (paid-through < today in site TZ?) and Overlocked source (SiteLink unit status? lock flag?).

---

## 3. Stripe Connect for SG + MY

### 3.1 Facts
- [DOC] PM 2026-10-13: payments use Stripe Connect; model OPEN (cross-repo.md §4 item 10).
- [DOC] Old system: per country one Stripe platform account (keys differ SG vs MY), per facility a connected
  account id (`master_facility.stripe_account`) + stored per-facility secret/publishable keys (AES), direct
  charges via `Stripe-Account` header, default site on the platform, refunds with the facility key. Express
  (CMS) uses Connect via `facilities.stripe_account_id` too [DOC 03-core-data-infra.md:41, 137, 161, 204].
  [INF] storing per-facility **secret keys** suggests Standard accounts owned by each entity; we must never
  store connected-account secret keys — use the platform key + `Stripe-Account` header for everything incl.
  refunds.
- [STRIPE] Direct charge Checkout: create the session with `stripeAccount: acct_…` option (Stripe.net:
  `RequestOptions.StripeAccount`), optional `payment_intent_data.application_fee_amount`
  (https://docs.stripe.com/connect/saas/quickstart).
- [STRIPE] Destination charge Checkout: session on the platform with `payment_intent_data.transfer_data.destination`
  (+ `application_fee_amount`), optional `on_behalf_of` to make the connected account settlement merchant
  (https://docs.stripe.com/connect/marketplace/quickstart, https://docs.stripe.com/connect/payment-links).
- [STRIPE] With `on_behalf_of`, Stripe converts to the connected account's default currency
  (https://docs.stripe.com/connect/currencies/fx-quotes-api).
- [STRIPE] Webhooks: connected-account scope for direct charges; platform scope for platform/destination/SCT
  charges and platform customers; `stripe listen --forward-connect-to` for local tests
  (https://docs.stripe.com/webhooks).
- [STRIPE] Idempotency keys ≤ 255 chars, pruned after 24 h (https://docs.stripe.com/api/connected-accounts).
- [STRIPE] Delayed methods emit `checkout.session.async_payment_succeeded|failed`
  (https://docs.stripe.com/api/checkout/sessions). [INF] PayNow (SG), FPX/GrabPay (MY) are relevant if
  e-wallets are approved → we must handle async events or pin `payment_method_types`.
- [STRIPE] Cross-border payouts self-serve only US/UK/EEA/CA/CH platforms
  (https://docs.stripe.com/connect/cross-border-payouts).
- [INF, verify with Stripe] With direct charges a platform Customer/PaymentMethod does not exist on the
  connected account; saved cards are per account (the old code clones PMs). Checkout with `customer` on a
  direct charge needs a Customer created on that connected account → our `stripe_customer_id` must be keyed by
  (customer, stripe account), not one column on Customer as in the demo [DOC 05:177].

### 3.2 Options (trade-offs) [INF]
| Option | Merchant of record / statement | Refunds & disputes | Webhook | Fit |
|---|---|---|---|---|
| A. Direct charges, one platform per country, connected account per legal entity (or per site) | connected account | connected account bears; refund via platform key + `Stripe-Account` | Connect-scope endpoint(s) | Matches old system; clean SG/MY split; customers/cards per account |
| B. Destination charges + `on_behalf_of`, one platform per country | connected account settles | platform debited, reverses transfer | platform-scope endpoint | One Customer + saved card on platform; simpler autopay later; platform carries dispute liability |
| C. Destination charges without `on_behalf_of` | platform | platform | platform-scope | Platform is merchant: tax/invoicing in platform entity name — likely wrong for 2 entities |
| D. One platform for SG+MY | — | — | — | Cross-border limits (§3.1) — likely blocked |
Recommended default to propose [INF]: A or B with **one platform per country** and the connected account id
stored per **site** (`site.stripe_account_id`, nullable = platform). Our Transaction row stores
`stripe_account_id` so refunds / lookups hit the right account.

### 3.3 Questions for the PM / business
1. Who owns the platform account(s)? One per country (SG entity, MY entity) or one group platform?
2. Connected accounts: per legal entity or per site (old = per facility)? Account type (Standard/Express/Custom)?
   Are the existing old-system connected accounts reused (they keep running for the old app)?
3. Charge type: direct vs destination (+ `on_behalf_of`)? Who bears disputes/refunds?
4. Application fee: any? (none in the old code [INF from PaymentDAL.cs:443-466: no ApplicationFeeAmount]).
5. Payment methods: card only, or PayNow / GrabPay / FPX / TNG (async → extra webhook events)?
6. Saved cards / autopay: in release 1? (needs Customer per account, off-session charges, SCA handling, consent).
7. Refunds: who may refund (maker-checker like old?), does SiteLink get a reversal entry, which op?
8. Move-in and reservation payments in-app: approved as new flows? Reservation fee retained or refunded on
   cancel?
9. Statement descriptor (old suffix "Extra Space Asia"); receipt emails from Stripe or from us?
10. MY `payment_verification` (Stripe payment link with expiry, MY only) — needed? [DOC 03-core-data-infra.md:107, 358]

---

## 4. Proposed payment shape for S1 (input for the spec, all [INF])
- One `payment` aggregate per Checkout (our table), `payment_line` per lease/unit; columns: `site_id`, currency
  (from site), `stripe_account_id`, `checkout_session_id` (unique), `payment_intent_id`, `amount numeric(12,2)`,
  status, `kind` (`bill`, `move_in`, `reservation_fee`), `idempotency_key`.
- Checkout creation: server prices (bills: SiteLink balance; move-in: `MoveInCostRetrieveWithDiscount_v2`;
  reservation: reserve-charges quote); Stripe idempotency key = our payment id; `expires_at` ≥ 30 min
  [DOC 05:603-605: Stripe minimum 30 min]; pin `payment_method_types` unless async handled; metadata
  `{kind, paymentId}` on session AND `payment_intent_data`.
- One payment per (customer, site) per Checkout [INF: a session belongs to one Stripe account under Connect →
  a multi-site bill payment must split per site/account; the demo's multi-lease single session breaks under
  Connect if leases are in different accounts].
- Webhook: verify against the configured secrets (platform + Connect scopes); store `event.id` in a processed
  events table (unique) — better than demo's per-branch guards; flip PENDING→PAID with conditional update and
  insert outbox rows in the SAME transaction; return 200.
- Jobs (idempotent): `PostBillPaymentToSiteLink(paymentLineId)` — guard: `sitelink_receipt_no IS NULL` +
  row lock; `CompleteMoveIn(paymentId)` — re-run cost check, call `MoveIn*`; if SiteLink refuses (unit gone /
  price changed) → refund job (Stripe idempotency key `refund-<paymentId>`). Retries exhausted → status
  `NEEDS_ATTENTION` + admin list + alarm.
- 🔴 Risk [INF]: `PaymentSimpleCashWithSource` and `MoveIn*` are NOT idempotent in SiteLink. A job that times out
  after SiteLink wrote the receipt will post twice on retry. Mitigation: before retrying, read
  `PaymentsByLedgerID` / ledger to detect the earlier receipt (match amount + time window), or no automatic
  retry after an ambiguous timeout (manual reconcile). Needs a decision.
- Reconciliation job: PENDING payments older than session expiry → ask Stripe (`sessions.get`) to catch missed
  webhooks (demo has none [DOC 05:563-565]).

---

## 5. Leads / viewings (spec 06)

### 5.1 Entities [DOC 06:57-135]
- `Lead`: name, email, phone?, siteId?, unitId? (storage only), interestType (free text: waitlist / call-back /
  quote-request), durationMonths int?, rentalAmount double? (opaque), status `NEW|CONTACTED|CONVERTED|CLOSED`
  (manual, no transitions), source `mobile-app`, notes (holds cowork unit line, preferred start, message),
  customerId never set by API. No indexes.
- `ViewingAppointment`: customerEmail (identity!), phone?, siteId (RESTRICT), unitId?, scheduledDate (UTC
  midnight of the day), timeSlot `"HH:MM"` text, status `SCHEDULED|RESCHEDULED|CANCELLED|COMPLETED`, notes,
  customerId never set. No unique (site, date, slot).

### 5.2 Endpoints (all accept the anonymous key) [DOC 06:146-317]
| Route | Behaviour |
|---|---|
| `POST /api/v1/leads` | body `{unitId?, unitInterestType?, durationMonths?, rentalAmount?, coworkUnitId?, preferredStart? YYYY-MM-DD, message? ≤1000, customer{name, email, phone?}}` → `{success:true, leadId}` 200; unknown unit ids silently ignored |
| `GET /api/v1/viewing-appointments/time-slots?location&scheduledDate` | 18 slots 09:00–17:30, capacity 1 per (site, UTC day, slot) for any unit; no hours/closures/TZ/past filter |
| `GET /api/v1/viewing-appointments/conflicts?userEmail&unitId` | `{hasConflict}` = active viewing for that unit+email with `scheduledDate >= now` (today not counted) |
| `POST /api/v1/viewing-appointments` | create SCHEDULED, 200 row; no slot/past/dup check; bad unitId → 500 |
| `PUT /api/v1/viewing-appointments/:id` | partial update, ALWAYS → RESCHEDULED (revives CANCELLED/COMPLETED); no ownership |
| `DELETE /api/v1/viewing-appointments/:id` | soft cancel; idempotent; no ownership |
| `GET /api/v1/me/viewing-appointments?userEmail` | active ones by email (case-sensitive), embeds full site + unit; JWT ignored |
Lucy paths these replace [DOC DEMO/README.md:340-377]: `submitUnitInterest`, `timeConflictCheck`,
`BookAView/getTimeSlots|getAll|create|update|deleteEvent` → the Flutter app needs all of them.

### 5.3 Side effects / integrations / crons [DOC 06:429-443]
None: no emails, no calendar invite, no audit, no SiteLink, no cron (nothing completes past viewings or ages
leads). Legacy flows "sometimes created a SiteLink waiting-list entry" [DOC 06:340-342]. SiteLink has
`LeadGeneration` (unused) [DOC sitelink ops :79] — [INF] could push leads into SiteLink's inquiry tracking so
site staff see them; field names must be read from the WSDL; ask PM.

### 5.4 Admin screens [DOC DEMO/src/services/admin/resource-registry.ts:228-260, 322-350]
- `leads`: group "Leads", icon TrendingUp, list `name, email, status, source, createdAt`, search `name, email`,
  order createdAt desc, permission `leads.write`, form fields name*, email*, phone, site, unit, interestType,
  durationMonths, rentalAmount, status enum, source, notes (text). Editable, creatable, deletable (generic).
- `viewingAppointments`: group "Tenants", icon Calendar, list `customerEmail, scheduledDate, timeSlot, status`,
  search `customerEmail`, order scheduledDate desc, permission `reservations.write`, fields customer, email*,
  phone, site*, unit, scheduledDate*, timeSlot*, status (4 values), notes.
- `transactions`: group "Payments", icon CreditCard, list `provider, amount, currency, status, createdAt`,
  search providerReference, permission `payments.write`, enum omits MANUAL [DOC 05:133-136].
- Dashboard [DOC DEMO/src/services/domain/dashboard.service.ts:43-150]: KPIs leadsTotal, leadsNew7d, revenue;
  30-day trend (signups, leads, revenue per UTC day); leadsByStatus; transactionsByProvider; recent 6 leads and
  6 transactions. [INF] ours: revenue per currency, day buckets in site/country TZ.
- Client admin artifact has the same nav groups (Tenants: Customers, Leases, Reservations, Viewing Appointments);
  its viewing page not wired [DOC client-artifacts/03-es-admin.md:26, 259, 276]. No leads screen in artifacts.
- Owner wants identical admin pages: generic list/edit pages. [INF] keep the look, but our API is explicit
  per resource (no generic CRUD engine per S0 spec) and Transaction/payment pages read-only.

### 5.5 Port decisions to flag [INF unless cited]
- Ownership (security rule 7): signed-in callers → identity from JWT; set `customerId`; `/me/viewing-appointments`
  from the token. Guests: keep anonymous create? If yes, PUT/DELETE need a secret (e.g. per-appointment
  manage token) — otherwise anyone with an id can cancel. Demo's own suggestion: check only for `type==user`
  [DOC 06:423-427]. Contract change for Flutter.
- Slot rules: site TZ (`site.time_zone`), opening hours per site, reject past slots, enforce capacity with a
  partial unique index `(site_id, scheduled_date, time_slot) WHERE status IN (SCHEDULED, RESCHEDULED)`.
- Lower-case emails; integer `durationMonths` → 400 not 500; unknown unitId → 400/404 not 500.
- Notifications: confirmation email to customer + site staff? (none in demo; old app's feedback form emailed the
  company mailbox [DOC 01-mobile-api.md:590]). Spam/rate limit on anonymous `POST /leads`.
- Cron: mark past viewings COMPLETED / NO_SHOW? Lead aging? None in demo.

---

## 6. Acceptance tables worth porting as xUnit [DOC]
- Spec 05 §9.1 My Bills checkout (13 rows) — keep 1-8, 12-13; change 9-10 (no +0.01 tolerance, decimal), 11.
  [05:826-842]
- Spec 05 §9.2 webhook rows 1-9, 21-22 (My Bills + generic); 10-20 belong to S2/S3. [05:844-869]
- Spec 05 §9.3 rounding — replace with our decimal rounding helper tests (JS-parity cases irrelevant once
  money is `decimal`; keep `29.10 → 2910` minor units, `1.005 → 1.01` with AwayFromZero if that is the rule).
- Spec 06 §9.1 leads (13 rows), §9.2 time slots (9), §9.3 conflicts (7), §9.4 CRUD (12) [06:547-611] — keep the
  shape rows; rows that encode defects (9.4 #3 double booking, #4 500, #7 revive CANCELLED, 9.3 #6 case-sensitive,
  9.1 #13 customerId null) flip if we fix them.
- Spec 04 Q12 reserve-charges `{10, 0.9, 50, 60.9}` [03:1030] for reservation-fee pricing.
- Old system: next bill date rule and bill outstanding rule [01-mobile-api.md:427-440] if PM chooses old rules.

---

## 7. Disagreements (artifact / old vs demo)
| Topic | Demo | Old system | Client artifact |
|---|---|---|---|
| Bill amount | ledger chargeBalance | Σ dcBal>0 excl. un-invoiced rent+insurance | amountDue, editable |
| Partial pay | yes, ≤ balance (+0.01) | per-facility flag, min 10, ≤ 12× rent | any amount (bug: marks fully paid) |
| Card entry | hosted Checkout | Stripe SDK token in app, 1 saved card | in-app form (we never do) |
| Saved cards | Stripe Checkout remembers (`off_session`) | `user_payment_card`, one card | list, default, Remove, Recurring flag |
| Autopay | none (web-app localStorage fake) | RecurringPaymentJob, Disabled | per-unit switch |
| E-wallets | none | none | SG PayLah!, MY TNG/GrabPay/RazorPay |
| Connect | none (one key, sgd) | direct charges per facility | — |
| Move-in payment | app-reported / simulated | n/a (no move-in in old app) | fake Stripe |
| Refund | none for storage | maker-checker, facility key, SiteLink untouched | never to card (app) |
| Late fee (storage) | from SiteLink | Express-only late fees | S$25 / 10 days overdue (agreement text) [03-es-admin.md:192, 245] |
| Overlocked status | none | none | Overlocked > Overdue > Paid |
| Rewards on payment | none | points on success | "1 pt per S$1" text |
| 3DS | Checkout handles | MY true, SG false | — |
| Leads/viewings | thin, anon | not in old YES app (Lucy had them) | admin nav only |

---

## 8. Not verified / gaps
- Demo `origin/main` not fetched: payments/leads changes after `6be4474` unknown.
- Stripe: direct charges across regions; Customer reuse under direct charges; Stripe.net current API version
  and `EventUtility` signature options — check with context7/Stripe before the plan.
- `Hangfire.PostgreSql` transaction enlistment (outbox vs enlisted job) — still open from S0 spec §8.
- SiteLink `LeadGeneration` field names and whether SG/MY sites use SiteLink inquiry tracking.
- Whether the old connected accounts (one per facility) are the ones the PM means by "Stripe Connect".
- `bTestMode` behaviour of `MoveIn*` (`SITELINK_TEST_MODE` default true in demo) [DOC 04:602].
