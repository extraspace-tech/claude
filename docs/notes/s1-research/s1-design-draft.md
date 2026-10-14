# S1 design draft (sections as presented; the spec is written from this)

## §2 Data model (presented 2026-10-14, awaiting yes)

Conventions (S0): snake_case, UUID v7 ids, `numeric(12,2)` money + `char(3)` currency, `timestamptz` UTC, business dates as `date` in the site's zone, statuses as text (`HasConversion<string>()`), SiteLink ids `int`. Admin-edited tables get `xmin` version + audit. A feature reads another feature only through `Contracts/`.

### Sites (feature `Sites`, plan S1-1)
| Table | Columns (main) | Notes |
|---|---|---|
| `site` | `location_code` UQ, `sitelink_site_id` UQ, `name`, `display_name`, address, `latitude`/`longitude`, `country` (`SG`/`MY`/`KR`), `time_zone` (IANA, NOT NULL), `currency` (`SGD`/`MYR`/`KRW`; minor units per currency, KRW has none), `tax_percentage numeric(5,2)`, `tax_label` (`GST`/`SST`/`VAT`), `facility_type` (kept for S2), `active`, `stripe_account_id` (NULL = cannot take payments) | Admin-edited, like the demo. No corp code column (config). |
| `unit_sync_state` | PK `site_id`, `last_time_polled_ticks bigint`, `last_synced_at` | Separate from `site` so the sync never writes an admin-edited row. |
| `storage_type`, `unit_size` | as the demo (`key` UQ, labels, sort, `min/max_area_sqft`) | Admin taxonomies. |
| `unit` | `site_id`, `sitelink_unit_id` (UQ with site), `sitelink_unit_type_id`, `unit_name`, width/length/`area_sqft`, floor, feature flags, 5 rates + `standard_security_deposit` (nullable numeric), `rented`, `rentable`, `waiting_list_reserved`, `deleted_at`, `storage_type_id`, `unit_size_id`, `last_synced_at`; `available` = stored generated column | Sync-only writer; admin read-only. Fix: sync sets `unit_size_id` from the area range. Dropped: never-written `admin_fee` / `reservation_fee`. |

Dropped: `RentalPlanQuote` (written, never read). `Promotion` → S4.

