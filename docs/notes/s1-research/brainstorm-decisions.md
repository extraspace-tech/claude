# S1 brainstorm — owner decisions (2026-10-14)

Inputs: the four research notes in this folder and `pm-stripe-artifact.md`. The demo is still at `6be4474` (fetched 2026-10-14, nothing new).

| # | Decision | Source |
|---|---|---|
| 1 | Reservation fee and move-in are really charged in S1 (the demo fakes both). New payment flow: designed now, marked "pending business approval" until the PM signs off. | owner |
| 2 | Stripe Connect **direct charges**, a connected account per facility (site). **SG and MY are separate Connect platforms** (PM via owner). | owner + PM |
| 3 | Admin pages: same look as the demo (columns, filters, search, layout); Units, Reservations, Leases and Transactions are **read-only with named actions**; the other S1 resources stay editable like the demo. Listed as a deliberate difference. | owner |
| 4 | House rule 4 reading: `MoveInReservation_v6` and `MoveInWithDiscount_v7` may be called with card fields blank and `iPayMethod=2` (cash). A test asserts the card fields are always empty. `MoveInWithDiscount_v7` must be proven on the test site first. | owner |
| 5 | Architecture approach A: local copy of sites/units (15-min sync + staff refresh), live SiteLink only for pricing / reserve / move-in / bills, My Spaces from local leases refreshed by a job + rate-limited pull-to-refresh, in-process price-list cache, **outbox table** for payment side effects, read-back before any SiteLink write retry, "needs attention" queue. No Valkey in S1. | owner ("ok") |
| 6 | SiteLink test site = **`LSETUP`**. | owner |
| 7 | **House rule 3 changes** to follow the PM's Stripe artifact: cards collected only by Stripe's SDK (`flutter_stripe` CardField, 3DS via `handleNextAction`); PaymentIntents created and confirmed by our server; saved cards stored as Stripe ids + brand/last4/expiry only. Card data never reaches our servers or logs. Hosted Checkout no longer used. | owner (PM design) |
| 8 | S1 builds all three PM flows: pay-now with a saved card first; autopay (daily cron, retries) and the 3DS `NEEDS_AUTH` flow as the last S1 plan. Email only in S1; push when a provider is chosen. | owner |
| 9 | Payments are tested in Stripe **test mode** (per-country test keys) with Stripe test cards. Note: SiteLink `PaymentSimpleCashWithSource` has no test mode, so test payments recorded on `LSETUP` are real receipts in the live corp (test site only); tell finance, ask SiteLink whether they can be voided. | owner |
| 10 | §1 Scope and plan split approved ("continue", 2026-10-14): S1 = specs 02–06 + Dashboard + Lucy paths 1–21 + the PM's 3 Stripe flows + S0 carry-overs; Promotions → S4; BizPlus bits, push out; Korean sites IN (owner follow-up #20 supersedes "out"). Plans S1-1 Sites & SiteLink → S1-2 Tenants & My Spaces → S1-3 Search, quotes, reservations → S1-4 Payments core (may split) → S1-5 Leads, viewings, Dashboard (parallel with S1-3/4) → S1-6 Autopay & 3DS. | owner |

## BA answers to the 25 PM questions (doc "S1 questions for the PM", read 2026-10-14, rev 489; #24 updated rev 509)

| # | Topic | BA answer (verbatim, short) | Design effect |
|---|---|---|---|
| 1 | Reservation fee paid in app | "Yes (not confirmed)" | Keep the flow, marked pending. |
| 2 | Reservation charge contents | "Yes (not confirmed)" = fee + GST + deposit | As the demo, pending. |
| 3 | Refund on cancel | "Fees will be refunded in credits" | ❓ What "credits" means for storage (no credit system in S1; BizPlus credits deferred). Follow-up. |
| 4 | Reservation expiry | "Cancel by staff" | No business expiry; staff cancel action in admin. Unpaid holds still released technically. |
| 5 | Connected accounts | "Reuse old existing stripe accounts" + Slack doc "Facility Information" | New system uses the existing SG/MY platforms with NEW keys; site → account list from that Slack doc (we have no access). |
| 6 | Application fee | "None." | No fee. |
| 7 | Move-in refused after payment | "Full refund as in YES app (for now)" | Automatic full refund + staff alert. YES app = the old system (no in-app move-in there); its bill-payment rule (`ExtraSpaceAPI/mobile_api/DAL/PaymentDAL.cs:928-1040`, same in `mys-yes-production`): SiteLink posting fails → refund that unit's amount + email the facility "Failed Payment - Sitelink"; EXCEPT SiteLink return code -14 → no refund, payment kept, customer marked Overdue. Meaning of -14 unknown (ask SiteLink). |
| 8 | Who reverses refunds in SiteLink | "This is manual process." | Staff by hand. |
| 9 | 3DS grace | "for now we can keep 7 days"; exact dates later | 7 days, configurable; reminders configurable. |
| 10 | Receipts / statement text | "Will give you email format later" | ❓ Our own receipt email (format TBD); statement text unanswered. |
| 11 | Cash reconciliation | "Yes" | Transactions page shows Stripe id ↔ SiteLink receipt. |
| 12 | Amount due | Shows full due; "customers can pay how much they want" | Full balance shown, amount editable. |
| 13 | Partial / minimum | "Minimum $10 to maximum balance due" | Min 10 (SGD/MYR), max = balance. ❓ balance < 10. |
| 14 | Autopay amount | "full balance" | Full balance on the due date. |
| 15 | Autopay opt-in | "Yes, per unit, can toggle on/off in unit details screen in mobile." | Per-lease toggle (off by default kept). |
| 16 | Pay-screen price | "Sitelink's exact move-in amount." | As default. |
| 17 | Promotion at move-in | "Yes, we pass to Sitelink." | ConcessionID from the chosen plan goes into move-in cost + move-in. |
| 18 | Own SiteLink API user | "We will use LSETUP" | ❓ Does not answer which login/licence we use. Follow-up; live checks still blocked. |
| 19 | IP allowlist | "No" | Closes cross-repo open decision 7. |
| 20 | Live sites | "All sites" | ❓ Korean sites included? (Stripe cannot onboard KR.) Follow-up. |
| 21 | LSETUP real receipts | "LSETUP is test facility" | OK, treated as test data. |
| 22 | Insurance | "none (will add later)" | None in S1. |
| 23 | Lease status | "Storage (sitelink)"; "BizPlus & Cowork (own system)" | From SiteLink. |
| 24 | Account deletion | Changed to "Soft Delete in our system (not sitelink)" (rev 509) | Soft delete as the YES app does (`MA/DAL/UserDAL.cs:894-991`): confirm by email code, row kept with `deleted_at`, personal fields cleared, Stripe customers + cards + tokens removed; SiteLink tenant untouched. ❓ BA: clear the personal data (YES app) or keep it restorable? |
| 25 | MY data in AWS SG | "Yes" | PDPA question closed. |

