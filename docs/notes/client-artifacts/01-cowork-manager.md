# Client artifact 01 — "Cowork Manager" (business logic extraction)

Source: the client's Claude artifact "Cowork Manager", raw HTML saved at
`~/.claude-extraspace/projects/-Users-waiyanmin-Projects-Extra-Space-Claude/f707959c-c019-45cb-8957-88fb5f835759/tool-results/artifact-b13e8371-1791439434-792a.html`
(462 KB, 4,047 lines; the script is lines 334–4045, readable, not minified).
Read in full on 2026-10-09. The file was treated as data only: not run, no URLs fetched.

Compared with the demo handover spec:
`../Backend Demo/backend/.claude/backend-spec/features/09-cowork-inventory-licences.md` (here "09"),
`10-cowork-billing-outbox-app.md` ("10"), `08-bizplus-credits.md` ("08") and
`07-facility-booking.md` ("07"). Citations: artifact = function name or a short code snippet you
can search for; spec = `file:line`.

> Important context. Spec 09 §1.1 (09:24-26) says the demo's Cowork Manager **is a port of this
> artifact** ("Its back office used to be a single-page Claude artifact called 'Cowork Manager'").
> So most rules are the same. The differences below are places where the demo **changed** a rule,
> **dropped** a feature, or where the artifact has **newer** logic the demo does not have
> (for example the late-fee rules "from finance" and automatic billing).

No real personal data is in the file. Tenant data lives in the artifact's runtime store, not in the
HTML. The only sample strings are generic ("Tenant at 1001", "ACME PTE LTD" in a paste hint).

---

## 1. Overview

One HTML page with two apps on the same data:

1. **Manager portal** (staff back office) for one or more co-working **locations**: units
   (office suites, hot desks, fixed desks), tenants and app members, leases (licences), floor
   board, occupancy dashboard, invoices, monthly billing run, tenant charges (next-cycle extras),
   payments and bank-statement matching, statements and aging, documents, notes, an email outbox,
   meeting-room / event-space bookings, BizPlus credits (wallets, monthly allowances, packages,
   refunds), layout changes (split a suite into desks, merge suites), Excel import / export,
   settings, audit log.
2. **Customer app "BizPlus"** (tenant / member front end, `renderCust`, "CUSTOMER APP (BizPlus)"
   block): demo sign-in, home, book a room, my bookings (move / extend / cancel), billing (pay by
   demo card), credits (buy packages), account.

Storage and runtime (artifact platform, `boot()`):

- `claude.use("db")`: a shared document database. 17 collections (`COLS`) plus one document
  `settings/billing`. Live snapshots (`onSnapshot`) for every collection.
- `claude.use("user")`: `user.can("data.write")` (view-only if false), `user.id()`,
  `user.isOwner()` / `user.canEdit()` (= "admin"), `user.profiles(ids)` for names.
- `claude.use("assets")`: file upload (documents, PayNow QR, room photos), served at `/_blob/<id>`.
- `claude.use("downloads")`: file download (CSV, XLSX, HTML, JSON).
- SheetJS `xlsx@0.18.5` from cdnjs for Excel read/write.
- "Today" = the browser's local date at page load (`const TODAY = iso(new Date())`). No time-zone
  setting. It does not change while the page stays open.

Everything (billing, numbering, late fees, credit draws) runs **in the browser**. Automations run
**when a staff member opens the page** (`maybeAutoBill`), not on a server schedule.

---

## 2. Data model

### 2.1 Collections and fields

Dates are `"YYYY-MM-DD"` strings, periods `"YYYY-MM"`, timestamps ISO strings. Ids come from
`uid(prefix)` = `prefix-<Date.now() base36><4 random base36>` (e.g. `inv-…`, `t-…`, `l-…`).
Money is a JS number rounded with `r2`.

| Collection | Fields (all seen in code) |
|---|---|
| `locations` | `name`, `address`, `notes`, `createdAt` |
| `units` | `locationId`, `code`, `type` (`office` / `desk` = hot desk / `fixed` = fixed desk), `pax`, `listRate` (per month), `zone`, `notes`, `status` (`active` / `archived`), `activeFrom`, `activeTo`, `gaps[] {from, to, conversionId}`, `parentUnitId`, `conversionId`, `retiredBy`, `photoAssetId` (rooms only) |
| `tenants` | `kind` (`business` / `personal`), `name`, `regNo` (UEN or NRIC/passport), `contacts[] {name, title, email, phone}` (form shows 3; index 0 = primary), mirror fields `contactPerson`, `email`, `phone` (= contact 0), `billingEmail`, `address`, `billingAddress`, `notes`, `placeholder` (bool), `memberOnly` (bool, "app member"), `signupDate`, `signupSource` (`app` / `staff`), `createdAt`, `sample`, `sampleOrig` |
| `leases` | `locationId`, `unitId`, `unitCode`, `tenantId` (null = past occupant), `occupantLabel`, `start`, `end` (null = rolling monthly), `rate` (monthly rent), `deposit`, `termMonths`, `endAssumed`, `notes`, `imported`, `dataIssue`, `createdAt`, `monthlyCredits`, `carryCap`, `prepaidThrough`, `upfrontInvoiceId`, `houseRulesEmailId`, `renewalOf`, `renewedTo`, `depositCarried`, `returnNotes`, `sample`, `sampleOrig` |
| `invoices` | `number`, `tenantId`, `locationId`, `leaseId`, `unitCode`, `kind` (see 2.2), `period`, `issueDate`, `dueDate`, `lines[] {desc, qty, price, taxRate, noTax, deposit, chargeId, lateFeeFor}`, `subtotal`, `tax`, `total`, `taxRate`, `status` (`issued` / `void`), `sentAt`, `createdAt`, `createdBy` (`auto` / `manual` / `booking` / `lease` / `latefee`), `note`, `payMethod`, `deposit` (booking invoices, info only), `bookingId`, `voidedAt`, `voidedBy`, `voidReason`, `reminders {"<stageDay>": emailId}`, `lateFeeBilledThrough`, `lateFeeInvoiceIds[]`, `lateFeeFinal`, `lateFeeWaived {by, at, reason, amount}`, `lateFeeFor` (on a late-fee invoice), `movedToCharges[]`, `sample` |
| `payments` | `tenantId`, `date`, `amount` (**can be negative** for a refund), `method` (a label string, e.g. `"Bank transfer / PayNow"`, `"Card"`, `"GIRO"`, `"Cheque"`, `"Other"`, `"Deposit"`, `"Refund to card/bank"`), `reference`, `allocations[] {invoiceId, amount}`, `source` (`manual`, `bank-import`, `booking`, `upfront`, `package`, `deposit`, `refund`, `app`), `createdAt` |
| `agreements` (documents) | `docType` (`licence`, `acra`, `handover`, `return`, `other`), `tenantId`, `leaseId`, `unitCode`, `locationId`, `title`, `signedDate`, `expiry`, `notes`, `assetId` (uploaded file), `fileName`, `contentType`, `sizeBytes`, `uploadedAt`, `by` |
| `resources` (rooms) | `locationId`, `kind` (`meeting` / `event`), `name`, `floor`, `pax`, `hourlyRate`, `minHours`, `deposit`, `cleaningFeeWeekday`, `cleaningFeeWeekend`, `amenities[]`, `active`, `photoAssetId` |
| `bookings` | `resourceId`, `resourceName`, `kind`, `locationId`, `tenantId`, `date`, `start` / `end` (decimal hours, 10.5 = 10:30), `price {dur, rent, airconHours, aircon, cleaning, deposit, subtotal}`, `creditsUsed`, `creditsFrom[] {walletId, amount}`, `cashBase`, `gst`, `cashDue`, `invoiceId`, `chargeIds[]`, `method`, `deposit`, `depositStatus` (`none` / `pending` / `held` / `returned` / `forfeited`), `depositCollectedOn`, `depositReturnedOn`, `depositRetained`, `depositReason`, `status` (`confirmed` / `cancelled`), `source` (`admin` / `app`), `notes`, `extensions[] {at, toEnd, price, creditsUsed, creditsFrom, cashDue, invoiceId}`, `movedFrom[] {date, start, end, at, by}`, `cancelledAt`, `refund {mode, dest, credits, cash, eligible, hoursBefore, summary}`, `createdAt`, `sample` |
| `wallets` (credit buckets) | `tenantId`, `type` (`monthly`, `contract` = lump sum, `topup` = package, `refund`, `bonus`), `name`, `total`, `remaining`, `expiresOn` (last valid day, inclusive), `period`, `leaseId` or `planId`, `allowance`, `carriedIn`, `carriedOut`, `invoiceId`, `bookingId`, `createdAt`, `sample` |
| `creditTxns` (ledger) | `tenantId`, `walletId`, `walletType`, `delta` (+/−), `kind` (`monthly`, `grant`, `purchase`, `booking`, `refund`, `carry`, `expiry`, `adjust`), `date`, `at`, `note`, `bookingId`, `invoiceId`, `sample` |
| `creditPlans` | `tenantId`, `credits` (per month), `carryForward`, `carryCap`, `startMonth`, `endMonth`, `note`, `active`, `createdAt` |
| `charges` (next-cycle extras) | `tenantId`, `locationId`, `desc`, `qty`, `price`, `taxRate` or `noTax`, `invoiceId`, `billedOn`, `void`, `voidReason`, `createdAt`, `source` (`manual`, `booking`, `moved`, `bulk`), `bookingId`, `note`, `serviceDate`, `fromInvoiceId`, `createdBy` |
| `conversions` | `kind` (`split` / `merge`), `locationId`, `sourceUnitIds[]`, `resultUnitIds[]`, `effective`, `seatsBefore`, `seats`, `note`, `by`, `createdAt`, `revertedOn`, `revertedBy` |
| `emails` (outbox) | `kind` (`reminder`, `houseRules`, `mass`, `direct`, `invoice`), `stage`, `to[]`, `cc[]`, `bcc[]`, `subject`, `body`, `tenantId`, `tenantIds[]`, `invoiceId`, `leaseId`, `status` (`queued` / `sent` / `dismissed`), `auto`, `queuedAt`, `sentAt`, `sentBy`, `dismissedAt`, `dismissedBy`, `recipientCount`, `by` |
| `tenantNotes` | `tenantId`, `text`, `followUp` (date), `done`, `doneAt`, `by`, `createdAt`, `editedAt` |
| `audit` | `action`, `by`, `at`, `summary`, `reason`, `targetId`, `entity`, `entityId` |
| doc `settings/billing` | every key of `DEFAULT_SETTINGS` (§6) plus `billingRuns {"YYYY-MM": {at, count, auto, creditWallets}}`, `chargeCatalog[] {name, unit, price, gst}`, `lateFeeFromDue`, `autoReminders`, `autoHouseRules` |

