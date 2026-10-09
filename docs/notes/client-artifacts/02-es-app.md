# Client artifact: "ES App UI Test" (customer mobile app prototype)

Read on 2026-10-09 from the saved raw HTML/JS
(`tool-results/artifact-eecdf2e9-1791515129-5968.html`, 1.2 MB; about 480 KB after removing
embedded base64 photos). The whole file was read: markup (screens), the i18n dictionary and all
JavaScript. Everything below comes from the code, not from a rendered view.

The file was written by the client. It is **a prototype, not a spec**: all data is hard-coded,
every payment is mocked, and there is no server. Treat it as a picture of what the client wants to
see and how they think the rules work. Where it disagrees with the demo spec, the owner decides.

Citations: artifact code is cited by **function name or a short searchable snippet** (search the
raw HTML for it). Demo spec is cited as `NN:line` = `../Backend Demo/backend/.claude/backend-spec/features/NN-*.md:line`.
No real personal data is copied here. Persona contact names and e-mails are shown as
`<sample person>`.

---

## 1. Overview

- A phone-frame web page that imitates the Flutter app ("mirrored from the real app's AppColors /
  AppTextStyles"). Header comment: "Home-tab revamp … 4-tab bottom nav (Home/My Spaces/BizPlus/Bills)
  with Profile moved to a header avatar". The code shows up to **5** tabs (see §2.1).
- It covers: guest Welcome page, Home, My Spaces (storage units + workspace seats), unit detail
  pages, Bills (storage units and workspace invoices), BizPlus room booking (book, extend, change
  date, cancel), My Credits (BizPlus credit wallet), buying credit packages, Rewards (points and
  storage rebate vouchers), Account details, cards, linked e-wallets, facility PIN codes, delete
  account, language and country.
- **Three countries** are modelled: Singapore, Malaysia, Korea (`PERSONA_COUNTRIES`). Features are
  switched on per country: BizPlus/workspace only in Singapore; Rewards in Singapore and Malaysia,
  not Korea. Our first release is Singapore only (cross-repo §4, 2026-10-09), so the MY/KR parts are
  reference only.
- A "Switch customer" sheet (tap the name top-left) jumps between 9 seeded personas
  (`PERSONAS`: p1–p7 in Singapore, pmy1 Malaysia, pkr1 Korea). Each persona is **one company**
  with one contact person. This is a demo tool, not a product feature.
- Version comments in the code go up to "Version 57", so the client iterated on it many times.
  Several things were added and then hidden (Explore section, Bluetooth unlock, Select a location).

---

## 2. Screens & flows

### 2.1 Screen list

| Screen id | What it shows | How you reach it |
|---|---|---|
| `screenWelcome` | Guest landing: "Welcome to Extra Space Asia!", "Sign up now" benefit list (per country), Announcements (mock promo "10% off first month"), **Log in** / **Sign up** buttons | Profile sheet → Log out |
| `screenExplore` (Home) | Greeting + name, globe (country flag) button, avatar; Credits and Reward-points mini cards; overdue payment banner; carousels: Storages, Workspaces, Bizplus Bookings; "Bizplus at your facility" promo; Promotions ("Refer a friend" dummy); Explore section (hidden) | Home tab |
| `screenMySpaces` | Storage / Workspace segmented tabs; payment status banner; unit list | My Spaces tab |
| `screenStorageDetail` | One storage unit: status chips, balance card + Pay, Access (PIN, hidden Bluetooth unlock), Your unit (size, pills), Rental & billing (rent, paid through, next billing, plan, insurance, recurring toggle), site contact buttons | Tap a storage unit card |
| `screenWorkspaceDetail` | One workspace seat: chips, balance + Pay, Access card (hidden), Rental & billing (rent, "Additional charges › View", paid through, next billing, plan, recurring toggle), site contact | Tap a workspace card |
| `screenBills` | Storage / Workspace tabs → facility list → facility detail. Storage detail = tick-and-pay unit table. Workspace detail = sub-tabs **Invoices / Upcoming Charges / History** | Bills tab, Pay buttons, overdue banners |
| `invoiceDetailSheet` | One workspace invoice: facility, period, issued, due, lines, total, balance due or "Paid in full on … via …", Download (mock) | Tap an invoice row |
| `screenResource` (BizPlus) | Credits balance hero (only if the customer has booking history); tabs **Book** (list of 4 rooms/spaces) and **My Bookings** (Active / Past / Cancelled) | BizPlus tab (Singapore only) |
| `screenFacilityDetail` | Room photo, seats, location, specs, event-space fees text, standard-hours text, "Cancellation & termination policy", bottom bar "From S$X/hr" + action button | Tap a room, or tap an active booking |
| `screenCalendar` | "Select a date": 2 months, past days disabled | "Select date & time" / "Change date & time" |
| `screenTimeSlot` | 24-hour scrollable slider, 15-minute cells, drag handles, legend (Selected, Already booked, Outside standard hours, Past), banners | After picking a date; "Extend" goes straight here |
| `screenReview` | Price breakdown, "Top up with a credits package", "Pay with credits" toggle, credits applied + per-bucket draw list, GST, "Amount by card", Pay / Confirm | Continue on the slider |
| `screenPackageReview` | Package price, GST 9 %, total | Pick a package in "Buy more credits" |
| `screenStripe` | **Fake in-app card form** pre-filled with test card 4242…, "Test mode — no real charge is made" | Any payment with a card amount > 0 |
| `screenCredits` (My Credits) | Balance hero, This month / Next month allowance carousel (monthly plan) or Contract credit balance (lump-sum plan), Top-up credits lot, Refund Credits lot, Recent activity | Home Credits card, BizPlus hero |
| `screenRewards` | Points balance, expiry chip, earned this month, how you earn, redeem 3 rebate tiers, My vouchers, terms, Points history | Rewards tab / Home rewards card |
| `screenAccountDetails` | Name and Email (locked), Phone (editable), Cards management, Facility storage PIN code, Danger zone → Delete account | Avatar → Profile sheet → Account details |
| `screenCardsManagement` | Saved cards (Remove), Add a card, "Linked payment methods" (e-wallet per country) | Account details |
| `screenAddCard` | Live card preview, card number, name, expiry, CVC, **Recurring** checkbox, Save Card | Cards management |
| `screenFacilityPins` | Every storage unit with masked PIN and Show/Hide | Account details |
| `screenSelectLocation` | Map placeholder + 4 sites, "Explore Workspace" | Only from the hidden Explore section → effectively unreachable |
| Sheets / modals | Persona switcher, Profile, Delete account confirm, Language + Country, Buy more credits, Cancel booking, Cancellation policy, Leave-booking confirm, Choose e-wallet (MY), WhatsApp chat mock, Bluetooth unlock modal, Success modal, Toast | — |

Bottom nav (`bottomNavHtml`): Home, My Spaces, Bills, then **BizPlus** only if
`countryHasBizPlus()`, then **Rewards** only if `countryHasRewards()`. Singapore therefore has 5
tabs. Tabs are "root" pages: they reset the back stack (`resetNavTo`). Other pages push onto a
stack and the back arrow pops one page (`showScreen` / `navBack`).

### 2.2 Sign-in and onboarding

There is **no sign-in, sign-up, one-time-code or onboarding flow** in this prototype.

- `logOut()` only shows `screenWelcome`.
- On the Welcome page, "Log in", "Sign up", every benefit row, the promo button and every bottom
  tab call `enterAppFromWelcome()`, which just goes back to Home as the same persona
  (comment: "no separate guest-mode screens were built behind them, per the user's spec").
- Welcome benefits per country (`renderWelcomeBenefits`): always "Manage your bills in one place";
  "Earn rewards on every payment" if Rewards is on; "Browse BizPlus at Commonwealth" if BizPlus is
  on. Order: bills, rewards, BizPlus.
- The PIN note says "We verify it's you with a one-time code before showing it", but **no code is
  asked**: `toggleStoragePin()` / `toggleWorkspacePin()` / `toggleFacilityPinShown()` reveal the PIN
  at once.

### 2.3 Home

- Greeting text is static "Good afternoon" + persona contact name.
- **Credits card** (Singapore only) = `totalCredits()` (this month, see rule R4). **Reward points
  card** (SG/MY) = points balance.
- **Overdue payment banner** (`renderHomeQuickAccess`): collects every storage unit and workspace
  seat with `billingStatus === 'overdue'` (`getOverdueUnits`). Amount = Σ `amountDue`.
  - 1 overdue unit: label "Payment overdue · Unit <code>", sub-line "Due on <date>", button
    "Pay now".
  - 2+ overdue units: label "Payment overdue · N units", no date line; button "Pay now" if all
    are at one facility, else "View bills".
  - Button routing = `goToOverduePayment` (rule R27).
- **Storages / Workspaces carousels**: one card per unit; tile shows the unit code; tags = status
  pill + recurring pill; meta = site name; last line "Due on <date>" (overdue) or "Paid through
  <date>".
- **Bizplus Bookings carousel**: active bookings only (rule R20), soonest first; tile = day number
  + month; pill "Ongoing" or "Upcoming"; tap → facility detail in manage mode.
- **"Bizplus at your facility" promo**: shown only in Singapore and only when the customer has
  **no** bookings at all. Shows "From S$<lowest meeting-room rate>/hr" and "Up to <largest
  event-space capacity> guests".
- **Promotions**: always shown, dummy "Refer a friend, earn reward points" (no logic behind it).

### 2.4 My Spaces

- Storage / Workspace tabs (tabs hidden outside Singapore).
- Status banner: "All paid up" / "Payment due" + Σ overdue `amountDue` + "Pay now" (routes through
  `goToOverduePayment`, each tab only for its own kind). The Workspace banner prints
  `'SGD ' + total` with a hard-coded "SGD" while the Storage banner uses `formatMoney` ("S$").
- "Your units" / "Your workspaces" list (same card as Home). Empty states: "You don't have a storage
  unit with us yet." / "You don't have a workspace membership with us yet."

### 2.5 Storage unit detail (`renderStorageDetailScreen`)

- Chips: status (Overlocked / Overdue / Paid) + Recurring / Non-recurring.
- Balance card: overdue → "Balance overdue", amount, "Due <date>", button "Pay S$X" → Bills with
  this unit ticked (`payStorageBill` → `goToBillsForUnit`). Not overdue → "Balance", S$0.00,
  "Paid through <date>", disabled "All paid up". Payment is never done on this page.
- Access: "Open 24 hours", Storage PIN (masked, Show/Hide). "Unlock Door (Bluetooth)" button is
  `display:none` ("hidden for now (Version 23)"). "Share lock access" removed (Version 32).
- Your unit: Width, Length, Area = width × length (sq ft), Floor; pills: wine unit → "Wine",
  "<N> wine cases", deck name; other units → "Air-con" or "Non-aircon" + access type
  (Drive-up / Walk-in / Upper locker / Lower locker / Locker).
- Rental & billing: Monthly rent, Paid through, Next billing, Plan, **Storage insurance** "Basic
  plan · up to <coverage> coverage" and "<premium>/mo" (fixed per country, rule R31), **Recurring
  payment** switch with card label; when on, note "Next charge on <next billing> to <card>. Nothing to
  do."
- Site card: Navigate, Call (toast "Calling <phone>…"), WhatsApp.

### 2.6 Workspace seat detail (`renderWorkspaceDetailScreen`)

Same layout as storage, minus the unit card and insurance. Header "Unit <code>", sub-line
"<title> · <site> · <floor>". Access card (Facility PIN, "Share lock access — Coming soon") is
`display:none`. Extra row **"Additional charges › View"** → Bills, workspace facility, Upcoming
Charges tab (`goToWorkspaceAdditionalCharges`). Recurring switch as storage. Amounts are printed
with a hard-coded "S$".

### 2.7 Bills

1. Tabs Storage / Workspace (hidden outside Singapore). Opening Bills always lands on Storage,
   facility list (`openBillsScreen`).
2. **Facility list**: units of the chosen kind grouped by `siteName` (first-seen order). Row =
   facility name, "N unit(s)", status pill (Overlocked if any unit overlocked, else Overdue if any
   overdue, else Paid).
3. **Storage facility detail**: blue "My Bills" hero, back link, table *Unit No. / Amt Due (S$) / Amt
   to Pay (S$)*. Each unit row: checkbox, unit code, "Due <date>" (overdue) or "Paid on <paid-through
   date>" (the label says "Paid on" but shows the paid-through date), Amt Due, an **editable** Amt to
   Pay field (default = amount due; disabled "0.00" for a paid unit). Overdue rows also show "Use
   reward ›" → toast "Use reward — coming soon". Checkboxes are shown on paid rows too.
4. **Workspace facility detail**: sub-tabs **Invoices** (default when opened from the list),
   **Upcoming Charges** (default from the shortcut buttons), **History**.
   - Invoices: table *Invoice / Amt Due / Amt to Pay*. Only overdue invoices get a checkbox and an
     editable amount; paid ones show a blank spacer and disabled 0.00. Tap → invoice detail sheet.
   - Upcoming Charges (read-only): note "<S$ total> of charges (printing, extras, bookings) will
     appear on your next monthly invoice." + list (description, date, amount).
   - History: one row per payment: date, "<method> · <reference>", amount.
5. **Pay bar** (`billsRecalcPayBar`): shown only when a facility is open, it has something overdue,
   and (workspace) the Invoices tab is active. Shows "N unit(s) selected" / "N invoice(s) selected"
   and the total of the typed amounts; button "Pay Selected Units" / "Pay Selected Invoices",
   disabled when nothing is ticked.
6. **Pay** (`payBillsSelected` → `goToStripe` → `completeStripePayment`, kind `billsPayment`):
   - Storage: every selected unit becomes `billingStatus 'current'`, `paidThroughLabel =
     nextBillingLabel`, `amountDue 0` — **whatever amount was typed**.
   - Workspace: every selected invoice becomes `paid`; a payment row is added (date "Today",
     method = default card "Brand •• last4" or "Card on file", reference = invoice number).
     The workspace seat's own `billingStatus`/`amountDue` is **not** updated, so the Home banner still
     shows it overdue (prototype gap).
   - Success modal "Payment successful", "<Units/Invoices …> paid in full · <amount> charged to your
     card."

### 2.8 BizPlus booking (new booking)

1. **Book** tab: all 4 resources in one list (the Meeting Rooms / Event Space filter was removed in
   Version 33). Card: photo, type tag, name, "<pax> pax · <floor>" (event space: "guests"),
   "S$<rate> / hr" (+ " · min 2 hrs" for the event space). If a site other than Bizplus Commonwealth /
   Bizplus Boon Keng was chosen, the list is replaced by "BizPlus meeting rooms and event spaces are
   only available at Bizplus Commonwealth and Bizplus Boon Keng." All 4 resources have the
   Commonwealth address.
2. **Facility detail**: specs list; event space adds "Cleaning fee S$50.00 (weekdays) / S$100.00
   (weekends), plus a S$500.00 refundable deposit. Minimum 2-hour booking."; all rooms add
   "Standard hours: Mon–Fri 9am–7pm, Sat 9am–2pm. Outside these hours, an aircon extension charge of
   S$40/hr applies." Building card says "Open until 5:30 PM" (conflicts with 24/7 booking, see §9).
3. **Calendar** (`renderCalendar`): only 2 months, **hard-coded** September 2026 and October 2026
   (`CAL_MONTHS`). Days before today are disabled. Picking a day sets the credit pool (rule R5),
   shows "Selected: <date> · billed to <pool>" and opens the slider after 200 ms.
4. **Time slider** (`openTimeSlotScreen`, `renderTimeSlot`): rules R8–R13. Summary card shows
   "<Mon d> · <start> – <end>" and "<duration> · S$<rent + aircon>" (+ "(incl. aircon extension)").
   Banners: same-day cutoff (blocks Continue), aircon warning with "Contact our BizPlus team"
   (WhatsApp mock). Continue is disabled when the duration is below the minimum or the cutoff applies.
5. **Review** (`renderReviewScreen`, `updateReviewCreditSplit`): rows "<Room> rental" (duration ×
   rate), "Aircon extension" (hours × S$40), event space: "Cleaning fee" (sub-label "Weekday rate" or
   "Weekend / public holiday rate") and "Refundable deposit" ("Held on your card, refunded after the
   event"). The line labelled **"Sub-total"** shows `totalDueNow` = subtotal **+ deposit**. Then "Top
   up with a credits package", "Pay with credits" switch (default on), "Credits applied", a per-bucket
   draw list, "GST (9%) — Not charged on credits or the refundable deposit", "Amount by card". Button
   = "Pay S$X" if card amount > 0, else "Confirm booking". Formulas: rules R14–R18.
6. **Pay**: card amount 0 → credits drawn at once, booking saved, success modal "Paid with N
   credits". Card amount > 0 → fake Stripe page → 900 ms "Processing…" → credits drawn (if any),
   booking saved with its per-bucket split, success modal "<N> credits + S$X charged" or "S$X charged
   to your card. Your credits were not touched." (+ "Includes a S$500.00 refundable deposit.").
   If the booking is outside standard hours, the success modal repeats the aircon note.
7. After a new booking the app lands on **My Credits**.

### 2.9 Managing a booking

Tap an **active** booking (Home carousel or BizPlus › My Bookings › Active) →
`openFacilityDetailForBooking` → facility detail in "manage" mode (`updateFacilityDetailButton`):

| Booking state | Buttons | Rule |
|---|---|---|
| Ongoing now | **Extend** only. No Cancel ("Ongoing bookings can no longer be cancelled.") | R21 |
| Upcoming, ≥ 12 h before start | **Change date & time** + **Cancel** | R22, R23 |
| Upcoming, < 12 h before start | Change button disabled + banner "This booking starts in N hours — date & time changes must be made at least 12 hours before the start time. You can still cancel, but a refund won't apply this close to the start." Cancel still shown | R22, R23 |

Past and cancelled cards open the plain facility detail (a new booking).

- **Extend** (`beginExtendFlow`): straight to the slider, title "Extend booking", start handle locked
  (opacity .35), end handle only moves forward in whole hours. Review title "Review extension",
  main row "Extension — <room>", "Additional charge". Lands on BizPlus › My Bookings.
- **Change date & time** (`beginChangeDateFlow`): calendar ("Pick a new date for this booking —
  changes are free of charge.") → slider (defaults to the original start and length) → review
  "Confirm change": old time struck through, new time, row "Date & time change — Free", "Change fee
  S$0.00", credits section hidden, button "Confirm change". Lands on BizPlus › My Bookings.
- **Cancel** (`beginCancelBooking` → `cancelSheet`): shows "Amount paid" (credits / cash / both) and
  "Refund" with an explanation (rule R23). "Confirm cancellation" / "Keep booking". Lands on BizPlus
  › My Bookings, toast with the result.

### 2.10 Buying credits

- "Buy more credits" sheet (`buySheet`): 200 credits S$190 "Valid 1 month"; 500 credits S$450
  "Valid 3 months" **"Best value"**; 1000 credits S$850 "Valid 6 months".
- From My Credits: package → "Review purchase" (price, GST 9 %, "Total due now") → fake Stripe →
  credits added (rule R7) → My Credits, "Credits purchased successfully".
- From the Review Booking screen ("Top up with a credits package"): a modal **"Leave this booking?"**
  — "Your current time-slot selection will be lost". "Continue to payment" goes to the package
  review; the booking is abandoned. The comment says: "a package purchase is its own separate
  checkout, never folded into a booking's combined payment." (`previewCreditDraw` still accepts a
  `pendingPkg`, but no caller passes one — leftover code.)

### 2.11 My Credits (`render`)

- Hero: "<company> · Available balance", `totalCredits()`, buttons "Book BizPlus", "Buy more credits".
- **Monthly plan**: swipeable "This month's allowance" (remaining / allowance, bar, tag "Carry-forward
  on" or "No carry-forward", text "Up to <cap> unused credits roll into next month. Resets <date>." or
  "Unused credits do not roll over. Resets <date>.") and "Next month's allowance" (remaining /
  allowance, "Includes up to <carry> credits carried forward from this month if unused — up to
  <total> credits available from <date>").
- **Lump-sum plan**: "Contract credit balance" remaining / total, "Contract credits do not reset
  monthly — they draw down until the contract ends on <date>."
- **Top-up credits** panel (one lot): name, remaining / total, tag "Expiring soon" if ≤ 10 days else
  "Active", "Expires <date> · N days left."
- **Refund Credits** panel (one lot, shown only when total > 0): same layout; default text "Credits
  refunded from a cash-paid cancellation, valid for 1 month."
- Recent activity list (persona `txns`, newest first).
- Footnote: "Credits are managed by your company admin via the BizPlus Credits portal. Monthly and
  top-up credits are used automatically, earliest-expiring first."

### 2.12 Rewards (`renderRewardsScreen`)

Balance; expiry chip "<pts> pts expire on <date>" (only if seeded); "+N pts earned this month" or
"No points earned this month yet"; "Earn 1 pt for every S$1 paid on your self storage bill." (currency
symbol swapped per country); "Redeem a storage rebate voucher — Use it on any storage bill under My
Bills."; 3 tiers (rule R29); My vouchers; terms "Vouchers apply to storage rental only. Credits can be
used for meeting room bookings." (no-BizPlus variant drops the credits sentence); Points history.

### 2.13 Account, cards, wallets, PINs, delete

- Profile sheet: initials, name, email, "Account details", "Log out".
- Account details: Name and Email **disabled** ("Name and email are on file with Extra Space Asia —
  contact support to update them."), Phone editable, "Save changes" saves the phone with no validation.
- Cards management: "<Brand> •• <last4>", "Expires MM/YY · Default", Remove; "Add a card".
- Add Card: see rule R33. Footnote claims "Card details are tokenized by Stripe. Only the last 4 digits
  are stored in this app." — in the prototype the full number is typed into the app's own form.
- Linked payment methods (`renderLinkedWalletSection`): Singapore "Link PayLah!", Korea "Link PayApp",
  Malaysia "Link e-wallet" → choose Touch 'n Go eWallet / GrabPay / RazorPay. One tap = "Linked" +
  toast. No real flow.
- Facility storage PIN code: every storage unit (not workspace seats), PIN masked, Show/Hide.
- Delete account → sheet "This permanently deletes your account and everything in it — storage units,
  bookings, credits and reward points. This can't be undone." → "Delete my account" → only a toast
  **"Account deletion requested — our team will follow up by email"**. Nothing is deleted.

### 2.14 Language and country

- Languages: English, Bahasa Melayu, Korean (`LANGUAGES`, `I18N`). Only Home, My Spaces, Bills,
  BizPlus list, Rewards and the sheets are translated; booking steps, detail pages and Stripe stay
  English ("known limitation").
- Country list (`COUNTRIES`): Singapore → English only; Malaysia → English (default), Malay; Korea →
  Korean (default), English. Picking a country also moves the customer to that country's persona
  (`setCountry` → `switchCountry`).
- The globe button shows the selected country's flag.

### 2.15 Notifications

Only in-app toasts (3.2 s) and success modals. **No push, e-mail or SMS** is shown or mentioned,
except: the delete-account toast promises a follow-up e-mail; the aircon flow tells the customer to
**contact the BizPlus team on WhatsApp** (mock chat with a pre-filled message: "Hi, I've booked
<room> on <date> from <time>, which is outside standard operating hours. Could you help activate the
aircon extension for this booking?") to activate the aircon and "retrieve your access card".

---

## 3. Data model (as used by the prototype)

### 3.1 Customer / persona (`PERSONAS[]`)

| Field | Meaning |
|---|---|
| `id`, `country` (`Singapore`/`Malaysia`/`Korea`) | |
| `company`, `contact` (<sample person>), `initials`, `email` (<sample person>), `phone` | Company is the account holder; contact is the person |
| `cards[]` | `{id, brand, last4, expiry 'MM/YY', isDefault, recurring?}` |
| `linkedWallet` | `paylah` / `tng` / `grabpay` / `razorpay` / `payapp` / null |
| `storageUnits[]` | §3.2 |
| `workspaceUnits[]` | §3.3 |
| `workspaceInvoices[]`, `workspacePayments[]`, `workspaceCharges[]` | §3.4 |
| `rewardPoints` | `{balance, earnedThisMonth, expiring?{amount, dateLabel}, history[], vouchers[]}`; Korea persona has none |
| `type` | `'monthly'` or `'lumpsum'` (credit plan) |
| monthly: `monthlyAllowance, monthlyRemaining, carryForward (bool), monthlyCarryCap, nextMonthAllowance, nextMonthRemaining, monthlyResetLabel` | |
| lumpsum: `lumpsumTotal, lumpsumRemaining, contractEndLabel` | |
| `lot` | one top-up lot `{name, remaining, total, expiresLabel, daysLeft, expiresOn}` or null |
| `refundLot` | one Refund Credits lot, same shape, created on first cash refund |
| `txns[]` | credit activity `{title, sub, amountLabel, kind 'earn'/'spend'}` |
| `bookings[]` | §3.5 |

Seeded plans (to see the variety): p1 monthly 150/mo, carry cap 30, top-up lot 200; p2 monthly
20/mo, no carry; p3 lump sum 500 (310 left) to 31 Dec 2026 + "100 bonus credits" lot; p4 monthly
50/mo cap 20, no bookings (shows the promo); p5 lump sum 1000 (640 left) to 30 Jun 2027; p6 brand-new
customer (no units, no cards, 0 credits); p7 monthly 30/mo cap 10, storage + workspace + bookings.
MY and KR personas have zero credits and no workspace.

### 3.2 Storage unit

`id, code, siteName, address, floor, size, widthFt, lengthFt, status ('Active'), lastAccess,
bluetoothDeviceName, pin (4 digits), monthlyRent, paidThroughLabel, nextBillingLabel, planLabel
('Monthly · since <date>'), recurring (bool), autopayCardLabel, billingStatus ('overdue' |
'current'), overlocked (bool, optional), amountDue, dueDateLabel, unitType ('aircon' | 'non_aircon'
| 'wine'), unitAccess ('drive_up' | 'walk_in' | 'upper_locker' | 'lower_locker' | 'locker' |
'wine'), wineCases, wineDeck (wine only), features[], sitePhone`.

### 3.3 Workspace seat

`id, title ('Hot Desk' | 'Fixed Desk' | 'Office Suite (4 seats)'), workspaceType ('desk' | 'fixed'
| 'office'), code, siteName, address, floor, seats, status, pin, monthlyRent, paidThroughLabel,
nextBillingLabel, planLabel, recurring, autopayCardLabel, billingStatus, amountDue, dueDateLabel,
features[], sitePhone, photo?`.

### 3.4 Workspace billing

- Invoice: `id, sortKey, number ('INV-YYMM-NNN', e.g. INV-2609-108), facility, period ('Sep 2026'),
  issueDateLabel, dueDateLabel, amount, status ('overdue' | 'paid'), lines[{desc, amount}]`.
  Sample: issued on the 25th of the month before, due on the 1st; one invoice per facility per month
  covering all the customer's seats there ("Monthly rent — Fixed Desk (FD05), 1–30 Sep 2026").
- Payment: `id, sortKey, facility, dateLabel, amount, method ('Visa •• 1234'), reference (invoice
  number)`.
- Upcoming charge (not yet invoiced): `id, sortKey, facility, desc, dateLabel, amount`. Samples:
  "Meeting room booking — overage (2 hrs)" S$40, "Key card replacement" S$30, "Additional cleaning —
  Office Suite" S$80, "Mail handling — Sep 2026" S$20.

### 3.5 BizPlus booking

`id, resourceId, year, month (0-based), day, startHour, endHour (hours as a float, multiples of 0.25),
cancelled, creditsUsed, cashAmount (card money for the booking incl. GST, excl. deposit), bucket
('this' | 'next' | 'lumpsum'), creditsFromPool, creditsFromLot, creditsFromRefundLot`.
New ids: `'bk' + Date.now() + random(0..999)`.
Status is derived, not stored (rule R20). No reference number, passcode, hold or payment status.

### 3.6 Resources (`RESOURCES`) — all at "491B Commonwealth Drive", "Open until 5:30 PM"

| id | Name | Kind | Floor | Pax | S$/hr | Extra |
|---|---|---|---|---|---|---|
| mr1l1 | Meeting Room 1 | meetingRoom | Level 1 | 4 | 20 | |
| mr2l1 | Meeting Room 2 | meetingRoom | Level 1 | 8 | 40 | |
| mr1l2 | Meeting Room 1 | meetingRoom | Level 2 | 10 | 50 | |
| es1l1 | Event Space | eventSpace | Level 1 | 40 | 175 | cleaning 50 weekday / 100 weekend, deposit 500, min 2 h |

Seeded "already booked" hours per resource (`getBookedHours`): mr1l1 [13], mr2l1 [16,17], mr1l2
[13,14], es1l1 [15,16] — the same hours on **every** date.

### 3.7 Sites (`SITES`, used only by the hidden Select-a-location screen)

Bizplus Commonwealth (bizplusAvailable), Bizplus Boon Keng (bizplusAvailable), Extra Space Tai
Seng, Extra Space Kallang Way — each with address, distance label, free-parking flag.

---

## 4. Calculations & rules

Money is JavaScript `number` (double). Display uses `toFixed(2)` (KRW: whole numbers). **No
rounding is applied to stored values** (GST is kept unrounded and only formatted).

### Credits wallet

- **R1 — 1 credit = S$1.** Credits applied = `min(available, subtotal)` in S$ (`updateReviewCreditSplit`).
  The prototype never floors because every subtotal is a whole number (whole hours × whole rates,
  surcharge in S$10 steps, whole fees).
- **R2 — Plans.** Monthly: `monthlyAllowance` per month, optional carry-forward capped at
  `monthlyCarryCap`. Lump sum: one pool `lumpsumTotal` until `contractEndLabel`, no monthly reset.
- **R3 — Carry-forward preview.** `carry = carryForward ? min(monthlyRemaining, monthlyCarryCap) : 0`;
  next month shows "up to `nextMonthAllowance + carry`". The prototype never runs a month-end; the
  preview is display only.
- **R4 — Available credits.** `totalCredits(bucket) = pool + lot.remaining + refundLot.remaining`,
  where pool = `lumpsumRemaining` (lump sum), `nextMonthRemaining` (bucket 'next') or
  `monthlyRemaining`. **No expiry check**: an expired lot still counts.
- **R5 — Which month pays.** Chosen by the calendar **tab**: first month → 'this', second month →
  'next', lump sum → 'lumpsum' (`selectCalendarDate`). Extensions always use 'this' (or lump sum).
- **R6 — Draw order** (`deductCredits`, `previewCreditDraw`): candidates pool, lot, refundLot sorted by
  expiry ascending; no expiry (= lump sum pool) last. Pool expiry = 1st of next month for 'this'
  (`MONTHLY_POOL_RESET`), 1st of the month after for 'next'. Ties keep the order pool, lot, refundLot.
  Take `min(bucket.remaining, left)` from each in turn. The per-bucket amounts are saved on the
  booking.
- **R7 — Package purchase** (`completeStripePayment`, kind `purchase`): **all packages share one lot**:
  `lot.remaining += credits; lot.total += credits; lot.expiresOn = TODAY + validity months`
  (overwrites the old expiry — comment calls it "a known simplification"). Validity: 200 → 1 month,
  500 → 3, 1000 → 6 (`PACKAGE_VALIDITY_MONTHS`, default 1). Month maths is JS `new Date(y, m + n, d)`
  (31 Jan + 1 month → 3 Mar).
- **R7a — Package price.** `gst = price × 0.09`, `total = price + gst` (190 → 17.10 → 207.10;
  450 → 40.50 → 490.50; 850 → 76.50 → 926.50).
- **R7b — Lot tag.** "Expiring soon" when `daysLeft ≤ 10`, else "Active".

### Booking calendar and time slot

- **R8 — Bookable days.** Today and later, inside the 2 hard-coded months. No max-advance setting.
- **R9 — Bookable hours.** 00:00–24:00, every day ("Resources are bookable 24/7"). Grid = 15 minutes.
- **R10 — Start and length.** Start on any 15-minute mark; **length is always whole hours**
  (11:15 → 12:15, 13:15 …, never 11:45). Minimum 1 h for meeting rooms, 2 h for the event space
  (`minDuration`). Maximum = end of the day (24:00); no cross-midnight.
- **R11 — Earliest start today.** Device clock rounded **up** to the next 15 minutes (11:17 → 11:30;
  11:30 stays 11:30) (`minSelectableHour`). Other days have no limit. Default start: today = earliest
  start; other days = 09:00 (`DEFAULT_FUTURE_DAY_START_HOUR`). If the default collides, scan forward in
  15-minute steps; if nothing fits, start at the earliest time with the minimum length.
- **R12 — Same-day cutoff** (`isSameDayBookingCutoffBlocked`): a booking **for today** is blocked
  unless the device clock hour is `>= 9 and < 16` (09:00–15:59). Extensions are exempt. Changes of
  date are **not** exempt. Banner: "<Meeting rooms|Event spaces> can only be booked for today between
  9:00 AM and 4:00 PM."
- **R13 — Conflicts.** Booked data is whole hours. Any whole hour touched by `[start, end)` that is in
  the booked list blocks the slot (`clampStart`, `clampEnd`, `conflictFree`). Dragging the end shrinks
  the length one hour at a time until free, never below the minimum. Dragging the start keeps the
  length and walks back in 15-minute steps to a free position. Moving the whole bar is refused if it
  would overlap.

### Booking price

- **R14 — Standard hours / aircon surcharge** (`isHourSurcharged`, `surchargeHoursFor`):
  - Sunday: whole day surcharged.
  - Saturday: standard 09:00–14:00, rest surcharged.
  - Monday–Friday: standard 09:00–19:00 (code comment: "9am–6pm + 6–7pm grace").
  - Counted per 15-minute block: `surchargeHrs = (number of quarter-hours whose clock hour is
    surcharged) / 4`. `aircon = surchargeHrs × 40`.
  - No public-holiday rule (the cleaning-fee label mentions public holidays, the code does not).
- **R15 — New booking breakdown** (`computeBookingBreakdown`):
  ```
  dur      = end − start (hours)
  rent     = dur × hourlyRate
  aircon   = surchargeHrs(start..end) × 40
  cleaning = eventSpace ? (Sat or Sun ? 100 : 50) : 0
  deposit  = eventSpace ? 500 : 0
  subtotal = rent + aircon + cleaning          // credits can pay all of it
  totalDueNow (shown as "Sub-total") = subtotal + deposit
  ```
- **R16 — Extension breakdown** (`computeExtendBreakdown`): only the added time:
  `rent = (newEnd − originalEnd) × rate`, `aircon` on `[originalEnd, newEnd)`, no cleaning, no
  deposit.
- **R17 — Credits, GST and card** (`updateReviewCreditSplit`):
  ```
  available       = totalCredits(bucket)
  creditsApplied  = useCredits ? min(available, subtotal) : 0
  cashBeforeGst   = subtotal − creditsApplied
  gst             = cashBeforeGst × 0.09           // never on credits, never on the deposit
  bookingCash     = cashBeforeGst + gst           // stored as booking.cashAmount
  cardAmount      = bookingCash + deposit
  ```
  Deposit is always on the card, never paid with credits, never taxed. If `cardAmount ≤ 0` there is no
  payment page.
- **R18 — Worked examples** (from the code, Mon–Fri unless stated):
  - Meeting Room 1 L1, Tue 10–12, no credits: rent 40, GST 3.60, card 43.60.
  - Same room Tue 18:45–20:45 (2 h, starts on a quarter): rent 40; surcharged quarters 19:00–20:45 =
    7 → 1.75 h × 40 = 70; subtotal 110.
  - Event Space Sun 10–12, 0 credits: rent 350, aircon 80, cleaning 100, subtotal 530, GST 47.70,
    booking cash 577.70, + deposit 500 → card 1,077.70.
  - Event Space Tue 10–12, 100 credits: subtotal 400, credits 100, GST 27, booking cash 327, card 827.

### Managing bookings

- **R19 — Change of date/time** (`beginChangeDateFlow`, `applyDateChange`): allowed only while the
  booking is ≥ 12 h away (same check as the refund, `evaluateRefund`). **Free**: no re-pricing, no
  credit movement, even if the new slot is longer, after-hours, on a weekend, or in another month. The
  slider is **not** locked to the original length (only the minimum length applies).
- **R20 — Booking status** (`bookingStatus`, `isBookingOngoingNow`): cancelled → 'cancelled'; date
  after today → 'active'; date before today → 'past'; today → 'past' if `endHour ≤ 9`, else 'active'.
  "Ongoing" = today and `9 ≥ startHour and 9 < endHour`. The "now" hour is the **fixed demo hour 9**
  (`DEMO_NOW_HOUR`), not the device clock.
- **R21 — Extend.** Only an ongoing booking. Start locked; add whole hours (min 1); same conflict
  rules; same-day cutoff does not apply. Paid like a booking (R16 + R17) from 'this' month or the lump
  sum. Credits used by an extension are **not** added to the booking's `creditsUsed`.
- **R22 — 12-hour rule** (`evaluateRefund`):
  `hoursUntil = (bookingStart − (TODAY at 09:00)) / 3,600,000`; `eligible = hoursUntil ≥ 12`
  (exactly 12 h is eligible). "Now" = today 09:00 (demo clock).
- **R23 — Cancel** (`cancelRefundPreview`, `confirmCancelBooking`). Not allowed while ongoing;
  always allowed while upcoming:
  - No payment on file → "No refund".
  - < 12 h → **no refund at all** ("within the 12-hour cutoff").
  - ≥ 12 h, **credits only** → the same credits go back to the buckets they came from
    (`poolRefundSplit`: pool / lot / refundLot by the saved split; old bookings without a split → all
    to the pool). If the lot or refund lot no longer exists, that part is **silently lost**
    (`if (split.toLot > 0 && p.lot)`). No expiry check.
  - ≥ 12 h, **any cash** (cash only or mixed) → one Refund Credits amount
    `creditsBack = creditsUsed + Math.round(cashAmount)` where `cashAmount` **includes GST**
    (excludes the deposit). Nothing goes back to the card ("Cash payments are refunded as credits").
  - Refund Credits expire **1 month from the booking date, not the cancel date**:
    `expiry = new Date(y, m + 1, d − 1)` (last usable day; e.g. booking 10 Oct → valid to 9 Nov)
    (`refundLotExpiryFor`). All refunds share **one** refund lot; a new refund overwrites its expiry.
  - The deposit is not part of the refund; policy text says it is "returned in full after your event,
    provided there is no damage and no additional cleaning is required".
- **R24 — Policy text** (`policySheet`, marked placeholder): (1) free cancellation up to 12 h before;
  (2) inside 12 h the full amount is forfeited; (3) no-shows are treated as used in full; (4) date/time
  can be changed free up to 12 h before, subject to availability; (5) event-space deposit returned in
  full if no damage and no extra cleaning; (6) "Placeholder text — contact the BizPlus team at least 7
  days in advance to end a recurring booking arrangement early." (no recurring bookings exist in the
  prototype).

### Bills and payment routing

- **R25 — Storage unit pay amount.** Default = `amountDue`; editable free text, `parseFloat`, no
  minimum, no maximum, no decimals check. Paying marks the unit fully paid whatever the amount.
- **R26 — Workspace invoice pay amount.** Only overdue invoices; default = invoice amount; editable,
  no validation; paying marks the invoice fully paid.
- **R27 — Overdue routing** (`goToOverduePayment`):
  1 overdue unit → Bills › its facility, that unit ticked (Upcoming Charges tab for workspace);
  2+ at one facility → that facility, all ticked; 2+ across facilities → Bills facility list on the tab
  of the first overdue unit's kind. For a **workspace** seat this lands on the read-only Upcoming
  Charges tab, where nothing can be paid (workspace is paid from Invoices) — a prototype gap.
- **R28 — Status pills.** Overlocked (black) wins over Overdue (red) wins over Paid (green).
  Overlocked = "a facility-applied second lock over serious non-payment", layered on top of
  `billingStatus`.

### Rewards

- **R29 — Redeem tiers** (`REWARD_REDEEMABLES`): 1,000 pts → S$10; 2,000 pts → S$20; 5,000 pts →
  S$50 (= 100 points per S$1). Redeem button disabled with "need N more" when balance < cost.
  `redeemReward`: balance −= pts, a voucher "S$<amount> · <today>" is added, history "Redeemed ·
  S$<amount>" "−<pts> pts".
- **R30 — Earning.** Text only: "1 pt for every S$1 paid on your self storage bill". **Paying a bill
  in the prototype adds no points.** No welcome bonus. Points expiry is only a seeded chip.
  Vouchers can't be used yet ("Use reward — coming soon").

### Other

- **R31 — Storage insurance** (`INSURANCE_INFO`): one "Basic plan" per country, not optional, no
  toggle: Singapore cover S$2,000 for S$8/mo; Malaysia RM6,000 for RM25/mo; Korea ₩2,000,000 for
  ₩9,000/mo.
- **R32 — Money format** (`formatMoney`): currency symbol only (S$, RM, ₩ — "the user explicitly asked
  that MYR/KRW never be shown"), thousands separators, 2 decimals (KRW 0).
- **R33 — Add card validation** (`saveNewCard`): ≥ 12 digits, name not blank, expiry matches `MM/YY`,
  CVC ≥ 3 digits. Input auto-formats 4-digit groups (max 16 digits) and the "/" in the expiry. No Luhn
  check, no "expiry in the future" check. Brand: starts 4 → Visa; 51–55 or 22–27 → Mastercard; 34/37 →
  Amex; else "Card". First card becomes default; removing the default makes the next card default.
- **R34 — Feature gating** (`applyCountryFeatureGating`): no BizPlus → hide Credits card, BizPlus tab,
  Storage/Workspace tabs (force Storage); no Rewards → hide Rewards card and tab.
- **R35 — Bluetooth unlock** (hidden): modal states idle → connecting ("Hold your phone near the
  padlock") → after 1.6 s unlocked ("Door unlocked. It will re-lock automatically in a few minutes."),
  sets `lastAccess = 'Just now'`. Text names an **igloohome** padlock.

---

## 5. Constants

| Name | Value | Where |
|---|---|---|
| GST rate | 0.09 (on cash part of a booking and on package price) | `GST_RATE` |
| Aircon extension rate | S$40 / hour, prorated per 15 min | `AIRCON_RATE` |
| Standard hours | Mon–Fri 09:00–19:00, Sat 09:00–14:00, Sun none | `isHourSurcharged` |
| Same-day booking window | 09:00–16:00 device time | `BOOKING_CUTOFF_START_HOUR`, `BOOKING_CUTOFF_END_HOUR` |
| Default start on a future day | 09:00 | `DEFAULT_FUTURE_DAY_START_HOUR` |
| Slider range / grid | 0–24 h / 15 min | `SLOT_START`, `SLOT_END`, `QUARTER_WIDTH` |
| Min duration | meeting room 1 h, event space 2 h | `minDuration` |
| Refund / change cutoff | 12 h | `evaluateRefund` |
| Demo "now" hour | 9 | `DEMO_NOW_HOUR` |
| Event space | S$175/h, cleaning S$50 weekday / S$100 Sat–Sun, deposit S$500 | `RESOURCES` |
| Meeting rooms | S$20 (4 pax), S$40 (8 pax), S$50 (10 pax) per hour | `RESOURCES` |
| Packages | 200 cr S$190 1 mo; 500 cr S$450 3 mo (Best value); 1000 cr S$850 6 mo | `buySheet`, `PACKAGE_VALIDITY_MONTHS` |
| Refund Credits validity | booking date + 1 month − 1 day | `refundLotExpiryFor` |
| Lot "Expiring soon" | ≤ 10 days left | `render` |
| Reward tiers | 1000→S$10, 2000→S$20, 5000→S$50 | `REWARD_REDEEMABLES` |
| Points earning (text) | 1 pt per S$1 of storage bill | `rewards_info_html` |
| Insurance Basic plan | SG 2,000 / 8; MY 6,000 / 25; KR 2,000,000 / 9,000 | `INSURANCE_INFO` |
| Countries | SG (S$, BizPlus, Rewards), MY (RM, Rewards), KR (₩) | `PERSONA_COUNTRIES` |
| Languages | en, ms, ko | `LANGUAGES` |
| E-wallets | SG PayLah!; MY Touch 'n Go, GrabPay, RazorPay; KR PayApp | `WALLET_INFO` |
| BizPlus sites | Bizplus Commonwealth, Bizplus Boon Keng | `renderResourceList` |
| Toast duration | 3.2 s | `showToast` |

---

## 6. Stubs, mocks and demo shortcuts

- No backend. All data in `PERSONAS`, `RESOURCES`, `SITES`; changes live only until reload.
- "Switch customer" persona sheet and country switcher (demo only).
- Log in / Sign up do nothing; no OTP anywhere, including PIN reveal.
- **Stripe is faked** inside the app: a card form pre-filled with 4242 4242 4242 4242, 12/29, 123;
  900 ms delay; always succeeds.
- Add Card collects full card number and CVC in the app; nothing is tokenised.
- E-wallet linking is one tap.
- Recurring payment switches only flip a flag and show a note; no charge ever runs.
- Bills payment ignores the typed amount and marks everything fully paid.
- Invoice "Download" → toast only. Navigate / Call → toasts. WhatsApp → mock chat.
- "Use reward", "Book another seat", "Share lock access", "Rent another" → "coming soon" or hidden.
- Delete account → toast only.
- Bluetooth unlock: hidden; 1.6 s timer.
- Calendar months hard-coded (Sep–Oct 2026); "today" = device date; "now" for status and refunds =
  09:00; "now" for the slider and same-day cutoff = device clock. These two clocks disagree.
- Booked hours are the same fixed hours on every date.
- Static labels: `monthlyResetLabel`, `paidThroughLabel`, `dueDateLabel`, `nextBillingLabel` are text,
  not dates; nothing rolls over.
- Seeded credit activity amounts (−8 for "Meeting Room — 1 hr", −15 for "2 hrs", −100 for "2 hrs",
  −175 for "Full day") **do not follow** the price rules (R15); they are decoration.
- Explore section and Select-a-location screen are hidden; Promotions and Announcements are dummy.

---

## 7. Comparison with the demo spec

Legend: **SAME**, **DIFFERENT** (artifact vs demo), **ONLY IN ARTIFACT**, **ONLY IN DEMO**.

### 7.1 Sign-in, identity, account (demo 01)

| Topic | Verdict | Artifact | Demo |
|---|---|---|---|
| Sign-in | DIFFERENT | No sign-in at all; Welcome buttons enter the app | Email-only login, no password, JWT 30 days (01:136-192); flagged as account takeover (01:188-192). Our S0 = email + one-time code (cross-repo §4) |
| Account holder | DIFFERENT | One **company** per account with one contact person | `Customer` = one person keyed by e-mail, optional `businessName`, `uenNumber` (01:85-103) |
| Edit profile | DIFFERENT | Name/e-mail locked, phone editable | `/me/login` body may overwrite names/phone; no profile endpoint (01:136-146) |
| Delete account | ONLY IN ARTIFACT | "Deletion requested", staff follow up by e-mail | Not present; our open decision 6 (cross-repo §4) |
| Language / country | ONLY IN ARTIFACT | en/ms/ko, SG/MY/KR | SG only; app headers `Accept-Language`/`Country-Code` ignored (01:43-47) |
| Gate / keypad PIN | DIFFERENT | 4-digit PIN **per unit**, shown in app, "OTP before showing" (not built) | `SiteLinkTenantLink.accessCode` = one 6-digit gate code **per tenant per site** (01:118, 04:487); not returned to the app |

### 7.2 Storage units and My Spaces (demo 03, 04)

| Topic | Verdict | Artifact | Demo |
|---|---|---|---|
| My Spaces Storage tab | SAME idea | Units with rent, paid-through, balance | `activeRentals` with SiteLink balance `{chargeBalance, paidThruDate, totalDue}` (04:379-398) |
| Unit status pills | ONLY IN ARTIFACT | Paid / Overdue / **Overlocked**, Recurring / Non-recurring | Only balance numbers; no overlock flag |
| Unit type | DIFFERENT | `aircon` / `non_aircon` / **wine** (+ wine cases, deck); access type drive-up / walk-in / upper / lower locker | `Unit.climate` bool + StorageType/UnitSize (03:160, 03:108-143) |
| Storage insurance | DIFFERENT | Fixed "Basic plan" S$2,000 cover S$8/mo on every unit | Insurance always 0; `InsuranceCoverageID -999` (03:233, 04:563) |
| Recurring / autopay | ONLY IN ARTIFACT | Per-unit switch, "Next charge on … to …" | No autopay; Checkout only saves the card (`setup_future_usage`) (05:337-339) |
| Bluetooth unlock (igloohome) | ONLY IN ARTIFACT (hidden) | Mock modal | Not in demo |
| Workspace tab | DIFFERENT | Seats with title, PIN, rent, recurring, invoices | SiteLink-based workspace leases (04:629-680) **and** Cowork licences via `/me/cowork` (10:975-1049) |
| Reservations / viewings in My Spaces | ONLY IN DEMO | — | `reservations`, `viewingAppointments` lists (04:383-389) |

### 7.3 Bills and payments (demo 05, 10)

| Topic | Verdict | Artifact | Demo |
|---|---|---|---|
| Pay several storage units in one go | SAME | Tick units, one payment | `items[] {leaseId, amount}` one Checkout (05:205-213) |
| Partial amount | DIFFERENT | Any typed amount, no checks; unit marked fully paid | `0 < amount ≤ amountDue + 0.01`, server-checked (05:305-309) |
| Card entry | DIFFERENT | In-app card form (fake Stripe) + in-app Add Card | Stripe-hosted Checkout only; "no card data ever touches the service" (05:18-28, 05:62-65) |
| Saved cards / "Recurring" card flag | ONLY IN ARTIFACT | Card list, default card, Remove | Not in demo (only Stripe's own saved card) |
| E-wallets (PayLah!, TNG, GrabPay, RazorPay, PayApp) | ONLY IN ARTIFACT | One-tap link | Not in demo; only 4 approved Stripe flows (05:41-60) |
| Use reward on a bill | DIFFERENT | Link "coming soon" | Apply voucher to a unit = status change only, no billing effect (11:339-354) |
| Workspace invoices list + detail | SAME idea | Number, period, issued, due, lines, total, balance | `/me/cowork.invoices[]` (10:1008-1016, 10:1039-1042) |
| Invoice number format | SAME | `INV-YYMM-NNN` | `{prefix}-{YYMM}-{NNN}` (10:1226-1227) |
| Invoice statuses | DIFFERENT | overdue / paid | paid / overdue / partial / open (10:1039-1040) |
| Seat billing status | DIFFERENT | overdue / current | overdue / due / paid (10:1038) |
| Workspace "recurring" | DIFFERENT | Switch per seat | Always `false` (10:1037) |
| Pay selected invoices | SAME idea | Tick overdue invoices, editable amount | `POST /me/cowork/invoices/checkout`, amount ≤ balance, 422 codes (10:1051-1079, 10:1722-1731) |
| Upcoming charges (waiting) | SAME | Read-only list + "will appear on your next monthly invoice" | `charges[]` = waiting charges (10:1045-1046) |
| Payment history | SAME | Date, method, reference | `payments[]` with `methodLabel`, `invoiceNumbers` (10:1017-1021) |
| Invoice download | ONLY IN ARTIFACT (mock) | Button | Not built |
| Sample issue/due days | DIFFERENT | Issued 25th, due 1st | `dueDays` 7 default (10:327, 10:349) |

### 7.4 BizPlus facility booking (demo 07)

| Topic | Verdict | Artifact | Demo |
|---|---|---|---|
| Rooms and rates | SAME | MR 20 / 40 / 50, ES 175 + 500 deposit | Seed MR1-L1 20, MR2-L1 40, MR1-L2 50, ES-L1 175 + 500 (07:2222) |
| Standard hours / aircon surcharge | SAME | Mon–Fri 9–19, Sat 9–14, Sun all day; S$40/h per 15 min | Same values (07:2155-2163); per-type config (07:160-161) |
| Cleaning fee | SAME | 50 weekday / 100 weekend, flat | Same (07:2156, 07:2165) |
| Deposit | SAME | Card only, no GST, never credits | Same (07:204, 07:1179) |
| GST only on cash part | SAME | `(subtotal − credits) × 9%` | Same, decision Q4, finance to confirm (07:1172-1173, 07:1975) |
| Rounding | DIFFERENT | No rounding (display only) | `round2` on every line (07:1041-1050, 07:1128) |
| Bookable hours | DIFFERENT | 24/7 (00–24) | OPEN rows, seed 08:00–22:00 daily (07:238-252, 07:2222) |
| Slot grid / length | DIFFERENT | Start on 15 min; **length whole hours only** | Start and length on the 15-min grid; min/max duration per type (07:148-150, 07:1233-1234); e.g. 18:45–20:00 allowed (07:2227) |
| Min duration | SAME | MR 1 h, ES 2 h | ES min 2 h (07:2234) |
| Max advance | DIFFERENT | 2 hard-coded months | `maxAdvanceDays` 90 (07:152) |
| Same-day window | SAME | Today only between 09:00 and 16:00; extensions exempt | Same (07:159, 07:1736-1738, 07:2182-2183) |
| Earliest start today | SAME | Now rounded up to 15 min | `roundUpToSlot` / `earliestSelectableStart` (07:1739-1744, 07:2186-2187) |
| Default start other day | SAME | 09:00 | `futureDayDefault "09:00"` (07:1743-1744) |
| Conflict check | DIFFERENT | Whole-hour buckets | Exact intervals + buffer; Postgres EXCLUDE (07:34-36, 07:1070-1086) |
| Payment hold | ONLY IN DEMO | — | PENDING_PAYMENT, 33-min hold, late-payment refund (07:1357-1359, 07:1382-1399) |
| Promo codes, add-on services, invitees, member rate | ONLY IN DEMO | — | (07:1188-1223, 07:1137-1148, 07:1328-1329) |
| Reschedule | DIFFERENT | Free, ≥ 12 h, **length may change**, no re-pricing | Free, ≥ 12 h (BizPlus), **same length only** (`DURATION_CHANGED`), no re-pricing (07:1439-1467) |
| Extend | SAME | Only while ongoing; added time only; no deposit/cleaning | `canExtend = ongoing` for BizPlus; FLAT charges and deposit never on extension (07:1757, 07:1469-1495) |
| Cancel while ongoing | SAME | Not allowed | `canCancel = upcoming` (07:1758, 07:2193) |
| 12-hour refund rule | SAME | `hoursUntil ≥ 12` eligible | `refundWindow` ≥ 720 min, exactly 12 h eligible (07:1732-1733) |
| Refund to card | SAME | Never | BIZPLUS_CREDIT: never to card (07:119, 07:1650) |
| Status model | DIFFERENT | active / past / cancelled, ongoing by fixed hour 9 | PENDING / UPCOMING / ONGOING / PASTBOOKING / CANCELED / EXPIRED from the server clock (07:1801-1811) |
| Booking reference / passcode | ONLY IN DEMO | — | `ESB-xxxxxx`, 6-digit passcode (07:291-292) |
| Aircon activation by WhatsApp; access card pickup | ONLY IN ARTIFACT | Customer must message BizPlus team | Not in demo |
| Booking e-mails | ONLY IN DEMO (not built) | — | Phase 2 (07:1930-1933) |

### 7.5 BizPlus credits (demo 08)

| Topic | Verdict | Artifact | Demo |
|---|---|---|---|
| 1 credit = S$1 | SAME | | (08:14) |
| Plans | SAME (+1) | Monthly, Lump sum | NONE, MONTHLY, LUMPSUM (08:32-36) |
| Tier names | DIFFERENT | Seeds 150, 20, 50, 30 /mo | Basic 20, Standard 50, Premium 150, else Custom (08:1239) |
| Carry-forward preview | SAME | `min(remaining, cap)` | `projected = enabled ? min(remaining, cap) : 0` (08:389-390) |
| Month that pays | DIFFERENT | Calendar tab index (this / next) | Booking's start date month, site-local; "never the client's calendar tab" (08:1415, 08:897) |
| Wallet scope | DIFFERENT | One wallet per customer (company) | One wallet per customer **per site** (08:19-21) |
| Draw order | SAME core | Soonest expiry first, lump sum last | Same + LEGACY rank, tie-break createdAt/id (08:879-884, 08:1413) |
| Packages | SAME prices | 200/190/1 mo, 500/450/3 mo best, 1000/850/6 mo | Seed P200/P500/P1000 same (08:211-213) |
| Package lots | DIFFERENT | All packages merge into **one lot**, expiry overwritten | Each package its own bucket ("lots never merge", D1) (08:1412) |
| Package expiry date | DIFFERENT (edge) | JS month overflow (31 Jan + 1 → 3 Mar) | Clamped to month end (08:857-859) |
| Package inside a booking checkout | DIFFERENT | **Not allowed**: leave the booking, pay separately | Allowed, one Stripe payment, D12 (08:1176-1200, 08:1423) |
| Complimentary / legacy buckets, admin adjustments | ONLY IN DEMO | — | (08:23-30, 08:1276-1299) |
| Expiry of credits | DIFFERENT | Never enforced (expired lot still spendable) | Lazy upkeep + daily job expire buckets (08:962-1003) |
| Month-end rollover | ONLY IN DEMO | Only a preview | `planRollover` (08:1319-1355) |
| Refund, credits only | SAME (+gap) | Back to original buckets | Same; expired bucket → new Refund Credits (D9) (08:1092-1096, 08:1420) |
| Refund, any cash | DIFFERENT | `credits + round(cash **incl. GST**)` | `credits + round(cash **before GST**)`, D5 open for finance (08:1085, 08:1416) |
| Refund Credits expiry | SAME | 1 month from booking date (last day = date + 1 mo − 1) | expires at 00:00 on booking date + 1 month (08:860, 08:1427) |
| Refund Credits buckets | DIFFERENT | One shared refund lot, expiry overwritten | New REFUND bucket per cancelled booking (08:1061-1064) |
| "Expiring soon" ≤ 10 days | ONLY IN ARTIFACT | Tag | Demo gives `daysLeft` only (08:396-398) |
| Credits ledger | DIFFERENT | Free-text activity list | `CreditLedgerEntry` per bucket, kinds, idempotency keys (08:160-178, 08:1301-1317) |

### 7.6 Rewards (demo 11)

| Topic | Verdict | Artifact | Demo |
|---|---|---|---|
| Earning | DIFFERENT | Text "1 pt per S$1 of storage bill"; nothing coded | No earning engine; only 2,000 welcome bonus at first login (11:18, 11:472-483) |
| Redeem tiers | DIFFERENT | S$10 / 20 / 50 for 1,000 / 2,000 / 5,000 pts | Seeds S$10 / 20 / 50 for 1,000 / 1,800 / 4,000 (11:667) |
| Voucher | DIFFERENT | Label "S$10 · <date>" | Code `RWD-XXXXXXXX`, statuses REDEEMED / APPLIED / EXPIRED (11:83-106) |
| Use voucher | DIFFERENT | On a storage bill (coming soon) | Apply to a unit, no billing effect (11:339-354) |
| Points expiry | ONLY IN ARTIFACT | Chip "<pts> pts expire on <date>" | No expiry (11:89) |
| Earned this month | SAME | Shown | `earnedThisMonth`, SG month start (11:294-313) |
| Rewards per country | ONLY IN ARTIFACT | Off in Korea | — |

### 7.7 Admin / CMS (demo 11, 12)

| Topic | Verdict | Artifact | Demo |
|---|---|---|---|
| "Credits are managed by your company admin via the BizPlus Credits portal" | DIFFERENT | Implies a **customer-side** company admin | Credits managed by ExtraSpace staff in the BizPlus dashboard (08:45) |
| Promotions / announcements / referral | ONLY IN ARTIFACT (dummy) | Home + Welcome cards | Demo has blogs and FAQs only (11:356-398); `Promotion` table unused (11:23) |

---

## 8. Corrections to the earlier rendered-page summary

| Rendered summary said | Source shows |
|---|---|
| Monthly allowance 150, resets on the 1st | Only persona p1. Others: 20, 50, 30, 0, and lump-sum plans 500 / 1000. "Resets" is a static label; pool expiry for draw order = 1st of next month |
| Carry-forward cap 30 | p1 only; p4 cap 20, p7 cap 10, p2 none |
| Room 1 h = 8 credits / 2 h = 15 credits | **Wrong.** These are decorative seeded history rows. Real rule: credits = S$ of the subtotal (1:1). MR1-L1 1 h = S$20 = 20 credits |
| S$50/hr vs "from S$20/hr" conflict | Not a conflict. S$50 is the static placeholder of the detail page ("Room 15A") before render; rooms cost 20 / 40 / 50 / 175 and "From S$20" = cheapest meeting room |
| Free cancellation ≥ 12 h | Correct, but the "refund" is **credits only**, never card; cash is converted incl. GST; inside 12 h nothing comes back; ongoing bookings can't be cancelled |
| Refund credits valid 1 month | Correct, counted from the **booking date**, not the cancel date |
| PIN reveal after one-time code | **Not built.** The text says so, the code shows the PIN on tap |
| igloohome Bluetooth unlock | Exists only as a **hidden** button + mock modal |
| Stripe cards with Recurring toggle | The card form is **in-app** (full number + CVC); "Recurring" is a checkbox per card plus a separate per-unit recurring switch; no charge ever runs |
| Delete account | Only a "deletion requested" toast |
| 1 point per S$1 on storage bills | Text only; no points are added on payment |
| GST 9 % not on credits or deposit | Correct; GST is also charged on credit packages |

Missed by the rendered view: country gating (SG/MY/KR), Welcome page, Overlocked status, overdue
routing (R27), editable partial bill amounts, workspace Invoices / Upcoming Charges / History, invoice
sheet, extend / change / cancel flows, whole-hour length rule, 24/7 slider, same-day 09:00–16:00
cutoff, aircon S$40/h prorated per 15 min, cleaning fee, deposit, per-bucket draw list, "Leave this
booking?" modal for packages, e-wallets, insurance plan, 3 languages.

---

## 9. Conflicts and open questions (for the owner / client)

1. **Sign-in.** The prototype has none. Our S0 decision is e-mail + one-time code. Confirm the
   Welcome → Log in / Sign up screens map to that.
2. **Company vs person.** The prototype treats the account as a company with one contact. Demo and
   S0 treat it as a person (e-mail). Who owns credits and bills when a company has several staff?
3. **PIN.** Per unit (artifact) or SiteLink's per-tenant gate code (demo)? Do we really require a
   one-time code before showing it?
4. **Booking length.** Whole hours only (artifact) or 15-minute steps (demo)? Bookable 24/7
   (artifact) or opening hours 08:00–22:00 (demo seed)? The facility page also says "Open until 5:30 PM".
5. **Standard hours text.** Mon–Fri 9am–7pm (UI) vs code comment "9am–6pm + 6–7pm grace". Which is
   the business rule?
6. **Public holidays.** The cleaning fee label says "Weekend / public holiday rate"; no holiday list
   exists in either source.
7. **Reschedule length.** Artifact lets the length change for free; demo forbids it. A longer slot for
   free is a loophole. Recommend the demo rule.
8. **Refund of GST.** Artifact converts cash **including** GST to credits; demo excludes GST (D5,
   pending finance). Needs a finance answer.
9. **Packages during a booking.** Artifact forces a separate purchase; demo allows one combined
   payment (D12). Which one?
10. **One lot vs many lots** for packages and refund credits. Recommend the demo (separate buckets);
    merging loses earlier expiry dates.
11. **Recurring / autopay.** The artifact shows per-unit recurring payment and per-card "Recurring".
    Our rules allow only Stripe-hosted Checkout; off-session charging is a **new payment flow and needs
    business approval** (cms.md house rule 3).
12. **In-app card form.** Not allowed by our rules (no card data). Card management must be Stripe's
    own saved cards. Confirm the client accepts this.
13. **E-wallets (PayLah! etc.).** Out of scope for release 1 unless the owner adds them.
14. **Storage insurance.** Artifact shows a fixed Basic plan (S$2,000 / S$8). The admin artifact uses
    a rate table by rent (see `03-es-admin.md`). The demo has no insurance. Where does the real
    insurance data come from (SiteLink insurance coverage?)
15. **Overlocked status.** Where does it come from (SiteLink)? What may an overlocked customer do?
16. **Points earning.** 1 point per S$1 of storage bill: on which amount (incl. GST?), when (on
    SiteLink payment?), and do points expire (the chip suggests yes)? Demo has only a welcome bonus.
17. **Reward tiers.** 1000/2000/5000 (artifact) vs 1000/1800/4000 (demo seed).
18. **Use reward on a bill.** Should a voucher reduce a storage bill (SiteLink posting?) — demo says no
    billing effect.
19. **Partial payments.** Allowed? Artifact allows any amount; demo allows partial ≤ balance.
20. **Aircon extension activation** by WhatsApp and access card pickup: should the system notify the
    BizPlus team automatically instead?
21. **Delete account:** request only (staff follow-up) or real deletion? (Store rule, open decision 6.)
22. **"Company admin via the BizPlus Credits portal"**: is there a customer-side company admin role?
    Not in the demo.
23. **Workspace seat vs invoice status** are not linked in the prototype (paying invoices leaves the
    seat overdue). Demo derives seat status from invoices (10:1717-1719) — keep the demo rule.
