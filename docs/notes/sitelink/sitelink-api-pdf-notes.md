# SiteLink vendor PDFs — notes for S1

Researcher notes, 2026-10-14. Read-only. Sources: SiteLink Transaction API v2.19 (rev. 20 Jan 2026, 303 pages) = **API p.N**;
SiteLink Reporting API v1.11 (rev. 14 Apr 2017, 41 pages) = **Reporting p.N**. N = PDF page marker, not the printed TOC number
(the TOC is about 2 pages behind). The vendor marks both "highly confidential": this file paraphrases; never copy it into a code repo.
**[DOC]** = read in the PDF; **[INF]** = inferred. The PDF documents 176 methods; the live WSDL has 308 (`s1-checks.md` summary 4).

## Summary

1. **Blank `sLocationCode` on `TenantListDetailed_v3` searches every site of the corp** (max 50 rows, fuzzy). API p.251 [DOC]. This settles the open question in our notes.
2. **`iSource` values change from one operation family to another.** Payments and reservation fees use 3 = Call Center, 10 = Website. `MoveInWithDiscount_v7` and reservations use 1 = Call Center, 5 = Website. `MoveInReservation_v6` uses 3 = Kiosk, 5 = Website [DOC]. The demo's 5 is correct for move-ins and reservations and wrong for payments.
3. **`iPayMethod` is documented:** 0 Credit Card, 1 Check, 2 Cash, 3 Debit Card, 4 ACH. API p.116-117 [DOC].
4. **`bTestMode` does not mean "dry run".** It skips the card processor, but SiteLink still records the payment. API p.102, 117, 174 [DOC]. A test-mode move-in on a live corp is a real move-in.
5. **The -14 pre-check is possible:** `PaymentSettings` returns `iDaysPastDueNoOnlinePayment` (API p.132). Compare it with `dPaidThru` (API p.68, p.123) [DOC + INF]. **-7 has no readable setting.** The only possible dry run is `CalculateSurchargeAmounts`, which returns -7 and -14 without card data (API p.20-21) [DOC]. It might also fail with -21 at sites that have no card configuration [INF].
6. **Return codes belong to each operation.** -2, -7, -11 and -14 mean different things in move-in, payment and tenant operations. Map codes per operation [DOC].
7. **The PDF has no rate limit, quota, timeout, IP allowlist, idempotency key, or void/reverse operation** [DOC by absence]. The only guidance: poll units about every 15 minutes and clear the cache nightly (API p.294). The Reporting API can return -90 under load; wait 15 s (Reporting p.5).
8. **Security level: every operation we need works with "API Regular".** Ledgers, payments and move-ins require it. The Reporting API needs "API All Reports" (Reporting p.4) [DOC].
9. **No currency code anywhere.** The only per-site setting is `iCurrencyDecimals` / `iTaxDecimals` (`UnitTypePriceList_v2`, API p.302). Dates are sent without an offset. A null date is any date with a year before 1800 (API p.10) [DOC].
10. **There is no card-free reservation-fee operation.** Every `ReservationFeeAdd*` operation needs card data (API p.174-181) [DOC].

## 1. Return codes per operation

Standard codes, possible on every call (API p.11) [DOC]: -88 key access level too low, -89 invalid licence key, -91 insufficient security rights,
-92 site disabled, -93 network down, -96 invalid web access login, -97 invalid corp/location code, -98 invalid logon, -99 general exception.