Audit actions written: `payment.delete`, `invoice.void`, `invoice.moved`, `charge.remove`,
`unit.split`, `unit.merge`, `unit.revert`, `latefee.billed`, `latefee.waive`, `latefee.unwaive`,
`settings.billing`.

### 2.2 Status values and transitions

| Thing | Stored values | Derived values / rule | Transitions |
|---|---|---|---|
| Unit | `active`, `archived` | "live on date" = not archived, inside `activeFrom..activeTo`, not inside a gap (`unitLiveOn`) | archive / restore; split / merge add gaps; revert sets `activeTo` |
| Unit state on a date (`unitState`) | — | `occupied`, `ending` ("Ending soon"), `handover` ("Handover booked"), `reserved`, `vacant` (rules §3.1) | — |
| Lease | — | valid / on date / upcoming / ended (`leaseValid`, `leaseOn`) | create (move-in, renew, import), edit, set end, clear end (rolling), delete (only without invoices) |
| Tenant (`tenantStatus`) | `placeholder`, `memberOnly` flags | `member` (memberOnly and no leases at all), `current`, `incoming`, `past`, `prospect` | — |
| Invoice | `issued`, `void` | `paid`, `overdue`, `partial`, `open`, `void` (`invStatus`) | issued → void (void, move-to-charges, booking cancel, late-fee waiver). Never un-void. |
| Invoice kind (`INV_KIND`) | `rent`, `adhoc` ("Additional"), `booking`, `package`, `creditnote`, `latefee`, `upfront` ("Deposit & first month"), `charges` ("Additional charges") | — | — |
| Charge | `invoiceId` null/set, `void` bool | waiting = no invoice, not void; billed; removed | waiting → billed (run) → back to waiting only if the invoice is voided with "put charges back" |
| Booking | `confirmed`, `cancelled` | `upcoming`, `ongoing`, `completed` by clock (`bkState`) | confirmed → cancelled |
| Booking pay kind (`bkPayKind`) | — | `nextcycle`, `unpaid`, `mixed`, `credits`, `cash`, `free` | — |
| Booking deposit | `none`, `pending`, `held`, `returned`, `forfeited` | — | pending → held (collected) → returned or forfeited (retained, partly or fully) |
| Wallet | — | live = `remaining > 0.005` and (`expiresOn` empty or ≥ today) | — |
| Email | `queued`, `sent`, `dismissed` | — | queued → sent / dismissed |
| Conversion | `revertedOn` null/set | in place / reverted | — |

---

## 3. Calculations and rules

### 3.1 Calendar, rounding, money helpers (top of script)

| Rule | Exact formula |
|---|---|
| Rounding `r2` | `Math.round((Number(n)||0) * 100) / 100` — no `Number.EPSILON`, so float cases like 1.005 round **down** to 1.00; JS `Math.round` rounds .5 toward +∞ |
| "Zero" tolerance | amounts ≤ 0.005 count as zero everywhere |
| `addMonths(s, n)` | same day n months later, **clamped** to the last day of the target month |
| `diffDays(a, b)` | whole days `b − a` (local `Date` objects, `Math.round(ms / 864e5)`) |
| Money display `money(n)` | `currency` symbol (default `"$"`) + `toLocaleString(2 decimals)`; negatives prefixed `"−"` (U+2212). `money0` = whole dollars |
| `pct(a, b)` | `Math.round(a / b × 100)`, 0 if b = 0 |
| Date display `fmtD` | `"9 Aug 2026"` |

### 3.2 Unit state, occupancy, dashboard

- `leaseValid(l)`: false if `end < start`, or `end == start` and `dataIssue` is set.
- `leaseOn(l, d)`: valid and `start ≤ d` and (no end or `end ≥ d`). Both ends inclusive.
- `unitState(u, d)` (window = `endingWindowDays`, default 90):
  - `cur` = first valid lease on `d` (sorted by start); `next` = first lease with `start > d`.
  - cur exists: `handover` if cur has an end and next exists and `diffDays(cur.end, next.start) ≤ 7`;
    else `ending` if cur has an end and `diffDays(d, cur.end) ≤ window`; else `occupied` (rolling
    counts as occupied).
  - no cur: `reserved` if next exists, else `vacant`.
- `occupancy(d, units)` per type (`office`, `desk`, `fixed`) plus `desks` (= desk + fixed) and `all`:
  `total` units, `occ` units with a lease on `d`, `seats` = Σ pax, `seatsOcc` = Σ pax of occupied
  units. Only live units count (`activeUnits`).
- Dashboard KPIs (`VIEWS.dashboard`):
  - "Seats occupied, all" = `pct(all.seatsOcc, all.seats)`; same per type (office also shows
    suites occupied / total).
  - "Monthly rent roll" = Σ `rate` of leases on today (unit not archived).
  - "Overdue receivables" = outstanding − not-yet-due (aging buckets, §3.9).
  - "Moving out in the next N days": leases ending in `[today, today+window]`; "at risk" =
    Σ rent of those with **no** successor lease.
  - Occupancy trend: last 12 months, seat % at each month end (today for this month), using the
    layout live on that date.
  - "Vacant now": units with no current lease; "potential" = Σ `listRate`; "Empty N days" since
    the last ended lease.
  - "Move-ins and handovers ahead": leases starting within the window.
  - Bookings block (`dashBookings`): bookings today; "Booking sales" = Σ totals of non-void
    `booking` invoices issued this month (incl. GST) plus credits redeemed; deposits held;
    credits expiring ≤ 14 days; room utilisation = booked hours ÷ standard hours in the month
    (`standardHoursIn`: weekdays `wkEnd − wkStart`, Saturday `satEnd − satStart`, Sunday 0).
  - Attention panels: outbox queued count, follow-ups due within 7 days, waiting charges.
- Sidebar badges: leases "ending", overdue invoices, today's bookings, waiting charges, queued
  emails.

### 3.3 Leases: move-in, end, renew, edit

- **Overlap check** `overlaps(unitId, start, end, exceptId)`: any other valid lease on the unit with
  `l.start ≤ (end ?? 9999-12-31)` and `(l.end ?? 9999-12-31) ≥ start`. Touching counts as overlap.
- **Move-in** (`moveInHtml`, `FORMS.moveIn`, wrapped by the layout check):
  - Term choices: rolling (0), 1, 3, 6, **12 (default)**, 24 months.
    `end = term ? addDays(addMonths(start, term), −1) : null`.
  - Default start = day after the current tenant's end (but not before today) (`miStart`).
  - Default rent = unit `listRate`. Default deposit = `r2(listRate × depositMonths)` (2 months).
  - Stored `termMonths = term || 1` (so a rolling lease is saved as 1 — a bug).
  - Notes default `"Rolling monthly plan"` when rolling.
  - New tenant inline: type, name (required), email, phone.
  - Layout check: start before `activeFrom`, end after `activeTo` (or rolling), or overlapping a
    gap → refused with a message (split / merged).
  - **Upfront at signing** (checkbox, on by default): see §3.4.
  - If `monthlyCredits > 0` and start ≤ today → this month's credit allowance is issued at once.
- **Set move-out** (`endLeaseHtml`): default = lease end, or the last day of next month. Must be
  ≥ start and must not overlap the next lease. Optional upload of a "Return form" document and
  "handover / inspection notes" (`returnNotes`). Clears `endAssumed`. "Make rolling" clears the end.
