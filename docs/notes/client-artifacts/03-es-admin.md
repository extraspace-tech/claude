# Client artifact: "ExtraSpace Admin" (admin console prototype)

Read on 2026-10-09 from the saved raw HTML/JS
(`tool-results/artifact-29820823-1791530283-dd77.html`, 73 KB). The whole file was read (markup,
styles skimmed, all JavaScript). Everything below comes from the code.

The file was written by the client. It is a **prototype**: no server, data hard-coded, SiteLink
mocked. Only two pages work: **Customers** and **Leases**. Treat everything here as a statement of
what the client wants, not as a contract.

Citations: artifact code by **function name or a short searchable snippet**; demo spec as `NN:line`
= `../Backend Demo/backend/.claude/backend-spec/features/NN-*.md:line`. The artifact's seed data holds
customer e-mails and phone numbers that look real (personal and staff addresses). None are copied
here; they are shown as `<sample person>`.

---

## 1. Overview

- Dark-themed self-storage admin console "ExtraSpace · Self Storage", "cloned from a product
  screenshot". Signed-in user shown as "Platform Admin". A Light / Dark / System theme toggle exists
  but does nothing.
- Left nav (same groups as the demo's admin):
  - **Dashboard**
  - **Platform**: Sites, Storage Types, Unit Sizes, Units
  - **Tenants**: Customers, Leases, Reservations, Viewing Appointments
- Only **Customers** and **Leases** are wired (`setPage`: `known = page === 'customers' || page ===
  'leases'`). Every other page shows "This section isn't wired up in this prototype yet." The app
  opens on **Leases** (`setPage('leases')`).
- New ideas compared with the demo admin:
  1. Leases filtered by **country** and **facility** (Singapore, Korea, Malaysia; 24 facilities).
  2. **"Add Customer from Sitelink"**: staff type a customer's e-mail and pull their new storage
     lease from SiteLink on demand instead of waiting for the sync.
  3. **"Refresh this site" / "Refresh all sites"** buttons.
  4. Per lease, staff **generate a License Agreement and a Storage Insurance application** as
     documents and capture the **customer's handwritten signature** on screen (finger / Apple
     Pencil). A lease is "Active" only when both are signed.
- No sign-in, no RBAC, no audit log in the prototype.

---

## 2. Screens & flows

### 2.1 Customers (`renderCustomerRows`, `renderCustomerDetails`)

- Table: Email, First Name, Last Name, Phone, City, chevron. Empty values show "—".
- Search box and "New" button: present, **not wired**.
- Click a row → modal "Customer Details" with sub-title = display name
  (`custDisplayName`: "First Last", or the part of the e-mail before "@" when both are blank).
  - Email: **disabled**, hint "Email can't be changed here".
  - First Name, Last Name, Phone, City: editable (trimmed on save, no other validation).
  - "Save Changes" → updates the row, toast "Customer details saved".
- Seed: 7 customers (`<sample person>` × 7). Several have only an e-mail (names blank), matching how
  customers created by e-mail login look in the demo.

### 2.2 Leases page (`renderLeaseRows`)

- Filters:
  - Country chips: All Countries, Singapore, Korea, Malaysia (`renderCountryFilter`). Picking a
    country resets the facility to "All Facilities".
  - Facility dropdown grouped by country (`renderFacilitySelect`), only facilities of the chosen
    country.
  - Filter logic (`visibleLeases`): a specific facility wins; else country; else all.
- Toolbar: "Search leases..." (not wired), **Add**, **Refresh this site**, **Refresh all sites**.
- Table: Customer (e-mail), Unit, Status badge, Monthly Rent (with currency), Start Date, chevron.
  Empty: "No leases recorded for this facility yet."
- Status (`leaseStatus`): **Active** (green) only if the agreement **and** the insurance form are both
  signed; otherwise **Pending** (amber).

### 2.3 Add Customer from Sitelink (`openAddLeaseModal`)

1. Modal "Add Customer from Sitelink", field "Customer Email", hint "Sitelink only syncs hourly — try
   newcustomer1@example.com …".
2. "↻ Refresh from Sitelink" → button shows "Checking Sitelink…", 600 ms → lookup by e-mail
   (`sitelinkLookup`: trimmed, lower-cased, exact match in a mock table of 5 records).