| Operation (page) | Specific codes [DOC] |
|---|---|
| `MoveInReservation_v6` (API p.102-103) | >0 = LedgerID (+ `iLeaseNum`); -1 save failed; -2 unit not available; -3 insurance / invalid coverage ID; -4 card type; -5 payment type; -6 charge description; -7 insurance category missing; -8 admin-fee category; -9 rent category; -10 security-deposit category; **-11 amount ≠ required amount**; -12 time zones; -13 keypad zones; -14 card number invalid; -15 card declined; -16 overpay failed (move-in done); -17 move-in cost calc; -18 tenant not in reservation; -19 reservation/tenant mismatch; -20 reservation settings; -21 create charges; -22 reservation record; -23 concession data; -30 admin fee; -31 unit; -33 insurance; -34 move-in data; -36 card info; **-83 move-in date > 2 months in the past**; -84 debit needs test mode; -95 tenant; -100 card not authorised |
| `MoveInWithDiscount_v7` (API p.117-118) | >0 = LedgerID (+ `iLeaseNum`); -1…-14 as above (-17 also "invalid concession plan"); -20 site not set up for Authorize.Net/PPI; -21 no card config for site; -25 unit; -26 keypad zone; -27 time zone; -28 billing frequency; -29 channel type; -83; -84; -95; -100 |
| `MoveInCostRetrieveWithDiscount_v2` (API p.79) | 0 no data; -1 general; -2 invalid concession plan; -3 invalid insurance coverage; -25 unit; -29 channel type |
| `ReservationNewWithSource_v5` (API p.204) | >0 = WaitingID, `Ret_Msg` = `iGlobalWaitingNum`; -1 DB connect; -2 save; -3 concession plan; -25 unit; -26 rent tax rates; -95 tenant |
| `ReservationUpdate_v4` (API p.212) | >0 = WaitingID; -1 invalid WaitingID; -2 save; **-3 reservation already moved in**; -4 concession plan; -25 unit; -95 tenant |
| `TenantNewDetailed_v3` (API p.266-267) | `RT`: 1 + `TenantID` + `AccessCode`, plus a `Tenants` table; -1 last name and access code required; **-2 invalid or duplicate gate code**; -3 read; -4 save; -5 call error; -6 general; -7 schema; -95 |
| `TenantListDetailed_v3` (API p.252) | -1 failed to get data |
| `LedgersByTenantID` (API p.68) | -1 invalid tenant ID. No `_v2`/`_v3` in the PDF |
| `PaymentSimpleCashWithSource` (API p.142) | confirmed as already known: -1, -2 zero amount, -3, -7, -9, -10, -11, -14, -95. -40 bad source is **not** listed here, although it was seen live (S02) [DOC + INF: code lists are incomplete] |
| `PaymentSimpleCheckWithSource` (API p.145-146) | same as Cash + **-40 invalid source**. Its source list reads "1 – Call Center, 10 – Website" (probably a doc typo for 3) [DOC/INF] |
| `PaymentSimpleBankTransferWithSource` (API p.139-140) | text copied from ACH: -1 ACH failed; -2 commit; -4 ledger data; **-7 "payment must equal full charge amount"**; -14; **-15 tenant has ACH and checks disabled**; -20 save; -25 unit; -95 |
| `CalculateSurchargeAmounts` (API p.21) | -1, -2, -3, -4 ledger, -5, -6, -7, -9, -10, -11, -12, -14, -21 no card config, -95 |
| `PaymentsByLedgerID`, `ChargesAllByLedgerID` (API p.124, p.29) | standard codes only |
| `PaidThroughDateByLedgerID`, `PaymentSettings` (API p.123, p.132) | -1 |

**-7 / -14 control.**
- -14: `PaymentSettings` (API p.132) returns `iDaysPastDueNoOnlinePayment`. It is a site setting, edited in SiteLink's "Web Template Configuration" form. The same row has `bACH_Disabled`, `iDaysPastDueNoACHPayment`, `bCreditReservationFeeMoveIn`, `dcRM_RoundTo` and `iReservExpirDays` [DOC].
  - The past-due state is not returned as a number. `PaidThroughDateByLedgerID` says paid-through "can also be used" to find how many days a payment is late (API p.123) [DOC].
  - Pre-check: days past due = today (site time zone) − `dPaidThru`, then compare with the setting. How SiteLink counts the days (from paid-through, or from the due date + grace) is not stated [INF].