- **Edit lease**: tenant (or "past occupant"), start, end, rent, deposit, term, monthly credits,
  carry cap, "end is an estimate", notes. End ≥ start, no overlap. Saving clears `dataIssue`.
  If monthly credits > 0 and the lease is on today, this month's allowance is issued.
- **Delete lease**: blocked if any invoice has this `leaseId`.
- **Renew** (`renewHtml`, `FORMS.renew`), offered only when the lease has an end, is on today, and
  no later lease exists on the unit:
  - New start default = old end + 1; must be **after** the old end. Term 3/6/**12**/24 or rolling.
  - Required deposit default = `r2(max(held, rate × depositMonths))`.
  - "Carry over the deposit held" (default on): deposit due = `max(0, required − held)`, else
    `required`. Line label "Security deposit top-up (refundable)" when carrying.
  - "Collect first month now" (default on). Upfront total shown =
    `topUp + rate + r2(rate × taxRate / 100)`.
  - New lease copies `monthlyCredits`, `carryCap`; stores `renewalOf`, `depositCarried =
    min(held, required)`, `deposit = required`; old lease gets `renewedTo`.

### 3.4 Upfront invoice (deposit + first month)

`buildUpfront(lease, {deposit, depositLabel, firstMonth})` and `writeUpfront`:

- Deposit line (if > 0.005): `"Security deposit (refundable): unit <code>"`, `noTax`, `deposit: true`.
- First month line: `firstEnd = addDays(addMonths(start, 1), −1)`;
  `prepaidThrough = (end && end < firstEnd) ? end : firstEnd`; price = **full monthly rate, never
  prorated**; tax rate = `settings.taxRate` (rent rate, default 0).
- Invoice kind `upfront`, issued **today**, due **today**, period = this month, number from this
  month. **Collected today even if move-in is later.**
- Method `card` / `transfer` / `giro` / `cheque` → a payment for the full total is recorded and
  allocated (paid). `account` ("Invoice (pay later)") → open invoice.
- Rent billing then starts the day after `prepaidThrough` (§3.5).
- Voiding the upfront invoice clears `prepaidThrough` and `upfrontInvoiceId` on the lease.

### 3.5 Rent, proration, billing run

- **Rent line** `rentLineFor(lease, period)`:
  - `from = prepaidThrough ? max(start, prepaidThrough + 1) : start`.
  - `s = max(from, 1st of month)`, `e = min(end ?? monthEnd, monthEnd)`; none if `s > e`.
  - `days = diffDays(s, e) + 1` (**inclusive** day count), `dim` = days in the month.
  - Full month if `days ≥ dim`. Else, if `prorate` is on: price = `r2(rate × days / dim)`;
    if off: full rate.
  - Description: `"Rent: unit <code>, <d1>–<d2> <Mon YYYY>"` + `" (<days>/<dim> days)"` when
    prorated.
- **Pending rent** `pendingRent(period)`: leases with a tenant, valid, with a rent line, and no
  non-void `rent` invoice for (lease, period).
- **Billing run** `runBilling(period, auto)`:
  1. Issue date = today. Due date = `issue > 1st of period ? issue + dueDays : 1st + dueDays`
     (`dueDays` default 7; settings label "Payment terms (days after the 1st)").
  2. One `rent` invoice per pending lease (one line, `taxRate = settings.taxRate`).
  3. **All** waiting charges (not void, not billed) are added to the tenant's **first** rent
     invoice of this run; if the tenant has none, one `charges` invoice is created for that tenant
     (location = charge's location or the first location). Each charge line keeps its own tax
     rate (or `noTax`) and `chargeId`; the charge gets `invoiceId` and `billedOn = issue`.
  4. Totals via `calcTotals` (§3.6). Invoice numbers allocated in creation order with the
     **period's** YYMM.
  5. If `period ≤ this month`: monthly credit allowances for that period are issued (§3.11).
  6. `settings.billingRuns[period] = {at, count, auto, creditWallets}` (overwritten on re-run).
  - **No late fees in the run** (see §7, stubs). Re-running only bills leases not yet billed.
  - Manual run screen lets staff pick a month from: 2 months back, last month, this month, next
    month.
- **Automatic billing** (`maybeAutoBill`, setting `autoBilling` default **true**):
  - Runs once per page load, after all data loaded, only for users who can write.
  - Takes a lock on `settings/billing` (`ref.acquire({holder, ttlMs: 60000})`); stops if not got.
  - `periodsDue()` = this month, plus next month once
    `today ≥ (1st of next month − invoiceAdvanceDays)` (default 7 days before the 1st).
  - For each due period not yet in `billingRuns` (re-read fresh): `runBilling(period, true)`.
  - Then: monthly credits for this month, payment reminders (if `autoReminders`), house-rules
    emails (if `autoHouseRules`). A toast reports what ran.

### 3.6 Totals and tax

- `calcTotals(lines, rate = settings.taxRate)`:
  `subtotal = r2(Σ qty × price)`;
  `tax = r2(max(0, Σ over lines without noTax of qty × price × (line.taxRate ?? rate) / 100))`
  (rounded **once** on the sum); `total = r2(subtotal + tax)`.
- **Two tax rates** in settings:
  - `taxRate` (default **0**, label `taxLabel` default `"Tax"`): rent lines, upfront first month,
    ad-hoc invoices, ad-hoc "next cycle" charges.
  - `bookingTaxRate` (default **9**, "GST"): room bookings, credit packages, price-list charges
    with GST ticked (`chargeRate`), late-fee GST.
- `chargeTotal(c) = r2(qty × price × (1 + rate/100))`, rate 0 if `noTax` (per-charge rounding).
  In the charge form preview tax is rounded **per line** (`chgCalc`) — a small mismatch with
  `calcTotals`.
- Invoice title: "Tax invoice" when tax > 0 or kind booking/package; "Credit note" for
  `creditnote`; else "Invoice". GST reg. no. printed when set.

### 3.7 Invoice numbering

`nextInvoiceNumber(period, used)`:
`prefix = settings.invoicePrefix || "INV"`; `yymm = period[2..3] + period[5..6]`;
number = `"<prefix>-<yymm>-" + pad3(max existing n for that prefix-yymm + 1)` (computed from the
invoices loaded in the browser plus numbers already used in this batch).

- YYMM source: the **period** for run invoices; the **issue date's month** for ad-hoc; **today's
  month** for upfront, booking, package, credit note; the payment date's month for a final late fee.
- Credit note (`creditnote`): the next INV number with the prefix replaced by `"CN"`
  (`.replace(/^([^-]+)/, "CN")`) — it shares the INV sequence and does not reserve it.
- No server counter: two browsers can produce the same number (only the auto run is locked).

### 3.8 Payments and allocation

- Record payment: tenant, date, amount (> 0 in the form), method (`Bank transfer / PayNow`,
  `Card`, `GIRO`, `Cheque`, `Other`), reference, per-invoice "apply" amounts.
- Default allocation `fifo(open, amount, firstId)`: open invoices of the tenant (non-void,
  balance > 0.005) sorted by `dueDate + number`; optional chosen invoice first; each gets
  `r2(min(left, balance))`. Remainder = **unallocated credit** (shown as "Credit $x").
- Validation: an applied amount may not exceed that invoice's balance (+0.005); the sum may not
  exceed the payment (+0.005).
- Invoice balance = `total − Σ allocations` (0 if void). Status order: void → paid (≤ 0.005) →
  overdue (`dueDate < today`) → partial → open.
- `tenantBalance` = Σ non-void invoice totals − Σ payment amounts.
- `applyCredit(tid, invId)`: uses the tenant's unallocated payments (oldest first) to pay an
  invoice (used for final late-fee invoices).
- Delete payment: confirm, hard delete, audit `payment.delete`.
- Void invoice (§4.4) turns its allocations into unallocated credit.

### 3.9 Statements and aging

- `aging(invoices)` on the unpaid balance: `late = diffDays(dueDate, today)`; ≤ 0 "Not yet due",
  1–30, 31–60, 61–90, 90+.
- `statementData(tid, from, to)`: events = non-void invoices (date = issue date, debit = total) and
  payments (credit = amount); sorted by date, invoices before payments on the same day; events
  before `from` fold into the opening balance; running balance; closing balance.
- Statement screen adds a line "Late fees accruing on overdue rent (not yet invoiced, incl. GST,
  grows daily)" and "To settle today" = closing + accrued late fees.
- Receivables ledger (all tenants): aging buckets, unapplied credit, balance; shown when
  |balance| > 0.005 or something is due.

### 3.10 Late fees (block "LATE FEES (rules from finance)")

Comment in code: rate 12% p.a. on the **rental before GST**; if paid more than `graceDays` (13)
after the due date the fee counts **every day from the due date**; fee = days / 365 × rate ×
rental; GST added on top; accrues daily until paid; finalised as its own "Late fee" invoice dated
the payment date; staff can waive with reason + audit.

`lateFeeFor(inv, asOf = today)`:

