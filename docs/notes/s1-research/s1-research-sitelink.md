# S1 research — SiteLink CCWs 3.5 integration

Researcher notes, 2026-10-14. Read-only. Tags: **[D]** = documented, with a file:line cite; **[I]** = inferred, not verified.
Abbreviations: `S02` = `../Backend Demo/backend/.claude/backend-spec/features/02-sitelink-integration.md`;
`S03` = `.../features/03-units-sites-quotes.md`; `S00` = `.../00-architecture-and-conventions.md`;
`OB1/OB2/OB3` = `docs/notes/old-backend/01-mobile-api.md` / `02-admin-cms.md` / `03-core-data-infra.md`;
`OPS` = `docs/notes/sitelink/ccws-3.5-operations.md`; `ART2/ART3` = `docs/notes/client-artifacts/02-es-app.md` / `03-es-admin.md`;
`demo/` = `../Backend Demo/backend/src/`; `old/` = `../../Extra Space old/extraspace-backend/` (secrets files NOT opened).

Demo freshness: the local clone has no commits after baseline `6be4474` on `origin/main` (I did not `fetch`, so newer remote
commits are possible). The spec is a snapshot of 2026-10-08.

---

## 1. Transport and wire basics

- [D] One ASMX endpoint `https://api.smdservers.net/CCWs_3.5/CallCenterWs.asmx`, SOAP 1.1 document/literal wrapped, namespace
  `http://tempuri.org/CallCenterWs/CallCenterWs`, `SOAPAction = <ns>/<Op>` (S02:24-32).
- [D] Every result is an ADO.NET DataSet (inline `xs:schema` + `diffgr:diffgram` → `NewDataSet` → repeated `<Table>`, `<Table1>`, `<RT>`,
  `<Ledgers>`, `<Receipts>`… elements). NULL column = element missing. All leaf values are strings (S02:245-277).
- [D] **Element order must match the WSDL `xs:sequence`** (S02:205-208). Spec recommends raw `HttpClient` + hand-built envelope
  + `XDocument` parser over a svcutil proxy (S02:948-1038). S0 spec §(line 441) says "the SiteLink SOAP client gets the same limits
  on its binding" — that wording assumes WCF; with raw `HttpClient` the standard `Microsoft.Extensions.Http.Resilience` pipeline
  applies directly. [I] Raw HttpClient is the better fit with S0's resilience stack.
- [D] Booleans are `"true"/"false"` strings — a historic demo bug made every flag true (S02:279-283). Numbers parse invariant;
  `decimal` in C# (S02:1046-1049).
- [D] **Dates**: SiteLink returns offset-less **site-local** timestamps; the demo parses them as UTC (S02:289-294, S02:913-915).
  Requests send UTC ISO with `Z` (S02:214-215). [I] For us this is a defect, not parity: parse SiteLink times in `site.time_zone`
  (house rule), and test what SiteLink does with a `Z` date — `dMoveInDate 2026-10-15T00:00Z` is 08:00 SGT (same day), but a
  site-local midnight converted to UTC (`2026-10-14T16:00Z`) may land on the previous business day. UNVERIFIED on the live API.
- [D] 1900-era sentinel for unset dates (`dMovedOut`), treat year ≤ 1900 as null (S02:686, S02:1040-1042).
- [D] .NET ticks cursor `lngLastTimePolled` is opaque, round-trip only, `bigint` (S02:339-341).

## 2. Every SiteLink operation the demo calls

R = read, W = write. "Card?" = takes card fields. All verified against the live WSDL (S02:878-881, OPS:5).