- -7: no API setting found. "Full payment required" is probably a site rule that the amount must equal the balance [INF]; the bank-transfer wording supports this.
  - Pre-check: call `CalculateSurchargeAmounts` (tenant, unit list, amount list, no card) before Stripe Checkout. It lists -7 and -14 (API p.20-21) [DOC].
  - Whether it applies the same validation as the payment call is not stated [INF]. It is meant for surcharge previews and may return -21 at sites without card configuration [INF].
  - Safest rule: charge exactly the amount SiteLink says is due [INF].

## 2. Enum values

| Field | Values | Source |
|---|---|---|
| `iPayMethod` | 0 Credit Card, 1 Check, **2 Cash**, 3 Debit Card, 4 ACH. `MoveInReservation_v6` names the field but lists no values | API p.116-117, p.102 [DOC] |
| `iSource`, payments + reservation fees | 3 Call Center, 10 Website. Exceptions: `PaymentSimpleWithPrepaidDiscount` lists 2 = Call Center; `POSItemPayment*` adds 2 = Kiosk | API p.125-151, p.176-180, p.147, p.156 [DOC] |
| `iSource`, `MoveInWithDiscount_v2…v7` | 1 Call Center, 5 Website API | API p.108-116 [DOC] |
| `iSource`, `MoveInReservation_v2…v6` | 3 Kiosk, 5 Website | API p.98-102 [DOC] |
| `iSource`, `ReservationNewWithSource*`, `ReservationList*` `iCallType` | 1 Call Center, 5 Website | API p.196-203, p.189 [DOC] |
| `iInquiryType` | 0 Unknown, 1 Email, 2 Web, 3 Phone, 4 WalkIn | API p.203, p.211 [DOC] |
| `QTRentalTypeID` | 1 Quote (inquiry), 2 Order (reservation); `ReservationUpdate_v4` adds 3 Rental | API p.203, p.211 [DOC] |
| Reservation `iStatus` (`ReservationUpdate_v4`) | 0 do not update, 1 restore (from cancelled/deleted), **2 cancel**, 3 delete | API p.211 [DOC] |
| `QTCancellationTypeID` | 1 price too high, 2 not ready, 3 not moving, 4 other storage, 5 competitor, **6 other reasons**, 7 location, 8 features, 9 duplicate, 10 mystery shopper, 11 stop calling, 12 phone issue, 13 unable to reach, 14 refused info, 15 converted | API p.211-212 [DOC] |
| `QTRentalStatusID` (`ReservationList_v3`) | 1 Completed, 2 Cancelled, 3 Active | API p.190 [DOC] |
| `iBillingFrequency` (move-in) | 3 Monthly, 7 28-day. Full list in `ReservationList_v3` `BillingFreqID`: 1 daily, 2 weekly, 3 monthly, 4 quarterly, 5 semi-annual, 6 annual, 7 28-day | API p.117, p.190 [DOC] |
| `ChannelType` | 0 StandardRate, 1 WebRate (`-29` if invalid) | API p.78, p.117 [DOC] |
| `-999` on `ConcessionPlanID` / `ConcessionID` / `InsuranceCoverageID` / `iPromoGlobalNum` | -999 is printed in the "DBNull value" column, so it is the null value: no discount / no insurance / no promotion | API p.78, p.102-103, p.116, p.203, p.212 [DOC legend + INF meaning] |
| `iCreditCardType`, `iAccountType` (card branch, we never fill it) | 5 MC, 6 VISA, 7 Amex, 8 Discover, 9 Diners; account 1 consumer checking, 2 consumer savings, 3 business checking | API p.116-117 [DOC] |
| `bTestMode` | Present on: `MoveIn`, all documented `MoveInReservation*` / `MoveInWithDiscount*`, `PaymentSimple`, `PaymentSimpleWithSource*`, `PaymentSimpleWithPrepaidDiscount`, `PaymentMultipleWithSource*`, `POSItemPayment*`, `ReservationFeeAdd*`. When true, the card is **not processed but SiteLink still processes the payment**. Debit requires test mode (-84). **Not on Cash/Check/BankTransfer** | API p.72-149, p.174-180 [DOC] |
| `iShowOn` / `iAvailableAt` (discounts) | iShowOn 0 all, 1 move-ins, 2 payments. iAvailableAt: values 0-5 (0 everywhere, 1 client, 2 website, 3 kiosk, 4 call centre/corp, 5 SpareFoot), or bitmask ≥ 16 (16 client, 32 website, 64 kiosk, 128 call centre, 256 SpareFoot) | API p.54-55 [DOC] |