### Customer profile (feature `Identity`)
`customer` + nullable `address_line1`, `address_line2`, `postal_code`, `city`, `country`, `company_name`, `company_uen`. Email stays immutable. `deleted_at`. Account deletion (BA #24 + owner: soft delete, personal data kept): confirmed by an email code; `deleted_at` set, refresh tokens revoked, autopay off, saved cards detached in Stripe, tenant links removed; the profile and all history stay. Email unique only among live rows (partial UQ where `deleted_at IS NULL`). SiteLink tenant untouched.

### Tenancy (feature `Tenancy`, plans S1-2/S1-3)
| Table | Columns (main) | Notes |
|---|---|---|
| `sitelink_tenant_link` | `customer_id`, `site_id`, `sitelink_tenant_id`, `linked_at`, `last_verified_at` | UQ (`site_id`, `sitelink_tenant_id`); several tenants per customer per site allowed; never moved silently to another customer. Access code NOT stored (read live). |
| `reservation` | `customer_id`, `site_id`, `unit_id`, `sitelink_tenant_id`, `sitelink_waiting_id`, `status` (`AwaitingPayment`/`Held`/`Converted`/`Cancelled`), `date_needed date`, `hold_until` (only for `AwaitingPayment`, technical release of an unpaid hold), `concession_id`, `monthly_rent`, `reservation_fee`, `tax`, `security_deposit`, `currency` | Partial UQ on `unit_id` where status in (`AwaitingPayment`,`Held`) = DB guard against double holds. |
| `move_in` | `customer_id`, `site_id`, `unit_id`, `reservation_id`, `sitelink_tenant_id`, `move_in_date date`, `amount` (SiteLink's move-in total), `currency`, `status` (`AwaitingPayment`/`Processing`/`Done`/`NeedsAttention`/`Cancelled`), `lease_id`, `last_error` | Intent row written before any SiteLink call. UQ `reservation_id`. |
| `lease` | `customer_id`, `site_id`, `unit_id`, `sitelink_tenant_id`, `sitelink_ledger_id` (UQ with site), `start_date`, `end_date`, `monthly_rent`, `billing_frequency`, `status` (`Active`/`Ended`), `moved_in_at`, `moved_out_at`, `paid_through_date`, `balance`, `balance_refreshed_at`, `autopay_payment_method_id` (S1-6), `last_synced_at` | Mirror of a SiteLink ledger; written by move-in and by the sync. Autopay: `autopay_enabled` (customer toggle per unit, BA #15) + `autopay_payment_method_id`. |
| `signed_agreement` | `customer_id` NOT NULL, `lease_id`/`reservation_id`, two URLs, `signed_at` | As the demo, owner-checked. |

### Payments (feature `Payments`, plans S1-4/S1-6)
| Table | Columns (main) | Notes |
|---|---|---|
| `payment` | `customer_id`, `site_id`, `kind` (`ReservationFee`/`MoveIn`/`Bill`/`Autopay`), `status` (`Pending`/`Paid`/`NeedsAuth`/`Failed`/`FailedAuth`/`Refunded`), `amount`, `currency`, `stripe_account_id`, `stripe_payment_intent_id` UQ, `payment_method_id`, `attempt`, `failure_code`, `refunded_amount`, `disputed_at`, `paid_at`, `reservation_id`/`move_in_id`, autopay `lease_id` + `period` | PM's "Transaction". One per site. Stripe idempotency key `pay-{id}` / `rent-{leaseId}-{period}-a{attempt}`; UQ (`lease_id`,`period`,`attempt`) for autopay. |
| `payment_line` | `payment_id`, `lease_id`, `unit_id`, `sitelink_tenant_id`, `sitelink_ledger_id`, `amount`, `sitelink_receipt_id`, `posted_at` | One SiteLink posting each; `sitelink_receipt_id IS NULL` = not posted yet. |
| `stripe_customer` | `customer_id`, `platform` (`SG`/`MY`), `stripe_account_id` (NULL = platform), `stripe_customer_id` | UQ NULLS NOT DISTINCT (customer, platform, account). Merges the PM's platform customer + `StripeAccountCustomer`. |
| `payment_method` | `customer_id`, `platform`, `stripe_payment_method_id` UQ, `brand`, `last4`, `exp_month`, `exp_year`, `fingerprint`, `is_default` | Partial UQ one default per (customer, platform). No card data. |
| `payment_method_clone` | `payment_method_id`, `stripe_account_id`, `stripe_payment_method_id` | UQ (`payment_method_id`, `stripe_account_id`). |
| `stripe_event` | PK `event_id`, `platform`, `type`, `received_at`, `processed_at` | Webhook dedupe. |

### Platform
`outbox_message`: `kind`, `payload jsonb`, `correlation_id`, `created_at`, `available_at`, `attempts`, `last_error`, `processed_at`, `failed_at`. Written in the same transaction as the change; a Hangfire job drains it. Also fixes the S0 login-code email gap. "Needs attention" = a screen over failed outbox rows + `move_in`/`payment` problem states; no table of its own.

### Leads (feature `Leads`, plan S1-5)
| Table | Notes |
|---|---|
| `lead` | As the demo + `customer_id` (set when signed in), `rental_amount numeric`; status `New`/`Contacted`/`Converted`/`Closed`. Anonymous allowed (rate-limited). |
| `viewing_appointment` | `customer_id` NOT NULL (sign-in required), `site_id`, `unit_id`, `scheduled_date date` (site zone), `time_slot time`, `status`; partial UQ (`site_id`,`scheduled_date`,`time_slot`) where active = capacity 1 enforced by the DB. |

Open in §2: (a) cards are saved per country platform; (b) account deletion = soft delete, personal data kept (BA #24 + owner); signing in again = new account (default); (c) viewings need sign-in. No business expiry of reservations (BA #4: staff cancel).

### Findings from `s1-checks.md` (2026-10-14) that touch the design
- Hangfire.PostgreSql cannot join an EF transaction (own connection; only ambient `TransactionScope`) → outbox table confirmed.
- Every `ReservationFeeAdd*` takes card data → the reservation fee cannot be recorded in SiteLink on the reservation. Proposed default: Stripe charges the fee at reserve; at move-in, `MoveIn*` posts SiteLink's full total, Stripe charges total − fee already paid (same connected account). Cancel/expiry → refund or keep = PM #3. New PM question.
- `PaymentSimpleCheckWithSource` (`sCheckNumber`) / `PaymentSimpleBankTransferWithSource` (`sTransferNumber`) are card-free and carry a reference (our payment id) → dedupe by read-back. Stays Cash unless finance agrees (shows as cheque / transfer in SiteLink reports).
- Bill-read ops' response columns are unknown (the demo never calls them) → My Bills needs one LSETUP capture, blocked on our SiteLink login (PM #18).

## §3 SiteLink client + unit sync (APPROVED 2026-10-14, with the revision and PDF additions below)

- **Client:** `Integrations/SiteLink/`, a typed `HttpClient` that posts SOAP 1.1 envelopes (no WCF / `System.ServiceModel`). One C# method per operation we use (~20); element names exactly as the WSDL. The DataSet reply (`diffgram`) is parsed into rows; `RT.Ret_Code < 0` → `SiteLinkException(code, message)`. Each operation is tagged Read or Write.
- **Card guard:** `MoveInReservation_v6` / `MoveInWithDiscount_v7` built by one helper that always writes the card / bank elements blank + `iPayMethod 2`; a unit test asserts every card element is empty. No other card-carrying operation has a method (never-call list, `ccws-3.5-operations.md:5`).
- **Config:** `SiteLink:BaseUrl`, `CorpCode`, `CorpUserName`, `CorpPassword` (user-secrets locally, Secrets Manager `es/<env>/sitelink` on AWS), `SiteLink:WriteAllowList` (location codes; staging/dev = `LSETUP` only; production = empty = all). A write to another site outside production throws before any call.
- **Resilience:** `Microsoft.Extensions.Http.Resilience`: timeout per attempt 30 s, total 60 s; retries (2, jittered back-off) for Read operations only; circuit breaker for the client. Writes never retry automatically; an unknown outcome (timeout) is resolved by a read-back (§7).
- **Errors to callers:** SiteLink down / breaker open → 503 `SITELINK_UNAVAILABLE`; SiteLink refusal → 502 `SITELINK_ERROR` (code in log). Known codes mapped where a flow needs them (-11 amount mismatch, -95 invalid tenant, -14 TBD).
- **Logging:** one line per call: `integration=SiteLink`, `operation`, `siteCode`, `elapsedMs`, `outcome`, `retCode`, `attempt`. Never request/response bodies on any environment (names, emails, gate codes inside).
- **Dates:** SiteLink dates are site-local without zone → one helper converts with `site.time_zone`.
- **Cache:** `IMemoryCache` per instance: price list (`UnitTypePriceList_v2`) and discount plans (`DiscountPlansRetrieve`) per site, 30 min. No Valkey.
- **Sites:** not synced; staff create and edit them (as the demo).
- **Unit sync job:** Hangfire recurring `UnitSync` every 15 min (`Jobs:UnitSync:Enabled`), `DisableConcurrentExecution`, active sites one by one, one failing site does not stop the others. First run per site = full `UnitsInformation_v3(0, true)` (demo's available-only bootstrap left rented units missing); then incremental by the ticks cursor. A site's upserts + cursor commit in one transaction. Mapping: absent column = keep old value, strict boolean parse, `dDeleted` → `deleted_at`, `unit_size_id` from area, BizPlus tag kept for S2.
- **Staff actions (QOL):** "Sync now" per site (enqueues that site) and "Full resync" (resets the cursor). Units page shows each site's `last_synced_at`.
- **Live unit refresh:** unit detail older than 30 min → one live `UnitsInformationByUnitID` (at most once per unit per 10 min); failure → stale data shown.
- **Tests:** recorded responses as synthetic XML fixtures (public repo: no real data), mapping + return-code tests, the card-field test, an allow-list test.

### §3 revision (owner 2026-10-14: SiteLink complained about call volume; old `TenantAsync` monthly + manual)
Replaces "Unit sync job every 15 min" and "Live unit refresh" above. Rule: **SiteLink is called when someone needs the answer, never on a short timer.**
- **Units (per site, 1 call = one site's changes):** one nightly incremental pass over active sites (03:00 site time) + on demand: when a customer browses a site whose data is older than 60 min, we answer from our copy at once and queue one incremental refresh for that site (at most 1 per site per 60 min). Before reserve / move-in, the one unit is read live (needed for correctness anyway). Staff "Sync now" / "Full resync" per site stay.
- **Customers (per customer, the expensive part):** no scheduled bulk sync. Refresh one customer's tenants/leases/balances only: at verified sign-in (tenant search by email — rare, refresh tokens last 60 days); when they open My Spaces / Bills and their data is older than 6 h (answer from the copy, refresh in background); pull-to-refresh (at most once per 10 min per customer); right before a payment (live balance of the leases paid); after our own move-in / payment / autopay. Unit details come from our unit table, never `UnitsInformationByUnitID` per unit.
- **Staff:** "Refresh from SiteLink" per customer (QOL); "Sync all customers" as a manual job only, off by default, throttled (1 call/s).
- **Guards:** a rate limiter in the SiteLink client (per instance, e.g. 2 calls/s, writes first); a daily call counter per operation in the logs + CloudWatch metric, so we can show SiteLink our numbers. Ask SiteLink for their actual limit.

### §3 additions from the SiteLink PDFs (`docs/notes/sitelink/sitelink-api-pdf-notes.md`, 2026-10-14)
- **Return codes are per operation** (-2 / -14 mean different things on move-in vs payment): each client method maps its own codes; no global table.
- **Login:** the client's SiteLink admin can create our own API user in the Corporate Control Center (level "API Regular"; reports need "API All Reports"); login is `user:::licencekey`. Recommend this over the old app's login (BA #18).
- **Never use `bTestMode`:** it still records the payment / move-in. Cash/Check/BankTransfer have no test mode. LSETUP is the only safe target.
- **Dates:** send site-local date-times without offset; vendor null date = a year before 1800 (the demo's 1970 placeholder is a real date) → verify on LSETUP which placeholder the blank card-expiry field needs.
- **-14 pre-check:** read the site's `PaymentSettings.iDaysPastDueNoOnlinePayment` (cached per site for a day) and compare with the lease's `dPaidThru` before charging a card; a blocked lease shows "please pay at the facility" instead of taking money. -14 at posting stays the YES rule + needs attention.
- **-7 (full payment required):** no readable setting → a partial payment refused with -7 is refunded automatically for that unit and the customer is told to pay the full amount; check LSETUP's behaviour first.
- **Sensitive replies:** `LedgersByTenantID` returns SSN, web password and gate code → parse only the columns we need; never store or log the others.
- **Currency decimals:** `UnitTypePriceList_v2` gives `iCurrencyDecimals` per site → cross-check with `site.currency` (KRW = 0) in the unit sync; mismatch = sync error for that site.

## §4 Tenant linking + My Spaces (APPROVED 2026-10-14)

- **Link at verified sign-in (S0 hook):** after `/auth/code/verify` succeeds, an outbox row queues `LinkTenants(customerId)`; sign-in never waits for SiteLink and never fails because of it. One call: `TenantListDetailed_v3` with blank `sLocationCode` (whole corp, fuzzy, max 50), keep only rows whose email equals the verified email (trimmed, case-insensitive); each match at a site in our `site` table → a `sitelink_tenant_link`. Also run by the staff action "Refresh from SiteLink".
- **Never move a link:** a (site, tenant) already linked to another customer is left alone; a needs-attention item "SiteLink email belongs to another account" is raised.
- **Stale link:** if a refresh shows the tenant's SiteLink email no longer matches the customer → the link is removed (its leases disappear from My Spaces) and logged. [INF: assumes the ledger/tenant reply carries the email; check on LSETUP.]
- **New tenant:** only at a paid reservation / move-in at a site with no link: `TenantNewDetailed_v3` from the verified profile; random 6-digit gate code, up to 3 tries on -2 (duplicate gate code); the link is saved at once (SiteLink's search lags behind new tenants).
- **Gate code:** never stored or logged; `GET /api/v1/me/leases/{id}/access-code` reads it live (owner check, rate-limited). PM may add an extra confirmation later.
- **My Spaces from our tables only:** `GET /api/v1/me/spaces` (customer from the token, no `userId`) → `activeRentals`, `pastRentals`, `reservations`, `viewingAppointments`, `refreshedAt`. Co-worker tab → empty (BizPlus deferred).
- **Refresh one customer** (`RefreshCustomer`): per linked (site, tenant) one `LedgersByTenantID` → upsert leases by (site, ledger id): unit (our unit row; unknown unit → queue that site's unit sync, lease keeps the SiteLink unit name meanwhile), rent, billing frequency, start date, paid-through, balance. Per-customer advisory lock `customer-refresh:<id>`; a second refresh while one runs is skipped.
- **Ending a lease (fixes the demo's "end all"):** only from a *successful* reply: its ledger has a moved-out date, or it is absent from the reply. Never on an error or timeout; never a lease we created in the last 24 h. Each end is logged with the reason.
- **When refresh runs** (§3 budget): verified sign-in; opening My Spaces / Bills when `refreshedAt` > 6 h (answer from the copy, refresh in background); `POST /api/v1/me/spaces/refresh` (pull-to-refresh, at most once per 10 min, else returns the copy with 200 + `refreshedAt`); before a payment; after our own move-in / payment / autopay.
- **Admin:** Customers page as the demo + tenant links (read-only), "Refresh from SiteLink", "Unlink tenant"; Leases page read-only.

## §5 Search, quotes, reservations, move-in (APPROVED 2026-10-14)

**Browsing (anonymous allowed, per-IP rate limit; all from our tables):** `GET /api/v1/sites` (currency, tax, time zone per site), `/storage-types`, `/unit-sizes`, `/units?location=…` (available units; shown price = `web_rate ?? standard_rate` and the list is sorted by that same price — demo sorted by another), `/units/{id}`, `/units/{id}/availability`. Stale site (> 60 min) → background unit refresh (§3).
**Quotes:** `POST /units/{id}/rental-plans` = the demo algorithm (03 §4.3: 1/3/6/12 months, best SiteLink discount plan, tax on rent + admin fee) as a pure function in `ExtraSpace.Engines`, `decimal`, half away from zero, site's currency decimals; price list + discount plans from the 30-min cache; not stored (`RentalPlanQuote` dropped). Each plan carries its `concessionId`. `GET /units/{id}/reserve-charges` = fee + tax on fee + deposit (demo, BA #2). Acceptance tables 03 Q1–Q12 (minus Q10) ported as `[Theory]`.
**Exact price (BA #16):** `GET /units/{id}/move-in-cost?date=&concessionId=` → live `MoveInCostRetrieveWithDiscount_v2` sum (cached 5 min per unit/date/concession). This is the only number a move-in charges. Dropped: the demo's `/reservations/preview` and `/leases/preview` (they echoed client numbers).
**Reserve (signed-in):** `POST /api/v1/reservations {unitId, dateNeeded, concessionId?, paymentMethodId}`
1. Unit available in our copy + one live unit read.
2. Advisory lock `reserve:<unitId>` + partial unique index; insert `AwaitingPayment`, `hold_until` = now + 15 min; amounts priced by the server.
3. Tenant: existing link or `TenantNewDetailed_v3` (§4).
4. `ReservationNewWithSource_v5` (holds the unit in SiteLink), then charge the saved card (§7). Paid → `Held`. Declined → SiteLink reservation cancelled, `Cancelled`. 3DS needed → stays `AwaitingPayment` until paid or `hold_until`; a job releases unpaid holds (SiteLink cancel). Fee 0 → `Held` at once.
**Cancel:** customer `DELETE /api/v1/reservations/{id}` (own, `Held` only) and staff "Cancel" in admin: `ReservationUpdate_v4` cancel first; SiteLink down → 503, nothing changes; then `Cancelled` + automatic Stripe refund of the reservation payment (BA #3) via outbox. No automatic expiry (BA #4).
**Move-in (signed-in):** `POST /api/v1/move-ins {unitId | reservationId, moveInDate, concessionId?, paymentMethodId, expectedAmount}`
1. Reservation must be the caller's and `Held`; else unit available + live unit read.
2. Live move-in cost = A. `expectedAmount` ≠ A → 409 `PRICE_CHANGED` with A (a confirmation, never the price).
3. Insert `move_in` (`AwaitingPayment`); charge A − reservation payment already paid (≥ 0; pending PM/LSETUP: does SiteLink's total already include the reservation fee / deposit?).
4. Paid → outbox `CompleteMoveIn`: lock `move-in:<unitId>`; `MoveInReservation_v6` (with reservation) or `MoveInWithDiscount_v7`, `dcPaymentAmount` = A, chosen concession (BA #17), card fields blank, `iPayMethod 2`. Success → lease (ledger id), reservation `Converted`, unit rented, `move_in` `Done`, receipt email. Refused (-11 price changed, unit gone, …) → full automatic refund + staff alert (BA #7), `move_in` `NeedsAttention`. Timeout → read `LedgersByTenantID` for a new ledger on that unit before anything else; never a blind re-send.
**Agreements:** `POST /api/v1/agreements` as the demo, owner-checked.
**Admin:** Units read-only (+ Sync now / Full resync); Reservations read-only + Cancel; Sites editable as the demo.

## §6 Admin pages, leads, viewings, Dashboard (APPROVED 2026-10-14; admin is desktop-only)

**Look = the demo** (`s1-research-crosscutting.md` §1–2): grouped sidebar (Platform, Tenants, Leads, Payments, + Access Control holding our S0 Staff / Roles / Audit under the demo's labels), items alphabetical in a group; list page (20 per page, `start–end of total`, search box, one select per filter, New button, row → full-page edit, trash + confirm, empty state, the demo's cell rendering: "—", Yes/No badges, status badges, `dd MMM yyyy`); full-page edit `/<area>/<id>` ("← Back to …", one card, fields in demo order, "This record is read-only."). Built as two shared React templates + a static config per page; typed endpoints per feature (`GET list ?page&pageSize&search&<filter>`, `GET {id}`, `POST`, `PATCH` + `version`, `DELETE ?version`). No generic CRUD engine (S0). Recharts installed.
**Pages (11):** Sites, Storage Types, Unit Sizes (editable; delete blocked with 409 when in use); Units (read-only + Sync now / Full resync, last synced per site); Customers (editable except email; + tenant links, Refresh from SiteLink, Unlink tenant); Leases (read-only); Reservations (read-only + Cancel → SiteLink cancel + Stripe refund); Viewing Appointments (editable as demo: status, notes, reschedule; staff can create); Leads (editable, create, delete as demo); Transactions (read-only: Stripe PaymentIntent ↔ SiteLink receipt no., refund/dispute state; refunds stay in the Stripe dashboard, BA #8); **Needs attention** (new: failed outbox steps, move-ins `NeedsAttention`, -14 payments, link conflicts; actions Retry / Mark resolved with a note). Promotions → S4.
**Permissions** (demo areas, our verbs; Owner holds all; reads of personal data and money are guarded, unlike the demo): `sites.manage` (Sites, Storage Types, Unit Sizes, unit sync); `customers.read` (Customers, Leases, Reservations, Viewings, Leads read); `customers.manage` (edit customers, refresh / unlink); `reservations.manage` (cancel reservations, edit viewings); `leads.manage`; `payments.read` (Transactions); `payments.manage` (Needs attention actions); `dashboard.read`. 403 on a missing permission (S0). Every write audited; audit screen gets the new record types.
**Dates / money in admin:** business dates in the site's zone, instants in the browser's zone (S0); money with the row's currency and its decimals (KRW none).
**Leads (mobile):** `POST /api/v1/leads` anonymous allowed, per-IP limit, `customer_id` when signed in, email lower-cased, unknown unit/site ignored as the demo, bad numbers → 400 (demo 500). No email (as the demo).
**Viewings (mobile, signed-in):** `GET /viewing-appointments/time-slots?location&date` = the demo's 18 slots 09:00–17:30 in the site's zone, minus taken and past slots; `GET /conflicts?unitId` (own, from today in site zone — demo missed today); `POST` (capacity 1 per slot by the DB index → 409 `SLOT_TAKEN`); `PUT {id}` reschedule own active only (demo revived cancelled/completed); `DELETE {id}` cancel own; `GET /me/viewing-appointments` from the token. No emails, no auto-complete job (as the demo).
**Dashboard** (`GET /admin/api/dashboard?country=`, `dashboard.read`): the demo's 6 cards and 5 charts/lists. Fixes: revenue = paid − refunded, **one figure per currency**; day buckets in Asia/Singapore for company-wide counts (`Admin:ReportTimeZone`) and the site zone for per-site data; occupancy one formula, deleted units excluded; "Payments by provider" (we only have Stripe) → "Payments by type" (bill / move-in / reservation fee / autopay); country filter SG / MY / KR (QOL).
**QOL list (for the spec):** Sync now / Full resync / last synced; Refresh from SiteLink / Unlink tenant; Reservation Cancel with refund; Needs attention page; Transactions ↔ SiteLink receipt; dashboard country filter; read-only money and SiteLink records (deliberate difference).

## §7 Payments, outbox, webhooks, autopay (presented 2026-10-14, awaiting yes)

**Stripe setup:** two platforms (SG, MY), each with its own secret / publishable keys and two webhook secrets (`es/<env>/stripe-sg`, `-my`). `site.country` picks the platform; `site.stripe_account_id` (the reused connected account, BA #5) is passed as `StripeAccount` on every facility call. One `StripeClient` per platform (never the global static key — old defect). No application fee. Amounts to minor units only inside the Stripe integration, per currency (SGD/MYR 2, KRW 0). Sites without an account (KR until decided) → pay endpoints 409 `PAYMENTS_UNAVAILABLE` ("pay at the facility").
**Cards:** `POST /api/v1/me/payment-methods/setup-intent {country}` → SetupIntent on that platform (`usage: off_session`, cards only) → app `CardField` + `confirmSetupIntent` → `POST /me/payment-methods {setupIntentId}` (server re-reads it from Stripe, checks owner) and webhook `setup_intent.succeeded` as backup; both idempotent on the PM id. Same fingerprint = one card. List / set default / delete (detach + its clones). Monthly card-expiry email (YES `card_expire_alert`).
**Pay now** (bills, BA #12–13): `POST /api/v1/me/payments {lines:[{leaseId, amount}], paymentMethodId}` → one `payment` per site. Checks: own active leases; live balance read; each line ≤ balance; total ≥ 10 (or the whole balance if smaller); -14 pre-check. Steps: insert `Pending` + lines and commit → clone card to the site account if new → PaymentIntent on the connected account (`confirm: true`, `setup_future_usage: off_session`, `return_url extraspace://stripe-redirect`, statement suffix "EXTRA SPACE ASIA", metadata app/payment/customer/site, idempotency `pay-{paymentId}`). `succeeded` → Paid; `requires_action` → `{clientSecret, stripeAccountId}` for `handleNextAction`; declined → `Failed` + message. Reservation fee and move-in use the same core (`kind`).
**One way to "Paid":** the sync reply, the webhook and the reconciliation job all call `MarkPaid(pi)`: `UPDATE … WHERE status IN (Pending, NeedsAuth)`; only the winner inserts the outbox rows (post to SiteLink / complete move-in / mark reservation Held / emails) in the same transaction.
**Posting to SiteLink** (`PostPaymentLine`, per line with no receipt): row lock, `attempted_at`, `PaymentSimpleCashWithSource` (iSource 10). Success → receipt id/no. -14 → YES rule (keep, needs attention, facility email). -7 and other refusals → refund that line (`refund-line-{id}`) + facility email (`unsuccessful_sitelink_payment`) + customer email. Timeout → read `PaymentsByLedgerID` for that amount after `attempted_at`; found → record it; not found → one more try; read fails → needs attention. All lines done → customer email (`successful_payment` + receipt).
**Webhooks:** `/api/v1/payments/webhook/{sg|my}` (platform) and `/api/v1/payments/webhook/{sg|my}/connect`; signature checked with that endpoint's secret; `stripe_event` row in the same transaction as the effect; 2xx only after commit. Events: `setup_intent.succeeded`, `payment_intent.succeeded` / `payment_failed` (`authentication_required` → NeedsAuth), `charge.refunded` (refunded amount; full → Refunded; needs attention "reverse in SiteLink", BA #8), `charge.dispute.created` (`disputed_at` + needs attention). PaymentIntents not ours (old app on the same accounts) → 200, ignored. WAF body-size rule exempts these paths (S0 carry-over).
**Reconciliation:** hourly job asks Stripe about `Pending` payments older than 30 min (missed webhooks). Stripe calls only.
**Outbox:** row in the same transaction; Hangfire dispatcher (every 30 s + a nudge after commit); handler idempotency named per step; back-off retries, then `failed_at` → Needs attention. The S0 login-code email moves onto it.
**Autopay (plan S1-6):** per-lease toggle with consent text (BA #15), default card unless one is chosen. Daily 09:00 site time: leases with autopay due today (paid-through + 1 day) → one live balance read each → skip if ≤ 0 or -14 blocked → full balance (BA #14) off-session, key `rent-{leaseId}-{period}-a{attempt}`. `insufficient_funds` → retry +1 and +3 days; other declines → Failed + customer email (`unsuccessful_payment`) + facility. `authentication_required` → NeedsAuth, email with `extraspace://payments/{id}/authenticate`, reminders day 1 and 3, `FailedAuth` after 7 days (BA #9; all configurable); `GET /api/v1/me/payments/{id}/authenticate` → clientSecret, stripeAccountId, card, amount, currency. Push when a provider exists.
**Testing:** Stripe test mode per platform with **test connected accounts** (the reused live accounts do not exist in test mode); test cards incl. 3DS and insufficient funds; `stripe listen --forward-connect-to`; SiteLink writes only on LSETUP.
**Not in S1:** YES `PaymentReminder` due-date emails (one SiteLink read per lease per day — against the call budget); Stripe's own receipt emails (we send ours).

### §7 changes from PM round 2 (2026-10-14)
- KR: another payment provider (not named) → S1 keeps `PAYMENTS_UNAVAILABLE` for KR sites; the KR provider is a separate later plan once named.
- Minimum 10 applies to the whole payment and to each unit line (#34).
- SiteLink limit is monthly and unknown (#32): the call counter reports a monthly total per operation, with a configurable alarm threshold.
- Move-in charge = SiteLink total − reservation money already paid (#28); -14 keep (#29); -7 refund + ask full (#30); no payment-due emails (#37); statement "EXTRA SPACE ASIA" (#38).
