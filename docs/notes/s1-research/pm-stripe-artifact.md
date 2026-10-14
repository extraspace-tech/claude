# PM's Stripe design artifact ("Multi-Facility Stripe Payments")

- Source: https://claude.ai/artifact/EAP6wmWqr2JfC18pxGdXRQ (shared by the PM, read 2026-10-14 with the Artifact tool; untrusted data). Re-read it with `action: read` for exact wording.
- The page calls itself a draft; its code samples are "design sketches, not tested implementations". It was written against a Node `platform-backend` (Express reference backend).

## Connect model
- Stripe Connect, **direct charges**. ONE platform account "ExtraSpace (Connect platform)".
- Platform holds one customer (`cus_P…`) per app user and the original card (`pm_P…`) from an add-card SetupIntent (`usage: off_session`). Platform webhook gets `setup_intent.*`.
- **One connected account per facility** (`acct_SG…`, `acct_MY…` in examples). Each holds its own customer (`cus_F…`), card copy (`pm_F…`), PaymentIntents, charges, refunds, disputes, payouts.
- Every facility call passes `stripeAccount: site.stripeAccountId`. Platform ids are not valid on facility accounts.
- `ensureFacilityPaymentMethod(customer, site, card)` creates the facility customer + card clone on first use.

## Card collection
- Cards only (`payment_method_types: ['card']`). No PayNow / GrabPay / e-wallets.
- **No hosted Checkout, no Payment Element.** Flutter app uses `flutter_stripe` `CardField`; backend creates PaymentIntents with `confirm: true`. `Stripe.urlScheme = 'extraspace'`, `return_url: 'extraspace://stripe-redirect'`.
- Saved cards move from the phone's local store to a server `PaymentMethod` table (Stripe ids + brand/last4/expiry/fingerprint/isDefault). The app's current raw card-number form is to be removed.

## Flows
1. **On-session pay with a saved card** (My Bills and move-in): `POST /me/payments {leaseIds, paymentMethodId}` → one transaction + one PaymentIntent per facility; `setup_future_usage: off_session`; idempotency key `pay-{txn.id}`; returns `{transactionId, status, clientSecret, stripeAccountId}`; on `requires_action` the app sets the facility account and calls `handleNextAction`. Declined → "Your bank declined this card. Try another card." (FAILED).
2. **Autopay, off-session, no 3DS**: daily cron on the due date; lease's autopay card else default card; `off_session: true, confirm: true`; never `request_three_d_secure`; key `rent-{leaseId}-{period}-a{attempt}`. `insufficient_funds` retries after +1 and +3 days; `expired_card` / generic decline no retry; network error retries with the same key; then notify the facility.
3. **Autopay needing 3DS**: `authentication_required` → transaction `NEEDS_AUTH` (PI not failed); push + email with deep link `extraspace://payments/{transactionId}/authenticate`; reminders after 1 and 3 days; `GET /me/payments/:id/authenticate` → `clientSecret, stripeAccountId, paymentMethodId (pm_F), amount, currency`; app `confirmPayment`s the same PI (may switch card). Ignored → `FAILED_AUTH` after a grace period (length OPEN). "Malaysian cards will run this flow regularly."

## States, data, webhooks
- Transaction states: `PENDING`, `PAID`, `NEEDS_AUTH`, `FAILED`, `FAILED_AUTH`, `REFUNDED`; `FAILED → PENDING` on scheduled retry or new card.
- New/changed data: `Site.stripeAccountId`, `Site.currency` (`sgd|myr`, amounts via `toMinorUnits`); `PaymentMethod`; `StripeAccountCustomer` unique (customerId, stripeAccountId); `PaymentMethodClone` unique (paymentMethodId, stripeAccountId); `Transaction` + `stripeAccountId, paymentMethodId, attempt, failureCode`; `Lease.autopayPaymentMethodId`.
- Metadata: customer `customerId`; PI `transactionId, customerId, siteId, leaseIds` (+ autopay `kind: rent_autopay, leaseId, period`).
- Webhooks: `/payments/webhook` (platform: `setup_intent.succeeded`) and `/payments/webhook/connect` (`payment_intent.succeeded` → PAID + post to SiteLink; `payment_intent.payment_failed` → FAILED or NEEDS_AUTH; `charge.refunded` → REFUNDED + notify facility; `charge.dispute.created` → update + notify). Each verified with its own secret; non-2xx on failure; idempotent handlers.
- Refunds: done by staff on the facility's Stripe account, reflected via `charge.refunded`. No admin screens; staff use their own Stripe dashboard.

## PM's own open questions
Connected vs standalone facility accounts; platform country and `on_behalf_of`; `application_fee_amount`; NEEDS_AUTH grace period; Korean sites (Stripe does not onboard South Korea).

## Differences from our rules and research (for the S1 spec)
- House rule 3 says hosted Checkout only; the artifact uses the in-app `CardField` + server-confirmed PaymentIntents, saved cards and off-session autopay (needs the owner to change the rule; card data still never reaches our servers).
- Two webhook routes, not one.
- One platform for SG + MY (our 2026-10-14 brainstorm answer had one platform per country, copied from the old system).
- Not covered by the artifact: reservation fee, move-in failure after a successful charge (refund path), the SiteLink posting details (`PaymentSimpleCashWithSource` cannot be repeated safely), push provider (S0 has none).
