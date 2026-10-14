# S1 checks — Hangfire enlistment and SiteLink WSDL contracts

Researcher notes, 2026-10-14. Read-only. **[DOC]** = read it (file:line, WSDL element or URL); **[INF]** = inferred, not verified.
WSDL: `https://api.smdservers.net/CCWs_3.5/CallCenterWs.asmx?WSDL`, plain GET 2026-10-14, 913,334 bytes, sha256 `4e7d6b87cfff84b2…`,
308 operations, no `<wsdl:documentation>` at all (saved in the session scratchpad only). No SOAP call was made.
`DEMO` = `../Backend Demo/backend/src/services/sitelink/`; `S02` = `../Backend Demo/backend/.claude/backend-spec/features/02-sitelink-integration.md`;
`HF` = `frankhommers/Hangfire.PostgreSql` at tag `1.21.1` (paths under `src/Hangfire.PostgreSql/`).

## Summary

1. **Hangfire enlistment is not safe for us; use the outbox table** (already brainstorm decision 5). Hangfire.PostgreSql opens **its own
   connection** per call and only joins an **ambient `System.Transactions` scope**; an EF `BeginTransactionAsync` is invisible to it.
2. Making enlistment work would mean replacing every EF transaction (advisory locks, `FOR UPDATE`) with `TransactionScope`, and two
   connections open at once escalate to a distributed transaction, which .NET supports on Windows only. Not viable on Fargate Linux.
3. CMS today: Hangfire.PostgreSql **1.21.1** (= latest tag), default options, so `EnableTransactionScopeEnlistment = true` but unused.
4. Newer SiteLink versions exist than the demo uses: `MoveInWithDiscount_v8`, `MoveInReservation_v7`, `ReservationNewWithSource_v6`,
   `MoveInCostRetrieveWithDiscount_v3/_v4`. The extra parameters are `intentId` / `PromoGlobalNum` / `bApplyInsuranceCredit` / `sCreditCardNum`.
5. Both demo move-in ops carry 5–7 card/bank elements (required ints/dates among them). The demo sends them blank with `iPayMethod 2`.
6. `PaymentSimpleCashWithSource` has **no reference/note field** (8 elements). `PaymentSimpleCheckWithSource` (`sCheckNumber`) and
   `PaymentSimpleBankTransferWithSource` (`sTransferNumber`) are card-free and carry a free reference string. That is a business choice (see §5).
7. `TenantListDetailed_v3` has `sLocationCode` (optional) and no other site filter. Whether blank = corp-wide is not in the WSDL.
8. Every response is `<any>` (DataSet). Response columns below come from demo code and S02, not the WSDL. The demo does **not** call
   `ChargesAndPaymentsByLedgerID`, `ChargesAllByLedgerID`, `PaymentsByLedgerID` or `LedgersByTenantID_v2/_v3`, so their columns are unknown.
9. The "never call" lists in our notes are incomplete: they miss `ReservationFeeAdd*` (in OPS), `TenantBillingInfoUpdate*`, `ReservationBillingInfoUpdate*`,
   `PaymentSimple`, `PaymentSimpleWithPrepaidDiscount*`, `SurchargeApplicable*`, `MultiUnitMoveIn*`, and the `_v4` move-in-cost ops that take `sCreditCardNum`.
10. No contradictions found on request names, element order or the 308 count; the corrections are in §6.

## A. Hangfire.PostgreSql and transactions