| Operation | Purpose | Feature / caller (S02:850-869) | R/W | Card? | Safe to auto-retry? |
|---|---|---|---|---|---|
| `UnitsInformationAvailableUnitsOnly_v2` | first-ever unit sync per site (ticks 0) | unit sync job | R | no | yes |
| `UnitsInformation_v3` | incremental unit sync from cursor; full resync with ticks 0 + excluded units | unit sync job, admin Units page (TEMPORARY), CLI resync | R | no | yes |
| `UnitsInformationByUnitID` | live availability refresh when row > 30 min old | `GET /units/:id` | R | no | yes |
| `UnitsInformationByUnitName` | fetch a rented unit never seen by sync (ledgers return only `sUnitName`) | lease sync, My Spaces refresh (≤ 1 per unit per 600 s) | R | no | yes |
| `UnitTypePriceList_v2` | admin fee, reservation fee per unit type | rental plans, reserve charges (cached 1800 s) | R | no | yes |
| `DiscountPlansRetrieve` | concession plans + unit-type restrictions | rental plans (cached 1800 s) | R | no | yes |
| `MoveInCostRetrieveWithDiscount_v2` | SiteLink's authoritative move-in total (Σ `dcTotal`) | `POST /leases` before each MoveIn | R | no | yes |
| `TenantListDetailed_v3` | find tenant by email (fuzzy, cap 50) | login linking, reserve, move-in, `/me/spaces` (cached 300 s) | R | no | yes |
| `LedgersByTenantID` | leases + per-lease `dcChargeBalance` | lease sync, My Spaces, My Bills amount cap | R | no | yes |
| `TenantNewDetailed_v3` | create tenant (random 6-digit `sGateCode`, DOB sentinel 1900) | reserve / move-in when no tenant found | **W** | no | **no** |
| `ReservationNewWithSource_v5` | waiting-list reservation; positive `Ret_Code` = WaitingID; collects no money | `POST /reservations` (inside 15 s Redis lock) | **W** | no | **no** |
| `ReservationUpdate_v4` | cancel reservation (`iStatus 2`, `QTCancellationTypeID 6`) | `DELETE /reservations/:id` (best-effort) | **W** | no | **no** (but cancel is naturally idempotent — [I]) |
| `MoveInReservation_v6` | move-in from a WaitingID; positive `Ret_Code` = LedgerID | `POST /leases` with a reservation | **W** | **card fields present, sent blank**, `iPayMethod 2` Cash | **no** |
| `MoveInWithDiscount_v7` | direct move-in | `POST /leases` without reservation | **W** | **card fields present, sent blank**, `iPayMethod 2` | **no** |
| `PaymentSimpleCashWithSource` | record Stripe-collected money on the ledger, `iSource 10` | Stripe webhook (My Bills) | **W** | no | **no** — no idempotency key in SiteLink |
| `SiteInformation`, `SiteSearchByPostalCode`, `PromotionsRetrieve` | wrappers only | unused | R | no | yes |

Card-carrying notes:
- [D] The two `MoveIn*` ops carry card elements in their WSDL sequence; the demo sends `iCreditCardType 0`, empty number/CVV,
  `dExpirationDate 1970-01-01`, `iPayMethod 2` (S02:762-822). This matches the house rule ("never fill the card branch",
  S02:55-61) — they are *not* card-carrying calls as used. Proven live for `MoveInReservation_v6` (ledger 603025, S02:764-765);
  [D] `MoveInWithDiscount_v7` with these placeholders is NOT stated as live-verified (S02:763-765).
- [D] Never call: `ReservationFeeAddWithSource*`, `PaymentSimpleWithSource*`, `PaymentMultipleWithSource*`, `POSItemPayment*`,
  `RefundPaymentCreditCard*`, `PaymentSimpleACH*` (OPS:5, S02:55-57, S02:729).
- [D] **Old system violates this**: posts app payments with `PaymentSimpleWithSource` + public Stripe test card numbers, CVV 123,
  `bTestMode=true`, and logs the full SOAP body including `sCorpPassword` (OB1:635-644, OB2:705). Do not copy.
- [D] `PaymentSimpleCashWithSource` has **no `bTestMode`**: every accepted call posts a real, permanent receipt, even in test mode
  (S02:225-230, S02:833-835). `iSource` must be 3 or 10 (5 → `-40`) (S02:316).
- [D] `SITELINK_TEST_MODE` defaults to **true** in the demo, and production must set false explicitly (S02:170). What `bTestMode=true`
  actually does on a move-in is unverified (S02:228-230).

