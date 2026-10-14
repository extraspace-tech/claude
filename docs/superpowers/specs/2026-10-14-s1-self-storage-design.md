# S1 Self-storage — design spec

- **Date:** 2026-10-14
- **Status:** APPROVED by the owner 2026-10-14 (sections §1–§7 one by one, then the whole spec). Implementation plans follow (`docs/superpowers/plans/`).
- **Sub-project:** S1 (S0 Foundation → **S1 Self-storage** → S4 Extras; S2/S3 BizPlus deferred, PM 2026-10-13)
- **Repo:** `../CMS` (`extraspace-tech/cms`, 🔴 public)
- **Owner:** the user (the only backend developer); the Flutter app is built by the same team
- **Sources:** demo spec features 02–06 and 12 (`../Backend Demo/backend/.claude/backend-spec/`, demo at `6be4474`); research notes `docs/notes/s1-research/` (`s1-research-*.md`, `s1-checks.md`, `pm-stripe-artifact.md`); SiteLink notes `docs/notes/sitelink/` (`ccws-3.5-operations.md`, `sitelink-api-pdf-notes.md`); decision ledger `docs/notes/s1-research/brainstorm-decisions.md` (owner decisions 1–10, BA answers #1–25, PM answers #26–38); the PM's Stripe artifact; the old YES app (`../../Extra Space old/extraspace-backend`, read-only) for business rules.

## 1. Context

S0 built the platform: customer and staff sign-in by email code, errors, logging, jobs, email, admin shell, CI/CD. S1 adds self-storage on top: sites and units from SiteLink, quotes, reservations, move-ins, My Spaces, bills paid by card through Stripe Connect, autopay, leads, viewings, and the admin pages and Dashboard for all of it. The goal stays a functional copy of the demo (same screens and logic), written from scratch, without the demo's known defects.

Three countries: Singapore, Malaysia and **Korea** (owner, 2026-10-14). Currency, time zone and tax live per site. SG and MY take card payments through two separate Stripe platforms; Korea uses another payment provider (PM #26, not named yet), so Korean sites show "pay at the facility" in S1.

## 2. Scope

### In S1
- Demo spec features 02 (SiteLink), 03 (sites, units, quotes), 04 (reservations, move-in, My Spaces), 05 (Stripe, My Bills), 06 (leads, viewings), and the Dashboard of 12.
- Lucy paths 1–21 of the demo `README.md:340-377` (the app flows of self-storage), see §12.
- The PM's three Stripe flows: pay now with a saved card, autopay off-session, autopay needing 3DS.
- S0 carry-overs: outbox (also for the login-code email), outside-call resilience, `site.time_zone` and currency, Money fixes (`default(Money)`, invariant culture), enums as strings, `customerId` on the request summary line, WAF body-size rule for webhooks, Recharts.
- In-app account deletion (App Store rule; soft delete, §5.2).

### Out of S1
- Promotions admin page → S4 (SiteLink discount plans are still used in quotes).
- BizPlus: workspace units, co-worker tab, facility types (the `facility_type` column stays so S2 needs no migration).
- Push notifications (no provider yet); email only.
- The Korean payment provider (a later plan once the PM names it).
- Insurance (BA #22: none, added later).
- The YES app's daily payment-due emails (PM #37: left out; they would break the SiteLink call budget).

### Plans (each gets its own plan file; order)
1. **S1-1 Sites & SiteLink** — `site`, taxonomies, `unit`, SiteLink client, unit refresh, outbox, resilience, Money/enum carry-overs.
2. **S1-2 Tenants & My Spaces** — customer profile columns, account deletion, tenant linking, customer refresh, My Spaces, gate code, admin Customers / Leases.
3. **S1-3 Search, quotes, reservations, move-in** — browsing, quote engine, move-in cost, reserve / cancel / move-in flows (payments called through the S1-4 contract).
4. **S1-4 Payments core** (may split into 4a cards + pay-now, 4b posting + webhooks) — Stripe integration, saved cards, pay now, My Bills, SiteLink posting, webhooks, reconciliation, Transactions + Needs attention pages.
5. **S1-5 Leads, viewings, Dashboard** — can run in parallel with S1-3 / S1-4.
6. **S1-6 Autopay & 3DS** — last.

## 3. Decisions this spec rests on

| Topic | Decision | Source |
|---|---|---|
| House rule 3 (payments) | **Changed:** cards are collected only by Stripe's SDK in the app (`flutter_stripe` `CardField`, 3DS via `handleNextAction`); our server creates and confirms PaymentIntents; saved cards are stored as Stripe ids + brand / last4 / expiry / fingerprint only. Card data never reaches our servers or logs. Hosted Checkout is no longer used. Webhooks: two routes per platform, each signature-verified. | owner, decision 7 (PM design) |
| House rule 4 (SiteLink cards) | `MoveInReservation_v6` and `MoveInWithDiscount_v7` are called with every card / bank element blank and `iPayMethod 2` (Cash, documented API p.116). No other card-carrying operation is ever called (full list `ccws-3.5-operations.md:5`). | owner, decision 4 |
| Stripe Connect | Direct charges; SG and MY are separate Connect platforms; the existing per-facility connected accounts are reused; no application fee; refunds done by staff in the Stripe dashboard. | owner + PM + BA #5, #6, #8 |
| Architecture | Local copy of sites/units/leases; SiteLink called on demand only (call budget, §6.6); outbox table for side effects; no Valkey in S1. | owner, decision 5 + 2026-10-14 call-volume ruling |
| Test site | SiteLink writes only on `LSETUP` outside production; Stripe test mode with test cards and test connected accounts. LSETUP receipts are real receipts on a test facility (accepted). | owner decisions 6, 9; BA #21 |
| Admin pages | Same look and logic as the demo; Units, Leases, Reservations, Transactions are read-only with named actions. | owner, decision 3 |
| Reservations | Reservation fee charged in the app (fee + tax + deposit); cancel = Stripe refund; no automatic expiry, staff cancel. | BA #1, #2 (not yet confirmed), #3, #4 |
| Bills | Full balance shown, customer may pay any amount; minimum 10 for the whole payment and for each unit; autopay charges the full balance; autopay per unit, customer toggle. | BA #12–15, PM #34 |
| Prices | The customer pays SiteLink's exact move-in amount; the chosen promotion is passed to SiteLink. | BA #16, #17 |
| Account deletion | Soft delete in our system; SiteLink tenant untouched; personal data kept. | BA #24, owner |
| SiteLink failures after payment | Move-in refused → full automatic refund; payment refused with -14 → keep the money as the YES app does; -7 → refund and ask for the full balance. | BA #7, PM #29, #30 |

These decisions are recorded in `.claude/rules/cross-repo.md` §4 (2026-10-14) and in house rules 3 and 4 of `.claude/rules/cms.md` / `.claude/CLAUDE.md`.

## 4. Solution layout (additions to S0 §3)

```
src/ExtraSpace.Api/
  Features/
    Sites/        site, storage_type, unit_size, unit, unit_sync_state; browsing + admin
    Tenancy/      sitelink_tenant_link, reservation, move_in, lease, signed_agreement; My Spaces, reserve, move-in + admin
    Payments/     payment, payment_line, stripe_customer, payment_method(_clone), stripe_event; cards, pay now, bills, webhooks, autopay + admin
    Leads/        lead, viewing_appointment + admin
    Dashboard/    read-only admin endpoint (reads other features through their Contracts)
    Identity/     (S0) + profile columns, deletion, LinkTenants hook through Tenancy's contract
  Integrations/
    SiteLink/     SOAP client, one method per operation, return-code mapping, call counter
    Stripe/       one StripeClient per platform, minor-unit conversion
  Platform/
    Outbox/       outbox_message, dispatcher job, handler registry
src/ExtraSpace.Engines/
    Quotes/       rental-plan and reserve-charge maths (pure)
```

Each feature exposes only `Contracts/` (house rule 10). Main contracts: `ISiteDirectory` (site by id / code, zone, currency, tax, Stripe account), `IUnitCatalog` (unit read, live check, queue refresh), `ITenantLinks` (link, refresh customer, tenant for site), `ILeaseReader`, `IPaymentService` (start a payment for a reservation / move-in / bill, refund), `ICustomerDirectory` (Identity: read profile, soft-delete hooks), `IOutbox` (enqueue in the caller's transaction).

## 5. Data model

Conventions (S0): snake_case, UUID v7 ids, money `numeric(12,2)` + `char(3)` currency, `timestamptz` UTC, business dates as `date` in the site's zone, statuses as text with `HasConversion<string>()`, SiteLink ids `int`. Admin-edited tables get `xmin` version + audit. Every foreign key and hot query is indexed.

### 5.1 Sites (`Features/Sites`)

| Table | Columns | Rules |
|---|---|---|
| `site` | `location_code` UQ, `sitelink_site_id` UQ, `name`, `display_name`, `description`, `hero_image_url`, `address1`, `city`, `region`, `postal_code`, `country` (`SG`/`MY`/`KR`), `phone`, `latitude`, `longitude`, `time_zone` (IANA, NOT NULL), `currency` (`SGD`/`MYR`/`KRW`), `tax_percentage numeric(5,2)`, `tax_label` (`GST`/`SST`/`VAT`), `facility_type` (`SelfStorage` default; `Workspace` kept for S2), `active`, `stripe_account_id` (NULL = no in-app payments) | Staff-edited (demo form fields). No corp code column (config). |
| `unit_sync_state` | PK `site_id`, `last_time_polled_ticks bigint`, `last_synced_at` | Written only by the sync, so it never touches the staff-edited `site` row. |
| `storage_type` | `key` UQ, `name`, `display_name`, `icon_path`, `image_path`, `sort_order`, `active` | Staff-edited (demo). |
| `unit_size` | `key` UQ, `label`, `display_name`, `description`, `unit_group`, `image_path`, `min_area_sqft`, `max_area_sqft`, `sort_order`, `storage_type_id` | Staff-edited (demo). |
| `unit` | `site_id`, `sitelink_unit_id` (UQ with site), `sitelink_unit_type_id`, `unit_name`, `description`, `width`, `length`, `area_sqft`, `floor`, flags (`climate`, `inside`, `power`, `alarm`, `ada`, `mobile`), `standard_rate`, `web_rate`, `board_rate`, `push_rate`, `preferred_rate`, `standard_security_deposit`, `rented`, `rentable`, `waiting_list_reserved`, `deleted_at`, `storage_type_id`, `unit_size_id`, `last_synced_at`; `available` = stored generated column `rentable AND NOT rented AND NOT waiting_list_reserved AND deleted_at IS NULL` | Written only by the sync; read-only in admin. The sync sets `unit_size_id` from the area range (the demo never did). The demo's never-written `admin_fee` / `reservation_fee` columns are dropped. |

Dropped from the demo: `RentalPlanQuote` (written, never read), `UnitSyncCursor` (replaced by `unit_sync_state`). `Promotion` → S4.

### 5.2 Customer (`Features/Identity`)

`customer` gains nullable `address1`, `address2`, `city`, `country`, `postal_code`, `company_name`, `company_uen` (the demo's admin form, needed by `TenantNewDetailed_v3`) and `deleted_at`. Email stays immutable (sign-in identity and SiteLink link key); the unique email index becomes partial: `WHERE deleted_at IS NULL`.

**Account deletion** (`POST /api/v1/me/delete/code` + `POST /api/v1/me/delete {code}`): confirmed by an email code (the YES app's `opt_account_delete` template). Effects, in one transaction plus outbox steps: `deleted_at` set, refresh tokens revoked, autopay switched off on every lease, tenant links removed; outbox steps detach every saved card in Stripe and delete the Stripe customers. Profile, leases, reservations and payments stay. SiteLink tenant untouched. Signing in again with the same email creates a **new** account (PM #35 "TBD": default, easy to change).

### 5.3 Tenancy (`Features/Tenancy`)

| Table | Columns | Rules |
|---|---|---|
| `sitelink_tenant_link` | `customer_id`, `site_id`, `sitelink_tenant_id`, `linked_at`, `last_verified_at` | UQ (`site_id`, `sitelink_tenant_id`); several tenants per customer per site allowed; never moved to another customer. Gate code not stored. |
| `reservation` | `customer_id`, `site_id`, `unit_id`, `sitelink_tenant_id`, `sitelink_waiting_id`, `status` (`AwaitingPayment`/`Held`/`Converted`/`Cancelled`), `date_needed date`, `hold_until`, `concession_id`, `monthly_rent`, `reservation_fee`, `tax`, `security_deposit`, `total`, `currency`, `cancelled_by` (`Customer`/`Staff`/`System`) | Partial UQ on `unit_id` WHERE status IN (`AwaitingPayment`, `Held`): the database refuses two holds on one unit. `hold_until` only releases an unpaid hold; there is no business expiry (BA #4). |
| `move_in` | `customer_id`, `site_id`, `unit_id`, `reservation_id` (UQ, nullable), `sitelink_tenant_id`, `move_in_date date`, `concession_id`, `amount` (SiteLink's total), `amount_charged` (after reservation money), `currency`, `status` (`AwaitingPayment`/`Processing`/`Done`/`NeedsAttention`/`Cancelled`), `lease_id`, `attempted_at`, `last_error` | Written before any SiteLink write, so a repeat or a crash can be reconciled. |
| `lease` | `customer_id`, `site_id`, `unit_id` (nullable until the unit is synced), `sitelink_unit_name`, `sitelink_tenant_id`, `sitelink_ledger_id` (UQ with site), `start_date`, `end_date`, `monthly_rent`, `billing_frequency` (`Monthly`/`TwentyEightDay`), `status` (`Active`/`Ended`), `moved_in_at`, `moved_out_at`, `ended_reason`, `paid_through_date`, `balance`, `balance_refreshed_at`, `autopay_enabled`, `autopay_payment_method_id`, `last_synced_at`, `created_by_app` | Mirror of a SiteLink ledger; written by our move-in and by the customer refresh. Autopay columns used from S1-6. |
| `signed_agreement` | `customer_id` NOT NULL, `lease_id` / `reservation_id`, `storage_agreement_url`, `insurance_agreement_url`, `signed_at` | As the demo, with an ownership check; URLs must be https. |

### 5.4 Payments (`Features/Payments`)

| Table | Columns | Rules |
|---|---|---|
| `payment` | `customer_id`, `site_id`, `kind` (`ReservationFee`/`MoveIn`/`Bill`/`Autopay`), `status` (`Pending`/`Paid`/`NeedsAuth`/`Failed`/`FailedAuth`/`Refunded`), `amount`, `currency`, `platform` (`SG`/`MY`), `stripe_account_id`, `stripe_payment_intent_id` UQ, `payment_method_id`, `attempt`, `failure_code`, `failure_message`, `refunded_amount`, `disputed_at`, `paid_at`, `needs_auth_since`, `reservation_id`, `move_in_id`, `lease_id` + `period` (autopay) | The PM's "Transaction". One per site. UQ (`lease_id`, `period`, `attempt`) for autopay. |
| `payment_line` | `payment_id`, `lease_id`, `unit_id`, `sitelink_tenant_id`, `sitelink_ledger_id`, `amount`, `status` (`Pending`/`Posted`/`Refunded`/`NeedsAttention`), `attempted_at`, `sitelink_receipt_id`, `sitelink_receipt_number`, `posted_at`, `refund_id`, `last_error` | One SiteLink posting each (bills, autopay). Reservation-fee and move-in payments have no lines. |
| `stripe_customer` | `customer_id`, `platform`, `stripe_account_id` (NULL = the platform), `stripe_customer_id` | UQ NULLS NOT DISTINCT (`customer_id`, `platform`, `stripe_account_id`). |
| `payment_method` | `customer_id`, `platform`, `stripe_payment_method_id` UQ, `brand`, `last4`, `exp_month`, `exp_year`, `fingerprint`, `is_default` | Partial UQ: one default per (customer, platform); UQ (`customer_id`, `platform`, `fingerprint`). |
| `payment_method_clone` | `payment_method_id`, `stripe_account_id`, `stripe_payment_method_id` | UQ (`payment_method_id`, `stripe_account_id`). |
| `stripe_event` | PK `event_id`, `platform`, `type`, `received_at`, `processed_at` | Webhook de-duplication. |

### 5.5 Leads (`Features/Leads`)

| Table | Columns | Rules |
|---|---|---|
| `lead` | `name`, `email` (lower-case), `phone`, `site_id`, `unit_id`, `interest_type`, `duration_months`, `rental_amount numeric`, `status` (`New`/`Contacted`/`Converted`/`Closed`), `source`, `notes`, `customer_id` | As the demo; `customer_id` set when the sender is signed in. |
| `viewing_appointment` | `customer_id` NOT NULL, `customer_email`, `customer_phone`, `site_id`, `unit_id`, `scheduled_date date` (site zone), `time_slot time`, `status` (`Scheduled`/`Rescheduled`/`Cancelled`/`Completed`), `notes` | Partial UQ (`site_id`, `scheduled_date`, `time_slot`) WHERE status IN (`Scheduled`, `Rescheduled`): one viewing per slot, enforced by the database. |

### 5.6 Platform

`outbox_message`: `kind`, `payload jsonb`, `idempotency_key` UQ, `correlation_id`, `created_at`, `available_at`, `attempts`, `last_error`, `processed_at`, `failed_at`, `resolved_at`, `resolved_by_staff_id`, `resolution_note`. Written in the caller's transaction (Hangfire.PostgreSql cannot join an EF transaction: `s1-checks.md` §A).

`attention_item` is **not** a table: the Needs attention page reads failed outbox rows, `move_in` / `payment_line` in `NeedsAttention`, disputed and refunded-but-not-reversed payments, and link conflicts (logged as a failed outbox row of kind `LinkConflict`).

## 6. SiteLink integration (`Integrations/SiteLink`)

### 6.1 Client
- A typed `HttpClient` posting SOAP 1.1 envelopes to CCWs 3.5 (no WCF). One C# method per operation we use; element names and order exactly as the WSDL (`s1-checks.md` §B). The DataSet reply is parsed into rows; only the columns we need are read.
- Operations used: `UnitsInformation_v3`, `UnitsInformationByUnitID`, `UnitTypePriceList_v2`, `DiscountPlansRetrieve`, `PaymentSettings` (past-due limit), `TenantListDetailed_v3`, `TenantNewDetailed_v3`, `LedgersByTenantID` (also the gate code), `PaymentsByLedgerID`, `ReservationNewWithSource_v5`, `ReservationUpdate_v4`, `MoveInCostRetrieveWithDiscount_v2`, `MoveInReservation_v6`, `MoveInWithDiscount_v7`, `PaymentSimpleCashWithSource`. Each is tagged Read or Write.
- **Return codes are per operation** (API PDF: -2 / -14 mean different things on move-in and payment). Each method maps its own codes into a typed result; unknown negative codes become `SiteLinkException(operation, code, message)`.
- **Card guard:** the two move-in methods are built by one helper that writes every card / bank element blank and `iPayMethod 2`. A unit test asserts every card element is empty. No other card-carrying operation gets a method.
- `bTestMode` is never used (it still records the payment, API p.102/117/174).
- Sensitive replies: `LedgersByTenantID` carries SSN, web password and gate code, and `TenantListDetailed_v3` the gate code (API p.67-68, p.251); we read only the columns we need and never log or store the others.

### 6.2 Configuration
`SiteLink:BaseUrl`, `SiteLink:CorpCode`, `SiteLink:CorpUserName`, `SiteLink:CorpPassword` (user-secrets locally; Secrets Manager `es/<env>/sitelink` on AWS), `SiteLink:WriteAllowList` (location codes; dev / staging = `LSETUP`; production = empty = all sites). A Write operation for a site outside the list throws before any call. Login: our own API user once the client's SiteLink admin creates it (PM #31, level "API Regular"); until then the YES app's login, copied by the owner into secrets with a no-print command (Claude never reads the old config files).

### 6.3 Resilience
`Microsoft.Extensions.Http.Resilience`: 30 s per attempt, 60 s total; 2 jittered retries for Read operations only; one circuit breaker for the client. Writes are never retried automatically; an unknown outcome is settled by a read-back (§8.6, §9.5). Callers see 503 `SITELINK_UNAVAILABLE` (down / breaker open) or 502 `SITELINK_ERROR` (refused, code in the log).

### 6.4 Logging and call counter
One line per call: `integration=SiteLink`, `operation`, `siteCode`, `elapsedMs`, `outcome`, `retCode`, `attempt`. No request or response bodies on any environment. A counter per operation and site feeds a CloudWatch metric; a monthly total per operation with a configurable alarm threshold (`SiteLink:MonthlyCallAlarm`), because SiteLink's limit is monthly and unknown (PM #32).

### 6.5 Dates, money
SiteLink date-times are site-local without offset: one helper converts both ways with `site.time_zone`. SiteLink's null date is any year before 1800; the placeholder for the blank card-expiry element is verified on LSETUP. `UnitTypePriceList_v2.iCurrencyDecimals` is checked against `site.currency` during the unit refresh (mismatch = that site's refresh fails, logged).

### 6.6 Call budget (owner 2026-10-14: SiteLink complained about the old app's daily volume)
Rule: **SiteLink is called when someone needs the answer, never on a short timer, and never once per customer in a batch.**
- A rate limiter in the client: 2 calls/s per instance, Writes first in the queue.
- Price list and discount plans: `IMemoryCache` per site, 30 min. Past-due setting: per site, 24 h. Move-in cost: per (unit, date, concession), 5 min.
- Units: §6.7. Customers: §7.4. No scheduled bulk customer sync; "Sync all customers" exists only as a manual staff job, off by default, throttled to 1 call/s.

### 6.7 Unit refresh
- Nightly job `UnitRefresh` (03:00 site time, `Jobs:UnitRefresh:Enabled`, no overlap): each active site once, one site's failure does not stop the others.
- On demand: when a customer lists a site's units and `last_synced_at` is older than 60 min, the answer comes from our copy and one refresh for that site is queued (at most one per site per 60 min).
- First refresh of a site = full `UnitsInformation_v3(0, true)` (the demo bootstrapped with available units only and missed rented ones); then incremental by the ticks cursor. A site's upserts and its cursor commit in one transaction.
- Mapping (demo 03 §4.1): an absent column keeps the old value; booleans parsed strictly (`"false"` is false); `dDeleted` → `deleted_at`; `area_sqft` = width × length; `unit_size_id` from the area range; BizPlus tag → `Workspace` storage type kept for S2.
- Before a reservation or move-in, the one unit is read live (`UnitsInformationByUnitID`).
- Staff: "Sync now" per site and "Full resync" (resets the cursor).

## 7. Tenant linking and My Spaces (`Features/Tenancy`)

### 7.1 Linking at verified sign-in
After `/auth/code/verify` succeeds, Identity enqueues `LinkTenants(customerId)` in its transaction; sign-in never waits for SiteLink. The job calls `TenantListDetailed_v3` once with a blank `sLocationCode` (whole corp, fuzzy, max 50 rows, API p.251), keeps rows whose email equals the verified email (trimmed, case-insensitive), and creates a link for each one at a site in our `site` table. The staff action "Refresh from SiteLink" runs the same job.

### 7.2 Link rules
- A (site, tenant) already linked to another customer is never moved; a `LinkConflict` item goes to Needs attention.
- If a refresh shows that the tenant's SiteLink email (`sEmail` in the `LedgersByTenantID` reply, API p.67-68) no longer matches the customer, the link is removed (its leases leave My Spaces) and logged.
- A new tenant is created only for a paid reservation or move-in at a site with no link: `TenantNewDetailed_v3` from the verified profile, random 6-digit gate code, up to 3 tries on -2 (duplicate gate code, API p.266). The link is saved at once, because SiteLink's search lags behind new tenants.
- Gate code: never stored or logged. `GET /api/v1/me/leases/{id}/access-code` reads it live (`sAccessCode` from `LedgersByTenantID`), owner-checked, 5 per hour per customer (PM #36: shown on request).

### 7.3 My Spaces
`GET /api/v1/me/spaces` (customer from the token; the demo's `userId` query is gone) answers from our tables: `activeRentals`, `pastRentals`, `reservations` (AwaitingPayment / Held), `viewingAppointments` (active, from today), `refreshedAt`. `?unitType=co-worker` returns an empty list (BizPlus deferred).

### 7.4 Refreshing one customer (`RefreshCustomer`)
- Per linked (site, tenant): one `LedgersByTenantID`. Upsert leases by (site, ledger id): unit matched by (site, `sUnitName`) because the reply has no unit id (unknown unit → queue that site's unit refresh, keep `sitelink_unit_name`), rent, billing frequency (`28` → `TwentyEightDay`), start date, paid-through, balance (`chargeBalance`, demo 04 §4.8).
- Per-customer advisory lock `customer-refresh:<customerId>`; a second refresh while one runs is skipped.
- **Ending a lease** (fixes the demo's "end all leases when SiteLink lists none"): only from a successful reply where its ledger is absent (the documented reply has no moved-out date; if an undocumented `dMovedOut` after 1800 appears, it is used as the end date). Never on an error or timeout. Never a lease we created in the last 24 h. Each end is logged with `ended_reason`.
- **When it runs:** after a verified sign-in (§7.1); when the customer opens My Spaces or Bills and `refreshedAt` is older than 6 h (answer from the copy, refresh in background); `POST /api/v1/me/spaces/refresh` (pull-to-refresh: at most once per 10 min, otherwise returns the copy with 200 and `refreshedAt`); right before a payment (§9.3); after our own move-in, payment or autopay.

## 8. Search, quotes, reservations, move-in

### 8.1 Browsing (anonymous allowed, per-IP rate limit; from our tables)
`GET /api/v1/sites?country=` (with currency, tax, time zone), `GET /api/v1/storage-types`, `GET /api/v1/unit-sizes`, `GET /api/v1/units?location=&storageTypeId=&unitSizeId=&search=` (available units; shown price = `web_rate ?? standard_rate`, sorted by that same price, nulls last), `GET /api/v1/units/{id}`, `GET /api/v1/units/{id}/availability`. Demo rules kept: unknown location → empty list, `address` never null.

### 8.2 Quotes (`ExtraSpace.Engines/Quotes`, pure)
- `POST /api/v1/units/{id}/rental-plans` → 4 plans (1, 3, 6, 12 months) by the demo algorithm (03 §4.3; `s1-research-units-leases.md` §3.3): best applicable SiteLink discount plan on the whole multi-month total, ties keep the earlier plan, tax on (rent after discount + admin fee), grand total adds reservation fee and deposit. Each plan carries `concessionId`. `decimal`, half away from zero, the site's currency decimals. Not stored. Plans are labelled as estimates; the binding number is §8.3.
- `GET /api/v1/units/{id}/reserve-charges` → fee, tax on the fee, deposit, total (demo 03 §4.4; BA #2).
- These replace Lucy's `reserveAUnitSummary` and `rentalSubmissionSummary` together with §8.3; the demo's `/reservations/preview` and `/leases/preview` (which echoed client numbers) are dropped.

### 8.3 Exact move-in amount
`GET /api/v1/units/{id}/move-in-cost?date=&concessionId=` → the sum of `MoveInCostRetrieveWithDiscount_v2` rows for that date and promotion, plus the reservation money already paid and the amount to charge now. This is the only amount a move-in charges (BA #16).

### 8.4 Reserve (signed in)
`POST /api/v1/reservations {unitId, dateNeeded, concessionId?, paymentMethodId}`:
1. Unit available in our copy, then one live unit read.
2. Advisory lock `reserve:<unitId>`; insert `AwaitingPayment` with server-priced amounts and `hold_until` = now + 15 min (the partial unique index refuses a second hold).
3. Tenant: existing link, else `TenantNewDetailed_v3` (§7.2).
4. `ReservationNewWithSource_v5` (holds the unit in SiteLink), then the payment (§9.3, kind `ReservationFee`). Paid → `Held`. Declined → SiteLink reservation cancelled, `Cancelled`. 3DS → the reply carries the client secret; the reservation waits until paid or `hold_until`, then a job cancels it in SiteLink. Total 0 → `Held` at once.
Korean sites (no Stripe account) with a total above 0 → 409 `PAYMENTS_UNAVAILABLE`.
`dExpires` is sent empty, so SiteLink applies the site's own default (`PaymentSettings.iReservExpirDays`, API p.132); whether SiteLink then drops the waiting entry on its own is checked on LSETUP (open item 8).

### 8.5 Cancel
Customer `DELETE /api/v1/reservations/{id}` (own, `Held` only) and staff "Cancel" (admin): `ReservationUpdate_v4` cancel first; if SiteLink is down → 503 and nothing changes; then `Cancelled` and an outbox step refunds the reservation payment in full through Stripe (BA #3; key `refund-{paymentId}`). Unit's local `waiting_list_reserved` is cleared only when the unit is not rented.

### 8.6 Move-in (signed in)
`POST /api/v1/move-ins {unitId | reservationId, moveInDate, concessionId?, paymentMethodId, expectedAmount}`:
1. With a reservation: it must be the caller's and `Held`. Without: unit available + one live unit read.
2. Live move-in amount A (§8.3). If `expectedAmount` ≠ A → 409 `PRICE_CHANGED` with A; the app shows it and the customer confirms again. The client's number is never the price.
3. Insert `move_in` `AwaitingPayment` with `amount` = A and `amount_charged` = A − reservation money already paid (≥ 0; PM #28 — verified on LSETUP). Charge it (§9.3, kind `MoveIn`); 0 → straight to step 4.
4. Paid → outbox `CompleteMoveIn(moveInId)`: lock `move-in:<unitId>`, set `Processing` + `attempted_at`, then `MoveInReservation_v6` (with a reservation) or `MoveInWithDiscount_v7` with `dcPaymentAmount` = A, the chosen concession (BA #17), card elements blank, `iPayMethod 2`.
   - Success → `lease` (ledger id from the reply), reservation `Converted`, unit rented, `move_in` `Done`, receipt email.
   - Refused (-11 amount changed, unit not available, …) → full automatic refund + facility alert, `move_in` `NeedsAttention` (BA #7).
   - -95 invalid tenant → drop the link, find or create the tenant again, one more try.
   - Timeout / unknown → read `LedgersByTenantID` for a new ledger on that unit after `attempted_at`; found → treat as success; not found → one more try; read fails → `NeedsAttention`. Never a blind re-send.
5. `POST /api/v1/agreements` stores the signed agreement URLs, owner-checked (demo 04).

## 9. Payments (`Features/Payments`, `Integrations/Stripe`)

### 9.1 Stripe setup
Two platforms: `Stripe:Platforms:SG` and `Stripe:Platforms:MY`, each with `SecretKey`, `PublishableKey`, `PlatformWebhookSecret`, `ConnectWebhookSecret` (Secrets Manager `es/<env>/stripe-sg`, `es/<env>/stripe-my`). New keys are issued for the new system; nothing is taken from the old code. `site.country` picks the platform; `site.stripe_account_id` (the reused connected account; site list from the owner) is sent as `StripeAccount` on every facility call. One `StripeClient` per platform, never the global static key. No application fee. Amounts become minor units only inside `Integrations/Stripe` (SGD / MYR × 100, KRW × 1). Statement descriptor suffix `EXTRA SPACE ASIA` (PM #38). Stripe's own receipt emails are not used.

### 9.2 Saved cards
- `POST /api/v1/me/payment-methods/setup-intent {country}` → a SetupIntent on that platform for the customer's platform Stripe customer (created on first use), `usage: off_session`, cards only → `{clientSecret, publishableKey}`.
- The app collects the card with `CardField` and `confirmSetupIntent`, then calls `POST /api/v1/me/payment-methods {setupIntentId}`; the server reads the SetupIntent from Stripe, checks it belongs to this customer and succeeded, and stores the card. The platform webhook `setup_intent.succeeded` does the same as a backup. Both are idempotent on the PaymentMethod id; the same fingerprint for the same customer and platform is kept once.
- `GET /api/v1/me/payment-methods`, `POST …/{id}/default`, `DELETE …/{id}` (detaches the card and its clones; refuses while it is the autopay card of a lease unless another card is chosen).
- Cards are per country (PM #33): an SG card cannot pay at an MY site.
- Before the first charge at a site, the card is cloned to that site's connected account and a customer is created there (`payment_method_clone`, `stripe_customer`).
- Monthly job: card-expiry email (the old CMS `card_expire_alert` template).

### 9.3 Pay now (one core for all kinds)
`POST /api/v1/me/payments {lines:[{leaseId, amount}], paymentMethodId}` (bills; the reservation and move-in flows call the same core through `IPaymentService`):
1. Checks: leases are the caller's and `Active`; one live balance read per tenant (`LedgersByTenantID`); each line ≥ 10 (or exactly that lease's whole balance when it is below 10 — not expected, BA #13) and ≤ that lease's balance; the total ≥ 10 (PM #34); the -14 pre-check (`PaymentSettings` past-due days vs `paid_through_date`; blocked → 409 `PAY_AT_FACILITY`); the site has a Stripe account (else 409 `PAYMENTS_UNAVAILABLE`). Lines are grouped into one `payment` per site.
2. Insert `payment` `Pending` + lines and commit.
3. PaymentIntent on the connected account: `amount`, `currency`, facility customer + cloned card, `confirm: true`, `setup_future_usage: off_session`, `return_url: extraspace://stripe-redirect`, metadata `{app: "es-cms", paymentId, customerId, siteId, kind}`, idempotency key `pay-{paymentId}`.
4. Result: `succeeded` → `MarkPaid` (§9.4); `requires_action` → reply `{paymentId, status: "RequiresAction", clientSecret, stripeAccountId}` and the app calls `handleNextAction`; declined → `Failed` + "Your bank declined this card. Try another card."
5. `GET /api/v1/me/payments/{id}` returns the current status (the app polls it after 3DS).

### 9.4 One way to Paid
The immediate reply, the webhook and the reconciliation job all call `MarkPaid(paymentIntent)`: `UPDATE payment SET status = 'Paid' … WHERE id = @id AND status IN ('Pending','NeedsAuth')`. Only the caller that changed the row inserts the outbox steps in the same transaction: `PostPaymentLine` per line (bills, autopay), `CompleteMoveIn` (move-in), `HoldReservation` (reservation fee), and the emails. A duplicate changes nothing.

### 9.5 Posting to SiteLink (`PostPaymentLine`, outbox, key `post-line-{lineId}`)
Row lock on the line; skip if it has a receipt. Set `attempted_at`, call `PaymentSimpleCashWithSource(tenant, unit, amount, iSource 10)`:
- Success → `sitelink_receipt_id`, `sitelink_receipt_number`, `Posted`.
- -14 (past due, online payments disabled) → keep the money (PM #29, the YES rule), line `NeedsAttention`, facility email; staff record it at the counter.
- -7 (full payment required) and other refusals → refund that line (`refund-line-{lineId}`), line `Refunded`, facility email (`unsuccessful_sitelink_payment`) and customer email asking for the full balance where -7 (PM #30).
- Timeout / unknown → read `PaymentsByLedgerID` (last 12 months, API PDF) for a payment of that amount after `attempted_at` not already matched to another line; found → record it; not found → one more try; the read fails → `NeedsAttention`.
- When every line of a payment is settled → customer email (YES `successful_payment` + `receipt_email`; the SG / MY receipt layout).

### 9.6 Webhooks
- Routes: `POST /api/v1/payments/webhook/{sg|my}` (platform events) and `POST /api/v1/payments/webhook/{sg|my}/connect` (connected-account events). Each checks the signature with its own secret; bad signature → 400.
- The event id is inserted into `stripe_event` in the same transaction as the effect; a duplicate returns 200 and changes nothing; 2xx only after commit, so Stripe retries a failure.
- Events: `setup_intent.succeeded` (§9.2); `payment_intent.succeeded` → `MarkPaid`; `payment_intent.payment_failed` → `Failed`, or `NeedsAuth` when the code is `authentication_required`; `charge.refunded` → `refunded_amount`, full → `Refunded`, and a Needs attention item "reverse it in SiteLink" (BA #8: staff do it by hand); `charge.dispute.created` → `disputed_at` + Needs attention.
- PaymentIntents without our metadata (the old app on the same connected accounts) → 200, ignored. (The old app's own webhook acts only on its own Redis-tracked intents, `01-mobile-api.md:659-663`; not verified in its code.)
- The firewall's 8 KB body-size rule exempts these two paths (S0-6 carry-over).

### 9.7 Reconciliation
Hourly job: payments still `Pending` 30 min after creation → read the PaymentIntent from Stripe and apply it (missed webhooks). Stripe calls only.

### 9.8 My Bills
`GET /api/v1/me/bills` (from our lease copy, refreshed per §7.4): per site, the leases with `balance > 0`: unit, amount due, due date (`paid_through_date + 1 day`), `overdue` (due date before today in the site's zone), `payBlocked` (-14 pre-check), currency, and whether payments are available at that site. The app's Bills tab, the "pay selected units" screen and the amount editing (BA #12) use it with §9.3.

### 9.9 Autopay (plan S1-6)
- `PUT /api/v1/me/leases/{id}/autopay {enabled, paymentMethodId?}` with the consent text shown in the app (BA #15; off by default). The default card is used unless one is chosen.
- Daily job, 09:00 site time: leases with autopay on whose due date (paid-through + 1 day) is today → one live balance read each → skip when the balance ≤ 0 or the -14 pre-check blocks it → charge the full balance (BA #14) off-session (`off_session: true, confirm: true`, never `request_three_d_secure`), key `rent-{leaseId}-{period}-a{attempt}`.
- `insufficient_funds` → retry after 1 and 3 days (new attempt rows); `expired_card` / other declines → `Failed`, customer email (`unsuccessful_payment`) and facility email; network error → retry with the same key.
- `authentication_required` → `NeedsAuth`: email with the link `extraspace://payments/{id}/authenticate`, reminders after 1 and 3 days, `FailedAuth` after 7 days (BA #9; all three in config). `GET /api/v1/me/payments/{id}/authenticate` → `clientSecret`, `stripeAccountId`, card, amount, currency; the app confirms the same PaymentIntent (and may switch card).
- Paid → the same posting as §9.5.

### 9.10 Outbox (`Platform/Outbox`)
`IOutbox.Enqueue(kind, payload, idempotencyKey)` inside the caller's EF transaction. A Hangfire dispatcher runs every 30 s and is also nudged right after commit. Each handler is idempotent by its key and by the row state it checks. Retries back off (1, 5, 15, 60 min); after the last one `failed_at` is set and the row shows on Needs attention, where staff can Retry or Mark resolved with a note. The S0 login-code email moves onto the outbox (removes the S0 "queued after commit" gap). Every row carries the `correlationId` of the request that created it.

## 10. Leads and viewings (`Features/Leads`)

- `POST /api/v1/leads`: anonymous allowed, per-IP limit (5 per hour), `customer_id` set when signed in, email lower-cased, unknown unit / site ids ignored as in the demo, wrong types → 400 (the demo gave 500). No emails (as the demo).
- `GET /api/v1/viewing-appointments/time-slots?location=&date=`: the demo's 18 half-hour slots 09:00–17:30 in the site's zone, minus taken slots and, for today, slots already past.
- Signed in: `GET /api/v1/viewing-appointments/conflicts?unitId=` (own active viewings for that unit from today in the site's zone; the demo missed today); `POST /api/v1/viewing-appointments` (taken slot → 409 `SLOT_TAKEN` from the index); `PUT /api/v1/viewing-appointments/{id}` (own, active only; the demo revived cancelled / completed ones); `DELETE /api/v1/viewing-appointments/{id}` (own, soft cancel, idempotent); `GET /api/v1/me/viewing-appointments`.
- No reminder emails and no job that completes past viewings (as the demo); staff set `Completed` in admin.

## 11. Admin UI and Dashboard

### 11.1 Look
Same as the demo (`s1-research-crosscutting.md` §1–2): sidebar groups Platform, Tenants, Leads, Payments, plus Access Control holding the S0 Staff, Roles and Audit pages under the demo's labels; items alphabetical inside a group. List page: 20 rows, `start–end of total`, search box, one select per filter, New button, row click → full-page edit, trash icon + confirm, empty state, the demo's cell rendering ("—", Yes/No badges, status badges, `dd MMM yyyy`). Edit page `/<area>/<id>`: "← Back to …", one card, fields in the demo's order, "This record is read-only." Built from two shared React templates and a static config per page, on typed endpoints per feature (`GET ?page&pageSize&search&<filter>`, `GET {id}`, `POST`, `PATCH` with `version`, `DELETE ?version`). No generic CRUD engine (S0). Desktop only (owner, 2026-10-14). Recharts is added.

### 11.2 Pages

| Group › page | Access | Actions |
|---|---|---|
| Platform › Sites | edit, create | delete refused with 409 when units or leases use it |
| Platform › Storage Types, Unit Sizes | edit, create, delete | 409 when in use |
| Platform › Units | read-only, filter Available | Sync now (per site), Full resync, last sync per site |
| Tenants › Customers | edit except email | tenant links (read-only), Refresh from SiteLink, Unlink tenant |
| Tenants › Leases | read-only | — |
| Tenants › Reservations | read-only | Cancel (SiteLink cancel + Stripe refund) |
| Tenants › Viewing Appointments | edit, create (demo) | — |
| Leads › Leads | edit, create, delete (demo) | — |
| Payments › Transactions | read-only | shows PaymentIntent, SiteLink receipt number per line, refund and dispute state; refunds are done in the Stripe dashboard |
| Payments › Needs attention (new) | read-only list | Retry, Mark resolved (with a note) |

### 11.3 Permissions
Owner holds all. Reads of personal data and money need a permission (the demo left reads open). 403 when missing (S0). New names: `sites.manage`; `customers.read` (Customers, Leases, Reservations, Viewings, Leads); `customers.manage` (edit customer, refresh, unlink); `reservations.manage` (cancel, edit viewings); `leads.manage`; `payments.read`; `payments.manage` (Needs attention actions); `dashboard.read`. Sites, Storage Types, Unit Sizes and Units are readable by any staff. Every admin write is audited; the audit screen gets the new record types.

### 11.4 Dashboard
`GET /admin/api/dashboard?country=` (`dashboard.read`): the demo's 6 cards (Customers +week, Active Leases, Active Reservations, Occupancy %, Revenue, Leads +week) and its charts / lists (activity 14 days, leads by status, occupancy by site, payments donut, recent leads, recent transactions). Fixes: revenue = paid − refunded, **one figure per currency**; day buckets in `Admin:ReportTimeZone` (default `Asia/Singapore`) for company-wide counts and in the site's zone for per-site figures; one occupancy formula, deleted units excluded; the payments donut shows **by type** (bill, move-in, reservation fee, autopay) because only Stripe exists; country filter SG / MY / KR.

## 12. Mobile API summary and clients affected

| Lucy path (app today) | Our route |
|---|---|
| 1 getSelfStorageTypes | `GET /api/v1/storage-types` |
| 2 getUnitSizes | `GET /api/v1/unit-sizes` |
| 3 getUnitsAll | `GET /api/v1/units` |
| 4 GetUnitDetailsById | `GET /api/v1/units/{id}` |
| 5 getRentalPlans | `POST /api/v1/units/{id}/rental-plans` |
| 6 getReserveCharges | `GET /api/v1/units/{id}/reserve-charges` |
| 7 submitUnitInterest | `POST /api/v1/leads` |
| 8 getMySpaces | `GET /api/v1/me/spaces` (+ `POST …/refresh`) |
| 9 cancelReservation | `DELETE /api/v1/reservations/{id}` |
| 10 unitAvailabilityCheck | `GET /api/v1/units/{id}/availability` |
| 11 timeConflictCheck | `GET /api/v1/viewing-appointments/conflicts` |
| 12 reserveAUnit | `POST /api/v1/reservations` |
| 13 reserveAUnitSummary | `GET /api/v1/units/{id}/reserve-charges` |
| 14 rentalSubmission | `POST /api/v1/move-ins` |
| 15 rentalSubmissionSummary | `GET /api/v1/units/{id}/move-in-cost` |
| 16–20 BookAView | `GET …/time-slots`, `GET /api/v1/me/viewing-appointments`, `POST`, `PUT`, `DELETE /api/v1/viewing-appointments/{id}` |
| 21 userSignedAgreements | `POST /api/v1/agreements` |

New routes with no Lucy path: `GET /api/v1/sites`, `GET /api/v1/me/bills`, payment methods, payments, autopay, access code, account deletion.

**Clients affected:** Flutter (all self-storage screens; Stripe SDK `CardField` + 3DS; deep links `extraspace://stripe-redirect` and `extraspace://payments/{id}/authenticate`; 409 `PRICE_CHANGED` / `PAY_AT_FACILITY` / `PAYMENTS_UNAVAILABLE` / `SLOT_TAKEN`; `refreshedAt`); admin UI (new pages, OpenAPI types); Stripe (two platforms × two webhook endpoints, test connected accounts); SiteLink (new API user); AWS (Secrets Manager entries, WAF rule scope, CloudWatch metric and alarm).

## 13. Jobs and configuration

| Job | Schedule | Calls |
|---|---|---|
| `OutboxDispatcher` | every 30 s + nudge | per step |
| `UnitRefresh` | nightly 03:00 site time + on demand | SiteLink, 1 per site |
| `ReleaseUnpaidHolds` | every 5 min | SiteLink cancel per expired hold |
| `PaymentReconciliation` | hourly | Stripe only |
| `CardExpiryEmail` | monthly | none |
| `AutopayRun` | daily 09:00 site time (S1-6) | SiteLink 1 per due lease + Stripe |
| `AutopayAuthReminders` | daily (S1-6) | none |
| `SyncAllCustomers` | manual only, off by default | SiteLink, throttled 1/s |

Each has `Jobs:<Name>:Enabled`. Config keys introduced: `SiteLink:*` (§6.2), `SiteLink:MonthlyCallAlarm`, `Stripe:Platforms:{SG,MY}:*` (§9.1), `Autopay:RetryDays` (1, 3), `Autopay:AuthReminderDays` (1, 3), `Autopay:AuthGraceDays` (7), `Admin:ReportTimeZone`.

## 14. Testing

- Unit tests: quote engine with the demo's acceptance tables 03 Q1–Q12 (Q10 replaced by our rounding cases) as `[Theory]` in `decimal`; reserve charges `{10, 0.9, 50, 60.9}`; unit mapping C5–C10; site-clock Z1–Z5 plus MY and KR rows; minor-unit conversion (SGD, MYR, KRW); SiteLink return-code mapping per operation; the move-in card-field test; the write allow-list test.
- Integration tests (Testcontainers PostgreSQL): reservations R3–R14 and move-in L4–L13 (demo 04, minus the trusted-client-money rows), My Spaces M4–M13 and M17–M18 rewritten for our lease-ending rule, My Bills checks (05 §9.1 rows 1–8, 12–13), webhook rows 1–9 and 21–22, leads and viewings (06 §9.1–9.4, rows that encoded demo defects flipped), the partial unique indexes, `MarkPaid` race (two callers, one winner), outbox retry and failure, and an ownership-denied case for every customer route.
- SiteLink and Stripe are faked in tests with recorded, **synthetic** responses (the repo is public: no real data). Stripe: the official test-mode keys only on developer machines and staging, never in CI.
- Live walks on staging: SiteLink writes only on `LSETUP`; Stripe test cards (success, 3DS `4000 0027 6000 3184`, insufficient funds `4000 0000 0000 9995`); `stripe listen --forward-connect-to` locally.
- Checks on LSETUP before S1-3 / S1-4 are called done: whether an ended ledger drops out of `LedgersByTenantID` (or shows an undocumented `dMovedOut`), the blank card-expiry placeholder, whether SiteLink's move-in total includes the reservation money (see `PaymentSettings.bCreditReservationFeeMoveIn`), -7 behaviour on a partial payment.

## 15. Differences from the demo

**Defects not copied:** fake payments and client-trusted amounts; no ownership checks (`/me/spaces?userId=`, reservation cancel, move-in of another customer's reservation, viewings); identity taken from the request body's email; webhook double posting (claim by id, not status); "end all leases" on an empty ledger list; reservations never expire yet hold units forever (now: staff cancel + unpaid-hold release); generic admin CRUD on money and SiteLink records; dashboard summing currencies and bucketing by UTC day; promotions permission never seeded; live SiteLink sync of every site on each admin Units page load; unit size never set by the sync; 1970 placeholder dates.

**Deliberate changes:** preview endpoints dropped (server prices); quotes not stored; Units / Leases / Reservations / Transactions read-only; guarded admin reads; 403 instead of 401; PATCH with version instead of PUT of all fields; payments by type on the dashboard.

**Additions (QOL):** Sync now / Full resync / last synced; Refresh from SiteLink / Unlink tenant; reservation Cancel with refund; Needs attention page; Transactions linked to SiteLink receipt numbers; dashboard country filter; card-expiry email.

## 16. Definition of done for S1

1. All six plans built, reviewed and walked on staging; `dotnet build` 0 errors, all tests green, OpenAPI snapshot and admin types regenerated.
2. A customer on LSETUP can: sign in and see linked units, browse and quote, reserve with a saved card (incl. 3DS), cancel and get refunded, move in, see the lease in My Spaces, pay a bill partly and fully, switch autopay on, and complete a 3DS autopay from the email link — all with Stripe test cards.
3. Every SiteLink write in those walks has a receipt / ledger in LSETUP and a matching row in our Transactions page; no SiteLink write reached another site.
4. Staff can do every admin action in §11.2; Needs attention shows each failure kind at least once in tests.
5. The SiteLink call counter shows the calls per operation for the walks.
6. Decision log, house rules 3 and 4, and `docs/notes/cms/built-so-far.md` updated.

## 17. Open items

1. **BA #1–2** (reservation fee charged; contents) still "not confirmed".
2. **PM #26:** which Korean payment provider, and whether it is needed for release 1.
3. **PM #35:** re-signup after a soft delete (default: new account).
4. **Site → Stripe connected-account list** (Slack "Facility Information"): the owner exports it.
5. **Our own SiteLink API user** (PM #31 yes): the owner asks the client's SiteLink admin; blocks the live checks of §14.
6. **SiteLink's monthly call limit** (PM #32: unknown): ask SiteLink; set `SiteLink:MonthlyCallAlarm`.
7. Columns of `ChargesAndPaymentsByLedgerID` / `LedgersByTenantID_v2/_v3` and the Reporting API receipts report are undocumented; S1 does not need them unless the LSETUP checks show `LedgersByTenantID` lacks a field.
8. **SiteLink's own reservation expiry** (`iReservExpirDays`): if SiteLink drops a waiting entry that we still show as `Held`, the customer refresh must notice it. Checked on LSETUP; the rule is added in S1-3 if needed.
9. **PM #10:** receipt email format — the YES app templates are reused; the MY branch versions are compared when S1-4 is planned.