## 3. Response columns

| Operation (page) | Table: columns [DOC] |
|---|---|
| `LedgersByTenantID` (API p.67-68) | `Ledgers` (one row per ledger), in this order: tenant block — `TenantID, SiteID`, gate code `sAccessCode`, `sWebPassword`, names, addresses, phones, `sEmail`, `bCommercial, bTaxExempt, bOnWaitingList, bNoChecks` (NSF), `dDOB`, `sLicense`, `sSSN`; then `LedgerID, bOverlocked, sUnitName, dcChargeBalance` (unpaid balance), `dPaidThru`, `uTSbigint`, `dcTotalDue`, `iLeaseNum, dMovedIn, dcRent, sBillingFrequency, TenantName, Address, ContactInfo`. **No UnitID, no `dMovedOut`**, no next-due date, no days past due. 🔴 Carries gate code, web password and SSN: never log or cache it raw |
| `ChargesAndPaymentsByLedgerID` | **Not documented**. Version history says it was removed in v1.x and added again later, but the PDF has no section for it (API p.12, p.14) |
| `ChargesAllByLedgerID` (API p.29) | Table named "RT" (probably a doc error): `ChargeID, SiteID, sChgCategory, dcAmt, dcTax1, dcTax2, dcPrice, dcQty, dChgStrt, dChgEnd, dcPmtAmt, bMoveIn, bMoveOut` |
| `PaymentsByLedgerID` (API p.124) | `PmtHistory`, **last 12 months only**: `dPmt, Description, Receipt` (receipt number), `ReceiptID, Payment, dPaidStr` |
| `PaidThroughDateByLedgerID` (API p.123) | `Charges`: `LedgerID, dPaidThru` |
| `LedgerStatementByLedgerID` (API p.69) | `Charges`: `ChargeID, ChargeDescID, LedgerID, dChgStrt, dChgEnd, sUnitName, sChgDesc, dcAmt, Tax, ChartOfAcctID, Payment, Balance, dChgStrtStr` |
| `CustomerAccountsBalanceDetails` (API p.42) | `Table1`, one row per category, **sum the rows** for the total due: `Ret_Code, LedgerID, UnitID, sUnitName, sItem, sCategory, dcPrice, dcAmt, dcTax, dcCredit, dcBalance, dcPayment, dcTotal, dStartDate, dEndDate`. `_v2` adds a Surcharge table (API p.43-44). It is in SiteLink's recommended payment flow (API p.10) |
| `CustomerAccountsChargesWithPrepayment_v2` (API p.50-51) | One row per charge: `UnitID, LedgerID, ChargeID, …, dChgStrt, dChgEnd, dCreated, sDesc, sChgCategory, dcAmt, dcTax1, dcTax2, dcBalance, dcPayment, dcCredit, …, bCurrLateFee, sNote, **iInvoiceNum**, NSF fields`. Input: prepay months 0-12 |
| `TenantInvoicesByTenantID` (API p.242-243) | `Table`: `SiteID, InvoiceID, iInvoiceNum, dInvoiced, EmployeeID, TenantID, dDue`; second table, per charge: `dcAmt, dcTax1, dcTax2, dcPmtAmt, dcBalAmt, dcBalDue, LedgerID, UnitID, dDue, …`. Input: date range + comma-separated TenantIDs |
| `TenantListDetailed_v3` (API p.251-252) | `Table`: `SiteID, TenantID, sLocationCode, sFName, sMI, sLName, sCompany, sAddr1, sAddr2, sCity, sRegion, sPostalCode, sPhone, sEmail, sMobile, sLicense, sAccessCode, bHasActiveLedger` |
| `MoveInCostRetrieveWithDiscount_v2` (API p.78-79) | `Table` (one row per charge): `Ret_Code, UnitID, ChargeDescription, ChargeAmount, TaxAmount, StartDate, EndDate, Width, Length, bClimate, UnitName, TypeName, dcPushRate*, bAnnivDateLeasing, b2ndMonthProrate*, iDayStrtProrating*, iDayStrtProratePlusNext*, iCurrencyDecimalPlaces*, bMoveInRequired, dcDiscount, dcTotal` (after discount), `ConcessionID, dcTenantRate, WebRate` (* = "N/A for this API") |
| `DiscountPlansRetrieve` (API p.53-55) | `RT`; `ConcessionPlans`: `ConcessionID, SiteID, QTTouchDiscPlanID, iConcessionGlobalNum, sPlanName, sDescription, sComment, iShowOn, bNeverExpires, iExpirMonths, bPrepay, bOnPmt, bManualCredit, iPrePaidMonths, iInMonth, iAmtType` (0 amount off, 1 % off, 2 fixed rate), `dcChgAmt, dcFixedDiscount, dcPCDiscount, bRound, dcRoundTo, ChargeDescID, iQty, iOfferItemAction, dcMaxAmountOff, bForCopr, dcMaxOccPct, bForAllUnits, bPermanent, dDisabled, sDefChgDesc, sChgDesc, sChgCategory, bApplyAtMoveIn, bProrateAtMoveIn, dcPrice, dcTax1Rate, dcTax2Rate, dcCost, dcInStock, iAvailableAt`; `ConcessionUnitTypes`: `ConcessionUnitTypeID, ConcessionID, UnitTypeID, dcWidth, dcLength`. No rows for a plan = valid for all types and sizes. Rounding pseudo-code for `dcRoundTo` 0 / 0.1 / 0.5 / 1 / 5 / 10 is on p.53 |
| `UnitsInformation_v3` (API p.294-295) | `Table`: 39 columns, including `UnitTypeID, sTypeName, UnitID, sUnitName, dcWidth, dcLength, bClimate, dcStdRate, bRented, bInside, bPower, bAlarm, iFloor, bWaitingListReserved, dMovedOut, bCorporate, bRentable, dDeleted, dcBoardRate, sUnitNote, dcPushRate, **dcTax1Rate, dcTax2Rate**, sUnitDesc, iEntryLoc, iDoorType, iADA, dcStdSecDep, bMobile, dcWebRate, dcPreferredRate, iPreferredChannelType, bPreferredIsPushRate`; `Table1`: `dLatestUpdated, lngLastTimePolled` |
| `UnitTypePriceList_v2` (API p.302-303) | `Table`, 44 columns: `SiteID, **iCurrencyDecimals, iTaxDecimals**, dcTax1Rate_Rent, dcTax2Rate_Rent, …, UnitTypeID, sTypeName, bChargeTax1, bChargeTax2, …, dcStdRate, dcStdWeeklyRate, iTotalUnits, iTotalOccupied, iTotalVacant, iTotalReserved, UnitID_FirstAvailable, …, dcAdminFee, dcReservationFee, bRented_FirstAvailable, bExcludeFromInsurance, ConcessionID` (best discount over a 12-month rental), `dcWebRate, dcBoardRate, dcPreferredRate, …`; plus `RT` |
| `PaymentSimple*WithSource` receipts (API p.139-145) | `Receipts`: `ReceiptID, SiteID, TenantID, EmployeeID, iPayBy, dcAmt, dRcpt, iReceiptNum` (already known) |
| `PaymentSettings` (API p.132) | `Table`: `iDaysPastDueNoOnlinePayment, bACH_Disabled, iDaysPastDueNoACHPayment, bCreditReservationFeeMoveIn, dcRM_RoundTo, iReservExpirDays` |