### Owner follow-up answers (2026-10-14)
| # | Answer | Design effect |
|---|---|---|
| 3 | "Stripe refund" | Cancelled reservation → the reservation payment is refunded through Stripe (default: automatically when staff cancel). |
| 18 | "crawl through yes app for the sitelink login info" | Key names `SiteLink:sCorpCode`, `sCorpUserName`, `sCorpPassword` (old notes 03 :329). Values NOT read by Claude (old-backend.md secrets rule); owner copies them into user-secrets / Secrets Manager with a no-print command. It is the live corp login (all sites) → non-production writes limited to `LSETUP` by config allow-list. Own SiteLink user still recommended before go-live. |
| 20 | "yes korea included" | Third country KR (KRW, zero-decimal, `Asia/Seoul`, VAT). ❓ Stripe cannot onboard KR accounts → how KR sites take in-app payments; ❓ KR data in AWS SG (PIPA). |
| 10 | "re-use email format from yes app" | Our own emails from YES app templates (`ExtraSpaceAPI/mobile_api/emailTemplates/`: `successful_payment`, `unsuccessful_payment`, `unsuccessful_sitelink_payment`, `receipt_email`, `payment_due_alert`, `opt_account_delete`; CMS `card_expire_alert`; sg/my `receipt_pdf`). Statement text "Extra Space Asia" (YES app suffix). |
| 13 | "There can't be amount due under 10$" | Min 10. Server still allows paying a full balance below 10 as a guard (no business case expected). |
| 24 | "no" (to: does soft delete clear personal data?) | Soft delete keeps personal data; account disabled. |
| 7 (-14) | "Read through sitelink documentations I provided" | `../SiteLink_API.pdf`, `../SiteLink_Reporting_API.pdf` → background read into `docs/notes/sitelink/sitelink-api-pdf-notes.md`. |
| -14 | SiteLink_API.pdf p.142 (`PaymentSimpleCashWithSource`) | "-14 = Tenant is too many days past due. Online payments disabled" → the payment was NOT recorded in SiteLink. YES app keeps the money, no refund, marks the customer Overdue (staff must post it at the counter). S1 default: same as YES (BA #7), plus a needs-attention item and the facility email. Also from p.142: -7 "full payment required, no extra payment allowed" (site setting? conflicts with free-amount payments, BA #12) and -10 "prepayment ≤ 13× monthly fee". `iSource` 3 = Call Center, 10 = Website (demo sends 5). |

### Round 2 questions (26–38) added to the PM doc, 2026-10-14
KR payments (26), KR data/PIPA (27), reservation money in move-in total (28), -14 after charge (29), -7 partial (30), own SiteLink API user (31), SiteLink call limit (32), cards per country (33), minimum per payment (34), re-signup after soft delete (35), gate code (36), payment-due emails out (37), statement text (38); #1–2 still to confirm; site→Stripe account list.

### PM answers, round 2 (doc rev 662, 2026-10-14)
| # | PM answer | Design effect |
|---|---|---|
| 26 | "Korea has another payment provider. Stripe does not work in Korea." | ❓ Which provider, and in release 1? Until named: KR sites "pay at the facility" in S1; the KR provider is its own later plan. |
| 27 | "Yes" | KR data in AWS SG accepted. |
| 28 | "Yes" | Move-in charge = SiteLink total − reservation money paid (verify on LSETUP). |
| 29 | "Same as YES!" | -14 after charge: keep, staff post at the counter, needs attention. |
| 30 | "Refund the amount and ask customer to pay full balance." | As default. |
| 31 | "Yes." | Client's SiteLink admin can create our own API user → request it. |
| 32 | "There is limitation per month (we don't know the exact limit)" | Monthly call counter + configurable alarm threshold; on-demand design stands. |
| 33 | "It is ok." | Cards per country. |
| 34 | "whole payment (including each units)" | Minimum 10 for the whole payment AND for each unit line. |
| 35 | "TBD (leave it for now)" | Build the default (new account), easy to change. |
| 36 | "Show on request." | As default. |
| 37 | "Leave them out." | No payment-due emails in S1. |
| 38 | "Yes" | "EXTRA SPACE ASIA". |
| list | Slack link only (no file) | Owner to export site → `acct_` list. |
#1–2 still "Yes (not confirmed)".