3. Found → card "<name> · <facility>, <country>" with Unit, Monthly Rent, Start Date; **Add** enabled.
   Not found → "No storage details found — Sitelink hasn't synced this customer yet — it refreshes
   hourly. Try again shortly, or double-check the email." Add stays disabled.
4. Typing in the e-mail field clears the result and disables Add again.
5. **Add** → new lease row `{facility, customerEmail (lower-case), customerName, unit, rate, startDate,
   agreement unsigned, insurance unsigned}`, the filters jump to that country + facility, toast
   "Customer added — pending agreement & insurance".
   - No duplicate check: adding the same e-mail twice creates two identical leases.

### 2.4 Refresh buttons

- **Refresh this site**: needs a specific facility, else toast "Pick a specific facility to refresh just
  that site." → toast "Refreshing <facility>…" → 700 ms → "<facility> is up to date."
- **Refresh all sites**: toast "Refreshing all 24 sites from Sitelink…" → 1.2 s → "All sites refreshed
  — this used a full round of Sitelink API calls, so use it sparingly."
- Both are mocks; nothing changes.

### 2.5 Lease menu and documents (`renderLeaseMenu`, `renderLeaseDocument`)

- Click a lease → modal titled with the customer name, sub-title "<facility> · Unit <unit> · <e-mail>".
  Two options, each with a badge "✓ Signed <date time>" or "Not yet signed":
  - **Generate Agreement File** → "Rental Agreement" document view.
  - **Generate Insurance File** → "Insurance Certificate" document view.
- Document view: back, title, close; the paper (§4.4, §4.5) with a "SAMPLE" watermark; footer:
  - unsigned → **Sign Document**;
  - signed → "✓ Signed <date time>" + **Sign Again** (re-signing is allowed and overwrites).

### 2.6 Signing (`openSigning`)

- Full-screen "Sign Rental Agreement" / "Sign Insurance Certificate", hint "Use your finger or Apple
  Pencil to sign in the box below", canvas with a "Sign here" placeholder.
- Drawing: pointer events; stroke width = pen pressure × 4.5 clamped to 1.3–4.5 for a pen, 2.6 for
  finger/mouse; ink `#17213a`; canvas sized to device pixel ratio.
- **Clear** wipes the canvas and disables Confirm. **Confirm Signature** is enabled after the first
  stroke. Confirm → `signature = canvas PNG data URL`, `signed = true`, `signedAt = now`; lease table
  re-renders (status may become Active); back to the document; toast "Agreement signed" /
  "Insurance certificate signed".
- Close (X) or Escape → back to the document without saving.
- This is an **in-person, staff-device** signature (an iPad at the counter), not a customer self-service
  e-signature.

### 2.7 Other plumbing

- Modal backdrop click closes (except the signing screen); Escape closes the modal, or leaves the
  signing screen. Toast 2.4 s.
- Dates are formatted `en-SG` ("dd Mon yyyy, hh:mm").

---

## 3. Data model (as used by the prototype)

### 3.1 Customer

`{id, email, firstName, lastName, phone, city}`. E-mail is read-only in the UI.

### 3.2 Facility (`facilities[]`, "sourced from Sites.xlsx (Loc / Name / State / Currency)")

`{code ('L001'…), name (legal entity name), country, currency ('$' | '₩' | 'RM'), insCode (insurance
form code), address?, uen?, regOffice?}`.

- Singapore (12): L001 Jurong (IMM), L002 Extra Space Pte Ltd (BKR, 301 Boon Keng Road), L003 Eunos
  Link (ELK), L004 West Coast (WC), L005 Marymount (MMR), L008 Kallang Way (KWY), L017 Woodlands
  (WDL), L018 AMK (AMK — the only one with UEN and registered office), L022 Toa Payoh (TPY), L025
  Hillview (HVW, no address), L029 Commonwealth (CMW), L030 Tai Seng (TS).
- Korea (8): L006 Yangjae, L011 Bundang, L013 Gasan, L019 Apgujeong, L021 Yeongdeungpo, L023 Yongsan,
  L024 Banpo, L031 Yangcheon (no addresses).
- Malaysia (4): L007 Extra Space Malaysia Sdn Bhd, L009 Segambut, L010 S51A, L026 Kota Damansara (no
  addresses).