What the PDF documents for the fields we asked about [DOC]:
- **Balance:** `dcChargeBalance`, `dcTotalDue` (Ledgers), or the sum of `CustomerAccountsBalanceDetails.dcTotal`.
- **Paid-through:** `dPaidThru`.
- **Invoice number:** `iInvoiceNum` (charges and invoices).
- **Receipt number:** `iReceiptNum` / `Receipt`.
- **Tax:** `dcTax`, `dcTax1`, `dcTax2`, `TaxAmount`, rates per unit.
- **Due date:** only the invoice `dDue`.

Not documented: a "next due date" or "days past due" column.

## 4. Scope, limits, accounts, security levels

| Topic | Finding |
|---|---|
| Blank `sLocationCode` | `TenantListDetailed_v3`: blank = search **all sites of the corp code**; also returns near matches; capped at 50 tenants (API p.251) [DOC]. The API user's site security policy (below) probably narrows "all" [INF] |
| Usage limits / quotas / rate limits | None in either PDF [DOC by absence]. Guidance only: unit cache refreshed about every 15 min, **cleared nightly** (API p.288, p.294). `EmployeeLogin` locks for 5 min after 3 bad attempts (API p.56). The Reporting API returns -90 when "high priority transactions" are running: wait 15 s and re-run (Reporting p.5-6) |
| Licence agreement | Not in the PDF: only a link to an external licence page, plus a separate request form for the licence key. Using the API means accepting it (API p.7, Reporting p.3) [DOC]. Its call-volume terms: unknown, ask SiteLink [INF] |
| Timeouts, IP allowlist | Not mentioned. Only "port 443 open" (API p.7) [DOC by absence] |
| Test mode | See §2 `bTestMode`. No sandbox corp is described; the PHP sample uses corp `CCTST`, location `Demo` (API p.8) [DOC]. Whether that is a usable test corp: unknown [INF] |
| Void / reverse / refund | No documented operation reverses a payment or receipt. `MoveOut` returns `dcRefund` (API p.121). `RefundPaymentCreditCard*` is in the WSDL but not in the PDF (and is card-bearing) [DOC]. Reversal = staff in SiteLink [INF] |
| Idempotency | None documented. Create calls return the new id in `Ret_Code`. For an unknown outcome, read back with `PaymentsByLedgerID` (12 months, has `ReceiptID`), `ReservationList_v3` (WaitingID or -999 = all pending, incl. `dcPaidReserveFee`, `iReserveFeeReceiptID`) or `LedgersByTenantID` [DOC ops; INF use] |
| Security levels | Two levels: **"API Regular"** and **"API Aggregator"** (API p.9). **Regular only:** `LedgersByTenantID`, `TenantListDetailed_v3`, `MoveInReservation_v6`, `MoveInWithDiscount_v7`, every `PaymentSimple*WithSource`, `PaymentsByLedgerID`, `ChargesAllByLedgerID`, `PaidThroughDateByLedgerID`, `PaymentSettings`, `CalculateSurchargeAmounts`, `CustomerAccountsBalanceDetails*`, `TenantInvoicesByTenantID`, `LedgerStatementByLedgerID`, `ReservationList_v3`, `TenantInfoByTenantID`. **Regular or Aggregator:** `UnitsInformation_v3`, `…AvailableUnitsOnly_v2`, `…ByUnitID/ByUnitName`, `UnitTypePriceList_v2`, `DiscountPlansRetrieve`, `InsuranceCoverageRetrieve`, `MoveInCostRetrieveWithDiscount_v2`, `ReservationNewWithSource_v5`, `ReservationUpdate_v4`, `ReservationFeeRetrieve`, `TenantNewDetailed_v3`, `SiteInformation` [DOC, each method header]. ⇒ we need **API Regular**. Aggregator is not defined further [INF: a partner/listing level] |
| Creating our own API user (API p.9) | Done by the facility owner in SiteLink's **Corporate Control Center** (Web Edition). Optional: add a Security Policy of type Site listing the permitted locations. Then Users → new user with name and password, tick **API Regular** (or Aggregator), tick All Sites or the policy, save. A training video is linked. Logon username = `<user>:::<API licence key>` (PHP sample, API p.8). The licence key comes from SiteLink's request form (API p.7). Reporting users: rights "API All Reports" / "API Insurance" (Reporting p.4) [DOC] |
| Wire rules (API p.10) | Send every parameter, spelled as in the WSDL. Dates as `2016-01-01T00:00:00` (no offset). **Null date = any year before 1800** (example `1700-01-01T00:00:00`). Booleans may need different casing [DOC] |