1. Only invoice kinds `rent` and `upfront` (`LF_KINDS`), not void, `lateFeeRate > 0`.
2. `base = lfRentBase(inv)` = Σ `qty × price` of lines that are **not** deposit, not charge, not
   late-fee, and positive. No base → no fee.
3. If `lateFeeFromDue` is set and `dueDate < lateFeeFromDue` → no fee (start-date switch).
4. `settledOn` = the payment date when cumulative allocations first reach the total.
   `end = settledOn ?? asOf`.
5. `days = diffDays(dueDate, end)`. If `days ≤ graceDays` → **no fee at all**.
6. Otherwise accrue **from the due date** (or from `lateFeeBilledThrough` if an interim fee was
   billed), segment by segment between payments, on the unpaid share:
   `fee += base × (outstanding / total) × segmentDays / 365 × rate / 100`.
7. `amount = r2(fee)`; `gst = r2(amount × lfGstRate / 100)` where `lfGstRate = bookingTaxRate`
   (9) unless `lateFeeGst` is false; `total = amount + gst`.

Billing the fee:

- **Final**: `lateFeeSweep` (runs 1.5 s after every data change) finds rent/upfront invoices that
  are now fully paid, not waived, not final, with a fee → creates invoice id `lf-<invoiceId>`
  (so it is created once), kind `latefee`, issue date = **payment date**, due = issue + dueDays,
  one line (`"Late payment fee on INV-…: N days late (due …, paid …), 12% p.a. on $X rental"`,
  taxed at `lfGstRate`), sets `lateFeeFinal`, then applies any unallocated credit to it, audit
  `latefee.billed`.
- **Interim** ("Invoice fee so far"): bills the fee accrued to today; sets
  `lateFeeBilledThrough = today`; it keeps accruing after that.
- **Waive**: reason required; stores `lateFeeWaived`; voids any open late-fee invoices (their
  allocations are removed, so paid money becomes credit); audit `latefee.waive`. "Undo waiver"
  removes it (audit `latefee.unwaive`).
- Customer app: the invoice sheet and "Pay all" add the accrued fee; paying by card first creates
  the final late-fee invoice (as of today) and pays it in the same payment.
- Display: per-day growth shown as `base × rate / 100 / 365 × (1 + GST)`.

### 3.11 Credits (BizPlus wallet inside the artifact)

- **1 credit = $1** of booking charges (rent of the room, aircon, cleaning). Credits never pay the
  deposit. GST applies only to the cash part.
- Wallet types: `monthly` ("Monthly credits"), `contract` ("Lump sum credits"), `topup`
  ("Top-up package"), `refund` ("Refund credits"), `bonus` ("Bonus credits", no code creates it).
- **Draw order** `walletsOf` + `planDraw`: live wallets sorted by `expiresOn` ascending; wallets
  with no expiry sort as `9999-12-31`; **contract (lump-sum) wallets always last**
  (`"9999-12-31~"`). Draw greedily; amounts `r2` (fractions allowed in admin).
- Balance = Σ remaining of live wallets **as of today** (not as of the booking date).
- **Monthly allowance** (`monthlyDue`, `issueMonthlyCredits(period)`), from two sources:
  - a lease with `monthlyCredits > 0` overlapping the period (one wallet per lease per period);
  - a `creditPlan` (staff "Grant credits → Monthly"), active, `startMonth ≤ period ≤ endMonth`.
  - Carry-forward: previous month's wallet for the same source → `carry = r2(min(prev.remaining,
    carryCap))`; the rest lapses. Previous wallet set to `remaining 0, carriedOut true`; ledger rows
    `carry` (−carry) and `expiry` (−lapsed). **Cap 0 = no carry**. Plans: cap only if
    `carryForward` ticked, else 0.
  - New wallet: `total = credits + carry`, `expiresOn = last day of the period`.
  - Issued by: the billing run (period ≤ this month), the page-open automation (this month),
    "Issue N monthly allowances" button, move-in / lease edit / plan grant (this month at once).
- **Lump sum**: one `contract` wallet, `expiresOn` = chosen date or none ("usually the contract end
  date"). No invoice.
- **Packages** (default list, editable): 200 cr $190 1 month; 500 cr $450 3 months; 1000 cr $850
  6 months; price **before GST**; custom package allowed. Sale = `package` invoice at
  `bookingTaxRate`, due today (or today + dueDays if "account"), payment recorded unless "account",
  `topup` wallet with `expiresOn = addDays(addMonths(today, months), −1)`. Credits are added at
  once **even when unpaid**.
- **Adjust**: set remaining and expiry with a required reason; `total = max(total, remaining)`;
  ledger `adjust` (delta).
- **Reports**: outstanding, expiring in 14 days, redeemed this month, package sales (incl. GST);
  monthly usage per customer = opening + monthly (net of carry-in) + bought + granted + refunds −
  used − lapsed = closing; utilisation = used ÷ (opening + added).

### 3.12 Room bookings (rules "mirror the BizPlus Credits app")

- Resources: meeting room or event space; hourly rate; minimum hours; event only: cleaning fee
  weekday / weekend, refundable deposit. New-room defaults: pax 4, $20/hr, min 1 h, cleaning
  $50 / $100, deposit $500.
- **Standard hours** (no aircon surcharge): Mon–Fri `wkStart 9`–`wkEnd 19`, Sat `9`–`14`,
  **Sunday all day surcharged** (`isSurcharged`).
- **Price** `priceBooking(res, date, start, end, extendFrom)`:
  `dur = r2(end − from)`; `rent = r2(dur × hourlyRate)`;
  `airconHours` = count of 15-minute steps whose **hour** is outside standard hours ÷ 4;
  `aircon = r2(airconHours × airconRate)` (default $40/hr);
  event and not an extension: `cleaning` = weekend fee on Sat/Sun else weekday fee; `deposit`;
  `subtotal = r2(rent + aircon + cleaning)` (deposit not in subtotal).
- **Credits used** = `r2(max(0, min(balance, subtotal, wanted)))`. `cashBase = subtotal − credits`.
  Invoice lines: room, aircon, cleaning, and a negative line "Credits applied: N credits (…)";
  GST via `calcTotals(lines, bookingTaxRate)` → GST only on the cash part (the negative credit line
  reduces the taxable sum).
- **Payment method**: `card`, `transfer`, `account` (invoice, pay later, due today + dueDays),
  `nextcycle` (only tenants with an active or upcoming lease → charges on next rent invoice).
  Card/transfer: `booking` invoice + payment recorded at once. Fully covered by credits →
  invoice with total 0, method "credits".
- **Validation**: may not pass midnight (end ≤ 24); duration ≥ `minHours`; no overlap on the same
  room and date (`bkConflict`: `b.start < end && b.end > start`). Admin is only **warned** about
  same-day window and past start time.
- **Time grid**: admin start in 15-min steps, 1–16 h; app start every 30 min from 7:00 to 23:00,
  duration 1–12 h, 21 days ahead.
- **Same-day bookings** in the app only while now is in `[sameDayStart 9, sameDayEnd 16)`.
- **Extend** (`FORMS.bkExtend`): +1–6 h (app +1–4 h); priced from old end to new end (aircon yes,
  cleaning/deposit no); same credit / payment options; new invoice or charges; stored in
  `extensions[]`.
- **Move** (`FORMS.bkMove`): same duration and **same price**; no re-pricing (staff told to raise
  an invoice if the new slot costs more). App: blocked inside the cutoff; admin can override.
- **Cancel** (`refundPreview`, `FORMS.bkCancel`):
  - Eligible for refund if `hours to start ≥ cancelCutoffHours` (12). Manager can force "full" or
    "none".
  - If eligible: unpaid booking invoices are voided; unbilled booking charges are voided; billed
    but unpaid charges get a negative credit charge on the next invoice.
  - Credits only → credits back to the **source wallets** (no expiry check).
  - Cash paid (`cashPaidFor`, incl. GST) → default: **Refund credits** wallet of
    `credits + Math.round(cash)` (cash **including GST**, rounded to whole dollars, 1:1), valid to
    `addDays(addMonths(bookingDate, refundCreditMonths), −1)` (1 month). Option "Money back to
    card or bank": creates a `creditnote` invoice (−cash, no tax) and a **negative** payment; credits
    go back to source wallets.
  - Not eligible: nothing returned; unpaid invoices stay payable.
  - Customer app cancel always uses policy + refund credits.
- **Deposit**: collected now (checkbox; app card = collected), "Mark collected", "Return deposit",
  "Retain deposit" (amount ≤ deposit, reason) → `adhoc` invoice (no tax) + payment method
  "Deposit" for the retained amount.

### 3.13 Tenant charges (next-cycle extras)

- Price list (`DEFAULT_CATALOG`, editable, stored as `chargeCatalog`): Printing B/W $0.20/page,
  Printing colour $0.80/page, Key card replacement $30/card, Mail handling $20/month, Additional
  cleaning $80/session, Parking (season) $150/month, Locker rental $30/month — all GST yes.
- Record charge: tenant (grouped "with a lease" / "no lease — billed separately at next run"),
  service date, lines (item, description, qty, price, GST yes/no at `bookingTaxRate`), note.
  Monthly items get `" (Mon YYYY)"` appended.
- Bulk entry: two price-list columns (default B/W and colour printing) × quantity per tenant with a
  lease, period label default last month.
- Edit charge (not booking ones), remove (soft void + audit).
- **Move unpaid invoice to next cycle** (`movableInvoices`, `moveInvoiceToCharges`): kinds
  `booking` / `adhoc`, not void, total > 0.005, **no payment allocated**, tenant has a lease → each
  line becomes a charge (`"<desc> (from INV-…)"`), invoice voided ("Moved to the next monthly
  invoice"), booking relinked, audit `invoice.moved`. "Move all" does all of them.
- "Next billing run" date shown = `max(today, 1st of next unbilled month − invoiceAdvanceDays)`.

### 3.14 Reminders, house rules, outbox

- **Reminders** (`queueReminders`): stages from `reminderDays` (default `"3, 7, 14"`, sorted,
  > 0). For each invoice of kind `rent` / `charges` / `upfront` that is overdue:
  `late = diffDays(dueDate, today)`; reached stages ≤ late; if the highest reached stage is not yet
  in `inv.reminders` → queue one email; `nth` = number of distinct emails already sent + 1; mark
  all reached stages with this email id. To = billing email (else first contact email); Cc = all
  other contact emails. Subject `"Payment reminder[ (2nd|3rd|Nth notice)]: INV-… is N days
  overdue"`. Body includes total, due date, days, balance, late-fee rule text (if rate > 0) with
  the fee so far, bank / PayNow text, sign-off = business name or centre name.