- Notes in the code: "Bizplus" sites from Sites.xlsx are **left out** ("co-working credit spaces, not
  self-storage sites"); SG addresses and insurance codes come from "Customer Storage Insurance
  Form.xlsx"; that workbook also lists **"Extra Space Toh Guan Pte Ltd" (TGR)**, which is not in the
  24-site list — "flagged, not reconciled".
- These codes (`L001`…) look like SiteLink location codes. Treat them as useful reference data for our
  `Site` seed, but confirm with the client.

### 3.3 Lease

`{id ('l1'…), facility (code), customerEmail, customerName, unit (unit name), rate (monthly rent in
local currency), startDate (text 'dd Mon yyyy'), agreement: Doc, insurance: Doc}`.

`Doc = {signed: bool, signedAt: ISO datetime | Date | null, signature: PNG data URL | null}`.

Status is derived (§4.1), not stored. 26 seeded leases across SG / KR / MY.

### 3.4 Mock SiteLink record (`sitelinkDB`)

Keyed by lower-case e-mail: `{customerName, facility, unit, rate, startDate}`. 5 records.

---

## 4. Calculations & rules

### 4.1 Lease status

`status = (agreement.signed AND insurance.signed) ? "Active" : "Pending"`.

### 4.2 Unit type label (`unitSizeLabel`, used on the agreement)

- Singapore only: unit name starts with **W** → "Wine Storage"; starts with **A** → "Aircon Storage";
  otherwise "Standard Storage" ("Prefix meanings confirmed for Singapore only").
- Malaysia / Korea: always "Storage Unit" (their prefixes A, G, H are unknown).

### 4.3 Money format (`money`)

`amount.toLocaleString('en-US')` with a prefix: `₩` for Korea, `RM` for Malaysia, else `$`. No fixed
decimals (e.g. "$144", "$2.5").

### 4.4 License Agreement paper (`buildAgreementPaper`)

| Part | Content / rule |
|---|---|
| Badge | "Standard Self Storage License Agreement · May 2026 template" |
| Number | `AGR-2026-` + lease number padded to 4 digits (l7 → `AGR-2026-0007`) |
| Parties | Owner line: with UEN → "<entity>, incorporated in Singapore (UEN …), registered office at …"; SG with address → "<entity>, registered office at <address>"; else the entity name. "("Facility Owner") and <customer> ("Storer") · <today>" |
| I. Storer Details | Name, Email, Contact No. = "On file with Sitelink" |
| III. Storage Details | Facility Location (address, or "<entity>, <country>"), Storage Unit No., Unit Type (§4.2), Storage Plan Period "From <start>, renews monthly thereafter (14 days' written notice to terminate)" |
| IV. Fee Schedule | **Security Deposit = 1 × monthly rent**; Monthly Storage Fee = rent "per month, inclusive of GST where applicable"; **Late Payment Fee = round(25 × currency factor) per 10 days overdue** (SG $25, MY RM80, KR ₩27,500) |
| Clause | Use for permitted goods, pay by due date, follow site rules; renews monthly; either party may end it on **14 days' written notice**; "not the complete License Agreement and is not binding" |
| Date | "Date of this Agreement: <today>" — always today, not the signing date |
| Signature | Image + name + "Signed <date>", or "✓ Signed electronically" (seeded signed docs without an image), or an empty line "Customer signature" |

(Section II is missing in the numbering: I, III, IV.)

### 4.5 Insurance application paper (`buildInsurancePaper`, `insuranceForLease`)

| Part | Content / rule |
|---|---|
| Badge / title | "Customer Storage Insurance Application Form" |
| Number | `CS-` + lease number padded to 4 + `-` + facility insurance code (`CS-0012-TS`); `XX` if missing |
| Meta | "Extra Space Singapore Holdings Pte Ltd · Policyholder: <customer> · <today>" |
| Fields | Name, Contact Details and Postal Address = "On file with Sitelink", Storage Location, Unit No., Coverage Effective Date = lease start, Sum Insured, Premium Per Month "(premium excludes GST)" |
| Rate table | 11 tiers, active tier highlighted (below) |
| Clause | Excludes cash, deeds, jewellery and watches, motor vehicles, boats, flammable or corrosive goods; excess "starting at" `round(250 × factor)` per claim (higher for named perils: landslip, subsidence, weather and water damage); claims on **replacement value for goods under 10 years old, indemnity value after**; SG: "Underwritten by MSIG Insurance (Singapore) Pte Ltd, under the group policy held by Storage Ventures Asia Pte Ltd and Extra Space Singapore Holdings Pte Ltd."; MY/KR: local arrangement wording, figures "scaled from the real Singapore rate table for prototyping" |

**Sum insured and premium table (SGD, "real" per the code comment, from the client's workbook):**

| idx | Sum insured | Premium / month |
|---|---|---|
| 0 | 1,000 | 2 |
| 1 | 5,000 | 4 |
| 2 | 10,000 | 6 |
| 3 | 15,000 | 8 |
| 4 | 20,000 | 10 |
| 5 | 25,000 | 14 |
| 6 | 30,000 | 18 |
| 7 | 35,000 | 22 |
| 8 | 40,000 | 24 |
| 9 | 45,000 | 30 |
| 10 | 50,000 | 40 |

**Tier picked by the prototype** (an invented rule, not from the workbook):
`rentSgd = rent / factor`; `< 120` → idx 1 (5,000 / 4); `< 180` → idx 2; `< 240` → idx 3; `< 300` →
idx 5; `< 360` → idx 7; else idx 9. Then `sum = round(tier.sum × factor)`, `premium =
round(tier.premium × factor × 100) / 100`, `excess = round(250 × factor)`.

**Currency factor** (`currencyFactor`, "rough"): KRW 1,100; RM 3.2; SGD 1.

In real life the customer chooses the cover; the prototype guesses it from the rent.

---

## 5. Constants

| Name | Value |
|---|---|
| Lease status rule | Active iff agreement + insurance signed |
| Agreement template | "May 2026 template", number `AGR-2026-NNNN` |
| Notice period | 14 days' written notice; renews monthly |
| Security deposit | 1 month's rent |
| Late payment fee | S$25 per 10 days overdue (scaled for MY/KR) |
| Insurance number | `CS-NNNN-<insCode>` |
| Insurance excess | from S$250 per claim |
| Insurer (SG) | MSIG Insurance (Singapore) Pte Ltd; group policy of Storage Ventures Asia Pte Ltd and Extra Space Singapore Holdings Pte Ltd |
| Rate table | 11 tiers, §4.5 |
| Currency factors | KRW 1,100; RM 3.2 |
| SiteLink sync stated | "hourly" |
| Mock delays | lookup 600 ms; refresh site 700 ms; refresh all 1.2 s |
| Toast | 2.4 s |

---

## 6. Stubs, mocks and demo shortcuts

- Pages not wired: Dashboard, Sites, Storage Types, Unit Sizes, Units, Reservations, Viewing
  Appointments.
- Customers search and New; Leases search: not wired.
- SiteLink lookup and both refresh buttons are mocks.
- Theme toggle and profile menu do nothing.
- Signature images live only in memory; no PDF is produced; "Generate … File" just renders HTML.
- Papers are marked "SAMPLE" and say they are excerpts, "not binding".
- No permission checks, no audit, no admin login.

---

## 7. Comparison with the demo spec

Legend: **SAME**, **DIFFERENT** (artifact vs demo), **ONLY IN ARTIFACT**, **ONLY IN DEMO**.

| Topic | Verdict | Artifact | Demo |
|---|---|---|---|
| Admin nav groups | SAME | Dashboard; Platform: Sites, Storage Types, Unit Sizes, Units; Tenants: Customers, Leases, Reservations, Viewing Appointments | Same resources and groups in the generic registry (12:985-1156); Dashboard KPIs (12:301-320) |
| Generic CRUD for the other pages | ONLY IN DEMO | Placeholders | Registry-driven list/create/edit (12:20-33) |
| BizPlus / Cowork / facility admin pages | ONLY IN DEMO | Not here (Cowork is a separate client artifact) | BizPlus dashboard, Cowork manager, facility resources (12:28, 12:1158-1365) |
| Admin login, RBAC, audit | ONLY IN DEMO | None | Session cookie, roles/permissions, AuditLog (12:29-33). Our S0: Entra SSO + RBAC + audit (cross-repo §4) |
| Customers list columns | SAME | Email, First, Last, Phone, City | `listFields` email, firstName, lastName, phone, city (12:1066) |
| Customer edit fields | DIFFERENT | First, Last, Phone, City; **e-mail locked** | Also address 1/2, country, postal code, business name, UEN; e-mail editable and required (12:1067-1077) |
| Leases list columns | SAME | Customer e-mail, Unit, Status, Monthly Rent, Start Date | `customer.email, unit.unitName, status, monthlyRent, startDate` (12:1125) |
| Lease status | DIFFERENT | Pending / Active **from signed documents** | ACTIVE / ENDED from SiteLink ledger (04:86, 12:1136) |
| Country / facility filter | ONLY IN ARTIFACT | SG / KR / MY chips + grouped facility list | No such filter; SG only |
| Facility master data | DIFFERENT | 24 facilities with codes L001…, legal names, insurance codes, SG addresses | `Site` rows with `locationCode`, name, address, tax % (12:985-1007); demo seeds test sites (LSETUP, SETUP2) |
| Getting a new lease | DIFFERENT | Staff type the e-mail and pull it from SiteLink on demand | Leases appear by app move-in (04:549-606) or by the live sync on each `/me/spaces` / login, which searches SiteLink by e-mail (04:684-723) |
| Sync frequency | DIFFERENT | "Sitelink only syncs hourly" | Unit sync every 15 min by default; lease sync live on each customer read (03:865, 04:686) |
| Refresh this / all sites | ONLY IN ARTIFACT | Manual buttons, "use sparingly" | Cron / CLI resync only (03:845-876) |
| Agreements | DIFFERENT | Generated in the admin; customer signs on a staff device; signature image stored | App sends URLs of already-signed agreements; `SignedAgreement` stores URLs only (04:110-123, 04:344-361) |
| Insurance | DIFFERENT | Application form with sum insured / premium table, MSIG wording | No insurance: `insuranceForMonth = 0`, `InsuranceCoverageID -999` (03:233, 04:563) |
| Security deposit = 1 month rent; late fee S$25 / 10 days | ONLY IN ARTIFACT | On the agreement | Demo reads deposits/fees from SiteLink move-in cost (04:561-564) |
| Unit type from name prefix (W / A) | ONLY IN ARTIFACT | Wine / Aircon / Standard | Demo uses `Unit.climate` and `StorageType` (03:160) |
| Multi-country currencies | ONLY IN ARTIFACT | $, RM, ₩ | SG only, SGD |

Cross-artifact note: the customer app prototype (`02-es-app.md` R31) shows a **fixed "Basic plan"
insurance (S$2,000 cover, S$8/month)** on every storage unit. This admin artifact uses an 11-tier table
(e.g. S$2,000 is not even a tier; S$8 buys S$15,000). The two client artifacts disagree.

---

## 8. Conflicts and open questions (for the owner / client)

1. **Agreement and insurance signing.** Is this a release-1 feature? Where does the customer sign —
   at the counter on a staff iPad (this artifact) or in the app (demo `POST /agreements` with URLs)?
   Do we store the signature image, a signed PDF, or both? Legal wording must come from the client.
2. **Lease status "Pending until signed".** Should an unsigned lease block anything (access, app
   features)? SiteLink already has the lease as active.
3. **Insurance source of truth.** Which table applies (app's Basic plan vs this 11-tier table)? Is
   insurance recorded in SiteLink (insurance coverage on the ledger) or only in our system? Who picks the
   cover — the customer, not a rent-based guess?
4. **Toh Guan (TGR)** is in the insurance workbook but not in the 24-site list. Is it a live site?
5. **Facility codes L001…** — are these the SiteLink location codes for production? Hillview has no
   address. Korea and Malaysia are out of scope for release 1 (SG only).
6. **"SiteLink syncs hourly"** — is that a real constraint (SiteLink API limits / cost)? The refresh-all
   warning ("full round of Sitelink API calls, use sparingly") suggests API call cost matters. The demo
   syncs units every 15 minutes and leases live.
7. **E-mail locked in admin** (and in the app). Who can change a customer's e-mail, given it is the
   sign-in identity (S0 OTP) and the SiteLink link key?
8. **Security deposit = 1 month's rent** and **late fee S$25 per 10 days**: are these real business
   rules, and are they charged in SiteLink?
9. **Unit-name prefixes** (W = wine, A = aircon) for Singapore: confirm, and confirm that SiteLink unit
   types can give the same answer more reliably.
10. **Re-sign.** "Sign Again" overwrites the old signature with no history. Should signed documents be
    immutable with a new version on re-sign?