Ops the old system uses that the demo does not, and S1 may need [D] (OB1:620-636, OB2:701-703):
`ChargesAndPaymentsByLedgerID`, `ChargesAllByLedgerID` (bills: outstanding excluding uninvoiced Rent/Insurance — OB1:438-442),
`TenantInvoicesByTenantID` (invoices), `PaymentsByLedgerID`, `CustomerAccountsBalanceDetails` (receipts), `TenantInfoByTenantID`,
`ApplyCredit` (rent vouchers), ReportingWs `Receipts` (receipts, offline-payment points job). [I] My Bills parity with the old app
(per-charge breakdown, tax lines `dcTax1/dcTax2`, receipts, invoice PDFs) needs some of these; the demo's My Bills uses only
`LedgersByTenantID.dcChargeBalance`.

## 3. Auth and configuration

- [D] Logon block on every op: `sCorpCode, sLocationCode, sCorpUserName, sCorpPassword` (S02:232-243). Plus HTTP header `sApiKey`
  (S02:166). **`sCorpUserName` must be `<user>:::<license key>`**; bare username fails `-98`/`-89` whatever the header says (S02:188-193).
  Sandbox `LSETUP` was callable without an API key (S02:191).
- [D] Demo: one default corp login from env + per-location overrides `SITELINK_<LOC>_CORP_{CODE|USERNAME|PASSWORD}` (regex,
  upper-case letters/digits only), computed at startup; `UAT SETUP2` has its own corp user (S02:171-186). `Site.siteLinkCorpCode`
  is stored but unused (S02:111).
- [D] Old system: one corp login per deployment; **SG and MY production share the same SiteLink corp account**
  (`sCorpCode`, `sCorpUserName`, `sCorpPassword` identical by hash) and differ only in `SiteID` / `sLocationCode` (OB3:352-354).
- [D] The corp has other real facilities, including Korea (`L013` "Extra Space - Gasan", Seoul) (S02:470-472).
- [D] Client admin artifact lists **24 facilities** with codes `L001…` and countries; codes "look like" SiteLink location codes
  — unconfirmed (ART3:133-148, ART3:312).
- [I] Design consequence: credentials are keyed by **corp**, not by site or country. Model: `site.location_code` (unique),
  `site.country`, `site.time_zone`, `site.currency`, `site.sitelink_corp` (a key into Secrets Manager `es/<env>/sitelink/<corp>`),
  `site.active`, `site.facility_type`. Probably one corp for SG+MY today, but keep the indirection so a second corp is config,
  not code. Do not copy the env-regex override scheme (it breaks on `_`/`-` codes and puts per-site secrets in env).
- [D] House rule: config from environment / secret store; never log the logon block (S02:1066-1067; S0 spec line 139: bodies never
  logged in production; staging redacted-body logging decided in S1).
- [D] The old CMS sets the SOAP binding `SendTimeout` from `SiteLink:timeOutInMinute` (minutes!) for the reporting client only
  (`old/ExtraSpaceCMS/admin_cms/Services/SiteLink/SiteLinkAPIs.cs:2194-2195` on `yes-production`).

## 4. SG vs MY, multi-site

- [D] Demo is single-country by design but multi-site: every call keyed by `Site.locationCode`; `Site.facilityType`
  (`SELF_STORAGE`/`WORKSPACE`) decides the My Spaces tab (S02:110-113). Unit type name `"bizplus"` → workspace (S02:484).
- [D] Old system: one DB per country, `master_facility` row per SiteLink site (id = SiteID), `user_tenantsite` link per site
  (OB3:137, OB3:363).
- [D] **Old tenant search is corp-wide**: `TenantListDetailed_v2` called with `sLocationCode: ""` on both `yes-production` and
  `mys-yes-production` (`old/ExtraSpaceAPI/mobile_api/Services/SiteLink/SiteLinkAPIs.cs:556` SG, `:483` MY). Rows carry `SiteID` /
  `sLocationCode` (S02:633-635). The demo instead loops **every active site** with one call each (`demo/services/domain/tenant.service.ts:166-178`,
  `myspace.service.ts:260-271`).
- [I] With 24 sites, a first login in the demo style costs 24 SOAP calls; a corp-wide search costs 1, then filter rows to our
  active sites (a shared SG+MY(+KR) corp returns tenants of every country — drop rows whose `sLocationCode` is not an active site).
  Must verify on the live API that blank `sLocationCode` still works with CCWs 3.5 `_v3` and returns all sites.