- **House rules** (`queueHouseRules`): for each lease with a tenant, valid, no email yet, and
  `start` between `today − 3` and `today` → queue `houseRules` email to all contact emails using
  the subject/body templates with `{name}`, `{unit}`, `{centre}`, `{business}`. Placeholder tenants
  are **not** skipped (they just have no address).
- **Compose**: groups — all current tenants, all app members, everyone (current + member +
  incoming), tenants with overdue invoices, incoming tenants, choose recipients. "Send to" all
  contacts / primary only / billing only. Delivery: one Bcc email (`{name}` → "there"; logged as
  **sent** immediately) split into mailto batches of ≤ 1,900 chars, or one personalised email per
  recipient (**queued**). Exactly one recipient → `direct` email logged as sent and opened in the
  mail app. Placeholders `{name}`, `{company}`, `{unit}`, `{balance}`, `{bank}`, `{business}`,
  `{centre}`; unknown ones stay as typed.
- Sending = open a `mailto:` link in the staff's own mail app, then "Mark as sent" / "Dismiss".
  Code says real sending needs an email service (Postmark / SendGrid suggested).
- Invoice "Email to tenant" = `mailto` with a text summary; sets `sentAt`.

### 3.15 Documents and notes

- Upload PDF or image ≤ 20 MB (asset store). Types: License agreement, ACRA / IC, Handover form,
  Return form, Other. "Expires soon" when expiry ≤ 60 days; "Expired" when past.
- `missingDocs(tid)`: ACRA business profile (business) or IC copy (personal) if the tenant has a
  live/upcoming lease or is an app member; a licence agreement per live/upcoming lease; a handover
  form per lease on today that is **not imported**; a return form per lease that ended in the last
  90 days.
- Notes: internal text, optional follow-up date, mark done, edit, delete. Dashboard shows
  follow-ups due within 7 days.

### 3.16 Layout changes (split / merge / revert)

- `earliestFree(ids)`: day after the latest lease end across the units, never before today; null
  if any unit has a rolling lease.
- **Split** a suite into fixed desks (`FORMS.convSplit`): only `office`, not archived, no
  `activeTo`, no existing conversion. Count 2–40 (default = pax), code prefix default
  `"<code>-D"`, desk rate default `Math.round(listRate / pax)` (**whole dollars**). Refused if the
  suite has a lease on or after the effective date, or a desk code already exists. Creates N
  `fixed` units (pax 1, `activeFrom = effective`, `parentUnitId`, `conversionId`), adds an open
  gap on the suite, saves the conversion, audit `unit.split`.
- **Merge** 2–3 suites (`FORMS.convMerge`): new `office` unit with chosen code (must be new), seats
  (default Σ pax; hint "10 + 10 → 25"), rate (default Σ list rates), `activeFrom = effective`;
  open gaps on all sources; audit `unit.merge`.
- **Revert** (`FORMS.convRevert`): date ≥ effective; refused if a result unit has a lease on or
  after it. Result units get `activeTo = date − 1`; source gaps closed at `date − 1` (removed if
  they never started); `revertedOn`; audit `unit.revert`.
- Floor board "Lease expiry list" (`availability`): no current → after reserved tenant / "Taken
  (rolling)" / from `max(today, activeFrom)`; rolling current → "Rolling, 1-month notice"; with a
  next lease → after next tenant; else day after current end (+ `*` if estimated). Filters:
  available within 30/60/90/180/365 days, minimum seats.

### 3.17 Validation and guards (summary)

| Action | Rule |
|---|---|
| Unit add/edit | code unique per location (case-insensitive); pax ≥ 1; zone from code if empty (`zoneOf`: starts with digit → `"Level <first digit>"`; prefix `FD` → "Fixed desks", `HD` → "Hot desks", else "Units"); renaming updates `unitCode` on its leases |
| Unit archive | blocked if it has a current or upcoming lease; not offered for units in a conversion |
| Unit delete | only if it has no leases |
| Location delete | only if it has no units |
| Tenant delete | blocked if any lease, invoice or payment |
| Lease delete | blocked if any invoice |
| Invoice edit | only if no payment applied, not void, not credit note, not booking/package |
| Invoice void | only owner / Editor (`isAdmin`); reason required; optional "put charges back" |
| Invoice next-cycle option | only tenants with an active or upcoming lease |
| Payment | allocations ≤ balance and ≤ payment |
| Settings | `endingWindowDays ≥ 7`; `invoiceAdvanceDays` 0–28; `invoicePrefix` letters/digits/underscore only; `refundCreditMonths ≥ 1` |
| Writes | every write wrapped by `guard`: needs db and `canWrite`; error codes `invalid_argument`, `quota_exceeded`, `resource_exhausted` shown as toasts |

### 3.18 Roles

- View-only: users without `data.write` (banner "Ask the owner for Contributor access").
- Admin = owner or Editor (`user.isOwner() || user.canEdit()`): needed to **void** invoices.
- Everything else: any user who can write.

---

## 4. Screens and workflows

### 4.1 Manager portal navigation (`NAV`)

Dashboard · Floor board · Room bookings · Tenants & members · Leases · Invoices · Tenant charges ·
Payments · Statements · Documents · Emails · Credits · Rooms & spaces · Locations · Settings.
Location picker at the top ("All locations" or one). Button "Open customer app".

| Screen | Main actions |
|---|---|
| Dashboard | Move in tenant, New booking, New invoice; "Finish setup" banner (placeholder tenants, estimated end dates, data issues); "Remove dummy data" |
| Floor board | Tiles grouped by zone (Level zones first) or lease-expiry list; filters by type and state; view as of a date; show archived; Import from Excel; Combine suites; Add unit; tile → unit drawer (edit, archive/restore, delete, schedule next tenant, convert to seats, combine, revert, lease history) |
| Tenants & members | Segments Tenants / App members / Everyone; filters status, type, "needs details"; search; Export CSV; Email; Move in tenant; Add app member; Add tenant. Drawer tabs: Overview (balance, overdue, rent, leases, charges, credits, bookings, invoices, payments), Notes, Documents, Emails |
| Leases | Filters active, upcoming, ending ≤ window, rolling, estimated end, ended, data issues, all; open → edit / renew / delete |
| Invoices | Banner about auto billing and waiting charges; search, month, status chips; Export; Run monthly billing; New invoice. Invoice view: record payment, email, mark sent, download HTML, print, open booking, move to next invoice, edit, void, late-fee panel (invoice fee so far, waive) |
| Tenant charges | KPIs (waiting, next run, billed this month, invoices to move); Waiting / Billed / Price list tabs; Record charge; Bulk entry; Move all |
| Payments | Search; Import bank statement; Record payment; banner for unapplied credit |
| Statements | All tenants aging ledger (Download CSV) or one tenant's statement (dates, CSV, print, email balance) |
| Documents | Type chips; missing list; Upload document |
| Emails | Outbox / Sent; Review & send (mailto), Mark as sent, Dismiss; Compose |
| Credits | Tabs Balances / Monthly usage / Packages bought; Issue monthly allowances; Grant credits (monthly plan or lump sum); Sell package; per-tenant credit statement; Excel exports |
| Rooms & spaces | Room cards with this month's usage %; Add / edit room; Book |
| Room bookings | Day timeline (24 h, hatched = aircon hours, click empty slot to book) or list (upcoming, today, past, cancelled, deposits open); Sell credits package; New booking; booking drawer (extend, change date & time, cancel, deposit actions); add / remove sample bookings |
| Locations | Cards with seat occupancy; open floor board; import units; add unit; edit; delete |
| Settings | Business details, currency, prefix, tax label/rate, payment terms, ending window, auto billing, proration; billing runs list; audit log (latest 60); backup JSON; remove dummy data; automation (late fee rate, grace, start date, GST on late fee, advance days, deposit months, reminder days, auto reminders, auto house rules, bank / PayNow / QR, house-rules template); room booking rules + credit packages |

