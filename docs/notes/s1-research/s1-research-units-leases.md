# S1 research: sites, units, quotes (spec 03) + reservations, leases, My Spaces (spec 04)

Researcher: read-only Opus subagent, 2026-10-14. Demo HEAD = `6be4474` (= sync baseline; no `fetch` done).
Paths: `SPEC` = `../Backend Demo/backend/.claude/backend-spec/`; `DEMO` = `../Backend Demo/backend/`.
Tags: **[DOC]** = read in the cited file. **[INF]** = my inference, not verified. **[DEFECT]** = known demo defect, never copy.

---

## 0. Ten things that shape the S1 design (summary)

1. [DOC] **No ownership anywhere in spec 04.** All 7 routes take identity from the body (`customerDetails.email`) or query (`userId` = email); the JWT is ignored (SPEC 04:162-165, 04:788). Verified in code: `DEMO/src/controllers/v1/me/methods/spaces.get.ts:8,20` (`findUnique({ where: { email: userId } })`) and `DEMO/src/controllers/v1/reservations/methods/[id].delete.ts:11` (`cancelReservation(id)` with no caller). Move-in also converts any `reservationFor` id, even another customer's (04:557, 04:792). [DEFECT]
2. [DOC] **Money is trusted from the client.** Reservation and move-in record `grandTotal` + `paymentStatus:"completed"` as reported (04:26-33, 04:142, 04:600). The web-app fakes a Stripe id `demo_sim_<uuid>` (`DEMO/web-app/src/pages/MoveInPage.tsx:76-94`). Our rules need server pricing, hosted Checkout and the webhook, with the SiteLink move-in run as an idempotent job after payment (cms.md rules 3, 7, 11). This is a contract redesign, not a port.
3. [DOC] **Two different prices.** The quote is the demo's own maths: the best discount is applied once to the whole multi-month total (03:715-733). The move-in charges SiteLink's own `MoveInCostRetrieveWithDiscount_v2` sum, which SiteLink checks exactly (`-11` on a mismatch) (04:600). So the two can differ, and nothing reconciles them. [INF] For Checkout we must charge the SiteLink number, or make the quote come from SiteLink.
4. [DOC] **The demo uses `double` everywhere**, with JS `round2` = `Math.round(n*100)/100` (half toward +inf) (03:950-954). Currency is hard-coded `"SGD"` (`DEMO/src/services/domain/quote.service.ts:89,163`, `/sites` 03:320). GST = `Site.taxPercentage`, default 9 (03:87). For SG + MY we need per-site currency and tax (SST in MY), and `decimal`.
5. [DOC] **GST is applied two ways.** The rental plan has no GST on the reserve charge (03:713). `reserve-charges` adds GST on it (03:751, 03:914 #11). Pick one rule.
6. [DOC] **SiteLink move-in operations have card fields.** `MoveInReservation_v6` and `MoveInWithDiscount_v7` are sent with `iPayMethod:2` (cash), empty card fields and `dExpirationDate:"1970-01-01…"` (04:775-776). They are not on our forbidden list (`docs/notes/sitelink/ccws-3.5-operations.md:5`), but they take card parameters. Owner ruling needed (house rule 4). `SITELINK_TEST_MODE` defaults to `"true"` (04:602, `DEMO/src/config/env.ts:25`).
7. [DOC] **The concurrency guard is weak.** Reserve uses a Redis try-lock `unit-reserve-lock:{id}` (15 s, no renewal), the SiteLink call runs first, and then three DB writes that are not in a transaction (04:521-526). Move-in has no lock and no availability check (04:604). Cancel has no status guard, so cancelling a CONVERTED reservation sets the unit back to `available=true` (04:545). [INF] For us: a Postgres advisory lock `unit-reserve:<unitId>` plus one transaction, and a reconciliation for orphan SiteLink entries.
8. [DOC] **My Spaces runs a live SiteLink sync on every call**, site by site in sequence. It ends ALL active leases at a linked site when SiteLink lists no current ledger there, even a lease created a moment ago (04:684-723, 04:796). It also re-points a tenant link to whoever searched by that email (04:703, 04:797). [INF] Under S0, the email is proven by the one-time code, so linking by email is fine. The "end all" rule and the latency still need a design (Hangfire job and/or a cache).
9. [DOC] **Reservations never expire.** `expiresAt` is never written, `EXPIRED` is never set, and there is no job (04:56, 04:793). SiteLink's `dExpires` is sent equal to `dNeeded` = now (`DEMO/src/services/sitelink/operations/reservations.ts:64`). [INF] The SiteLink waiting entry may count as expired at once. The reserve charge is never posted to SiteLink, because the demo skips `ReservationFeeAddWithSource_v2`, which carries card data (04:30). How the reserve fee reaches the SiteLink ledger is OPEN.
10. [DOC] **Insurance is 0 in the demo** (`insuranceForMonth/insuranceTotal = 0`, `InsuranceCoverageID -999`; 03:233, 04:774). The two client artifacts disagree with the demo and with each other: the app shows a fixed Basic plan (S$2,000 for S$8/mo), the admin uses an 11-tier table. The admin artifact also makes lease status depend on signed documents. SiteLink has `InsuranceCoverageRetrieve*` / `InsuranceCoverageAddToLedger*` (`ccws-3.5-operations.md:67-72`). OPEN for the PM.

---

## 1. Entities and tables (demo, Prisma; SPEC 03 §2, 04 §2)

Demo conventions [DOC 03:56-60]: PascalCase quoted tables, camelCase columns, cuid text ids, `Float` = `double precision`, `timestamp(3)` UTC, app-set `updatedAt`. None of these bind us; we use snake_case, UUID v7 and `numeric(12,2)`.

| Table | Source of truth | Key columns / notes |
|---|---|---|
| `Site` | **Local** (seed + admin CRUD; NOT synced from SiteLink, 03:93) | `locationCode` UNIQUE (SiteLink `sLocationCode`, the app's "site key"); `siteLinkSiteId` UNIQUE; `facilityType` enum `SELF_STORAGE`/`WORKSPACE`; `name`, `displayName`, address fields, lat/lng, `timezone` (null → "Asia/Singapore"), `taxPercentage` double default 9; `active`; `siteLinkCorpCode` (informational) (03:71-93). No currency column. |
| `UnitSyncCursor` | Local | PK `siteId`; `lastTimePolledTicks` bigint (.NET ticks returned by SiteLink, only round-tripped); `lastSyncedAt`. A row = "this site has synced before" (03:96-106). |
| `StorageType` | Local taxonomy | `key` UNIQUE: `self-storage`, `workspace` (both must exist before the first sync, 03:123); `name`, `displayName`, icon/image, `sortOrder`, `active`; `siteId` unused (03:108-122). |
| `UnitSize` | Local taxonomy | `key` UNIQUE (small/medium/large), `label`, `unitGroup` S/M/L, `minAreaSqft`/`maxAreaSqft` (size estimator), `storageTypeId`. **Sync never sets `Unit.unitSizeId`**, so the size filter matches only seeded units (03:125-143, 03:907). |
| `Unit` | **SiteLink-backed local cache** | UNIQUE `(siteId, siteLinkUnitId)` = upsert key; `siteLinkUnitTypeId` (joins price list + discount restrictions); `unitName` (ledgers join by name); width/length/`areaSqft` = w×l; floor; flags climate/inside/power/alarm/ada/mobileUnit; rates `standardRate`, `webRate`, `boardRate`, `pushRate`, `preferredRate`; `standardSecurityDeposit`; `adminFee`/`reservationFee` columns **never written**; `rented`, `rentable`, `waitingListReserved`, derived `available = rentable && !rented && !waitingListReserved && !deletedAt`; `deletedAt` (SiteLink `dDeleted`); `lastSyncedAt` (03:145-184). |
| `Promotion` | Local, CMS only | enums `PromotionSource` SITELINK/INTERNAL, `PromotionAmountType` FIXED/PERCENT/FIXED_RATE; nothing writes SITELINK rows and **nothing reads the table for pricing** (03:186-216). |
| `RentalPlanQuote` | Local, write-only | 4 rows per quote call; money columns; `concessionId`; `promotionSnapshot` jsonb; `expiresAt` = now+30 min. **Never read back, never cleaned up** (03:218-243). |
| `Reservation` | Local mirror of a SiteLink waiting-list entry | `customerId`, `unitId`, `siteId` (RESTRICT FKs); `siteLinkWaitingId`; `status` enum PENDING/HELD/CONVERTED/CANCELLED/EXPIRED; `dateNeeded` = now; `quotedRate`, `expiresAt`, `gst` never written; client-reported `reserveCharge`, `securityDeposit`, `grandTotal`, `currency`, `paymentProvider`, `paymentReference`, `paymentStatus` (04:48-84). |
| `Lease` | Local mirror of a SiteLink ledger | `siteLinkLedgerId` (unique per site in code only, not in DB), `siteLinkLeaseNum`, `reservationId` UNIQUE (one lease per reservation → P2002 → 409), `startDate`, `endDate` (client `dateTo`; null from sync), `monthlyRent`, `billingFrequency` "monthly"/"28-day", `status` ACTIVE/ENDED, `movedInAt` (row-creation time), `movedOutAt` (04:86-108). |
| `SignedAgreement` | Local audit | `customerId` (nullable), `customerEmail`, `reservationId`, `leaseId`, `storageAgreementUrl`, `insuranceAgreementUrl`, `signedAt`; no uniqueness, one row per call (04:110-123). |
| `Transaction` (shared with 05) | Local | provider enum STRIPE/PAYUP/SITELINK_CASH/SITELINK_OTHER/MANUAL; status PENDING/SUCCEEDED/FAILED/REFUNDED; `amount` = client grandTotal; written only when both a provider and a reference exist (04:125-150). |
| `SiteLinkTenantLink` (01/02) | Local link | `(customerId, siteId) → siteLinkTenantId, accessCode`; UNIQUE `(siteId, siteLinkTenantId)` (04:154). |
| `ViewingAppointment` (06) | Local | read by the My Spaces storage tab (04:620). |

SiteLink owns: units, rates, price list (`UnitTypePriceList_v2`: adminFee, reservationFee, webRate per type), discount plans (`DiscountPlansRetrieve`), tenants, waiting-list entries, ledgers, balances, paid-through dates and the move-in cost (03:24-29, 03:892-898, 04:777).

---

## 2. Endpoints

### 2.1 Mobile, catalogue (spec 03). Auth: `mobileAuth` = anon key OR customer JWT; all accept guests; none reads identity (03:255)

| Method + path | Purpose | Notes |
|---|---|---|
| GET `/api/v1/sites?facilityType=self-storage\|workspace\|all&siteName=` | Location picker | `siteName` = locationCode exact match, ignores facilityType (03:272); `currency` always "SGD", `taxpercentage` lowercase key; `address` never null (Flutter crash) (03:310-320) |
| GET `/api/v1/storage-types` | Filter chips | never lists `workspace` (03:327) |
| GET `/api/v1/unit-sizes?unitTypeId&unitSubTypeId&coWorkingTypeId` | Size chips | `[]` for co-worker (03:344-346) |
| GET `/api/v1/units?location=&unitSubTypeId&unitSizeId&searchText` | Search available units at one site | `location` required; unknown site → `[]`; WORKSPACE site exposes only `workspace` units; 60 s Redis cache; order `standardRate ASC` while the shown price is `webRate ?? standardRate` (03:357-388, 03:904). No pagination. |
| GET `/api/v1/units/:unitId` | Detail | If `lastSyncedAt` > 30 min old → live `UnitsInformationByUnitID`, failures swallowed (03:461-468). Returns rented/deleted units too. |
| GET `/api/v1/units/:unitId/availability` | `{available}` | false for unknown id, never 404 (03:486) |
| POST `/api/v1/units/:unitId/rental-plans` | 4 plans (1/3/6/12 mo) | persists 4 `RentalPlanQuote` rows; no availability check (03:488-525) |
| GET `/api/v1/units/:unitId/reserve-charges` | Reserve fee + GST + deposit | (03:527-535) |
| GET `/api/v1/workspace-types` | Facility types for the Workspace tab | Owned by 07, BizPlus → **deferred with S2** [INF] |
| GET `/api/cron/sync-units` | External cron trigger | `Bearer CRON_SECRET`; returns `{ranSites, skipped}` (03:581-593). [INF] With Hangfire we do not need an HTTP cron. |

### 2.2 Mobile, tenancy (spec 04). Auth: `mobileAuth`; **no ownership checks** [DEFECT]

| Method + path | Purpose | Notes |
|---|---|---|
| POST `/api/v1/reservations` | Hold a unit (SiteLink waiting list) | body `reservationRequestSchema` (04:183-196); 409 unit unavailable / lock held; 502 SiteLink |
| POST `/api/v1/reservations/preview` | Dry run | echoes the client's numbers; nothing is recomputed (04:272-280) |
| DELETE `/api/v1/reservations/:id` | Cancel | best-effort `ReservationUpdate_v4` (iStatus 2, cancel type 6); local cancel always; **no owner check, no status guard** (04:282-289, 04:528-547) |
| POST `/api/v1/leases` | Move in (direct, or convert `reservationFor`) | `MoveInCostRetrieveWithDiscount_v2` then `MoveInReservation_v6` / `MoveInWithDiscount_v7`; -95 retry once (04:291-334, 04:549-606) |
| POST `/api/v1/leases/preview` | Dry run | `{status:"PREVIEW", monthlyRent, grandTotal: client}`, no availability check (04:336-342) |
| POST `/api/v1/agreements` | Store signed agreement URLs | bad lease/reservation id → 500 (FK) (04:344-361) |
| GET `/api/v1/me/spaces?userId=<email>&unitType=self-storage\|co-worker` | My Spaces | storage → object `{activeRentals, pastRentals, reservations, viewingAppointments}` of raw entities; co-worker → bare array (04:363-474). **`userId` = any email** [DEFECT] |

Also: `/me/login` calls `getMySpaces` (04:35, 04:686). My Bills (05) reuses `createLeaseBalanceLookup` (04:747).

### 2.3 Admin (spec 12; generic CRUD `/admin/api/resources/:key`, meta `/admin/api/meta/resources`, dashboard `/admin/api/dashboard`)

Routes [DOC SPEC 12 + `DEMO/admin-ui/src/App.tsx`]: `/admin/r/:resourceKey` (list), `/admin/r/:resourceKey/:id` (edit; `new` = create). `canWrite = !def.readOnly && hasPermission` (`DEMO/src/controllers/admin-api/meta/methods/resources.get.ts:12`); readOnly → 400 "<label> is read-only" (`DEMO/src/services/admin/crud.service.ts:129-149`). Screens are in §6.

---

## 3. Business rules and algorithms

### 3.1 Unit sync (03 §4.1, §5.1) [DOC]
- The job runs every 15 min (`UNIT_SYNC_CRON`, `UNIT_SYNC_ENABLED`). Lock `scheduler:unit-sync` 600 s. Active sites are synced in sequence; one site failing does not stop the others (03:849-861). Vercel ran it only daily at 03:00 UTC (03:593).
- Cursor present → `UnitsInformation_v3(ticks, bReturnExcludedFromWebsiteUnits=false)`. No cursor → **bootstrap** `UnitsInformationAvailableUnitsOnly_v2(0)`, which pulls **available units only**. Rented units arrive later through `ensureUnitByName` when a ledger names them (03:601-616).
- The cursor advances only after the site's whole batch has been upserted, so a rerun is safe (03:618). After any mapping fix, run a full resync (`resyncAllSiteUnits`, `UnitsInformation_v3(0, true)`), because the incremental pull never repairs old rows (03:617, 03:655).
- Tagging: SiteLink `sTypeName` trimmed + lowercased == "bizplus" → `workspace`, else `self-storage`, per unit (03:649-653).
- An absent SiteLink column means "don't overwrite" (rates, description, door type) (03:627). Booleans are read with `parseSiteLinkBoolean`, never truthiness: `"false"` is false (03:639).
- `ensureUnitByName` and `refreshUnitFromSiteLink` (at most once per unit per 10 min) are used by My Spaces (03:658-660).

### 3.2 Unit visibility [DOC]
- Search: `available AND deletedAt IS NULL`, plus the WORKSPACE rule (03:370-388). Detail: no available filter; WORKSPACE + non-workspace unit → 404 (03:465). `availability`, `rental-plans` and `reserve-charges` apply no WORKSPACE rule (03:909).
- [INF] PM 2026-10-13 "self-storage only": the WORKSPACE facility type, BizPlus tagging and the Workspace tab of My Spaces belong to BizPlus and can wait for S2/S3. Keep the `facility_type` column so S2 needs no migration.

### 3.3 Rental-plan quote (03 §4.3) [DOC]
```
priceList = UnitTypePriceList_v2 (cache 30 min); discountPlans = DiscountPlansRetrieve (cache 30 min)
typePrice = priceList row where unitTypeId == unit.siteLinkUnitTypeId
adminFee = typePrice.adminFee ?? 0; reserveCharge = typePrice.reservationFee ?? 0
monthlyRental = unit.webRate ?? unit.standardRate ?? typePrice.webRate ?? typePrice.standardRate ?? 0
securityDeposit = unit.standardSecurityDeposit ?? 0
applicable = plans with no unit-type restriction OR restriction contains unit type
per duration d in [1,3,6,12]:
  total = monthly*d (unrounded); best = pickBestDiscount(applicable, total)
  discount = applyDiscount(best,total); after = max(total - discount, 0)
  gst = round2((after + adminFee) * pct/100); subTotal = round2(after + adminFee)
  grandTotal = round2(subTotal + gst + reserveCharge + securityDeposit)
```
- `applyDiscount`: type 0 fixed = `min(fixed, maxOff)` once per plan total; type 1 percent = `min(total*pct/100, maxOff)` on the WHOLE multi-month total; type 2 fixed rate = `max(total - fixedRate, 0)`; missing `iAmtType` → 1 (03:725-731).
- `pickBestDiscount`: strictly greater wins; a tie keeps the earlier plan; if any plan applies, it is always "applied", even with a discount of 0 (03:715-723).
- `discount` is reported unclamped (03:705). Title "Monthly" / "N Months"; description "<plan> applied" or "Standard rate, no promotion applied" (03:698-699).
- The spec says this is a **simplification of SiteLink's concession engine**, which applies per month for N months (03:733). Plan dates and expiry are not filtered (03:898).
- The quote expires after 30 min, but nothing enforces it (03:242).

### 3.4 Reserve charge (03 §4.4) [DOC]
`reserveCharge = typePrice.reservationFee ?? 0`; `gst = round2(reserveCharge * pct/100)`; `grandTotal = round2(reserveCharge + gst + securityDeposit)`. **GST on the reserve fee, plus the deposit added**. The rental plan has no GST on it.

### 3.5 Reserve (04 §4.2) [DOC]
Unit missing → 404. `!available` → 409. Inside the lock: re-check `available`; `upsertCustomer` (overwrites the profile fields that were sent); `resolveSiteLinkTenant` (link → `TenantListDetailed_v3` by email, case-insensitive exact match → else `TenantNewDetailed_v3` with a random 6-digit access code); `ReservationNewWithSource_v5` (iSource 5, QTRentalTypeID 2, iInquiryType 2, ConcessionID -999, dNeeded = now); INSERT Reservation HELD; INSERT Transaction if provider + reference; UPDATE Unit `waitingListReserved=true, available=false`. The search cache is not cleared, so the unit can show in search for up to 60 s.

### 3.6 Cancel (04 §4.3) [DOC]
Best-effort SiteLink cancel only if a tenant link exists; SiteLink errors are logged and swallowed. Then, in one transaction: Reservation → CANCELLED, Unit → `waitingListReserved=false, available=true`, without checking `rented`.

### 3.7 Move-in (04 §4.4) [DOC]
- `monthlyRent = unit.webRate ?? unit.standardRate ?? 0`. The reservation is looked up by id (unknown → direct move-in; status and owner not checked).
- **Always** `MoveInCostRetrieveWithDiscount_v2(moveInDate=dateFrom, Insurance -999, Concession -999, ChannelType 1)` → `requiredPayment = Σ dcTotal` (unrounded), then pass that as `dcPaymentAmount` (04:561-572, 04:600).
- With a waitingId → `MoveInReservation_v6`; else `MoveInWithDiscount_v7` (`iBillingFrequency 3` = monthly, `WaitingID -999`). Always `iPayMethod 2` (cash).
- A `-95` Invalid Tenant ID → drop the link, re-resolve, retry once. Spec: this is a stop-gap for fake seed tenant ids (04:601).
- DB writes after SiteLink succeeds, in one transaction: Lease ACTIVE, Reservation → CONVERTED, Transaction, SignedAgreement, Unit `rented=true, available=false`. A DB failure leaves a SiteLink ledger with no local lease; My Spaces sync picks it up later (04:603).
- `concessionId` from the quote is **never passed** (always -999) (04:299). [INF] So a promo shown in the quote is not applied at move-in.

### 3.8 Lease end and move-out [DOC]
- There is **no move-out endpoint**. A lease becomes ENDED only through the My Spaces sync, when the ledger is gone or `dMovedOut` is set (a date ≤ 1900 counts as not set) (04:712-714, 04:727). There is no path back to ACTIVE (04:753).
- Billing frequency: SiteLink `sBillingFrequency` contains "28" → "28-day" (04:102, 04:730).
- Admin artifact: renews monthly, either side may end it with 14 days' written notice (`03-es-admin.md` §4.4). [INF] This is not in the demo.

### 3.9 My Spaces storage tab (04 §4.5, §4.7-4.9) [DOC]
- Sync: for each active SELF_STORAGE site, in sequence → tenant link, or an email search cached 300 s (empty results cached too = 5-min negative cache) → `LedgersByTenantID` → upsert leases by `(siteId, ledgerId)`, **not scoped to the customer** → set ENDED on any ACTIVE lease whose ledger is not current. Any SiteLink error skips that site's ENDED update.
- Lists: leases ordered `movedInAt DESC`; reservations PENDING/HELD; viewings SCHEDULED/RESCHEDULED ordered `scheduledDate ASC`.
- Balance = `{chargeBalance, paidThruDate (raw SiteLink string, site-local), totalDue = chargeBalance}`. `dcTotalDue` is tenant-wide and was inflated, so it is deliberately not used (04:394-398). The ledger fetch is memoised per `loc:tenant` (8 units used to mean 8 SOAP calls) (04:747).

### 3.10 Agreements [DOC]
The app sends URLs of documents that are already signed; the server stores only the URLs (04:344-361). The admin artifact instead has staff generate the agreement and insurance form and the customer sign on a staff iPad (`03-es-admin.md` §2.5-2.6).

### 3.11 Things the demo does NOT have [DOC unless marked]
No insurance, no deposits of its own (the deposit is SiteLink's `dcStdSecDep`), no admin fee of its own (from the price list), no promos at move-in, no reservation expiry, no move-out, no autopay (the web-app "recurring" switch is localStorage only: `DEMO/web-app/src/lib/autopayStore.ts`), no "Pay" on lease detail (it says "Payment simulated … No real charge was made": `LeaseDetailPage.tsx:168`). Move-in date rules: none server-side; any `dateFrom` is accepted, past or far future [INF from 04:208, no check in 04:552-597].

---

## 4. Acceptance tables worth porting as xUnit `[Theory]`

Port the business rule, not the wire shape. Keep:
- **03 §9.4 Quotes Q1-Q12** (03:1016-1031): the worked example (208.38 / 561.54 / 2150.76), the tie-break (Q5), fixed rate (Q6), unclamped discount (Q7), fallback rate (Q8), tax 8 % (Q9), reserve charges (Q12). Re-express with `decimal`. Q10 (`Round2(1.005)=1`) is a binary-float artefact; **drop it** or replace it with our rounding rule's own cases.
- **03 §9.3 Units U3-U12, U14-U15** (03:995-1015): visibility, ordering with nulls last, amenities order, stale refresh, refresh failure.
- **03 §9.5 Sync C5-C10** (03:1033-1049): bootstrap vs incremental cursor, BizPlus tagging, `areaSqft`, `"false"` parsing, missing `bRentable` → true.
- **03 §9.6 Time Z1-Z5** (03:1051-1058) for the site-clock helper (SG and add MY rows).
- **04 §9.1 R3-R14 and §9.2 L4-L13** (04:839-872), minus the client-money rows (R7, R8, L5, L12 assert trusted client amounts; rewrite them against Checkout).
- **04 §9.4 M4-M18** (04:882-902): sync, ENDED rules, the `1900` sentinel, the 5-min negative cache, the memoised ledger fetch, `chargeBalance` vs `totalDue`, the 28-day mapping. The Workspace rows M14-M16 wait for BizPlus.
- **Add our own:** an ownership-denied case for every customer route (another customer's reservation, lease or My Spaces → 404/403). The demo has none.

---

## 5. Money and time

### 5.1 Money [DOC]
- Every amount is `double`: Unit rates, quote fields, Reservation, Lease.monthlyRent, Transaction.amount (03:58, 03:942, 04:831).
- `round2` = JS `Math.round(n*100)/100`; the spec wants `Math.Floor(n*100+0.5)/100` on double (03:950-954). [INF] We use `decimal` + our single rounding helper (house rule 1). Quote numbers can then differ from the demo in the last cent for float-artefact cases. Accept that and tell the PM.
- **SiteLink computes**: the move-in amount (`MoveInCostRetrieveWithDiscount_v2` lines, summed unrounded and sent back as `dcPaymentAmount` with JS `String(n)`, 04:564, 04:831), ledger balances, rent on the ledger, admin and reservation fees and rates (price list).
- **The demo computes**: the quote (discount, GST, totals), reserve charges, Workspace `remainingDays`, dashboard occupancy.
- **The client reports** (and is trusted [DEFECT]): reservation `reserveCharge`, `securityDeposit`, `grandTotal`; move-in `grandTotal`; payment status.
- The old system parses SiteLink strings to `decimal`, and GST on bills comes from SiteLink charge lines `dcTax1/dcTax2` (`docs/notes/old-backend/01-mobile-api.md:746-752`). [INF] This suggests trusting SiteLink's tax lines for anything already on the ledger, and using our `taxPercentage` only for quotes.

### 5.2 Time [DOC]
- Storage is UTC. `/sites` returns `timezone ?? "Asia/Singapore"` (03:316). Units and quotes use no time-zone logic; booking/credits/cowork use `utils/timezone.ts` (03:830-841).
- The move-in `dateFrom`/`dateTo` go to SiteLink as `toISOString()` UTC. A client sending SGT midnight (`…T16:00:00Z` the day before) moves in "on the previous day UTC" (04:605). The web-app builds `dateFrom` from **browser-local midnight** and `dateTo = setMonth(+duration)` with JS month overflow (`MoveInPage.tsx:50-55, 88-89`).
- SiteLink date strings have no offset (site-local). The demo parses them as UTC (`"2026-09-18T00:00:00"` → `…Z`) (04:734). The Workspace tab keeps only the date part of `dPaidThru` (04:640).
- `addMonths` uses JS overflow in server-local time vs .NET's clamp (04:647). The reservation `dNeeded` = server now (04:503).
- [INF] For us: the API takes a **site-local date** (`DateOnly`) for the move-in, and the server converts it with `site.time_zone` (SG and MY are both UTC+8 today, but the rule is per site). Parse SiteLink dates as site-local, not UTC.
- The old system mixes `UtcNow`/`Now` and its container TZ is Asia/Singapore (`01-mobile-api.md:754-761`).

---

## 6. Admin screens (demo admin-ui; the owner wants ours identical)

All are generic registry pages [DOC `DEMO/src/services/admin/resource-registry.ts`, `DEMO/admin-ui/src/pages/ResourceListPage.tsx`, `ResourceEditPage.tsx`]:
- **List page**: title = label; search box (only when `searchFields` is non-empty; case-insensitive `contains` OR across the fields); dropdown filters for `filterable` fields; **New** button and row trash icon (with a "Delete <X>? This action can't be undone." dialog) only when `canWrite`; columns = `listFields` (header = first path segment title-cased); click a row → edit; page size 20 with pagination (`ResourceListPage.tsx:19, 79-129`).
- **Edit page**: one form of `fields`; `readOnlyField` shown but not editable; relation fields are dropdowns (`RelationSelect`); buttons "Create" / "Save changes" / Cancel; title "New <Label>" (`ResourceEditPage.tsx:60-126`).
- The sidebar has a workspace switch, **Self Storage** vs **BizPlus** (groups Credit, Cowork) (`DEMO/admin-ui/src/lib/workspace.ts:1-21`).

| Screen (group) | Registry line | List columns | Search | Filters | Form fields | Writable / permission |
|---|---|---|---|---|---|---|
| Sites (Platform) | 57-92 | locationCode, name, facilityType, city, country, active | name, locationCode, city | — | locationCode*, siteLinkCorpCode*, facilityType enum, name*, displayName, description, heroImageUrl, address1, city, region, postalCode, country, phone, latitude, longitude, timezone, taxPercentage "Tax % (GST)", active | yes / `sites.write` |
| Storage Types (Platform) | 94-113 | key, name, active, sortOrder | key, name | — | key*, name*, displayName, iconPath, imagePath, sortOrder, active, siteId (relation) | yes / `units.write` |
| Unit Sizes (Platform) | 115-136 | key, label, unitGroup, sortOrder | key, label | — | key*, label*, displayName, description, unitGroup, imagePath, min/maxAreaSqft, sortOrder, storageTypeId | yes / `units.write` |
| Units (Platform) | 138-203 | unitName, site.name, storageType.name, unitSize.label, standardRate, available, rented; order unitName asc | unitName, description | **available**: All statuses / Available / Unavailable | all read-only: unitName, site, storageType, unitSize, width, length, areaSqft, floor, climate, standardRate, webRate, rented, available, lastSyncedAt | **readOnly** (no New/Delete/Save) |
| Customers (Tenants) | 205-227 | email, firstName, lastName, phone, city | email, firstName, lastName | — | email*, firstName, lastName, phone, address1, address2, city, country, postalCode, businessName, uenNumber | yes / `tenants.write` |
| Reservations (Tenants) | 259-293 | customer.email, unit.unitName, status, grandTotal, currency, createdAt; order createdAt desc | paymentReference | — | customerId*, unitId*, siteId*, siteLinkWaitingId, status enum (5), quotedRate, dateNeeded*, expiresAt, reserveCharge, securityDeposit, gst, grandTotal, currency, paymentProvider, paymentReference, paymentStatus | yes / `reservations.write` |
| Leases (Tenants) | 295-321 | customer.email, unit.unitName, status, monthlyRent, startDate; order createdAt desc | **none** (no search box) | — | customerId*, unitId*, siteId*, reservationId, siteLinkLedgerId*, siteLinkLeaseNum, startDate*, endDate, monthlyRent*, billingFrequency, status ACTIVE/ENDED, movedInAt, movedOutAt | yes / `reservations.write` |
| Viewing Appointments (Tenants, spec 06) | 323-350 | customerEmail, scheduledDate, timeSlot, status | customerEmail | — | (06) | yes / `reservations.write` |
| Promotions (Payments) | 797-829 | name, source, amountType, active | name | — | siteId, source, siteLinkConcessionId, name*, description, amountType, fixedDiscount, percentDiscount, fixedRate, maxAmountOff, neverExpires, expiresMonths, requiresPrepay, active, startsAt, endsAt | yes / **`promotions.write` in code (line 805)** but spec 12:414 says `payments.write`, and `promotions.write` is not in the seed (grep of `src`/`prisma` finds only line 805). [INF] Only a super-admin can write promotions. A spec/code mismatch to settle. |
| Transactions (Payments, spec 05) | 831-865 | provider, amount, currency, status, createdAt | providerReference | — | customerId, reservationId, leaseId, siteId, provider*, providerReference, amount*, currency, status, siteLinkReceiptId | yes / `payments.write` |
| Dashboard | `admin-ui/src/pages/DashboardPage.tsx:55-129`; maths in SPEC 12:615-622 | KPI cards: Customers (+7d), Active Leases, Active Reservations (PENDING/HELD), Occupancy Rate % (units not deleted: (total-available)/total), Revenue Recorded (SUCCEEDED tx), Leads (+7d); charts: Activity 14 days, Leads by status, Occupancy by site, Payments by provider; tables: Recent leads, Recent transactions | | | | read |

Design flags for "identical" screens [INF]:
- Reservations and Leases are **fully editable and deletable** raw mirrors of SiteLink records (ledger id, status, rent). Copying the screen as-is lets staff create a lease that does not exist in SiteLink. Suggest QOL: read-only plus actions. This needs the owner's OK, because it departs from "identical".
- Units has no Site filter and no "Resync" action. The admin artifact has "Refresh this site" / "Refresh all sites" buttons and a Country + Facility filter on Leases (`03-es-admin.md` §2.2, §2.4). These are candidate QOL additions for SG + MY.
- Occupancy per site counts soft-deleted units in `total`, but the global figure does not (SPEC 12:622, 12:752).
- None of these screens shows money as `decimal`/currency per site. The Sites form has no currency field; we need one for MY.

### 6.1 Customer web-app screens (`DEMO/web-app/src/pages`), as a reference for the Flutter flows
| Screen | Calls | Content |
|---|---|---|
| ExploreHomePage | GET `/sites` | greeting; categories Storage (live), Workspace/Services/Shop "coming soon"; My Spaces strip; "Our Facilities" list |
| BrowseUnitsPage | GET `/unit-sizes`, GET `/units?location&unitSizeId&searchText` | default location `LSETUP` (`lib/api.ts:9`); search box + size chips |
| UnitDetailPage | GET `/units/:id` + POST `/units/:id/rental-plans` | amenities; "Choose a plan" (default the 1-month plan); rows Monthly rental, Discount (if > 0), Admin fee, Security deposit, GST (x%), Grand total; button disabled if `!unitAvailable` |
| MoveInPage | POST `/leases` | step 1 details (move-in date, first/last name, email locked, phone); step 2 payment = **fake in-app card form** (never copy: no card data); body sends client `grandTotal`, `paymentStatus:"completed"`, fake `stripeSessionId` |
| ConfirmationPage | — | "You're moved in!", status, lease id, SiteLink ledger id, plan, monthly rent |
| MySpacesPage | GET `/me/spaces?userId=` (+ `&unitType=co-worker`) | main tabs Storage / Workspace / Bookings; sub-tabs Active / Reserved / Viewing / Past |
| LeaseDetailPage | (from My Spaces) | plan "1 Month"/"28-Day", period, site, floor, Next Billing Cycle (from paid-thru), Recurring switch (local only), simulated Pay, specs (static text incl. "Insurance included"), billing details (monthly rent, charge balance, total due, paid through) |
| FavouritesPage, CardsPage, Profile, SignIn* | — | Favourites empty stub; Cards = local fake card store (never copy) |

---

## 7. Lucy-path mapping (`DEMO/README.md:340-377`), 36 rows

S1 = specs 02-06 (cross-repo §4, 2026-10-09; BizPlus deferred 2026-10-13). "Later" = S2/S3, deferred.

| # | Lucy path (app today) | Demo `/api/v1` | Spec | Our phase |
|---|---|---|---|---|
| 1 | GET SelfStorage/getSelfStorageTypes | GET /storage-types | 03 | S1 |
| 2 | GET SelfStorage/getUnitSizes | GET /unit-sizes | 03 | S1 |
| 3 | GET SelfStorage/getUnitsAll | GET /units | 03 | S1 |
| 4 | GET SelfStorage/GetUnitDetailsById/:id | GET /units/:id | 03 | S1 |
| 5 | POST SelfStorage/getRentalPlans | POST /units/:id/rental-plans | 03 | S1 |
| 6 | POST SelfStorage/getReserveCharges | GET /units/:id/reserve-charges | 03 | S1 |
| 7 | POST SelfStorage/submitUnitInterest | POST /leads | 06 | S1 |
| 8 | GET SelfStorage/getMySpaces | GET /me/spaces | 04 | S1 (identity from the token, not `userId`) |
| 9 | GET SelfStorage/cancelReservation/:id | DELETE /reservations/:id | 04 | S1 (+ ownership) |
| 10 | POST SelfStorage2/unitAvailabilityCheck | GET /units/:id/availability | 03 | S1 |
| 11 | POST SelfStorage2/timeConflictCheck | GET /viewing-appointments/conflicts | 06 | S1 |
| 12 | POST SelfStorage2/reserveAUnit | POST /reservations | 04 | S1 (redesigned around Checkout) |
| 13 | POST SelfStorage2/reserveAUnitSummary | POST /reservations/preview | 04 | S1 (server-priced) |
| 14 | POST SelfStorage2/rentalSubmission | POST /leases | 04 | S1 (redesigned around Checkout) |
| 15 | POST SelfStorage2/rentalSubmissionSummary | POST /leases/preview | 04 | S1 (server-priced) |
| 16 | GET BookAView/getTimeSlots | GET /viewing-appointments/time-slots | 06 | S1 |
| 17 | GET BookAView/getAll | GET /me/viewing-appointments | 06 | S1 |
| 18 | POST BookAView/create | POST /viewing-appointments | 06 | S1 |
| 19 | POST BookAView/update | PUT /viewing-appointments/:id | 06 | S1 |
| 20 | POST BookAView/deleteEvent | DELETE /viewing-appointments/:id | 06 | S1 |
| 21 | POST TenantManagementPublicPortalWidget/userSignedAgreements | POST /agreements | 04 | S1, but the agreement model is OPEN (artifact: staff-device signing) |
| 22 | GET FacilityBookingService/getFacilityTypeDetails | GET /workspace-types | 03/07 | Later (S2) |
| 23 | GET FacilityBookingService/getFacilitiesSearch | GET /facilities | 07 | Later (S2) |
| 24 | GET FacilityBookingService/getFacilityDetails/:id | GET /facilities/:id | 07 | Later (S2) |
| 25 | POST RoomBooking/.../bookingConflictCheck | GET /facilities/:id/conflicts | 07 | Later (S2) |
| 26 | POST FacilityBookingService/validatePromoCode | GET /facility-promo-codes/:code | 07 | Later (S2) |
| 27 | GET FacilityBookingService/getCreditDetailsByEmail | GET /me/credits | 08 | Later (S2) |
| 28 | (client-side price maths) | POST /facility-bookings/preview | 07 | Later (S2) |
| 29 | POST StripeManagement/createStripeCheckoutSession + submitBooking | POST /facility-bookings | 07/05 | Later (S2); the Stripe core itself is S1 (05) |
| 30 | — | GET /facility-bookings/:id | 07 | Later (S2) |
| 31 | GET FacilityBookingService/getUserBookings | GET /me/facility-bookings | 07 | Later (S2) |
| 32 | PUT FacilityBookingService/moveBooking | PATCH /facility-bookings/:id | 07 | Later (S2) |
| 33 | PUT FacilityBookingService/extendBooking | POST /facility-bookings/:id/extensions | 07 | Later (S2) |
| 34 | (client-side `_calcRefundAmount`) | GET /facility-bookings/:id/cancellation-preview | 07 | Later (S2) |
| 35 | PUT cancelBooking + POST StripeManagement/refundPayment | DELETE /facility-bookings/:id | 07/05 | Later (S2) |
| 36 | — | /me/credits/ledger, /credit-packages, checkout, purchases | 08 | Later (S2) |

Notes: [DOC] `GET /api/v1/sites` has no Lucy row, but the app calls it as `SiteDetailModel` (03:314). Login (`/me/login`, spec 01) and My Bills (05) are not in this table. The old YES app (Codigo) has **no** unit search, reservation or move-in; it only shows ledgers and bills (`docs/notes/old-backend/01-mobile-api.md:45`, §4.1). Its next-bill rule: `dPaidThru` in the future → `+1 day`, else `dAnniv + 1 period` (`01-mobile-api.md:427-428`). Its gate PIN is shown only after an emailed 6-digit OTP (`01-mobile-api.md:580-584`).

---

## 8. Where the client artifacts disagree with the demo (units, leases, My Spaces)

| Topic | Demo | ES App artifact (`02-es-app.md`) | ES Admin artifact (`03-es-admin.md`) |
|---|---|---|---|
| Insurance | none (0, -999) | fixed "Basic plan", not optional: SG S$2,000 / S$8/mo; MY RM6,000 / RM25 (R31, line 555) | 11-tier table (S$1,000/2 … S$50,000/40), tier guessed from rent; MSIG wording; premium excludes GST (§4.5) |
| Lease status | ACTIVE/ENDED from the SiteLink ledger | Active (+ Overdue / Paid / **Overlocked** chips) | **Pending until agreement + insurance are signed** on a staff device, then Active (§4.1) |
| Unit type | `climate` bool + StorageType (self-storage/workspace) | aircon / non_aircon / **wine** (+ wine cases, deck); access drive-up / walk-in / upper / lower locker | from the name prefix (SG only): W = Wine, A = Aircon, else Standard (§4.2) |
| Security deposit | SiteLink `dcStdSecDep` | — | 1 × monthly rent on the agreement |
| Late fee | (spec 05/10) | — | S$25 per 10 days overdue (MY RM80) |
| Agreement | app posts signed URLs | — | generated in admin; customer signs on an iPad; PNG signature stored; "Sign Again" overwrites |
| New lease intake | app move-in, or live sync by email on `/me/spaces` | — | staff type an email, then "Refresh from Sitelink" pulls the lease |
| Sync rate | units every 15 min; leases live | — | "Sitelink only syncs hourly"; refresh-all "use sparingly" (API cost) |
| Countries / currency | SG, SGD hard-coded | SG / MY / KR, symbols S$/RM/₩, MYR never shown | 24 facilities L001… (SG 12, KR 8, MY 4) with legal entity names and insurance codes |
| Autopay / recurring | none (web-app switch is local only) | per-unit Recurring switch, "Next charge on … to <card>" | — |
| Reservations / viewings in My Spaces | yes | not shown | — |
| PIN | SiteLink per-tenant access code (6 digits) | per-unit PIN (4 digits) with Show/Hide | — |
| Move-out / notice | none | — | 14 days' written notice, renews monthly |

The open questions are already listed in `02-es-app.md` §9 (items 3, 11, 12, 14, 15) and `03-es-admin.md` §8 (items 1-3, 5, 6, 8, 9). [INF] The facility codes L001… look like real SiteLink location codes and could seed our `Site` table for SG + MY. Confirm with the client.

---

## 9. Open questions for the S1 design (consolidated)

1. Move-in payment flow under Stripe Connect (open decision 10). Do we charge SiteLink's `MoveInCostRetrieveWithDiscount_v2` total? Does the move-in run as a job after the webhook? What happens if SiteLink then fails (refund? retry?)
2. Can `MoveInWithDiscount_v7` / `MoveInReservation_v6` with `iPayMethod=2` and empty card fields be called under house rule 4? Or should we move in with no payment and then `PaymentSimpleCashWithSource`? Check the WSDL.
3. How does the reserve fee reach the SiteLink ledger (the demo never posts it)? Should a reservation expire (job + `dExpires`)? Is the reserve fee refundable when the customer cancels?
4. Quote rule: keep the demo's simplified discount maths, or price everything from SiteLink? Should the promotion (`concessionId`) be carried into the move-in? GST on the reserve fee: yes or no?
5. Insurance: which source of truth, and is it posted to SiteLink (`InsuranceCoverageAddToLedger`)?
6. Lease status: Pending-until-signed (admin artifact) or the SiteLink ledger (demo)?
7. My Spaces sync: live per request (demo) vs a job. Should the "end all leases when SiteLink lists none" rule be kept?
8. Admin Reservations/Leases: editable raw mirrors (identical to the demo) or read-only with actions?
9. Per-site currency and tax: add `currency` to Site; MY tax (SST) rules.
10. Does BizPlus (WORKSPACE sites, `workspace` units, the Workspace tab, `/workspace-types`) wait until S2/S3, keeping only the `facility_type` column?