- [D] SiteLink computes tax on move-in lines (`TaxAmount`, S02:608) and bills (`dcTax1/dcTax2`, OB1:441). [I] So SG GST vs MY SST
  for storage is SiteLink's concern; we should never recompute storage tax — only carry SiteLink's numbers.
- [I] Amounts carry no currency; currency = `site.currency`. A Stripe session amount must use the site's currency and Stripe account
  (Connect model OPEN, cross-repo §4 item 10).
- [D] Old MY branch keeps different reminder days and 3DS on; the split is code drift, not a SiteLink difference (OB3:352-360).

## 5. Caching and sync

Demo (Redis via `cached(key, ttl, loader)`, negative results cached too — S02:1056-1061):

| What | Where | TTL / cadence | Cite |
|---|---|---|---|
| Units | PostgreSQL `Unit` table (local copy) + `UnitSyncCursor` per site | cron `*/15 * * * *` in-process (Vercel daily) | S02:412-425, S02:95-104 |
| Unit search results | Redis prefix `units:search:<siteId>`, cleared after a sync that changed units | — | S02:337 |
| Unit detail freshness | live `UnitsInformationByUnitID` when row > 30 min old → most detail views make a live call | 30 min | S03:463-464 |
| Rented-unit refresh in My Spaces | Redis `unit:live-refresh:<siteId>:<unitName>` | 600 s | S02:533 |
| Price list, discount plans | Redis `pricing:unitTypePriceList:<loc>`, `pricing:discountPlans:<loc>` | 1800 s | S02:557, S02:587 |
| Tenant search by email | Redis `storage:tenant-search:<siteId>:<email>` / `workspace:…` | 300 s | S02:1059-1060 |
| Ledgers / balances | **not cached across requests**; memoised per request | — | S02:864 |
| Locks | `scheduler:unit-sync` 600 s; `unit-reserve-lock:<unitId>` 15 s | — | S02:420, S02:865 |

- [D] SiteLink guidance: poll units ~every 15 min, never per mobile request (S02:416-418). The demo's admin Units page syncs
  every site on every page load (TEMPORARY, S02:427-430) — do not port.
- [D] First sync uses `AvailableUnitsOnly_v2` because `UnitsInformation_v3` with ticks 0 returned no `Table` in this account;
  so rented units are discovered lazily by name (S02:326-330, S02:890-891).
- [D] After any mapping change, a full resync is needed; incremental polls never resend unchanged rows (S02:343-345).
- [D] Old system: ledgers 5 min, bills 1 min, receipts/invoices 5 min in Redis; units per site 3 h via a CMS job (now disabled)
  (OB3:384-388, OB2:641). Client admin artifact claims "SiteLink only syncs hourly" (ART3:72, ART3:251).

What our design must decide [I]:
1. **Unit sync** → a Hangfire recurring job (one per site, or one job looping sites) with `DisableConcurrentExecution` /
   Hangfire's own once-per-cluster guarantee; no Redis lock needed. Cursor in PostgreSQL. Advance the cursor in the same DB
   transaction as the unit upserts.
2. **Price list / discount plans** (rarely change, 1800 s): PostgreSQL snapshot refreshed by the same job, or `IMemoryCache` per
   instance (2–4 `api` tasks → at most 4× calls; SiteLink load is tiny, peak < 3 calls/s per cross-repo §4). Valkey is not
   required for correctness here.
3. **Tenant search / ledger reads**: short per-instance memory cache is enough at our load; cross-instance consistency matters
   only for "pay then see new balance" — invalidate on our own payment write. If we want shared invalidation across api tasks,
   that is the one real Valkey use case; otherwise S1 can defer Valkey (budget line stays).
4. Rate limits (login, codes) are already Postgres-backed in S0 [check built-so-far.md]; Valkey is not needed for them.
5. Never cache negative tenant-search results right after we created a tenant (search delay, §7).

## 6. Error handling

- [D] Success/failure convention: first `RT` row; `Ret_Code <= 0` → failure; no `RT` → OK; non-numeric `Ret_Code` → treated as OK
  (JS `NaN` quirk); create ops return the new id as positive `Ret_Code` (S02:296-306).
- [D] Known codes: `-2` invalid gate code (non-numeric); `-11` payment ≠ SiteLink's move-in cost; `-25` invalid UnitID; `-40` bad
  `iSource`; `-89`/`-98` auth (missing `:::key`); `-95` invalid TenantID (demo retries move-in once after re-resolving the tenant)
  (S02:309-319). Old system: `-14` on payment → user set Overdue (OB1:516-518).