### 4.2 Key workflows

1. **New location**: add location → add units one by one or import Excel.
2. **Move-in**: choose unit (hint shows earliest start) → tenant (existing or new) → start, term,
   rent, deposit, monthly credits, carry cap → upfront (method) → lease created → upfront invoice
   opens (paid or open) → credits issued if started.
3. **Monthly billing**: automatic on page open from 7 days before the 1st, or "Run monthly
   billing" → rent invoices (prorated), waiting charges added, monthly credits issued.
4. **Payment**: record manually (FIFO default) or import a bank file → match → record ticked rows.
5. **Overdue**: reminders queued at 3 / 7 / 14 days; late fee accrues after the 13-day grace,
   counted from the due date; final late-fee invoice issued when paid; staff may waive.
6. **Move-out**: set last day (+ return form) → final month prorated by the run → return form
   flagged as missing for 90 days.
7. **Renewal**: from the lease → new lease after the old end with deposit top-up and first month.
8. **Room booking** (staff or app): price → credits → GST on cash → invoice / payment / next-cycle
   charge → extend / move / cancel with 12-hour rule.
9. **Layout change**: split suite into desks or merge suites from an effective date; revert later.

### 4.3 Customer app (BizPlus) inside this artifact

- **Sign-in is a prototype**: pick any customer from a list (search by name/email); the chosen id
  is kept in `localStorage` (`bizplus.customer`). "The real app would use email or phone sign-in."
- **Sign-up**: full name, company (optional), email (required, must be unique across all contact
  emails), mobile, billing address → new `memberOnly` tenant, `signupSource "app"`.
- Tabs: Home (credit balance, next expiry, amount due incl. late fees, upcoming bookings), Book,
  My bookings, Billing (invoices to pay / paid, upcoming charges, payments, statement CSV), Credits
  (wallets, buy package, activity), Account (contact, billing email, billing address).
- Payments are **demo card only** ("VISA •••• 4242 · Demo card · no real charge") — a payment row is
  written directly. PayNow / bank details and QR are shown for manual transfer.
- Booking deposit is marked "held" when paying by card.

---

## 5. Import / export formats

### 5.1 Imports

| Import | Input | Columns (guessed by header regex, staff can remap) | Result |
|---|---|---|---|
| Units / leases (`importHtml`, `importPlan`, `imCommit`) | `.xlsx`, `.xls`, `.csv`; choose sheet | Unit `/unit\|inventory\|name\|no\b/` (else col 0); Type `/suite\|desk\|type/` (col 1); Pax `/pax\|capacity\|seat/` (col 2); Rate `/rate\|price\|rent/` (optional); Move-in `/date ?in\|start\|move.?in/`; Move-out `/date ?out\|end\|move.?out/` (optional). Mode = "history" if a start column is found, else "inventory" | Type: contains "fixed" → fixed, "desk" → desk, else office. Pax = max(1, n). New codes only (exact match against the location); `zoneOf(code)`. History: start required (day-first dates), one lease per row; open-ended rows get a **placeholder tenant** "Tenant at <code>" (one per row); ended rows get occupant "Past occupant (imported)"; end < start → `dataIssue`. No overlap check, no de-duplication of leases |
| Bank statement (`bankImportHtml`, `biMatch`, `biCommit`) | `.csv` / `.xlsx` / pasted rows (first row = headers) | Date `/date/` (col 0); Description `/desc\|narr\|detail\|particular\|ref\|memo\|payee\|remark/` (col 1); Amount `/credit\|deposit\|paid in\|money in/` then `/amount/` (else last col). "Dates are day/month" default on | Match: **high** = description contains an open invoice number (first found); **medium** = contains a non-placeholder tenant name (normalised length ≥ 4, first found) → invoice with equal balance, else oldest; **low** = exactly one open invoice with that amount (left unticked). Duplicate flag = same date, amount, reference (first 120 chars). Ticked rows → payment method "Bank transfer / PayNow", source `bank-import`, FIFO with the matched invoice first, allocations within the batch tracked |

Date parsing (`toISODate`): Excel serial number; `YYYY-MM-DD` (also `/` or `.`); `D/M/YY(YY)` or
`M/D` when day-first is off (2-digit year + 2000); else `new Date(text)`.
Amount parsing (`num`): strip everything except digits, `.` and `-`.

### 5.2 Exports

| Export | File | Columns |
|---|---|---|
| Tenants & members | `tenants-and-members-<today>.csv` | Type, Status, Name, Kind, Registration no., Units, Contact 1 name, Contact 1 title, Contact 1 email, Contact 1 phone, Contact 2 …, Contact 3 …, Address, Billing address, Billing email, Lease start, Lease end, Monthly rent, Credits, Balance, Signed up |
| Invoices (`doInvExport`) | `invoices-<tag>.xlsx` (sheets Summary, Invoices, Lines) or CSV per invoice / per line, or printable HTML pack | **Invoices**: Invoice no., Issue date, Due date, Billing period, Type, Customer, UEN / IC, Unit, Location, Subtotal, GST, Total, Paid, Balance, Status, Void reason, Sent. **Lines**: Invoice no., Issue date, Customer, Line, Description, Qty, Unit price, Amount, GST rate %, GST, Category (Deposit / Late fee / Additional charge / Rent / kind), Void. **Summary**: per type Invoices, Subtotal, GST, Total, plus "All". Period by issue date (for GST) or billing period; type filter; include void (zero amounts) |
| Statement | `statement-<name>-<to>.csv` | Date, Type, Reference, Details, Charges, Payments, Balance (+ opening / closing rows) |
| Receivables | `receivables-<today>.csv` | Tenant, Not yet due, 1-30, 31-60, 61-90, 90+, Balance |
| Credit usage | `credit-usage-<YYYY-MM>.xlsx` | Sheet "Usage by customer": Customer, Type, Opening, Monthly credits, Bought, Granted, Refunds, Used, Lapsed/expired, Closing, Utilisation %. Sheet "Transactions": Date, Customer, Activity, Wallet, Change, Note |
| Credit packages | `credit-packages-<today>.xlsx` | Bought, Customer, Package, Credits, Remaining, Used, Expires, Invoice, Price excl. GST, GST, Total, Invoice status |
| Invoice | `<number>.html` (QR embedded as data URI) | printable invoice |
| Backup | `cowork-backup-<today>.json` | settings + every collection |

CSV cells (`csvCell`): quoted only if they contain `"`, `,` or newline. **No formula-injection
guard, no BOM, `\n` line ends** (the demo adds all three, 09:1726-1731).

---

## 6. Constants and defaults

`DEFAULT_SETTINGS`:

| Key | Default | Key | Default |
|---|---|---|---|
| businessName / Address | "" | currency | `"$"` |
| taxRate (rent) | 0 | taxLabel | `"Tax"` |
| dueDays | 7 | autoBilling | **true** |
| prorate | true | invoicePrefix | `"INV"` |
| endingWindowDays | 90 | gstRegNo | "" |
| lateFeeRate | 12 (% p.a.) | graceDays | **13** |
| lateFeeGst | true | invoiceAdvanceDays | 7 |
| reminderDays | `"3, 7, 14"` | depositMonths | 2 |
| bankName / AccountName / AccountNo / payNowId / qrAssetId | "" | houseRulesSubject | `"Welcome to {centre}: house rules"` |
| houseRulesBody | same text as the demo's `DEFAULT_HOUSE_RULES_BODY` (10:356-371) | bookingTaxRate | 9 |
| airconRate | 40 | wkStart / wkEnd | 9 / 19 |
| satStart / satEnd | 9 / 14 | cancelCutoffHours | 12 |
| refundCreditMonths | 1 | sameDayStart / sameDayEnd | 9 / 16 |
| packages | 200/$190/1 mo, 500/$450/3 mo, 1000/$850/6 mo | billingRuns, creditRuns | {} |

Other constants: handover window 7 days (`unitState`); docs "expires soon" 60 days; return form
window 90 days; credits "expiring" 14 days; follow-ups 7 days; house-rules window 3 days; mailto
batch 1,900 chars; split max 40 desks; merge max 3 suites; invoice list shows 400, payments 400,
bookings 300; booking history 8 per tenant; audit 60 rows. Payment method labels `METHOD_NAME`:
card "Card", transfer "Bank transfer / PayNow", giro "GIRO", cheque "Cheque", account "Invoice
(pay later)", nextcycle "Next monthly invoice", credits "Credits". `PRESETS` (old charge list) is
defined but unused.