## 5. Reservation fee, concessions, currency, dates

- **Reservation fee:** `ReservationFeeAdd`, `…WithSource`, `…_v2` and `…ForMobileStorage` all charge a card themselves. The card fields are marked required (API p.174-181) [DOC].
  - SiteLink's flow is `ReservationFeeRetrieve` for the amount, then `ReservationFeeAdd` (API p.10) [DOC].
  - `PaymentSettings.bCreditReservationFeeMoveIn` says whether the fee is credited at move-in (API p.132) [DOC].
  - ⇒ A fee taken by Stripe cannot be posted as a SiteLink reservation fee [INF]. Options: no fee; post it after move-in as a payment; or a staff process. Business decision.
- **Concession at move-in:** pass the `ConcessionID` from `DiscountPlansRetrieve` as `ConcessionPlanID`, with the **same** ID in `MoveInCostRetrieveWithDiscount_v2`. The amount must match that cost (-11) (API p.78, p.116-117) [DOC]. Invalid plan → -17 (move-in) or -2 (cost) [DOC].
  - Check `ConcessionUnitTypes` (type and size) and `iAvailableAt` (website) before offering a plan [DOC p.53-55; INF use].
  - A reservation can carry a `ConcessionID`; web-only concessions still apply when staff move the tenant in (API p.203) [DOC].
  - "Promotions" (`PromotionsRetrieve`, `iPromoGlobalNum`) are corporate-level discounts; SiteLink says ≤ 1 % of customers use them and recommends `DiscountPlansRetrieve` (API p.162) [DOC].