- [D] Demo mapping: `Ret_Code <= 0` → 502 `SITELINK_ERROR` with the SiteLink message in the body; transport/SOAP fault → 500
  (S02:145-155). [I] For us: do not echo `Ret_Msg` to the mobile client (it can leak internals); map known codes to our own
  `code`s (e.g. `UNIT_NOT_AVAILABLE`, `SITELINK_UNAVAILABLE` 503 when the circuit is open) and log `retCode` + operation.
- [D] Demo has **no timeouts, no retries, no circuit breaker**; > 3000 ms logs a warning (S02:218-224, S02:895-897).
  Spec recommends timeout 30–60 s and Polly retry for reads only (S02:936-941). S0 spec requires timeout + breaker + safe-read
  retries on every outside call (S0 spec line 441; cms.md rule 11).
- [D] Best-effort callers (cancel reservation, webhook posting, login/spaces sync, balance lookup) swallow failures and log
  (S02:395-408). [I] A missing balance makes My Bills checkout fail with 400 "Invalid amount" — confusing; prefer 503.
- [I] Proposed resilience split: reads = timeout ~15–20 s per attempt, 2 retries with jitter on transport errors/5xx/timeouts only
  (never on `Ret_Code <= 0`), breaker per corp endpoint. Writes = single attempt, longer timeout (move-ins are slow), never retried
  automatically; a timeout on a write = **unknown outcome** → reconcile by reading (§8), not by re-sending.
- [I] SOAP faults come back as HTTP 500 with a fault body (S02:980 comment); treat as transport error, not retryable for writes.

## 7. Tenant linking

Demo behaviour [D]:
- `SiteLinkTenantLink(customerId, siteId, siteLinkTenantId, accessCode)`, unique `(siteId, siteLinkTenantId)`, **no unique on
  (customerId, siteId)**; code mostly reads `findFirst` (unordered) (S02:76-93, S02:916-917).
- Login (`resolveCustomerByEmail`) searches every active site by email, exact case-insensitive match, takes the **first** exact
  row per site (`.find`), links it, pulls ledgers (`demo/services/domain/tenant.service.ts:152-237`).
- `/me/spaces` re-searches sites with no link (cached 300 s) and upserts the link with `update: { customerId }` — i.e. **moves an
  existing link to the current customer** (`demo/services/domain/myspace.service.ts:266-284`; same in `tenant.service.ts:217-226`).
- Reserve / move-in: link exists → use it; else search; else `TenantNewDetailed_v3` with random 6-digit gate code (S02:347-366).
- 🔴 **Identity from the request body**: `POST /api/v1/leases` and `POST /api/v1/reservations` take `body.customerDetails.email`,
  `upsertCustomer` by that email (overwriting that customer's profile) and resolve the SiteLink tenant for it
  (`demo/controllers/v1/leases/methods/index.post.ts:13-14`, `reservations/methods/index.post.ts:14`, `tenant.service.ts:24-40`).
  This is the "email-only login" defect class in a second place.
- [D] **Tenant search delay**: a tenant created by `TenantNewDetailed_v3` is not searchable for an unknown time (one stayed
  unsearchable > 1 day) — persist the link at creation, never treat "not found" right after creation as final (S02:361-366).
- [D] `-95` stale link → delete link, re-resolve, retry once (S02:380-382).

Old system [D]: registration requires a SiteLink tenant with `bHasActiveLedger` at a known facility, then an emailed 6-digit OTP,
then `user_tenantsite` rows for every tenant/site (OB1:352-366). Link table PK `(tenant_id, site_id, user_id)` (OB3:78) →
several tenants per site per member supported [I from PK]. Tenant sync job rewrote links by email nightly (disabled) (OB2:639).

Our rule and design points:
- [D] S0 spec: link only inside "check the code" success, for the **verified** email, case-insensitive (S0 spec lines 222, 443).
  Identity for reserve/move-in/payments comes from the JWT customer, never the body.
- [I] Link **all** exact-email tenants per site (not just the first): a person can have several TenantIDs at one site (demo S02:93
  admits it). Store each link; each lease row stores its own `sitelink_tenant_id` (the demo Lease has no tenant id, so the
  webhook posts payment to `findFirst` tenant at the site — wrong when there are two: `demo/services/domain/payment.service.ts:197-206`).
- [I] Never silently move a link from customer A to B. Since `customer.email` is unique, a second customer can match the same
  tenant only if SiteLink's email changed; decide the rule (re-link to the new email's owner? flag for staff?). Also decide what
  happens when a linked tenant's SiteLink email changes away from the customer (stale link keeps showing their units and lets
  them pay). Re-verify links on each sync: drop a link whose tenant email no longer matches.