Sample data (`addSampleData`, flagged `sample: true`): 3 wallets (150 monthly, 50 monthly, 200
top-up) for the first current tenants, 7 meeting-room bookings over the next 6 days with mixed
methods, 1 event booking 4 days ahead (10:00–14:00, deposit collected). "Remove dummy data" deletes
`sample` rows and restores `sampleOrig` originals on leases and tenants.

---

## 7. Demo shortcuts, stubs and bugs seen in the artifact

1. All logic runs in the browser; "today" is the browser date at page load; no time zone.
2. Automations (billing, credits, reminders, house rules) run only when someone opens the page;
   the late-fee sweep runs after every data change in every open tab (no lock).
3. Invoice numbers are computed from loaded data (no counter, no lock except for the auto run).
4. Customer app sign-in = pick a customer; card payment = fake card 4242, payment written
   directly.
5. Emails are never sent; mailto only.
6. **Billing run late fees are a stub**: `billingRunHtml` has `const fees = []`; the Invoices
   banner says invoices "include … late fees", but `runBilling` adds none (late fees are separate
   invoices, §3.10).
7. **Void bug**: voiding a late-fee invoice patches `lateFeeThrough: null` on the source invoice,
   but the field actually used is `lateFeeBilledThrough` (and `lateFeeFinal` is not cleared), so a
   voided late fee is not re-opened.
8. `termMonths` saved as 1 for rolling leases (`termMonths: term || 1`).
9. Dashboard text says end dates were "estimated (12-month terms assumed)" at import, but the
   import sets `endAssumed: false`; only staff can set it.
10. A regex in the app card sheet assumes the currency is `S$` (`/Pay S\$[\d,.]+/`), while the
    default currency is `$`.
11. App "Changes close 12 hours before the start" is hard-coded text (ignores the setting).
12. Credit note numbers reuse the INV sequence with prefix `CN` and can collide with another CN in
    the same month.
13. `bonus` wallet type exists but nothing creates it; `invoice` email kind exists but nothing
    queues it.
14. Payment `source` for bank import is `"bank-import"` (the demo writes `bank_import`, 10:1961).
15. Fractional credits are possible in admin bookings and adjustments.
16. `creditBalance` uses today, so a booking months ahead can use a wallet that will have expired by
    then.

---

## 8. Comparison with the demo spec

Legend: **SAME**, **DIFFERENT** (artifact vs demo), **ONLY IN ARTIFACT**, **ONLY IN DEMO**.

### 8.1 Inventory, tenants, leases (spec 09)

| # | Rule | Verdict | Artifact | Demo |
|---|---|---|---|---|
| 1 | Lease validity and on-date | SAME | `leaseValid`, `leaseOn` | 09:1173-1176 |
| 2 | Unit state (handover ≤ 7 days, ending ≤ window 90) | SAME | `unitState` | 09:1177-1189 |
| 3 | Occupancy by type, seats | SAME | `occupancy` | 09:1214-1222 |
| 4 | Overlap check, touching = overlap | SAME | `overlaps` | 09:1196-1199 |
| 5 | End date from term | SAME formula; DIFFERENT storage | `addDays(addMonths(start, term), -1)`; rolling stored as `termMonths 1` | 09:1200-1206; rolling → null (09:1585) |
| 6 | Default deposit = rate × depositMonths (2) | SAME | `moveInHtml` | 09:1564 |
| 7 | Upfront: deposit noTax + full first month, prepaidThrough | SAME | `buildUpfront` | 09:1266-1276 |
| 8 | Renewal deposit = max(held, rate × months), carry → top-up | SAME | `renewCalc` | 09:1277-1284 |
| 9 | Renewal default term 12, start > old end | SAME | `renewHtml` | 09:1621-1623 |
| 10 | One renewal per lease | DIFFERENT | UI hides "Renew" if a later lease exists; `renewedTo` set, no hard check | DB unique `renewedFromId` + ALREADY_RENEWED (09:1360, 09:1619) |
| 11 | Monthly credits on a lease | DIFFERENT | Issued automatically every month as a wallet, with carry cap | Stored only, never synced (09:251, 09:2152) |
| 12 | Move-out notes and return form | DIFFERENT | Upload return form file + `returnNotes` field | Notes appended "Move-out notes: …" (09:1608-1609); no upload |
| 13 | Documents | DIFFERENT | Real file upload ≤ 20 MB | Metadata + http(s) URL only, C9 (09:80, 09:270-287) |
| 14 | Missing-documents rules | SAME | `missingDocs` | 09:1315-1327 |
| 15 | Doc label | DIFFERENT (spelling) | "License agreement" | "Licence agreement" (09:1321) |
| 16 | zoneOf | SAME | `zoneOf` | 09:1417-1420 |
| 17 | Unit code unique case-insensitive | SAME | `FORMS.unit` | 09:1422-1424 |
| 18 | Sheet import | SAME (placeholder per open row, no overlap check, no dedupe) | `importPlan`, `imCommit` | 09:1440-1454 |
| 19 | Import listRate default | SAME (0) | `r2(num(...))` or 0 | 09:1444 |
| 20 | Split: default count | DIFFERENT | `= pax` (input min 2) | `max(2, pax ‖ 2)` (09:1464) |
| 21 | Split: default desk rate | DIFFERENT | `Math.round(listRate / pax)` whole dollars | `round2(listRate / count)` (09:1466) |
| 22 | Split / revert rules (gaps, activeFrom/To, LEASED checks) | SAME | `FORMS.convSplit`, `convRevert` | 09:1468-1508 |
| 23 | Merge suites | ONLY IN ARTIFACT (working) | `FORMS.convMerge` (2–3 suites) | Modelled, no route (09:84, 09:2181) |
| 24 | Board shows future desks before their start | ONLY IN DEMO | Board hides units not live on the date unless "show archived" | "starts later" filter (09:1373-1375) |
| 25 | Lease expiry list | SAME | `availability` | 09:1395-1411 |
| 26 | Tenant ↔ app customer | DIFFERENT | Same `tenants` record is the app account (`memberOnly`, `signupSource`) | Separate `Customer` linked by `customerId` (09:77, 09:651) |
| 27 | Tenant CSV | DIFFERENT | Last column "Signed up"; "Lease start/end"; no BOM, no formula guard | Last column "Placeholder"; "Licence start/end"; BOM, `\r\n`, `'` guard (09:1705-1732) |
| 28 | Contacts | DIFFERENT | Array on tenant; billing = `billingEmail` | `CoworkContact` rows with `isBilling` (09:219-233) |
| 29 | Concurrency | DIFFERENT | None (browser) | `lockUnit` advisory lock (09:1343-1362) |
| 30 | Locations | DIFFERENT | Free-form `locations` collection | Site rows, `enableLocation` (09:396) |

### 8.2 Billing, payments, outbox (spec 10)