- **Multi-currency / KRW:** no currency code in any operation [DOC by absence]. Per-site `iCurrencyDecimals` and `iTaxDecimals` come from `UnitTypePriceList(_v2)` (API p.300, p.302). The cost-retrieve `iCurrencyDecimalPlaces` is "N/A for this API" (API p.78). One message hard-codes "$0" (API p.142) [DOC]. ⇒ Currency stays our `site.currency`; read the decimals per site and do not assume 2 [INF].
- **Dates / time zones:** dates have no offset (API p.10). Unit polling uses ticks "to prevent time zone inconsistencies" (API p.294) [DOC]. The PDF never states the zone of returned dates [DOC by absence]. `TimeZonesRetrieve` returns **gate-access time zones** (`TimeZID`, `dDailyOpen`, `dDailyClose`), not clock zones; that is what `iTimeZoneID` on move-in means (API p.283, p.112) [DOC]. A move-in date may not be more than 2 months in the past (-83) [DOC].
- **Unit polling:** for a first poll, pass ticks older than one month. Keep `lngLastTimePolled`. A unit held on the waiting list still shows as available in `AvailableUnitsOnly_v2` (API p.288) [DOC].

## 6. Reporting API (ReportingWs)

- Endpoint `https://api.smdservers.net/CCWs_3.5/ReportingWs.asmx`, same logon block, returns a DataSet (Reporting p.3, p.5) [DOC].
- Reconciliation candidates, each called with the logon block + start date + end date, one location per call [DOC]:
  - **`Receipts`** (Reporting p.19).
  - **`DailyDeposits`** (Reporting p.14; -2 if no daily close in the range).
  - `UnitPayments` (adds a unit name, Reporting p.41).
  - `AccountsReceivable` (Reporting p.20), `PastDueBalances` (Reporting p.15), `GeneralJournalEntries`, `FinancialSummary`.