- [I] Fuzzy search caps at 50 rows (S02:628); an exact-email match beyond row 50 is missed. Low risk, note it.
- [I] Creating a tenant: only at a paid move-in/reservation for that site, from the verified customer's profile. Gate code: the
  demo generates and stores it (`accessCode`), the old app reveals `sAccessCode` only after an extra OTP (OB1:582-584), the app
  artifact wants a per-unit PIN (ART2:640). Access codes are physical-security secrets: never log, consider not storing (read live).
  Unknown whether SiteLink rejects a duplicate gate code at a site.
- [I] Account deletion (App Store, open item 6): the old system never touched the SiteLink tenant on delete (OB1:470-473). We
  should delete our links, not the SiteLink tenant.

## 8. Concurrency and idempotency hazards

| Hazard | Demo behaviour | Our design need |
|---|---|---|
| Double move-in (double tap / retry) | No lock around `submitRental`; MoveIn hits SiteLink, then local DB tx (`demo/services/domain/rental.service.ts:46-146`) [D] | Advisory lock `move-in:<unitId>` (namespaced), plus a local "move-in attempt" row created **before** the SOAP call with a unique key (payment id / reservation id). Second request sees the row. [I] |
| Move-in posts Cash in SiteLink before money is collected | `paymentStatus` comes from the client; MoveIn sends `iPayMethod 2` with SiteLink's total regardless (S02:368-390, known defect "storage payments trusted on the client's word") [D] | Stripe Checkout first, webhook → idempotent job → MoveIn. New payment flow = business approval (house rule 3). [I] |
| Move-in cost drift between checkout and webhook | `-11` if amount ≠ SiteLink's current Σ `dcTotal` (S02:314, S02:387-390) [D] | Price the checkout from `MoveInCostRetrieveWithDiscount_v2` at session creation; at move-in re-fetch; if different → do not move in, flag for staff/refund. Proration depends on move-in date in site tz. [I] |
| Unit taken between checkout and move-in | Reserve holds via `waitingListReserved` locally + SiteLink waiting list (`reservation.service.ts:53-111`) [D] | Reservation (WaitingID) before checkout, `MoveInReservation_v6` after payment; decide expiry of unpaid holds and cancel via `ReservationUpdate_v4`. [I] |
| SiteLink write succeeds, our DB write fails | No compensation; orphan lease/reservation in SiteLink (S02:392-393, S02:898-900) [D] | Persist intent row first; on unknown outcome reconcile by reading (`LedgersByTenantID` for a new ledger on that unit; reservation list) before any re-send. [I] |
| Double `PaymentSimpleCashWithSource` | Webhook reads PENDING rows, then `updateMany` **by id**, not by status → two concurrent deliveries both post (`payment.service.ts:156-177`) [D] | Claim with `UPDATE … WHERE status='PENDING'` / row lock; one outbox/job row per transaction with a unique key; job writes receipt number; a retry first checks the receipt column. [I] |
| Payment timeout = unknown outcome | No retry at all; `siteLinkReceiptId null` = manual reconciliation (S02:401, S02:120) [D] | `PaymentSimpleCashWithSource` has no external reference field (only tenant, unit, amount, iSource — S02:831-835) so SiteLink cannot dedupe. After a timeout, read `PaymentsByLedgerID` / `ChargesAndPaymentsByLedgerID` for a payment of that amount after the attempt time before re-posting; else staff queue. [I] |
| Payment posted to wrong ledger | No `iLedgerID`; SiteLink picks the ledger from tenant+unit (S02:834) [D] | Store tenant + unit on the transaction from the lease row, not from a `findFirst` link. [I] |
| Unit sync overlapping itself | Redis lock 600 s (S02:420) [D] | Hangfire once-per-cluster; cursor advance in the same tx. [I] |
| Reservation race on one unit | Redis lock 15 s + re-read `available` (S02:865) [D] | PostgreSQL advisory lock `reserve:<unitId>` + `FOR UPDATE` on the unit row (engineering checklist §2). [I] |