| # | Finding | Tag / source |
|---|---|---|
| A1 | Latest tag is `1.21.1` (2026-02-11). `HEAD` is 2 commits later and changes only the csproj | [DOC] `git tag`, `git diff 1.21.1 HEAD --stat` |
| A2 | CMS pins `Hangfire.PostgreSql 1.21.1`, `Hangfire.Core/AspNetCore 1.8.25` | [DOC] `CMS/Directory.Packages.props:14-16` |
| A3 | CMS storage = `UseNpgsqlConnection(<conn string>)` + `SchemaName "hangfire"`, `PrepareSchemaIfNecessary`, `QueuePollInterval`; no enlistment option set | [DOC] `CMS/src/ExtraSpace.Api/Platform/Jobs/JobsSetup.cs:27-35` |
| A4 | Option `EnableTransactionScopeEnlistment`, **default `true`** | [DOC] HF `PostgreSqlStorageOptions.cs:50,130` |
| A5 | Every storage write runs in a `TransactionScope`. With enlistment on **and** `Transaction.Current != null`, it uses `Required` (joins the ambient scope); otherwise it uses `RequiresNew` | [DOC] HF `Utils/TransactionHelpers.cs:8-27`; `PostgreSqlStorage.cs:414-417` |
| A6 | The connection is `dedicatedConnection ?? CreateAndOpenConnection()`, i.e. **its own pooled connection**, then `connection.EnlistTransaction(Transaction.Current)` | [DOC] HF `PostgreSqlStorage.cs:400-412, 442-458` |
| A7 | An enqueue makes 2 storage writes: `CreateExpiredJob` (its own `UseTransaction`) and `WriteOnlyTransaction.Commit` (state + queue) | [DOC] HF `PostgreSqlConnection.cs:101,125`; `PostgreSqlWriteOnlyTransaction.cs:52-60` |
| A8 | EF `Database.BeginTransactionAsync()` is an ADO `DbTransaction` on EF's connection. It does **not** set `Transaction.Current`, so Hangfire takes the `RequiresNew` path on a second connection: **the job commits even if our transaction rolls back**, and it is visible to workers before our commit | [INF] from A5/A6 + how EF transactions work |
| A9 | Npgsql: with two connections open at the same time in one ambient transaction, the transaction becomes **distributed**. .NET 7+ supports that on **Windows only**, and Npgsql does not implement recovery ("discouraged"). Open-close-reopen without overlap reuses one physical connection | [DOC] npgsql docs `basic-usage.md` §"System.Transactions and distributed transactions" (https://www.npgsql.org/doc/basic-usage.html), lines 196-202 |
| A10 | For enlistment to work you need: an ambient `TransactionScope(AsyncFlowOption.Enabled)` around the EF work, **no** EF `BeginTransaction` inside it, and EF's connection closed before `Enqueue`. S0-3 code relies on explicit EF transactions for `pg_advisory_xact_lock` and `FOR UPDATE` (engineering checklist §1d) | [INF] |
| A11 | HF's own comment: a modified connection string with enlistment can "cause prepared transactions and probably fail when other statements (outside of hangfire) ran within the same transaction" (#248) | [DOC] HF `Factories/NpgsqlInstanceConnectionFactoryBase.cs:37-43` |
| A12 | Today the S0 login-code email already shows the gap: `HangfireEmailSender.Enqueue` calls `jobs.Enqueue` (own connection), not tied to the code row's transaction | [DOC] `CMS/src/ExtraSpace.Api/Integrations/Email/HangfireEmailSender.cs:22`; gap noted in `s1-research-crosscutting.md:139` |

**Conclusion.** Use an **outbox table** written by EF in the same `DbContext` transaction as the business change, drained by a
Hangfire recurring job (or by an after-commit enqueue plus a sweeper). Each job is idempotent on a unique key. Enlistment is
technically present, but on our stack (EF explicit transactions, Linux, advisory locks) it is either silently non-atomic (A8) or
distributed (A9). This matches `brainstorm-decisions.md:11` and `s1-design-draft.md:40`. [INF]

## B. SiteLink request contracts (WSDL `xs:sequence` order)

Every operation starts with the logon block `sCorpCode, sLocationCode, sCorpUserName, sCorpPassword` (all `string`, minOccurs 0). It is
left out below. `?` = minOccurs 0 (all strings). Every int, decimal, dateTime and boolean is minOccurs 1, so it is **required**. 💳 = card/bank field. [DOC] WSDL elements of the same name.

### B1. Move-in

| Op | Elements after logon, in order |
|---|---|
| `MoveInWithDiscount_v7` (demo) | `TenantID:int, sAccessCode?, UnitID:int, dStartDate:dateTime, dEndDate:dateTime, dcPaymentAmount:decimal, 💳iCreditCardType:int, 💳sCreditCardNumber?, 💳sCreditCardCVV?, 💳sCCTrack2?, 💳dExpirationDate:dateTime, 💳sBillingName?, 💳sBillingAddress?, 💳sBillingZipCode?, InsuranceCoverageID:int, ConcessionPlanID:int, iSource:int, sSource?, bUsePushRate:boolean, iPayMethod:int, 💳sABARoutingNum?, 💳sAccountNum?, 💳iAccountType:int, iKeypadZoneID:int, iTimeZoneID:int, iBillingFrequency:int, WaitingID:int, ChannelType:int, bTestMode:boolean, bApplyInsuranceCredit:boolean` |
| `MoveInWithDiscount_v8` (newest) | same as v7 **+ `intentId:int`** at the end |
| `MoveInReservation_v6` (demo) | `WaitingID:int, TenantID:int, UnitID:int, dStartDate:dateTime, dEndDate:dateTime, dcPaymentAmount:decimal, 💳iCreditCardType:int, 💳sCreditCardNumber?, 💳sCreditCardCVV?, 💳dExpirationDate:dateTime, 💳sBillingName?, 💳sBillingAddress?, 💳sBillingZipCode?, InsuranceCoverageID:int, ConcessionPlanID:int, iPayMethod:int, 💳sABARoutingNum?, 💳sAccountNum?, 💳iAccountType:int, iSource:int, bTestMode:boolean, bApplyInsuranceCredit:boolean, iPromoGlobalNum:int` (no `sAccessCode`) |
| `MoveInReservation_v7` (newest) | same as v6 **+ `intentId:int`** |

- Required card-branch elements (`iCreditCardType`, `dExpirationDate`, `iAccountType`) must be sent. The demo sends `0`, `1970-01-01T00:00:00Z`, `0`, blank strings, and
  `iPayMethod 2` = Cash [DOC] `DEMO/operations/moveIn.ts:31-34,59-84,113-145`. `iPayMethod` values are **not in the WSDL**; "2 = Cash" comes from the demo
  comment `moveIn.ts:21` [DOC, unverified against vendor docs]. Live success only for `MoveInReservation_v6` (ledger 603025) [DOC] S02:763-765.
- `intentId` (v8/v7) appears on many card ops (`PaymentSimpleWithSource_v4`, `ReservationFeeAddWithSource_v3`, …), next to `GetIntentStatus(intentId)` and
  `GenerateMFECheckoutUrl(iTenantId, iUnitId, dcAmount, sCurrency, bShowAutoPay, dcPreTaxAmount)` [DOC WSDL]. It looks like SiteLink's own hosted payment-intent
  rail [INF]. Out of scope (we use Stripe), but stay on v7/v6 or send the v8 `intentId` as a no-intent value only after a sandbox test.
- Response (both): `RT[0].Ret_Code` > 0 = new **LedgerID**; `RT[0].iLeaseNum` = lease number [DOC code] `moveIn.ts:85-90,146-152`; S02:827-830.

### B2. `MoveInCostRetrieveWithDiscount_v2`

Request: `iUnitID:int, dMoveInDate:dateTime, InsuranceCoverageID:int, ConcessionPlanID:int, ChannelType:int` [DOC WSDL]. No card field.
`_v3` adds `bApplyInsuranceCredit:boolean`; 💳 `_v4` adds `sCreditCardNum?` (do not use v4) [DOC WSDL].
Response `Table[]` columns (code; only `dcTotal` live-verified, rest unverified per S02:883): `UnitID, ChargeDescription, ChargeAmount, TaxAmount,
StartDate, EndDate, bMoveInRequired, dcDiscount, dcTotal, ConcessionID` [DOC code] `DEMO/operations/pricing.ts:121-132`. Required payment = Σ `dcTotal` (S02:615).

### B3. `PaymentSimpleCashWithSource`

Request: `iTenantID:int, iUnitID:int, dcPaymentAmount:decimal, iSource:int`. **Nothing else**: no ledger id, no reference, no note, no `bTestMode` [DOC WSDL].
`iSource` valid values 3 / 10 (5 → `-40` live) [DOC] `DEMO/operations/payments.ts:17-22`.
Response `Receipts[0]`: `ReceiptID`, `iReceiptNum` [DOC code] `payments.ts:53-57`. Table name and columns unverified live (S02:884).
**Dedupe:** impossible through this op. Card-free siblings with a reference string:

| Op | Elements after logon | Reference |
|---|---|---|
| `PaymentSimpleCheckWithSource` | `iTenantID:int, iUnitID:int, dcPaymentAmount:decimal, sCheckNumber?, iSource:int` | `sCheckNumber` |
| `PaymentSimpleBankTransferWithSource` | `iTenantID:int, iUnitID:int, dcPaymentAmount:decimal, sTransferNumber?, iSource:int` | `sTransferNumber` |

[DOC WSDL]. Whether SiteLink stores or shows the reference, rejects duplicates, or how finance wants Stripe money coded: unknown [INF]. House rule names
`PaymentSimpleCashWithSource`, so changing ops needs an owner/business decision.

### B4. Tenants

| Op | Elements after logon |
|---|---|
| `TenantListDetailed_v3` | `sTenantFirstName?, sTenantLastName?, sAddressLine1?, sAddressLine2?, sCity?, sState?, sZipCode?, sEmailAddress?, sPhoneNumber?, sCompany?, sUnitName?, sAccessCode?, sCRN?` |
| `TenantNewDetailed_v3` | `sWebPassword?, sMrMrs?, sFName?, sMI?, sLName?, sCompany?, sAddr1?, sAddr2?, sCity?, sRegion?, sPostalCode?, sCountry?, sPhone?, sMrMrsAlt?, sFNameAlt?, sMIAlt?, sLNameAlt?, sAddr1Alt?, sAddr2Alt?, sCityAlt?, sRegionAlt?, sPostalCodeAlt?, sCountryAlt?, sPhoneAlt?, sMrMrsBus?, sFNameBus?, sMIBus?, sLNameBus?, sCompanyBus?, sAddr1Bus?, sAddr2Bus?, sCityBus?, sRegionBus?, sPostalCodeBus?, sCountryBus?, sPhoneBus?, sFax?, sEmail?, sPager?, sMobile?, bCommercial:boolean, bCompanyIsTenant:boolean, dDOB:dateTime, sTenNote?, sLicense?, sLicRegion?, sSSN?, sGateCode?, sEmailAlt?, sRelationshipAlt?, sTaxID?, bSMSOptIn:boolean, sCountryCode?` |

- Site scope: the only site input is the logon's optional `sLocationCode`. There is no SiteID or "all sites" flag [DOC WSDL]. Whether blank = corp-wide is not
  documented. The old system used blank with `_v2` (`s1-research-sitelink.md:106-107`). Rows carry `SiteID` + `sLocationCode` (code). **Verify live** [INF].
- `TenantListDetailed_v3` response `Table[]`: `SiteID, TenantID, sLocationCode, sFName, sLName, sEmail, sPhone, sAccessCode, bHasActiveLedger` [DOC code] `DEMO/operations/tenants.ts:66-76` (S02:629 "live-exercised").
- `TenantNewDetailed_v3` response `RT[0]`: `TenantID`, `AccessCode` [DOC code] `tenants.ts:162-168` (live, S02:670). `dDOB` is required → the demo sends `1900-01-01` (`tenants.ts:28,148`).

### B5. Ledgers, charges, payments

| Op | Elements after logon | Response columns |
|---|---|---|
| `LedgersByTenantID` | `sTenantID?` (**string**) | `Ledgers[]`: `LedgerID, sUnitName, dcChargeBalance, dPaidThru, dcTotalDue` (tenant-wide, never per unit), `iLeaseNum, dMovedIn, dMovedOut, dcRent, sBillingFrequency` [DOC code] `tenants.ts:213-224`; live-exercised S02:675. **No UnitID** |
| `LedgersByTenantID_v2`, `_v3` | `sTenantID?` (same as v1) | unknown: demo does not call them [INF] |
| `ChargesAndPaymentsByLedgerID` | `sLedgerID:int` (named `s…` but typed **int**) | unknown (old system reads it; `dcTax1/dcTax2` on bills, `docs/notes/old-backend/01-mobile-api.md:441`) |
| `ChargesAllByLedgerID` | `ledgerId:int` (lower-camel, no prefix) | unknown |
| `PaymentsByLedgerID` | `sLedgerID:int` | unknown |

[DOC WSDL for requests]. To get the columns: capture one raw response per op in the sandbox (S02:884-885 asks the same), or read the old system's C# model
classes for these ops (not its config files). Not done here.

### B6. Reservations

| Op | Elements after logon | Card? |
|---|---|---|
| `ReservationNewWithSource_v5` (demo) | `sTenantID?, sUnitID?, dNeeded:dateTime, sComment?, iSource:int, sSource?, QTRentalTypeID:int, iInquiryType:int, dcQuotedRate:decimal, dExpires:dateTime, dFollowUp:dateTime, sTrackingCode?, sCallerID?, ConcessionID:int` | no |
| `ReservationNewWithSource_v6` (newest) | v5 **+ `PromoGlobalNum:int`** | no |
| `ReservationUpdate_v4` | `WaitingID:int, sTenantID?, sUnitID?, dNeeded:dateTime, sComment?, iStatus:int, bFollowup:boolean, dFollowup:dateTime, dFollowupLast:dateTime, iInquiryType:int, dcQuotedRate:decimal, dExpires:dateTime, QTRentalTypeID:int, QTCancellationTypeID:int, sCancellationReason?, ConcessionID:int` | no |
| `ReservationFeeAddWithSource` / `_v2` | `iTenantID:int, iWaitingListID:int, 💳iCreditCardType:int, 💳sCreditCardNumber?, 💳sCreditCardCVV?, 💳dExpirationDate:dateTime, 💳sBillingName?, 💳sBillingAddress?, 💳sBillingZipCode?, bTestMode:boolean, iSource:int` | **yes** |
| `ReservationFeeAddWithSource_v3` | `_v2` + `intentId:int` | **yes** |

[DOC WSDL]. No card-free reservation-fee op exists. A reservation fee taken by Stripe can only reach SiteLink as a payment / at move-in [INF].
Responses: `ReservationNew…` `RT[0].Ret_Code` > 0 = WaitingID; `ReservationUpdate_v4` returns only `RT` [DOC code] `DEMO/operations/reservations.ts:70-77,131-132` (live, S02:723, S02:748).

### B7. Units, prices, discounts

| Op | Elements after logon | Response (code) |
|---|---|---|
| `UnitsInformation_v3` | `lngLastTimePolled?` (string ticks), `bReturnExcludedFromWebsiteUnits:boolean` | `Table[]` units + `Table1[0].lngLastTimePolled` (and `dLatestUpdated`) |
| `UnitsInformationAvailableUnitsOnly_v2` | `lngLastTimePolled?` | same shape |
| `UnitTypePriceList_v2` | logon only | `Table[]`: `UnitTypeID, sTypeName, bClimate, bInside, dcWidth, dcLength, dcArea, dcStdRate, dcWebRate, dcStdWeeklyRate, iTotalUnits, iTotalVacant, iTotalOccupied, UnitID_FirstAvailable, sUnitName_FirstAvailable, dcAdminFee, dcReservationFee, ConcessionID` (44 columns per PDF; 18 read) |
| `DiscountPlansRetrieve` | logon only | `ConcessionPlans[]`: `ConcessionID, sPlanName, sDescription, bNeverExpires, iExpirMonths, bPrepay, iAmtType, dcChgAmt, dcFixedDiscount, dcPCDiscount, dcMaxAmountOff`; `ConcessionUnitTypes[]`: `ConcessionID, UnitTypeID` (names **unverified**, S02:883) |

Unit row columns read by `mapUnitRow`: `UnitTypeID, UnitID, sUnitName, sTypeName, dcWidth, dcLength, bClimate, dcStdRate, dcWebRate, dcBoardRate, dcPushRate,
dcPreferredRate, bRented, bInside, bPower, bAlarm, iFloor, bWaitingListReserved, bRentable, dcStdSecDep, sUnitDesc, iDoorType, iEntryLoc, iADA, bMobile, dDeleted`
(39 per the PDF) [DOC code] `DEMO/operations/units.ts:70-97,136-141,226-245`. Requests are [DOC WSDL].

## C. Card-carrying operations (complete list from the WSDL)

Every op whose request has a card or bank element (`*CreditCard*`, `sCCTrack2`, `*CVV`, `sABARoutingNum`, `sAccountNum`, `sCardNumber`) [DOC WSDL scan]:
`MoveIn`, `MoveInReservation*` (all 15), `MoveInWithDiscount*` (all 13), `MultiUnitMoveIn`, `MultiUnitMoveInCostRetrieve`, `MoveInCostRetrieveWithDiscount_v4`,
`…_Reservation_v4`, `…_28DayBilling_Reservation_v4`, `PaymentSimple`, `PaymentSimpleWithSource*`, `PaymentSimpleWithPrepaidDiscount*`, `PaymentMultipleWithSource*`,
`PaymentSimpleACH*`, `ReservationFeeAdd*` (6), `ReservationBillingInfoUpdate*` (3), `TenantBillingInfoUpdate*` (7), `RefundPaymentCreditCard*`, `POSItemPayment*`,
`SurchargeApplicable*`. `NationalMasterAccountsRetrieve` has an `sAccountNum` element: probably an account id, not bank data [INF].
Move-in ops are the exception we use. Card branch blank + `iPayMethod 2`.

## D. What our notes got wrong or missed

| Note : line | Says | Finding |
|---|---|---|
| `sitelink/ccws-3.5-operations.md:5` | never-call list = `PaymentSimpleWithSource*, PaymentMultipleWithSource*, POSItemPayment*, RefundPaymentCreditCard*, PaymentSimpleACH*` | **Incomplete**: add `ReservationFeeAdd*`, `PaymentSimple`, `PaymentSimpleWithPrepaidDiscount*`, `TenantBillingInfoUpdate*`, `ReservationBillingInfoUpdate*`, `SurchargeApplicable*`, `MultiUnitMoveIn*`, `MoveInCostRetrieve*_v4`; and say that `MoveIn*` carry card fields (allowed only blank + Cash) (§C) |
| `ccws-3.5-operations.md:3` | 308 operations | Correct (308 unique `wsdl:operation` names, 2026-10-14) |
| `s1-research/s1-research-sitelink.md:62` | cites OPS:5 for "never call `ReservationFeeAddWithSource*`" | OPS:5 does not list it (it comes from S02); fix the cite or OPS |
| `s1-research-sitelink.md:36` | demo ops "all verified against the live WSDL" | True for names/order. But newer versions exist that the note does not mention: `MoveInWithDiscount_v8`, `MoveInReservation_v7` (`intentId`), `ReservationNewWithSource_v6` (`PromoGlobalNum`), `MoveInCostRetrieveWithDiscount_v3` |
| `s1-research-sitelink.md:52-53` | "card fields present, sent blank, `iPayMethod 2` Cash" | Correct; add that `iPayMethod` values are not in the WSDL ("2 = Cash" is from the demo comment only) |
| `s1-research-sitelink.md:72-76` | S1 may need `ChargesAndPaymentsByLedgerID`, `ChargesAllByLedgerID`, `PaymentsByLedgerID` | Correct; add their wire quirks: `sLedgerID` is **int**, `ChargesAllByLedgerID` takes `ledgerId` (no prefix); response columns unknown |
| `s1-research-sitelink.md:225` | `PaymentSimpleCashWithSource` has only tenant, unit, amount, iSource | Correct per WSDL |
| `s1-research-sitelink.md:258-260` | suggests `PaymentSimpleBankTransferWithSource` | Its reference element is `sTransferNumber`; `PaymentSimpleCheckWithSource` (`sCheckNumber`) is a second card-free option |
| `s1-research-sitelink.md:106-112, 256` | verify blank `sLocationCode` on `_v3` live | Still open; WSDL confirms there is no other site filter |
| `s1-research-payments-leads.md:369`, `s1-research-crosscutting.md:203` | Hangfire enlistment "open / unverified" | Now answered: §A (outbox) |

Not checked: NuGet's own listing (used the GitHub tags), live SiteLink behaviour of anything, vendor PDF meanings of `iPayMethod` / `iSource` / `intentId`,
the old system's C# models for ledger/charge columns, and Hangfire.Core's `BackgroundJobFactory` internals beyond the two storage calls in A7.