| # | Rule | Verdict | Artifact | Demo |
|---|---|---|---|---|
| 31 | Rent line, inclusive days, proration `rate × days / dim` | SAME | `rentLineFor` | 10:1314-1321 |
| 32 | Due date formula | SAME | `runBilling` | 10:1343 |
| 33 | `calcTotals`, tax rounded once | SAME | `calcTotals` | 10:1201-1212 |
| 34 | Rent tax 0 / charge tax 9 | SAME values, DIFFERENT names | `taxRate` 0 (label "Tax"), `bookingTaxRate` 9 | `rentTaxRate` 0, `chargeTaxRate` 9, label "GST" (10:324-326) |
| 35 | Automatic billing | DIFFERENT | **On by default**; runs on page open for this month and next month from 7 days before the 1st | Off; never runs; manual only (10:1339-1341, 10:1939) |
| 36 | Invoice number format | SAME format; DIFFERENT allocation | `INV-YYMM-NNN`, max + 1 in browser | Counter row + advisory lock (10:1224-1244) |
| 37 | Charges on the run | DIFFERENT | All waiting charges go on the tenant's first rent invoice; no unit on charges | Charges carry a `unitId` and ride on that unit's invoice (10:274, 10:1324-1329) |
| 38 | Late fees in the billing run | DIFFERENT | None (stub) — fees are separate invoices | Added as lines on the tenant's first draft (10:1289-1296) |
| 39 | **Late-fee formula** | DIFFERENT | Base = **rental before GST**; if paid > 13 days late, count **from the due date**; segments on unpaid share; **GST 9% on the fee**; kinds rent + upfront only | Base = **invoice balance**; count from **due + grace + 1**; simple `balance × rate × days / 365`; **no tax**; all kinds except credit note (10:1348-1368) |
| 40 | Late-fee grace / switch | DIFFERENT | grace **13**, on when rate > 0, optional "from due date" cut-off | grace **7**, `lateFeesEnabled false` (10:333-334, 10:1925-1926) |
| 41 | Late-fee invoice kind, interim billing, waiver | ONLY IN ARTIFACT | `latefee` kind, `lf-<id>`, "Invoice fee so far", waive / undo with audit | none (InvoiceKind list 10:158-168) |
| 42 | Late fee on app payment | ONLY IN ARTIFACT | App adds fee to amount due and bills it on payment | — |
| 43 | Pay state, FIFO, aging, statement | SAME | `invStatus`, `fifo`, `aging`, `statementData` | 10:1370-1390 |
| 44 | Payment amount sign | DIFFERENT | Negative payment allowed (card refund) | CHECK `amount > 0` (10:202) |
| 45 | Credit notes | DIFFERENT | Created on card refund of a cancelled booking (`CN-…`) | Import only (10:168) |
| 46 | Void | SAME core (allocations removed, optional return charges, upfront clears prepaidThrough); DIFFERENT late-fee reset field (artifact bug, §7.7) | `FORMS.void` | 10:1392-1411 |
| 47 | Void permission | DIFFERENT | Owner / Editor | `billing.void` permission (09:81) |
| 48 | Move unpaid invoice to next cycle | SAME eligibility | `movableInvoices` | 10:1413-1428 |
| 49 | Bank-import matching | SAME idea; DIFFERENT details | first match wins; no `()` negatives; dedupe only a client flag | longest invoice number / name first; `()` negatives; server SHA-256 row hash (10:1483-1541) |
| 50 | Upfront payment methods (card/transfer/giro/cheque paid) | SAME | `writeUpfront` | 10:1463-1469 |
| 51 | Reminders: stages, nth, mark all reached | SAME | `queueReminders` | 10:1613-1636 |
| 52 | Reminder body (late-fee sentence) | DIFFERENT | "…incur a late fee of R% per annum on the rental, counted from the due date, plus GST. As of today it is $X incl. GST…" | "Late fees accrue at R% per annum after a G-day grace period; $X has accrued so far." (10:1593) |
| 53 | Reminder recipients | DIFFERENT | To = billingEmail else first contact email | billingEmail, else contacts with `isBilling`, else first (10:1601-1610) |
| 54 | House rules: window 3 days | SAME; DIFFERENT placeholder handling | queued even for placeholders | placeholders skipped (10:1643) |
| 55 | Compose Bcc | DIFFERENT | logged as **sent** at once; batches ≤ 1,900 | queued, kind MASS (10:1657-1659) |
| 56 | Compose one recipient | DIFFERENT | any group with one recipient → `direct`, logged as sent | `direct` only for custom + each + one (10:1660) |
| 57 | Automations schedule | DIFFERENT | On page open (+ billing + credits) | Daily cron 00:30 SGT, reminders + house rules only (10:1833-1852) |
| 58 | Tenant pays invoices in app | DIFFERENT | Fake card, payment written directly | Stripe Checkout + signed webhook (10:1051-1123) |
| 59 | Guest workspace browse / enquiry | ONLY IN DEMO | — | `/api/v1/workspace-units`, leads (10:1124-1170) |
| 60 | Billing settings keys | mostly SAME | `DEFAULT_SETTINGS` | 10:314-343 |
| 61 | Currency default | DIFFERENT | `"$"` | `"S$"` (10:322) |
| 62 | Invoice export (XLSX/CSV/HTML pack) | ONLY IN ARTIFACT (as a feature) | `invExportHtml`, `doInvExport` | not in 10 (reads come from `/snapshot`) |
| 63 | Credit usage / packages reports | ONLY IN ARTIFACT | `creditUsageHtml`, `packagesHtml` | — |

### 8.3 Bookings and credits (specs 07, 08, and 09 §4.9)

| # | Rule | Verdict | Artifact | Demo |
|---|---|---|---|---|
| 64 | 1 credit = $1, GST on cash part only, deposit not creditable / not taxed | SAME | `createBooking` | 08:14, 08:901-912 |
| 65 | Credits whole numbers | DIFFERENT | Fractions allowed (`r2`) | Integers only, floor (08:76, 08:906) |
| 66 | Draw order: earliest expiry first, lump sum last | SAME | `walletSortKey` | 08:879-884 |
| 67 | Which allowance a booking may use | DIFFERENT | any live wallet as of today | only the booking month's allowance (D4, 08:876, 08:897-899) |
| 68 | Monthly allowance expiry | SAME | last day of month | 1st of next month exclusive (08:25) |
| 69 | Carry-forward cap meaning | DIFFERENT | cap 0 = no carry; carry only if ticked | `carryForwardCap` null = **no cap** (08:35, 08:121) |
| 70 | Packages 200/190/1, 500/450/3, 1000/850/6, price pre-GST | SAME | `DEFAULT_SETTINGS.packages` | 08:211-213 |
| 71 | Package credits added before payment (pay later) | SAME | `FORMS.package` | 09:1837 |
| 72 | Package expiry | SAME | `addMonths(today, m) − 1 day` (inclusive) | `addMonths(date, m)` 00:00 exclusive (08:859) |
| 73 | Cancel cutoff 12 h, inclusive | SAME | `hrs ≥ cancelCutoffHours` | 08:1098-1099 |
| 74 | Refund credits amount | DIFFERENT | `credits + Math.round(cash incl. GST)` | `credits + round(cash before GST)`; GST not returned (08:1068-1069, 08:1085, 08:1101) |
| 75 | Refund to card | DIFFERENT | Manager option: credit note + negative payment | Never to card (08:1102) |
| 76 | Credits-only cancel returns to source wallets | SAME idea; DIFFERENT edge | no expiry check | expired buckets → new Refund Credits (D9, 08:1095-1100) |
| 77 | Refund credits validity 1 month from booking date | SAME | `addDays(addMonths(b.date, 1), -1)` | 08:29, 08:860 |
| 78 | Aircon surcharge outside standard hours | SAME idea; DIFFERENT config | per-site settings Mon–Fri 9–19, Sat 9–14, Sun all day, $40/hr, 15-min steps | per facility type `afterHoursSurchargePerHour` + STANDARD hours rows (07:121, 07:160, 07:1155) |
| 79 | Cleaning fee | DIFFERENT model | weekday / weekend amount on the room | `additionalCharges` with day applicability on the type (07:180) |
| 80 | Same-day window | DIFFERENT enforcement | app only (9–16); admin warned | enforced `[opens, closes)` (07:159, 07:1237) |
| 81 | Move a booking | DIFFERENT | no re-pricing | `rescheduleBooking` (09:1879-1884) |
| 82 | Admin ACCOUNT / NEXT_CYCLE only for tenants with a lease | SAME | `FORMS.booking` | 09:79, 09:1750-1751 |
| 83 | Deposit retain | SAME idea; DIFFERENT record | `adhoc` invoice + "Deposit" payment | `releaseDeposit` retain amount (07:124) |
| 84 | Credits per site | DIFFERENT | per tenant, no site | per customer per site (08:19) |
| 85 | Booking minimum / maximum | DIFFERENT | `minHours` per room; admin max 16 h, app max 12 h | `minDurationMinutes` / `maxDurationMinutes` per type (07:148) |

---

## 9. Open questions and conflicts (for the owner / finance)

1. **Late-fee rule: which is right?** The artifact's block is labelled "rules from finance":
   12% p.a. on the **rental before GST**, **13-day grace**, counted **from the due date** once the
   grace is passed, **plus 9% GST** on the fee, finalised as a separate late-fee invoice on
   payment, staff waiver. The demo uses 7-day grace, interest on the **balance** from after the
   grace, **no GST**, and keeps it **disabled**. These give different amounts. Finance must
   confirm (demo open item C11, 10:1925-1926).
2. **Automatic billing**: the artifact bills automatically (default on, 7 days before the 1st).
   The demo never bills automatically (C10). Which does the business want?
3. **Monthly credits with a lease**: the artifact gives them automatically each month with a carry
   cap; the demo only stores the number. Should a cowork lease drive the BizPlus allowance?
4. **Carry-forward cap meaning**: artifact cap 0 = nothing carries; demo cap null = unlimited.
5. **Refund credits after a cash booking cancel**: does the customer get back the GST as credits
   (artifact) or only the pre-GST amount (demo)? Can a manager refund to card (artifact) or never
   (demo)?
6. **Credits as fractions** (artifact) or whole numbers only (demo)?
7. **Booking month rule**: may a booking next month use this month's allowance (artifact yes,
   demo no)?
8. **Rent GST**: both store 0% on rent today ("Tax" label in artifact); finance to confirm (C4,
   09:78).
9. **Charges per unit**: the demo (2026-10-08) puts each charge on one unit's invoice; the artifact
   has no unit on charges. The demo is newer here; confirm with ops.
10. **Merge suites**: working in the artifact, missing in the demo. Needed for the first release?
11. **Document storage**: artifact stores real files; demo stores links only (C9). Our S2 plan
    adds S3 — confirm documents need upload.
12. **Booking move re-pricing**: artifact keeps the old price; check 07's reschedule rule before
    we decide.
13. **Currency default**: `$` (artifact) vs `S$` (demo). Singapore-only release → `S$`.
14. **Which artifact version is newest?** The demo spec (2026-10-08) mentions changes "§9.6"
    (units on charges) that are not in this artifact, while this artifact has late-fee and
    auto-billing logic the demo lacks. Ask the PM which copy is the latest source of truth.
15. Defects not to copy: browser-side numbering, no locks, fake card payment, negative payments,
    late-fee void bug (§7.7), no CSV formula guard, "today" from the browser clock.