## 9. Demo defects / risky patterns (do not copy)

1. Customer identity from request body on reserve and move-in (§7) [D].
2. Move-in records Cash in SiteLink on the client's word (known defect) [D].
3. Webhook double-post race (§8) [D]; SiteLink posting failure only logged, no queue (S02:401) [D].
4. Link stealing via `upsert … update: { customerId }` (§7) [D]; payment uses `findFirst` link (§8) [D].
5. No timeouts / retries / breaker (S02:895-897) [D]; demo `requiredPayment` and `Transaction.amount` are floats (S02:901-902) [D].
6. `SITELINK_TEST_MODE` default true and does not cover payments (S02:909) [D].
7. Offset-less SiteLink times parsed as UTC (S02:913-915) [D].
8. Admin page syncs all sites on every load; raw full response logged at info (S02:427-433) [D].
9. Error body echoes SiteLink `Ret_Msg` to clients (S02:149) [D].
10. `ReservationNewWithSource_v5` sends `dcQuotedRate 0`, `dExpires = now` — business acceptability unverified (S02:723-726) [D].
11. Seed data fabricates TenantIDs (cause of `-95`) (S02:892-894) [D] — our tests must use recorded responses, never fake ids on a live corp.
12. Old system: card-carrying `PaymentSimpleWithSource` with test card numbers and corp password in logs (OB1:638-644) [D];
    `TenantUpdate` re-sends ~50 fields incl. `sSSN`/DOB read-modify-write (OB1:624, OB2:559) [D] — avoid `TenantUpdate` unless needed.

## 10. Open questions (PM / SiteLink vendor / client IT)

1. **Corp and credentials**: is it one SiteLink corp for SG and MY (old config says yes, OB3:354)? Will we get our **own** API user
   + license key (not reuse Codigo's, which is committed in a repo with live secrets and must be rotated)? Per-country users?
2. **Sandbox**: can we use `LSETUP` / `SETUP2` (UAT sites the demo used) from staging? Are they in the production corp? A
   `PaymentSimpleCashWithSource` there posts a real receipt (no test mode). Is there a separate corp for testing?
3. **IP allowlist**: does SiteLink allowlist caller IPs? Our NAT gives fixed IPs (staging 1, prod 2) (S0 spec line 368; open item 7).
4. **Rate limits / fair use**: any per-corp call quota? Guidance is "poll every ~15 min" (S02:417).
5. **Which sites** are live for release (24 facilities in ART3; codes `L001…`)? Which are `WORKSPACE` (BizPlus deferred — do we still
   show SiteLink workspace leases in My Spaces?). KR sites must be excluded.
6. Does `TenantListDetailed_v3` with blank `sLocationCode` search the whole corp (old `_v2` did)? Verify live.
7. `bTestMode=true` semantics on `MoveIn*`; are blank card fields + `iPayMethod 2` accepted by `MoveInWithDiscount_v7` live?
8. Is a Cash-coded payment acceptable to finance for Stripe money, and how do they reconcile Stripe payouts against SiteLink receipts
   (no reference field on `PaymentSimpleCashWithSource`)? Would `PaymentSimpleBankTransferWithSource` or a note
   (`TenantNoteInsert`) suit better? Business decision.
9. Insurance: SiteLink insurance coverage (`InsuranceCoverageRetrieve*`, `InsuranceCoverageID` on move-in) vs the artifacts'
   fixed plan (ART2:555-556, ART3:290) — demo always sends `-999`.
10. Gate/access code: per tenant (SiteLink) vs per unit PIN (artifact); show it in the app? Extra OTP like the old app?
11. Billing frequency: demo always sends `iBillingFrequency 3` (monthly), 28-day exists (S02:817). Any 28-day sites?
12. Refunds and failed move-ins after payment: who reverses in SiteLink (old: staff by hand, OB2:571)?