- **No report columns are documented**: only "the report information" [DOC]. Capture a sample response from a test site before designing on it [INF].
- Limits [DOC]: -90 under load (retry after 15 s); -1 no data for the range. Right needed: "API All Reports". The document is from 2017 (v1.11) [DOC].

## 7. Where the PDFs contradict or settle our notes

| Note : line | Says | PDF says |
|---|---|---|
| `s1-checks.md:21`, `:101-102`; `s1-research-sitelink.md:106-112`, `:256` | blank `sLocationCode` = corp-wide is undocumented, verify live | **Documented**: blank searches every site of the corp (API p.251). Still worth one live check that the API user's site policy does not narrow it |
| `s1-checks.md:65`, `:162` | `iPayMethod` values not in vendor docs; "2 = Cash" only from the demo | Documented: 0 CC, 1 Check, 2 Cash, 3 Debit, 4 ACH (API p.116-117) |
| `s1-checks.md:82`; `s1-research-sitelink.md:67` | `iSource` must be 3 or 10 (5 → -40) | True **for payments only**. Move-in v7 = 1/5, MoveInReservation_v6 = 3 (Kiosk)/5, reservations = 1/5. The demo's 5 on move-in and reservation is valid; never reuse one constant |
| `s1-research-sitelink.md:68-69`, `:257` | what `bTestMode=true` does on a move-in is unverified | Card not processed, **SiteLink still records the payment / move-in** (API p.102, 117). Not a dry run |
| `s1-research-sitelink.md:159-161` | known codes -2 gate code, -11 cost mismatch, -14 overdue | Codes are per operation. On move-ins, -2 = unit not available and -14 = card number invalid. On payments, -2 = zero amount and -11 = charges not created. Map per operation |
| `s1-research-sitelink.md:211` | unknown whether SiteLink rejects a duplicate gate code | `TenantNewDetailed_v3` -2 = "invalid or duplicate gate code"; the gate code is required (API p.265-266) |
| `s1-checks.md:104`, `:64` (demo `dDOB 1900-01-01`, expiry `1970-01-01`) | sentinels | Vendor null date = year < 1800, e.g. `1700-01-01` (API p.10). 1900 may be stored as a real date of birth. DOB's null value is "Nothing" (API p.265) |
| `s1-checks.md:110` | `LedgersByTenantID` columns incl. `dMovedOut`; `_v2/_v3` unknown | PDF lists no `dMovedOut` (it may still come back undocumented); adds `SiteID`, `bOverlocked`, `sAccessCode`, `sWebPassword`, `sSSN`. `_v2/_v3` are not in the PDF |
| `s1-checks.md:112-114` | columns of `ChargesAllByLedgerID`, `PaymentsByLedgerID` unknown | Documented now (§3). `ChargesAndPaymentsByLedgerID` is still undocumented |
| `s1-checks.md:123` (WSDL: one `sUnitID`) | `ReservationNewWithSource_v5` request | The PDF lists Unit ID 1/2/3 (API p.203). The WSDL wins on the wire; the PDF table is probably stale [INF] |
| `s1-research-sitelink.md:241` (demo `dcQuotedRate 0`, `dExpires = now`) | business acceptability unverified | The PDF's null value for both is "Nothing" (optional) (API p.203). `PaymentSettings.iReservExpirDays` gives the site's default expiry (API p.132) |
| `s1-research-sitelink.md:28-30` | requests send UTC with `Z` | The PDF format has no offset (API p.10). Send site-local dates without `Z` [INF; still verify live] |
| `s1-research-sitelink.md:253` | rate limits / fair use unknown | Still unknown: the PDF has none. Only the 15-minute poll, nightly cache clear and Reporting -90 |
| `s1-research-sitelink.md:129`; `s1-checks.md:129` | no card-free reservation-fee op | Confirmed (API p.174-181) |

Not checked: the external licence agreement, the WSDL-only operations newer than the PDF (`_v8`, `_v7`, `_v6`, `intentId`), and every live behaviour.
