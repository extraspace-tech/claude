# Old backend inventory — 01: `mobile_api` (customer / mobile API)

Written 2026-10-09 by a read-only explorer. Source: `/Users/waiyanmin/Projects/Extra Space old/extraspace-backend`,
branch `yes-production` (Singapore). The Malaysia fork (`mys-yes-production`) is compared in §7.

**How to read paths.** Every path below starts at the repo root. To keep lines short, `MA/` means
`ExtraSpaceAPI/mobile_api/`. Example: `MA/Startup.cs:140` = `ExtraSpaceAPI/mobile_api/Startup.cs`, line 140.
"Inferred" means I did not see it directly in code; I reasoned it from code I did see.

**Secrets.** No secret value is copied here. Config is named by key only (for example `Jwt:Key`).

Scope: only `MA/`. The admin CMS (`ExtraSpaceCMS/admin_cms/`), `Express.Core`, `es_express`, the full MySQL
model, DB scripts and infra belong to other agents.

---

## 1. Overview

### 1.1 What it is

`mobile_api` is the backend of the **"Extra Space YES!" customer app** (Android/iOS package
`com.extraspaceasia.loyalty`, see `MA/Controllers/MasterController.cs:94`) and its web version
(`Site:WebUrl`, cookie login). The customers are **existing SiteLink tenants**: you can only register if SiteLink
already has you as a tenant with an active ledger at a known facility.

What it does:

- Login / first-time registration using the SiteLink tenant web password.
- Profile, logged-in devices, account delete (anonymise).
- My units / ledgers, bills, invoices, receipts, receipt and invoice PDFs (data comes live from SiteLink).
- Saved cards in Stripe (add, update, set default, delete).
- In-app rent payment (Stripe charge, then a matching payment posted into SiteLink). **Disabled in SG since
  2026-08-02; still live in MY** (§4.6, §7).
- Loyalty: ePoints, membership tiers, reward catalogue, redemption, wallet, third-party vouchers
  (UniqGift / WOGI), Extra Space rent vouchers.
- New partner endpoint `POST /v1/Reward/EarnPoints` (July 2026): award points for a SiteLink receipt.
- Noke smart locks: unlock, unit summary, guest sharing with SMS PIN, guest login by PIN, unlock-history PDF email.
- Facility gate/access PIN display (behind an email OTP).
- Notification inbox (push itself is sent by other code paths).
- Static content, FAQ, posts (articles), contact list, master data, app deep-link files.
- Feedback form (emails the company info mailbox).
- "Express" module (SG only): a separate small storage product with its own users, units and Stripe charge.
- Dev endpoints (Redis read/write/delete, outbound IP).

What I did **not** find in this project: unit search / availability from SiteLink, reservations, move-in,
move-out, autopay/recurring charge jobs, referrals. (There is an `IsRecurring` flag on saved cards and a
`RecurringPaymentLog` entity, but no code here charges cards on a schedule — inferred that recurring charging,
if any, lives in another project.)

### 1.2 Stack

- `MA/mobile_api.csproj`: `netcoreapp3.1`, ASP.NET Core Web API.
- EF Core 3.1 + `Pomelo.EntityFrameworkCore.MySql` 3.1.1 (MySQL), plus raw `MySql.Data` commands in a few places.
- Three closed-source in-house DLLs checked into `MA/Lib/`: `Codigo.UnitOfWork.MySql.dll` (repository + paging via
  stored procedure `sp_GetPagingData`), `Codigo.DataContract.dll` (response envelope `ApiResponseModel<T>`,
  `ResponseCode`), `Codigo.Crypto.dll` (AES with `Rijndael`, PBKDF2 hasher). Source code is not in the repo.
- `StackExchange.Redis` 2.2.4, `Stripe.net` 37.33.0, `SendGrid` 9.24.1, `SMSGlobal` 1.1.0, `AWSSDK.SimpleEmail` and
  `AWSSDK.SimpleNotificationService` (referenced, SES not used, SNS code present but unused), `RestSharp` 106,
  `DinkToPdf` 1.0.8 + native `libwkhtmltox.*`, `HtmlAgilityPack`, `HtmlSanitizer`, `AspNetCoreRateLimit` 4.0.0,
  `AutoMapper` 9, `log4net` + `MicroKnights.Log4NetAdoNetAppender` (logs into MySQL), `Swashbuckle` 5.4.1,
  `Microsoft.AspNetCore.Mvc.Versioning` 4.1.1, `System.ServiceModel.*` 4.4 (SiteLink SOAP client),
  `Bogus` (fake-data lib, referenced in production code — `MA/BL/ExpressBL.cs:2` imports it).
- SOAP client code generated in `MA/Connected Services/SiteLinkService/Reference.cs` (CallCenterWs) and
  `MA/Connected Services/SitelinkReportingService/Reference.cs` (ReportingWs). Endpoint
  `https://api.smdservers.net/CCWs_3.5/...` is hard-coded there.
- Container: `MA/Dockerfile` — `aspnet:3.1-focal`, `ENV TZ=Asia/Singapore`, downloads `libwkhtmltox.so` from GitHub
  at build time.

### 1.3 Startup and middleware pipeline

`MA/Program.cs`: loads `log4net.config`, Kestrel with `AddServerHeader = false`.

`MA/Startup.cs` `ConfigureServices`:

| Item | What | Where |
|---|---|---|
| CORS | Policy `AllowOrigin`: any header, any method, **any origin (`SetIsOriginAllowed(origin => true)`) with credentials** | `MA/Startup.cs:92-103` |
| API versioning | Default 1.0, assume default when missing, report versions. Routes are `/v{version}/...`; most actions accept 1.0 and 1.1 | `MA/Startup.cs:107-112` |
| Redis | One `ConnectionMultiplexer` from `Redis:ConnectionString`, `IDatabase` singleton | `MA/Startup.cs:114-115` |
| EF Core | `AddDbContextPool<Context>` with `Database:esConnectionString` | `MA/Startup.cs:118-122` |
| Stripe | Global static `StripeConfiguration.ApiKey = Stripe:SecretKey` | `MA/Startup.cs:140` |
| Health | `AddHealthChecks()`; mapped at `/healthcheck` and at `/` | `MA/Startup.cs:141, 496, 527` |
| Auth scheme "BasicAuthentication" | One app-wide username/password from `BasicAuth:UserName` / `BasicAuth:Password` | `MA/Startup.cs:151-152`, `MA/Handlers/BasicAuthenticationHandler.cs`, `MA/Services/UserService.cs` |
| Auth scheme "Bearer" | JWT HS256, key `Jwt:Key`, issuer = audience = `Jwt:Issuer`, lifetime checked, zero clock skew. Token also read from cookie `esAccessToken`. 401 body code 401 | `MA/Startup.cs:156-202` |
| Auth scheme "RefreshTokenBearer" | Same key; token also read from cookie `esRefreshToken`; failure code 498 | `MA/Startup.cs:203-247` |
| Swagger | Doc "v1", Basic + Bearer security schemes, XML comments from `mobile_api.xml`, adds optional header `client-type` | `MA/Startup.cs:253-305`, `MA/Handlers/HeaderHandler.cs` |
| Rate limit | `AspNetCoreRateLimit`, in-memory, real IP from header `X-Real-IP`, 8 rules (see §8) | `MA/Startup.cs:315-384` |
| PDF | `SynchronizedConverter(new PdfTools())` singleton (DinkToPdf) | `MA/Startup.cs:386` |
| JSON | System.Text.Json with custom `DateTimeConverter` | `MA/Startup.cs:392-395`, `MA/Common/DateTimeConverter.cs:38` |
| DI | All BL/DAL/services as Transient; `QueuedHostedService` + `BackgroundTaskQueue` | `MA/Startup.cs:399-460` |
| Hangfire | Fully commented out (was MySQL storage, tables `api_hangfire_*`) | `MA/Startup.cs:63-88, 529-543` |

`Configure` order (`MA/Startup.cs:462-544`):

1. `RateLimitMiddleware` (subclass of `IpRateLimitMiddleware`; quota response is **HTTP 200** with body code 429 —
   `MA/Handlers/RateLimitMiddleware.cs:30`).
2. `ResponseMiddleware` — adds security headers (nosniff, HSTS 90 days, CSP with `*.extraspaceasia.com.{country}`,
   X-Frame-Options SAMEORIGIN, no-cache, Referrer-Policy, Permissions-Policy) — `MA/Handlers/ResponseMiddleware.cs`.
3. Developer exception page in Development only.
4. CORS.
5. `UseStatusCodePages` with an empty body (all code commented).
6. Health checks `/healthcheck`; Swagger JSON `/swagger/v1/swagger.json`, UI `/swagger` (**enabled in every
   environment**, no auth).
7. `MetaDataMiddleware` (app version gate using table `app_version`) is **commented out** (`MA/Startup.cs:503`).
8. `OptionsMiddleware` — the real session check (see §3): copies cookie `esAccessToken` into the
   `Authorization` header, then for any Bearer token checks the DB with stored procedure `sp_CheckToken`
   (`MA/Handlers/OptionsMiddleware.cs:34-112`).
9. `UseHttpsRedirection`, `UseStaticFiles` (`wwwroot/fonts`, `wwwroot/receipt_form.html`), `UseRouting`,
   `UseAuthorization`. **`UseAuthentication()` is never called.** It still works because every `[Authorize]`
   names its scheme, so the authorization middleware authenticates per scheme (inferred from framework behaviour).
10. Culture fixed to `en-US` with short date `dd/MM/yyyy` (`MA/Startup.cs:510-520`).
11. `CustomLogger.Configure(emailService, env)` — every `LogErrorWithMetadata` call also **sends an email
    synchronously** to a hard-coded company tech mailbox (`MA/Common/CustomLogger.cs:70`, template
    `MA/emailTemplates/error_notification.html`).

Exceptions: no global exception middleware. Each action has its own try/catch that returns
`ExceptionHandler<T>.ExceptionError()` = code 500 + generic message, after writing an exception log
(`MA/Handlers/ExceptionHandler.cs`, `MA/Common/LogHelper.cs`).

Logging: `ILogger` (console by default; destination decided by infra — agent C) through `CustomLogger`
(JSON with Action/UserId/Message), plus log4net ADO appenders that insert into MySQL tables via
`sp_ErrorLog`, `user_payment_log`, `debug_log` (`MA/log4net.config`), plus `MA/DAL/MobileApiLoggerDAL.cs`
which inserts Noke call traces into table `api_logs` in the **log database** (`Database:LogConnectionString`),
plus `sitelink_transaction` rows for every SiteLink call (`MA/Services/SiteLink/SiteLinkAPIs.cs:2050-2083`).

### 1.4 Response envelope

All controller actions return `Ok(ApiResponseModel<T>)` → **HTTP 200 even for errors**; the real result is in the
body. JSON names are `error_code`, `error_msg`, and the payload (named `data`, inferred). Evidence: the reset-password
page reads `data.error_code == 0` and `data.error_msg` (`MA/emailTemplates/reset_password.html:203-206`); the
DataContract DLL contains `JsonPropertyName` values `error_code`, `error_msg`, `error_title`, `current_dt`,
`data_error_code`, `data_error_msg`. Success code is **0** (`ErrorCode.SUCCESS`, `MA/Common/StructCollection.cs`),
but the Express module returns `200` as success code. Error codes 700-801 are app-specific, and some numbers are
**reused for two meanings** (709, 711-715) — `MA/Common/StructCollection.cs`.

Exceptions to HTTP 200: JWT challenge 401; refresh failure 401 + header `error-code: 498`; `OptionsMiddleware` 401;
webhook 400; PDF downloads return `application/pdf`; content pages and the reset-password page return HTML.

Dates: the custom converter writes `DateTime` as `yyyy-MM-ddTHH:mm:sssZ` (`MA/Common/DateTimeConverter.cs:38`).
`sss` is "seconds twice", so the seconds part comes out with three digits (for example `...:055Z`), and `Z` is
added whatever the real kind is. The Flutter app must already tolerate this. Nullable `DateTime?` values probably
use the default ISO format (System.Text.Json 3.1 did not apply a `JsonConverter<DateTime>` to nullables —
inferred, verify with captured responses).

### 1.5 Size

| Folder | .cs files | Lines | Note |
|---|---|---|---|
| Controllers | 15 | 4,844 | 13 with routes |
| BL | 13 | 5,419 | `UserBL` 1,746, `AuthenticationBL` 1,280, `PaymentBL` 782 |
| DAL | 14 | 7,105 | `PaymentDAL` alone 3,199 |
| Services | 19 | 5,557 | `SiteLinkAPIs` 2,088, `UniqueGiftAPIs` 700 |
| Handlers | 11 | 795 | middleware, auth handlers |
| Common | 9 | 773 | enums, error codes, logger, utils, point maths |
| Model | 114 | 2,871 | request/response DTOs |
| Entities | 103 | 7,165 | EF entities + `Context.cs` (97 DbSets, incl. CMS and Hangfire tables) |
| Connected Services | 2 | 5,054 | generated SOAP proxies |
| emailTemplates | 25 files | — | HTML templates incl. `sg/` and `my/` PDF variants |
| **Total** | **302** | **~40,000** | |

### 1.6 Layers and request flow

```
HTTP → RateLimit → ResponseMiddleware → CORS → OptionsMiddleware (cookie→header, sp_CheckToken)
     → Routing → Authorization([Authorize(AuthenticationSchemes=...)])
     → Controller (logs request, AutoMapper Request→Model, TryValidateModel, reads UserId claim)
     → BL (business rules, builds ApiResponseModel)
     → DAL (EF via Codigo UnitOfWork; TransactionScope; some raw SQL)
     → Services (SiteLinkAPIs SOAP, StripePaymentService, NokeService REST, UniqGift/WOGI REST,
                 SendGrid email, SMSGlobal SMS, FCM push, Redis cache)
```

- **Controllers** (`MA/Controllers/`): thin, but all repeat the same pattern. `AccountController` and
  `ExpressController` inherit `ApiBaseController`, which adds `XssValidationFilter` (HTML-encodes string
  properties of an argument named `model` when the sanitizer would change them). Others inherit `ControllerBase`
  directly and get no filter.
- **BL** (`MA/BL/`): one class per area. Mixed concerns: BL also calls SiteLink, Noke, email directly.
- **DAL** (`MA/DAL/`): EF repositories plus large business logic (the whole payment flow lives in `PaymentDAL`).
- **Services** (`MA/Services/`): external system clients. `RedisCahceService` (sic) is also a read-through cache in
  front of SiteLink for ledgers, bills, invoices, receipts, PDFs.
- **Handlers** (`MA/Handlers/`): auth handlers, middleware, JWT creation, exception handler.
- **Common** (`MA/Common/`): `EnumCollection` (statuses), `StructCollection` (error codes/messages),
  `GeneralUtility`, `PointCalculator`, `CustomLogger`, `LogHelper`, `MappingProfile` (AutoMapper).
- **Lib** (`MA/Lib/`): the three closed-source DLLs.
- **Model** (`MA/Model/Request|Response|Info`): DTOs; snake_case and PascalCase both appear in JSON.
- **Entities** (`MA/Entities/`): EF Core scaffold of the shared MySQL DB (the full model is agent C's job).

---

## 2. Route inventory

**81 routed actions** in 13 controllers (82 `[Http*]` attributes; one is `[NonAction]`). Plus `/healthcheck`, `/`
(health), `/swagger`, static files. `SpaceController` and `ApiBaseController` have no routes.

Legend:
- Version column: `v1` = only `/v1/...`; `v1+1.1` = both `/v1/...` and `/v1.1/...` work (same code).
- Auth: **App-Basic** = HTTP Basic with the one shared app credential (`BasicAuth:*`, shipped inside the app);
  **JWT** = Bearer access token (header or `esAccessToken` cookie) + DB session check; **JWT-refresh** = refresh
  token scheme; **None** = no auth at all.
- Routes are case-insensitive.

### 2.1 `AuthenticationController` — base `/v{ver}/Authentication` (`MA/Controllers/AuthenticationController.cs`)

| Verb | Route | Ver | Auth | Purpose | Calls |
|---|---|---|---|---|---|
| POST | `/FirstLogin` | v1+1.1 | App-Basic | Start first-time registration: check email is an active SiteLink tenant, email a 6-digit OTP | `AuthenticationBL.FirstLogin` → SiteLink `TenantListDetailed_v2`, `AuthenticationDAL.GenerateVerifyPin`, SendGrid `opt_email.html` |
| POST | `/GetVerifyPin` | v1+1.1 | App-Basic | Resend OTP (same code as FirstLogin) | same |
| POST | `/VerifyOTP` | v1+1.1 | App-Basic | Check OTP; returns `setToken` (= `user_pin.id`) | `AuthenticationBL.VerifyPin` |
| POST | `/SetPassword` | v1+1.1 | App-Basic | Create local user from SiteLink data, set SiteLink web password, log in | `AuthenticationBL.SetPassword` → SiteLink `TenantListDetailed_v2`, `LedgersByTenantID`, `TenantUpdate`; `UserDAL.CreateAndSetPassword` / `UpgradeRecordOnlyUser` |
| POST | `/Login` | v1+1.1 | App-Basic | Email + password login (checked by SiteLink) | `AuthenticationBL.Login` → SiteLink `TenantLogin` per facility |
| POST | `/ChangePassword` | v1+1.1 | JWT | Change SiteLink web password; kills other sessions | `AuthenticationBL.ChangePassword` → `TenantLogin`, `TenantUpdate` |
| POST | `/ForgotPassword` | v1+1.1 | App-Basic | Create reset token, email reset link | `AuthenticationBL.ForgotPassword`, SendGrid `forgot_password.html` |
| GET | `/ResetPassword?token=` | v1+1.1 | None | Serve the HTML reset page (from `reset_password.html`) | `AuthenticationBL.ValidateResetPasswordToken` |
| POST | `/ResetPassword` | v1+1.1 | App-Basic | Set new password with reset token (called by that page) | `AuthenticationBL.ResetPassword` → SiteLink `TenantUpdate` |
| PUT | `/UpdateDevice` | v1+1.1 | JWT | Save push token (deviceType 1 Android / 2 iOS) | `AuthenticationDAL.UpdateDeviceToken` → table `user_device` |
| PUT | `/Logout` | v1+1.1 | None (parses Bearer itself) | Delete this session + push device | `AuthenticationDAL.Logout` |
| PUT | `/RefreshToken` | v1+1.1 | JWT-refresh | New access + refresh token | `AuthenticationBL.RefreshToken` |
| POST | `/Guest/VerifyPIN` | v1 | App-Basic | Noke guest login by 6-digit share PIN; IP lock-out | `AuthenticationBL.GuestVerifyPIN` → Noke `/user/locks/` |
| GET | `/LoggedInDevices` | v1+1.1 | JWT | List sessions (device name/uuid/type) | `AuthenticationDAL.GetUserLoggedInDevices` |
| PUT | `/LoggedInDevices/Logout` | v1+1.1 | JWT | Log out chosen device uuids; clears cookies if it was the caller | `AuthenticationDAL.LogoutLoggedInDevice` |

Login-type responses also set cookies `esAccessToken` / `esRefreshToken` (HttpOnly, Secure, SameSite=None,
domain `extraspaceasia.com.{country}`) — `MA/Controllers/AuthenticationController.cs:903-934`.

### 2.2 `AccountController` — base `/v{ver}/Account` (`MA/Controllers/AccountController.cs`)

| Verb | Route | Ver | Auth | Purpose | Calls |
|---|---|---|---|---|---|
| GET | `/GetProfile` | v1+1.1 | JWT | Profile + unread count + points + expiring points | `AuthenticationBL.GetProfile` |
| POST | `/UpdateProfile` | — | — | **`[NonAction]` — disabled** (line 128) | (`UserBL.UpdateProfile`) |
| GET | `/GetLedgers` | v1+1.1 | JWT | My units/ledgers from SiteLink (cached 5 min) + Noke lock data | `UserBL.GetLedgers` → `RedisCahceService.GetLedgers` → SiteLink; Noke `/user/locks/`; table `noke_unit` |
| GET | `/GetLedgersOld` | v1+1.1 | JWT | Same without Noke | `UserBL.GetLedgersOld` |
| GET | `/GetFacilityPinCode` | v1+1.1 | JWT | Email a 6-digit OTP before showing gate PINs | `UserBL.GetVerifyFacilityPinCode` → table `verify_facility_pin`, SendGrid `facility_pin_email.html` |
| POST | `/VerifyFacilityPinCode` | v1+1.1 | JWT | Check OTP, return gate access codes (`sAccessCode`) per unit | `UserBL.VerifyFacilityPinCode` → SiteLink `TenantListDetailed_v2`, `LedgersByTenantID` |
| PUT | `/UpdateNotificationSetting?allowPush=` | v1+1.1 | JWT | Push on/off | `UserDAL.UpdateNotificationSetting` |
| GET | `/GetPointTransaction?Page=` | v1+1.1 | JWT | Points history, 10 per page | `UserBL.GetPointTransaction` → `sp_GetPagingData` on `point_transaction` |
| POST | `/Noke/RequestUnlock` | v1 | JWT | Get unlock commands for a lock (mac + session) | `UserBL.RequestUnlock` → Noke `/lock/unlock/` |
| POST | `/Noke/RequestGuestUnlock` | v1 | App-Basic | Guest unlock using share PIN | `UserBL.RequestUnlock` (email empty → phone from share) |
| POST | `/Noke/GetSummary` | v1 | JWT | My Noke units, locks, 30-day unlock history, shares | `UserBL.GetSummary` → Noke `/user/locks/`, `/activity/search/`, `/user/shares/` |
| POST | `/Noke/AddShare` | v1 | JWT | Share unit access with a phone number; SMS a PIN | `UserBL.AddShare` → Noke `/user/share/create/`, SMSGlobal, table `noke_shares` |
| POST | `/Noke/RemoveShare` | v1 | JWT | Remove share | `UserBL.RemoveShare` → Noke `/user/share/delete/` |
| POST | `/Noke/SendAccessHistory` | v1 | JWT | Email 30-day unlock history PDF | `UserBL.SendSummaryReport` → Noke `/activity/search/`, SiteLink `SiteInformation`, `TenantInfoByTenantID`, DinkToPdf, SendGrid |
| DELETE | `/DeleteProfile` | v1+1.1 | JWT | Email account-delete OTP (10 min) | `UserBL.DeleteProfileRequest` → table `otps` |
| DELETE | `/DeleteProfile/{otpCode}` | v1+1.1 | JWT | Confirm delete: anonymise user, delete Stripe customer, sessions | `UserDAL.DeleteProfile` |

### 2.3 `PaymentController` — base `/v{ver}/Payment` (`MA/Controllers/PaymentController.cs`)

| Verb | Route | Ver | Auth | Purpose | Calls |
|---|---|---|---|---|---|
| GET | `/GetAllPaymentCard` | v1+1.1 | JWT | List saved cards from Stripe (ids AES-encrypted) | `PaymentDAL.GetAllPaymentCard` → Stripe PaymentMethods list, Customer get |
| POST | `/AddPaymentCard` | v1+1.1 | JWT | Add a card from a Stripe token/PaymentMethod id; **only one card allowed** | `PaymentBL.AddPaymentCard` → Stripe Customer create / PaymentMethod attach |
| PUT | `/UpdatePaymentCard` | v1+1.1 | JWT | Update holder name/expiry, set default, recurring flag | Stripe PaymentMethod update, Customer update |
| PUT | `/UpdateDefaultPaymentCard` | v1+1.1 | JWT | Set default card | Stripe Customer update |
| POST | `/DeletePaymentCard` | v1+1.1 | JWT | Delete card | Stripe PaymentMethod delete |
| GET | `/GetMyBills` | v1+1.1 | JWT | Outstanding per facility/unit (Redis 1 min) | `RedisCahceService.GetBill` → SiteLink `LedgersByTenantID`, `ChargesAndPaymentsByLedgerID`, `ChargesAllByLedgerID` |
| POST | `/MakePayment` | v1+1.1 | JWT | **Disabled**: returns code 404 "Not Found" (lines 478-482) | — |
| POST | `/MakePayment2` | v1+1.1 | JWT | **Disabled 2026-08-02** (commit `25ffa0e7`): returns 404 (lines 546-550). Was the main in-app payment | (was `PaymentBL.UnitPayment`) |
| GET | `/GetInvoices` | v1+1.1 | JWT | **Always returns empty list, outstanding 0** ("temporarily removed due to request from PM", `MA/BL/PaymentBL.cs:176-191`) | — |
| GET | `/GetReceipts` | v1+1.1 | JWT | Receipts from SiteLink (Redis 5 min) | `RedisCahceService.GetReceipts` |
| GET | `/GetPaymentTransaction` | v1+1.1 | JWT | App payments of last 6 months + next bill date + card last-4 | `PaymentDAL.GetAllTransaction`, Stripe |
| GET | `/GetPaymentHistory` | v1+1.1 | JWT | Legacy `user_payment` table, last 12 months | `PaymentDAL.GetAllPaymentHistory` |
| GET | `/GetReceiptDetail?receipt_no=` | v1+1.1 | JWT | One receipt (must be in my receipts and in `payment_facility`) | `PaymentBL.GetReceiptDetail` |
| GET | `/GetPaymentDetail?payment_id=` | v1+1.1 | JWT | Legacy payment detail | `PaymentDAL.GetPaymentDetail` |
| GET | `/DownloadReceiptPdf?receipt_no=&site_id=` | v1+1.1 | JWT | Receipt PDF (HTML template → wkhtmltopdf) | `RedisCahceService.DownloadReceipt` → `SiteLinkAPIs.GetPaymentReceiptPdf` |
| GET | `/DownloadInvoicePdf?invoice_id=` | v1+1.1 | JWT | Invoice PDF (only invoices of the caller) | `RedisCahceService.DownloadInvoice` |
| GET | `/StripePaymentStatus?paymentId=` | v1+1.1 | None (`[AllowAnonymous]`) | Status of a pending 3-D Secure PaymentIntent (needs Redis key `stripe_3dpayment_{id}`) | `PaymentBL.GetStripePaymentStatus` → Stripe PaymentIntent get |

### 2.4 `WebhookController` — no base route (`MA/Controllers/WebhookController.cs`)

| Verb | Route | Ver | Auth | Purpose | Calls |
|---|---|---|---|---|---|
| POST | `/webhook` | none | None (`[AllowAnonymous]`) | Stripe webhook. Handles only `payment_intent.succeeded` (and ignores `payment_intent.requires_action`). **No signature check** | `PaymentBL.HandleWebhookPayment` → `PaymentDAL.HandlePaymentIntent` |

### 2.5 `RewardController` — base `/v{ver}/Reward` (`MA/Controllers/RewardController.cs`)

| Verb | Route | Ver | Auth | Purpose | Calls |
|---|---|---|---|---|---|
| POST | `/EarnPoints` | v1+1.1 | **None** | Partner server-to-server: award points for a SiteLink receipt (email, locationCode, ledgerId, receiptNo?, receiptDate). Creates a "record-only" user if needed | `RewardBL.EarnPoints` → `SiteLinkUserHydrator`, `RewardPointService` → SiteLink `ChargesAndPaymentsByLedgerID` |
| POST | `/GetRewardList` | v1+1.1 | JWT | Catalogue page (10/page), filter category, sort | `RewardDAL.GetList` (`sp_GetPagingData`) |
| GET | `/GetFeaturedRewardList` | v1+1.1 | JWT | 4 featured + 4 newest | `RewardDAL` |
| POST | `/RedeemReward` | v1+1.1 | JWT | Spend points for a reward; issues UniqGift/WOGI voucher when third-party | `RewardDAL.RedeemReward` |
| GET | `/GetMyWallet?activeWallet=` | v1+1.1 | JWT | My redeemed vouchers (refreshes UniqGift status first) | `RewardDAL.GetMyWallet` |
| POST | `/GetMyExtraSpaceWallet` | v1+1.1 | JWT | My active Extra Space rent vouchers, excluding ids in `list_id` | `RewardDAL.GetMyExtraSpaceWallet` |

### 2.6 `NotificationsController` — base `/v{ver}/Notifications`

| Verb | Route | Ver | Auth | Purpose | Calls |
|---|---|---|---|---|---|
| GET | `/GetList?Page=` | v1+1.1 | JWT | Inbox, 100 per page | `NotificationDAL.GetList` (`sp_GetPagingData`) |
| PUT | `/IsRead?id=` | v1+1.1 | JWT | Mark read (own only) | `NotificationDAL.UpdateRead` |
| POST | `/DeleteNotifications` | v1+1.1 | JWT | Delete own notifications | `NotificationDAL.Delete` |

### 2.7 Content, FAQ, Post, Master, Feedback

| Controller | Verb | Route | Ver | Auth | Purpose |
|---|---|---|---|---|---|
| Content | GET | `/v{ver}/Content/{url}` | v1+1.1 | None | HTML page for `about-us`, `terms-of-service`, `privacy-policy`, `about-membership`, `cancellation-policy` from table `contents` |
| Content | GET | `/v{ver}/Content/GetContactUs` | v1+1.1 | None | All facility contacts (`contact` join `master_facility`) |
| Faq | GET | `/v{ver}/Faq` | v1+1.1 | App-Basic or JWT | All FAQs |
| Post | GET | `/v{ver}/Post/GetList?Page=&Keyword=` | v1+1.1 | JWT or App-Basic | Articles, 10/page, keyword search (**SQL injection, §8**) |
| Post | GET | `/v{ver}/Post/GetDetail?id=` | v1+1.1 | JWT or App-Basic | One article with tags |
| Master | GET | `/v{ver}/Master/GetMasterData` | v1+1.1 | App-Basic or JWT | Feedback subjects, reward categories, facilities, content links, Noke share durations `[1,7,30,-1]`, reward text |
| Master | GET | `/.well-known/assetlinks.json` | — | None | Android App Links file (hard-coded) |
| Master | GET | `/apple-app-site-association` | — | None | iOS universal links (hard-coded, two app IDs) |
| Feedback | POST | `/v{ver}/Feedback/CreateFeedback` | v1+1.1 | JWT | Save feedback, email the company info mailbox |

### 2.8 `ExpressController` — base `/v1/Express` (SG only; `MA/Controllers/ExpressController.cs`)

All v1 only, auth **App-Basic or JWT**, no ownership checks (user id comes in the body/route).

| Verb | Route | Purpose | Calls |
|---|---|---|---|
| GET | `/getMasterData?siteId=` | Express facilities, unit types, sizes | `ExpressBL.GetMasterData` |
| GET | `/getUnits?siteId=&unitTypeId=&parentArea=&sizeGroup=` | Units with storage-plan rates | `ExpressDAL.GetExUnits` |
| GET | `/GetUnitSizes?siteId=&unitTypeId=` | Size groups | `ExpressDAL.GetExUnitSizes` |
| GET | `/GetUnitTypes?siteId=` | Main unit types | `ExpressDAL.GetExUnitTypesMain` |
| GET | `/GetFacilities` | Express facilities | `ExpressDAL.GetFacilities` |
| POST | `/AddExUser` | Create **or update by email** an Express user incl. password | `ExpressDAL.AddExUser` (PBKDF2 hash) |
| GET | `/GetExUser/{id}` | Get Express user by id | `ExpressDAL.GetExUser` |
| POST | `/AddExUserPaymentCard` | Add Stripe card for an Express user id | `ExpressDAL.AddExUserPaymentCard` → Stripe |
| GET | `/GetExUserPaymentCard/{id}` | Get card row | `ExpressDAL.GetExUserPaymentCard` |
| POST | `/MakeExPayment` | Charge unit security deposit, reserve unit, email | `ExpressDAL.MakeExPayment` → Stripe PaymentIntent, SendGrid |
| GET | `/GetReservedUnit/{email}` | Reserved units for an email | `ExpressDAL.GetExReservedUnits` |

### 2.9 `DevController` — base `/v{ver}/Dev` (`MA/Controllers/DevController.cs`)

| Verb | Route | Ver | Auth | Purpose |
|---|---|---|---|---|
| GET | `/GetRedis?key=` | v1+1.1 | App-Basic | Read **any** Redis key |
| POST | `/PostRedis?key=&message=` | v1+1.1 | App-Basic | Write **any** Redis key |
| DELETE | `/DeleteRedis?key=` | v1+1.1 | App-Basic | Delete **any** Redis key |
| GET | `/outbound-ip` | v1 | None | Calls `https://api.ipify.org`, returns server's public IP (added 2026-01-16 as "TEMP") |

---

## 3. Auth model

### 3.1 Two kinds of caller

1. **Before login** the app calls with HTTP Basic, one shared app credential (`BasicAuth:UserName`,
   `BasicAuth:Password`; checked in `MA/Services/UserService.cs`). It is the same for every install, so it is an
   app identifier, not a secret. The reset-password HTML page even embeds it for its own POST
   (`MA/Controllers/AuthenticationController.cs:533-555`).
2. **After login** the app calls with `Authorization: Bearer <JWT>`. The web app instead uses the cookie
   `esAccessToken`; `OptionsMiddleware` copies it into the header unless the request already carries Basic auth.

Headers the app sends: `client-type: android|ios|web` (used to set the session device type,
`MA/Handlers/RequestContext.cs`); `app-version` / `app-version-code` are read only by the disabled
`MetaDataMiddleware`.

### 3.2 Registration (first login) — no social login, no SMS OTP

1. `POST FirstLogin {email, loginDeviceInfo}` — if no local user: device info cached in Redis
   `login_device_info_{email}` (2 h); SiteLink `TenantListDetailed_v2(email)`; requires a row with
   `bHasActiveLedger == "true"` at a facility listed in `master_facility`. Then a 6-digit OTP row in `user_pin`
   (expires 5 min, `MA/DAL/AuthenticationDAL.cs:113-150`) is emailed with SendGrid. Existing users get code 721
   `FIRST_LOGIN_ATTEMPT`. No active ledger → 713 `NO_SPACE_RENTAL`.
2. `POST VerifyOTP {email, pin}` → returns `setToken` = `user_pin.id` (GUID).
3. `POST SetPassword {setToken, password}` — rejects passwords found in `key_value["common password"]`;
   rebuilds tenant data from SiteLink ledgers (all facilities); creates the `user` row (or upgrades a
   "record-only" user created by EarnPoints — `MA/BL/AuthenticationBL.cs:390-402`); writes `user_tenantsite`
   rows; then **sets the password in SiteLink** with `TenantUpdate(sWebPassword)` for every tenant/site; then
   issues tokens.

**Passwords are not stored locally for app customers.** `user.password_hash` stays empty
(`MA/DAL/UserDAL.cs:344-400`). SiteLink's tenant web password is the only credential. (Express users are different:
they have a local PBKDF2 hash, `MA/DAL/ExpressDAL.cs:380, 405-406`.)

### 3.3 Login

`POST Login {email, password, loginDeviceInfo}` (`MA/BL/AuthenticationBL.cs:470-581`):
- Local user must exist and have `user_tenantsite` rows; status Inactive → 708 `ACCOUNT_SUSPENDED`.
- For each tenant site: SiteLink `TenantLogin(email, password, locationCode)`; any `Ret_Code > 0` = success.
- The "has active ledger" check is forced true: `bHasActiveLedger = true; //allow for temporarily` (line 527).
- Creates session row in `user_token` (id = random GUID "unique key"), clears Redis `user_invoice_{id}`,
  `user_ledger_{id}`.
- **One mobile session per user**: a login from Android/iOS deletes all other Android/iOS sessions and all push
  devices of that user (`MA/DAL/AuthenticationDAL.cs:405-417`). Web sessions are kept.

### 3.4 Tokens

- Access JWT (`MA/Handlers/JwtHandler.cs:36-62`): HS256 with `Jwt:Key`; claims `UserId`, `UniqueKey` (session id),
  `UserName`/`Name` (email), `Role = "tenant"`, `AppType`. Lifetime `Jwt:AccessTokenExpiry` **minutes** (20 in all
  configs).
- Refresh JWT (`JwtHandler.cs:66-89`): claims `RefreshId`, `UniqueKey`, `ExpiryOn`. Lifetime
  `Jwt:RefresTokenhExpiry` (sic) **minutes** in the JWT, but the API response and the cookie say **days**
  (`MA/BL/AuthenticationBL.cs:443, 561, 966`). Production value is 1 → the refresh JWT is valid for 1 minute only
  (staging 15). Likely bug; see §10.
- Session row `user_token.expiry_on` = now + `AccessTokenExpiry` **days** (20 days) (`AuthenticationDAL.cs:399`).
- Every Bearer request is checked by `OptionsMiddleware` → stored procedure `sp_CheckToken(UserID, AccessToken)`;
  no row → 401; status Inactive → 708. The token must match the latest stored access token, so this gives
  server-side logout/revocation. (The procedure body is not in this repo — agent C.)
- `PUT RefreshToken` builds a new pair from the session id, always with `AppType = web`
  (`AuthenticationBL.cs:948`), and stores them on the same `user_token` row.
- Change password / reset password delete other sessions (`CleanUserTokens`, `AuthenticationDAL.cs:313-315, 513`).

### 3.5 Forgot / reset password

`POST ForgotPassword {email}` → row in `forgot_password` (expires 4 h) → token = AES-encrypted JSON
`{id, email, expiry}` (`Codigo.Crypto`, key material from `AES:*`) → email link to `GET /v1/authentication/ResetPassword?token=...`
→ HTML page → `POST ResetPassword {token, newPassword, confirmPassword}` → SiteLink `TenantUpdate` for each site.
**The API response of ForgotPassword also returns the full reset link in `data`** (`MA/BL/AuthenticationBL.cs:772`) —
see §8, this is account takeover.

### 3.6 Guest (Noke share) login

`POST Guest/VerifyPIN {pin}` — PIN from `noke_shares`; checks share duration (1, 7, 30 days or −1 unlimited);
IP lock-out after `Noke:ConsecutiveFailedCount` (3) wrong PINs within `Noke:ConsecutiveFailedInMin` (15) for
`Noke:BlockIPDurationInMin` (15), stored in `noke_pin_failed`. Client IP = `Connection.RemoteIpAddress`
(behind a load balancer this may be the balancer's IP — inferred). Returns the guest's locks with offline keys.
No JWT is issued; the guest then calls `Noke/RequestGuestUnlock` with App-Basic + PIN.

### 3.7 Config key names used for auth

`BasicAuth:UserName`, `BasicAuth:Password`, `Jwt:Key`, `Jwt:Issuer`, `Jwt:AccessTokenExpiry`,
`Jwt:RefresTokenhExpiry`, `AES:Password`, `AES:Salt`, `AES:HashAlgorithm`, `AES:IV`, `Country:ShortName`
(cookie domain), `Noke:ConsecutiveFailedCount`, `Noke:ConsecutiveFailedInMin`, `Noke:BlockIPDurationInMin`.

---

## 4. Feature areas

### 4.1 Units and ledgers (`GET Account/GetLedgers`)

- Source: SiteLink, live. `RedisCahceService.GetLedgers` (key `user_ledger_{userId}`, 5 min) →
  `SiteLinkAPIs.GetLedgerResponses` (`TenantListDetailed_v2`, `LedgersByTenantID`, `UnitsInformationByUnitID`).
- Next bill date rule (old helper, `MA/BL/UserBL.cs:641-656`): if `dPaidThru` is in the future → `dPaidThru + 1 day`;
  else `dAnniv` + 1 month/week/day by `sBillingFrequency`.
- Controller rounds the size to 2 decimals and blanks `Type` (`MA/Controllers/AccountController.cs:210-218`).
- Noke: for each facility with `master_facility.noke_site_id`, calls Noke `/user/locks/` as the user's email,
  matches lock unit by unit name + email, adds lock `mac`, `offlineKey`, `scheduledUnlockCmd` to the ledger, and
  inserts missing rows into `noke_unit` (`UserBL.cs:321-401`). Config `Noke:hardcode` + `Noke:hardcodeUnitNames`
  can force two test unit names (false in prod).
- Tables: `user`, `user_tenantsite`, `master_facility`, `noke_unit`; log DB `api_logs`.

### 4.2 Bills, invoices, receipts, PDFs

- **Bills** (`GetMyBills`, `SiteLinkAPIs.GetBillResponse` from line 1201): per unit, outstanding = sum of SiteLink
  charge balances `dcBal > 0`, **excluding Rent and Insurance charges that have no invoice number yet**; due date =
  `dPaidThru + 1 day`; facility status "All Paid" (total 0) / "Current" (earliest due > now) / "Overdue".
  Taxes come from SiteLink (`dcTax1`, `dcTax2`). Result also written to `user.outstanding_amount` and
  `user_tenantsite.outstanding_amount` (`UserDAL.UpdateOutstandingAmount`). Cache `user_bill_{userId}` 1 min.
- **Invoices**: list endpoint returns empty (PM request). Invoice PDF still works: invoices from SiteLink
  `TenantInvoicesByTenantID` (cache `user_invoice_{userId}` 5 min), template `emailTemplates/{country}/invoice_pdf.html`,
  placeholders filled from SiteLink `SiteInformation` + `TenantInfoByTenantID`.
- **Receipts**: SiteLink receipts (cache `user_receipt_{userId}` 5 min). Receipt PDF from template
  `emailTemplates/{country}/receipt_pdf.html`, receipt data from SiteLink Reporting `Receipts` over the last 6 months,
  `CustomerAccountsBalanceDetails`, `PaymentsByLedgerID`; card brand/last-4 from Stripe when an app payment exists.
  PDF HTML cached `pdf_receipt_{userId}_{no}` / `pdf_invoice_{userId}_{no}` 5 min.
- PDF rendering: HtmlAgilityPack downloads every `<img src>` and inlines it as base64, then DinkToPdf A4 320 DPI
  (`MA/Controllers/PaymentController.cs:882-920, 983-1021`). If the HTML has no `<img>`, `SelectNodes` returns null →
  exception (inferred bug).
- Tables: `payment_transaction`, `payment_facility`, `payment_unit`, `master_facility`, `user_payment` (legacy).

### 4.3 Saved cards (Stripe)

- The app tokenises the card with Stripe's SDK (publishable key on the client) and sends only `stripeToken`
  (a PaymentMethod id) — class `PaymentCardRequest` in `MA/Model/Request/PaymentCardModel.cs`. **The server never
  receives PAN or CVV.**
- First card → Stripe Customer created with that PaymentMethod as default; row `user_payment_card` stores
  AES-encrypted `stripe_customer_id`, `default_card`, `recurring_card`, `is_recurring`, `expiry_on`
  (`MA/DAL/PaymentDAL.cs:1308-1397`). Second card is refused ("You have added payment card", `PaymentBL.cs:507-519`).
- Card ids returned to the app are the AES-encrypted Stripe PaymentMethod ids.
- All Stripe calls use the platform key, no Connect account (cards live on the platform account).

### 4.4 Profile and account deletion

- Profile = local `user` row + unread notifications + points + points expiring.
- Profile update is disabled (`[NonAction]`); profile data is refreshed from SiteLink at registration (and by the
  `SyncTenantDataAsync` helper, which is no longer called from login — commented out, `AuthenticationBL.cs:509-518`).
- Delete: OTP in `otps` (type `account_delete`, 10 min) → anonymise `user` (random email/mobile/names, first name
  "Deleted Account {units}"), status Deleted (3), delete Stripe customer, `user_payment_card`, `user_token`,
  `user_device`, `user_pin` (`MA/DAL/UserDAL.cs:894-991`). SiteLink tenant is not touched.

### 4.5 Notifications

- Inbox table `user_notification` (types: Wallet, Bill, Point, VoucherExpiry, CreditExpired, New_Invoice, Payment,
  Content — `MA/Common/EnumCollection.cs`).
- Rows are created here only by the payment flow; others presumably by the CMS (agent B).
- Push: Firebase **legacy** HTTP API `https://fcm.googleapis.com/fcm/send` with `PushNotification:ServerKey` /
  `SenderID` (`MA/Services/Firebase/NotificationService.cs:42-45`). Google shut the legacy API down in 2024, so push
  from this code very likely fails today (inferred — check logs).
- Push tokens: table `user_device` (`UpdateDevice`).

### 4.6 In-app payment (`MakePayment2` → `PaymentBL.UnitPayment`) — disabled in SG, live in MY

Kept here because MY still runs it and the business rules matter for the rebuild.

Request: `{cardId, units:[{siteId, tenantId, ledgerId, unitId, unitName, amount, walletId?}]}`.

Checks (`MA/BL/PaymentBL.cs:383-464`):
- Duplicate guard: Redis `mobile_payment_userid_{userId}_cardid_{cardId}` holds the request for 5 min; the same
  request again → "payment failed".
- Total must be **≥ 10** (S$/RM, hard-coded).
- Each unit amount must be ≤ **12 × monthly rent** if the unit rate is cached in Redis `units_information_{locationCode}`
  (key written elsewhere — inferred CMS).
- `Stripe:threeDS` = true → `ConfirmPayment` (3-D Secure capable); false → `UnitPayment`. SG prod false, MY prod true.

Flow (`MA/DAL/PaymentDAL.cs:218-1251`, and the 3DS variant 1964-2310 + 2316-2885):
1. Group units by (site, tenant) → one `payment_facility` per group, one `payment_unit` per unit, all under one
   `payment` row.
2. Wallet voucher per unit (Extra Space rent voucher from `redeem_reward`, status 1): discount = fixed amount, or
   `percent/100 × amount`; capped at the unit amount; facility total = amount − discount. Facility total
   > 999,999 → refused.
3. **Stripe charge per facility**, `PaymentIntent` with `confirm=true`, `setup_future_usage=off_session`,
   `idempotency key = payment_facility.id`, metadata FacilityName/SiteID/UnitID/UnitName/TenantID/WalletID, statement
   suffix "Extra Space Asia". **Stripe Connect**: if the facility is not the default site (`SiteLink:SiteID`),
   the PaymentMethod is cloned to the facility's connected account (`master_facility.stripe_account`, AES-encrypted)
   and the charge is made there (`PaymentDAL.cs:429-471`).
   Amount in cents = `long.Parse(amount.ToString("#.00").Replace(".", ""))` (line 448).
4. If Stripe succeeded and a voucher was used: SiteLink `ApplyCredit` on the biggest open invoiced charge of the
   ledger, reason "Extra Space Rent Vouchers"; voucher marked Used.
5. **Post the payment into SiteLink**: `PaymentSimpleWithSource` per unit for (amount − voucher) — see §5.1, it
   sends a dummy test card number. Before/after it reads `dPaidThru` to store due date and paid-through date.
6. SiteLink OK → award points (`RewardPointService`, eligible = amount − voucher), queue receipt email.
   SiteLink fails → Return code −14 sets user status Overdue (0) and does **not** refund; any other failure →
   partial Stripe **refund** with the facility's own secret key (`master_facility.stripe_secret_key`), refund row in
   `payment_transaction`; email to the facility ("Failed Payment - Sitelink").
7. Status per unit/facility/payment: Success 1, Failed −1, Partial_Failed 2, Refunded 5. Push + inbox notification
   "Successful/Unsuccessful Payment". Clears Redis bill/receipt/invoice/ledger caches.
8. 3DS path: if Stripe returns `requires_action`, confirm with `return_url = {Site:WebUrl}/redirect/PaymentStatus`,
   cache the request in Redis `stripe_3dpayment_{paymentIntentId}` for 1,440 min and return code 801 with the
   redirect URL. Completion happens only in the **webhook** (`payment_intent.succeeded`) via `HandlePaymentIntent`
   (`PaymentDAL.cs:2991-3176`), which reads that Redis key; `GET StripePaymentStatus` lets the app poll.
9. The whole thing runs inside a `TransactionScope` (ReadUncommitted, 15 min) **around external calls**; a DB failure
   after Stripe and SiteLink succeeded loses the local record (inferred risk).

Tables: `payment`, `payment_facility`, `payment_unit`, `payment_transaction`, `redeem_reward`, `point_transaction`,
`user`, `user_notification`, `user_device`, `user_payment_card`, `master_facility`, `key_value`.

### 4.7 Loyalty: points, tiers, rewards, vouchers

- **Tier** by months since `user.membership_date` (= SiteLink ledger `dCreated`): ≥ 48 months Gold, ≥ 12 Silver,
  else Blue (`MA/Common/PointCalculator.cs`). Multiplier Gold 1.5, Silver 1.2, Blue 1.0.
- **Points** = `ceil(multiplier × eligible amount)`; points expire after 2 years; `user.points` incremented and a
  `point_transaction` row (type Earned 1) added. Idempotency key is the row's `description`:
  `"{locationCode} - ePoints received - {receiptNo}"`, or `"... - L{ledgerId} - {yyyyMMdd}"` when no receipt number
  (`MA/Services/Reward/RewardPointService.cs:75-89`).
- Eligible amount (EarnPoints path) = sum over SiteLink `ChargesAndPaymentsByLedgerID` lines whose payment time
  equals the receipt time **to the minute** and whose charge description is in `key_value["award_points_category"]`,
  of `PmtSum − PmtSumByCredit − PmtSumByTransferCredit − PmtSumByAppliedRefunds` (`PointCalculator.SumEligibleAmount`).
- **EarnPoints** (`MA/BL/RewardBL.cs:81-190`): no auth; finds facility by `LocationCode`; finds user by email, or
  builds a **record-only user** (status 4 `RecordOnly`, no password) from SiteLink and inserts it; awards; saves.
  At registration the record-only user is upgraded in place, keeping its points.
- **Redeem** (`MA/DAL/RewardDAL.cs:129-370`): overdue users blocked (715); reward must be active and not ended;
  spend points FIFO by expiry from Earned/Adjusted rows (`point_use`); create `redeem_reward` (wallet) with expiry
  (Extra Space voucher: fixed date or N months; third-party: 1 year or vendor expiry); `user.points −= exchange_point`;
  add Used transaction. Third-party vendor chosen by config `ThirdPartyGift` (`uniquegift` SG, `wogigift` MY):
  - UniqGift v3: OAuth client-credentials token, `POST {baseURL}/products/{productCode}` with `Idempotency-Key =
    redeem_reward.id`; open-value vouchers use **face value = exchange points** (1 point = 1 currency unit);
    voucher URL and id stored; status later synced by `GET /vouchers/{id}` on every wallet view.
  - WOGI: balance check first (`/balance`), then `/products/issue`; card id + voucher link stored.
  - Isolation ReadUncommitted, no row lock: two parallel redeems can double-spend (mitigated only by the
    1-per-3-min IP rate limit).
- **Extra Space rent vouchers** are used only through the payment flow (§4.6, SiteLink `ApplyCredit`).
- Master data text: "For every $1 spent, you will earn 1, 1.2 or 1.5 epoints…" (`MA/DAL/MasterDAL.cs`).
- Tables: `point_transaction`, `reward`, `reward_category`, `reward_image`, `redeem_reward`, `user`, `key_value`.

### 4.8 Noke smart locks

All Noke calls go through `MA/Services/NokeService.cs`: `POST {Noke:baseUrl}{path}` with headers
`Authorization: {Noke:apiKey}` (company API key), `CompanyId: {Noke:companyId}`, `SiteId: {facility.noke_site_id}`,
and **either** `Email` (owner) **or** `Phone` (guest) to say who is acting. Timeout 2 s. Every call is logged into
`api_logs` (log DB) including responses with offline keys.

- `RequestUnlock`: `/lock/unlock/` with lock `mac` + `session` (from the phone's BLE session) → returns unlock
  commands. Guest path uses the share's phone; share expiry checked.
- `GetSummary`: `/user/locks/` (units where Noke user email = me **or empty**, `MA/BL/UserBL.cs:854`),
  `/activity/search/` (unlock events of type `unlock.accessed_online_phone_bt` / `unlock.accessed_offline_phone`,
  last `Noke:UnlockedHistoyInPastDays` = 30 days; names resolved from `noke_shares` / `user`), `/user/shares/`.
- `AddShare`: `/user/share/create/` (countryCode, phone, unitId) → new unique 6-digit PIN (`System.Random`,
  `MA/Services/PinCodeGenerator.cs:28`) → row `noke_shares` → SMS via SMSGlobal with app download link
  (`SMS:AppDownloadUrl`) and PIN. Durations 1/7/30/unlimited days. Rate limit 10 per 15 min.
- `RemoveShare`: `/user/share/delete/` then delete row.
- `SendAccessHistory`: unlock history → HTML → PDF → email to the user, plus the first address in
  `Noke:HardCodeEmails` (empty in SG prod, a developer address in staging).
- `RemoveExpiredNokeShares` exists (`UserBL.cs:1302`) but **nothing schedules it** (Hangfire commented out).
- Tables: `noke_shares`, `noke_unit`, `noke_pin_failed`, `master_facility.noke_site_id`.

### 4.9 Facility gate PIN

`GetFacilityPinCode` emails a 6-digit OTP (`verify_facility_pin`, 5 min); `VerifyFacilityPinCode` returns SiteLink
ledger `sAccessCode` for every unit (`MA/BL/UserBL.cs:545-604`). Note: `TenantUpdate` writes
`sGateCode = sAccessCode` every time a password is set (`MA/Services/SiteLink/SiteLinkAPIs.cs`, `TenantUpdateAsync`),
which may overwrite a different gate code (inferred risk).

### 4.10 Content, FAQ, posts, contacts, feedback

- `contents` rows by `content_type`; `faq` + `faq_item`; `post`, `post_tag`, `tag`; `contact` + `master_facility`;
  `feedback` + `feedback_subject` (email to the company info mailbox, template `feedback_email.html`).
- Images/URLs built from `Site:S3Url` (bucket paths `rewards/`, `post/`, `reward-category/icon/`, `others/`).
- Content page uses content type `"text /html"` (with a space) — `MA/Controllers/ContentController.cs:74`.

### 4.11 Express module (SG only)

A small separate rental product with its own tables `ex_user`, `ex_user_payment_card`, `ex_units`, `ex_unit_types`,
`ex_unit_types_main`, `ex_unit_sizes`, `ex_unit_storage_plan`, `ex_unit_storage_plan_detail`, `ex_storage_plan`,
`ex_floors`, `ex_facility`, `ex_rental`, `ex_reserved_units`, `ex_payment_transaction` (deeper model: agent C,
`es_express`).
- Storage-plan rate = `security_deposit × (1 − discount_percent/100)`; plan name and months from
  `ExpressConfig:exUnitStoragePlanName` / `ExpressConfig:exUnitNoOfMonths`.
- `MakeExPayment` (`MA/DAL/ExpressDAL.cs:650+`): charges the unit's `security_deposit` (server value) with Stripe
  (Connect account like §4.6), sets unit status Reserved, records `model.Amount` (client value) in the transaction,
  computes the email total with **GST 9% hard-coded** (`ExpressDAL.cs:776`). I saw no check that the unit is still
  vacant before charging, and the "user not found"/"no card" branches build an error object but do not return it
  (null reference follows).

---

## 5. External integrations

### 5.1 SiteLink (SMD, CallCenterWs 3.5, SOAP)

Credentials on every call: `SiteLink:sCorpCode`, `SiteLink:sCorpUserName`, `SiteLink:sCorpPassword`; location =
`master_facility.location_code` (fallback `SiteLink:sLocationCode`). Default Stripe site = `SiteLink:SiteID`.
Client: `MA/Services/SiteLink/SiteLinkAPIs.cs`; every call also inserts a counter row into `sitelink_transaction`.

Operations called (wrapper → SOAP op):

| SOAP operation | Used for | Card data? |
|---|---|---|
| `TenantListDetailed_v2` (by email) | registration, login data, record-only user, facility PIN | no |
| `TenantLogin` | login, change password | password (tenant web password) |
| `TenantUpdate` | set/change/reset web password (`sWebPassword`); re-sends whole tenant record incl. `sSSN`, DOB | password |
| `TenantInfoByTenantID` | PDFs, tenant update | no |
| `LedgersByTenantID` | ledgers, bills, registration, paid-through dates | no |
| `UnitsInformationByUnitID` | unit size/type | no |
| `ChargesAndPaymentsByLedgerID` | bills, voucher credit, points eligibility | no |
| `ChargesAllByLedgerID` | bills / balance | no |
| `PaymentsByLedgerID` | receipt PDF | no |
| `CustomerAccountsBalanceDetails` | receipt PDF | no |
| `TenantInvoicesByTenantID` | invoices | no |
| `SiteInformation` | PDFs | no |
| `ApplyCredit` | apply rent voucher to a charge | no |
| **`PaymentSimpleWithSource`** | post an app payment into SiteLink (`SimplePaymentWithSourceAsync`, **hand-built SOAP 1.2 XML over RestSharp**, not the WCF proxy) | **🔴 YES — card-carrying operation** |
| Reporting `Receipts` | receipt lookup (6 months) | no |

**🔴 Card-carrying call.** `SimplePaymentWithSourceAsync` (`MA/Services/SiteLink/SiteLinkAPIs.cs:158-227`) sends
`sCreditCardNumber = "*" + <Stripe public TEST card number chosen by brand>` (for example the Visa test number for
Visa), `sCreditCardCVV = 123`, expiry = today + 1 year, `bTestMode = true`, `iSource = 10`
(`MA/DAL/PaymentDAL.cs:813-834`). It is **not real card data** — the real charge already happened in Stripe — but it
is still a card-carrying SiteLink operation used as a "record a payment" trick. The whole XML body, including the
SiteLink corp username and password, is written to the application log (`SiteLinkAPIs.cs:179-184`), and the fake card
number goes into `sitelink_transaction.description` (line 192). Called from `PaymentDAL.cs:828` and `:2659`
(MakePayment2 paths; SG disabled, MY live).

Wrappers present but with no caller: `GateAccessData`, `FormsRetrieve`, `UnitPayments`, Reporting `UnitPayments`,
`PaymentMultipleWithSource` and the WCF `PaymentSimpleWithSource` (both card-carrying), `GetAccountBalance`.

### 5.2 Stripe (`Stripe.net` 37.33; `MA/Services/StripePayment/StripePaymentService.cs`)

- APIs: Customers (create, get, update, delete), PaymentMethods (create-clone on connected account, attach, get,
  list, update, delete), PaymentIntents (create with confirm, confirm, get, cancel), Refunds (create).
- Not used: Checkout, SetupIntents, Subscriptions.
- Keys: platform `Stripe:SecretKey` (global static); per facility encrypted `master_facility.stripe_secret_key`,
  `stripe_publish_key`, `stripe_account` (Connect account id). Refund temporarily replaces the **global** API key with
  the facility key (`StripePaymentService.cs:160`) — not thread-safe.
- Currency `Country:StripeCurrency` (`sgd` / `myr`); 3DS switch `Stripe:threeDS`.
- **Webhook**: `POST /webhook`, events handled: `payment_intent.succeeded` (acts), `payment_intent.requires_action`
  (no-op), others logged to console. Parsed with `EventUtility.ParseEvent(json)` — **the `Stripe-Signature` header is
  read but never verified** (`MA/Controllers/WebhookController.cs:47-48`). De-dup: Redis `wh_{paymentIntentId}` for
  3 min. Acts only when Redis key `stripe_3dpayment_{id}` exists (3DS flow), and trusts the status in the posted JSON.
  No webhook secret key exists in config.

### 5.3 Email

- **SendGrid only** (`MA/Services/AWSEmailSevice.cs` — the name says AWS but it calls SendGrid). Keys:
  `SENDGRID:ApiKey`, `SENDGRID:MailFrom`, `SENDGRID:SenderName`, `SENDGRID:ReplyTo`. Some mails use a hard-coded
  billing sender. `AWS:Email:*` (SES SMTP) keys exist in config but no code uses them (inferred unused).
- Templates in `MA/emailTemplates/`: `opt_email.html` (first-login OTP), `forgot_password.html`, `reset_password.html`
  (HTML page, not email), `facility_pin_email.html`, `opt_account_delete.html`, `feedback_email.html`,
  `successful_payment.html`, `unsuccessful_payment.html`, `unsuccessful_sitelink_payment.html`,
  `suspend_account.html`, `payment_due_alert.html`, `receipt_email.html`, `noke_unlock_history.html`,
  `unlock_history_pdf_template.html`, `ex_successful_payment.html`, `error_notification.html`, PDF templates
  `sg/` and `my/` `invoice_pdf.html` + `receipt_pdf.html` (and old/with-sidebar variants at root), images.
  Placeholders `{name}`, `{otp_code}`, `{country_currency}` etc. are replaced as plain text — no HTML encoding.

### 5.4 SMS

- **SMSGlobal** (`MA/Services/SMSGlobalService.cs`): keys `SMSGlobal:ApiKey`, `SMSGlobal:SecretKey`,
  `SMSGlobal:SenderId`. Only use: Noke share PIN SMS. The SMS text (with PIN) is logged (line 40).
- AWS SNS SMS (`MA/Services/AWSSMSService.cs`) exists but its only call is commented out.

### 5.5 Push — Firebase legacy FCM (see §4.5). Keys `PushNotification:ServerKey`, `PushNotification:SenderID`.

### 5.6 Rewards vendors

- UniqGift v3 (`MA/Services/UniqueGift/UniqueGiftAPIs.cs`): keys `UniqueGift:authURL`, `:baseURL`, `:scope`,
  `:clientId`, `:clientSecret`, `:cryptoKey`, `:orderNumber`, `:shortUrl`; older v1 section `UniqueGiftV1:*`
  (email/password login). Logs request headers including the Bearer token (line 231). Writes a vendor log via
  `Database:logConnectionString`.
- WOGI (`MA/Services/WOGIGift/WOGIGiftAPIs.cs`): Basic auth `WogiGift:username` / `WogiGift:password`, base
  `WogiGift:baseURL`; `/balance`, `/products/issue`, `/products/{id}`, `/cards/{id}`.
- Selector: `ThirdPartyGift` (`uniquegift` / `wogigift`).

### 5.7 Noke — §4.8. Keys `Noke:baseUrl`, `Noke:apiKey`, `Noke:companyId`, `Noke:hardcode`, `Noke:hardcodeUnitNames`,
`Noke:HardCodeEmails`, `Noke:UnlockedHistoyInPastDays`, plus the lock-out keys.

### 5.8 PDF — DinkToPdf + native wkhtmltopdf (`libwkhtmltox.so/.dll/.dylib` in `MA/`; Docker downloads it).

### 5.9 Other outbound calls

- `https://api.ipify.org` (Dev outbound-ip).
- Image downloads from any `<img src>` inside PDF HTML (S3 / site images).

### 5.10 Data stores

- MySQL main DB `Database:esConnectionString`; log DB `Database:LogConnectionString` (`api_logs`); `Database:logConnectionString`
  (UniqGift log; different key casing, same value — config keys are case-insensitive); `Database:hangfireConnection` (unused).
- Redis `Redis:ConnectionString` (plain, `ssl=False`). Keys: `user_ledger_{u}`, `user_bill_{u}`, `user_invoice_{u}`,
  `user_receipt_{u}`, `pdf_receipt_{u}_{no}`, `pdf_invoice_{u}_{no}`, `login_device_info_{email}`,
  `mobile_payment_userid_{u}_cardid_{c}`, `units_information_{locationCode}`, `stripe_3dpayment_{pi}`, `wh_{pi}`.
- S3: only URLs from `Site:S3Url`; `AWS:S3:*` credentials in config are not used by this project (inferred).

### 5.11 Full config key list (names only)

`Database:{esConnectionString, hangfireConnection, LogConnectionString}`, `AES:{Password, Salt, HashAlgorithm, IV}`,
`Logging:*`, `AllowedHosts`, `Jwt:{Key, Issuer, AccessTokenExpiry, RefresTokenhExpiry}`,
`SENDGRID:{ApiKey, MailFrom, SenderName, ReplyTo}`, `SiteLink:{sCorpCode, SiteID, sLocationCode, sCorpUserName, sCorpPassword}`,
`ThirdPartyGift`, `WogiGift:{baseURL, username, password}`, `UniqueGiftV1:{...}`,
`UniqueGift:{authURL, baseURL, scope, clientId, clientSecret, cryptoKey, orderNumber, shortUrl}`,
`AWS:S3:{AccessKey, SecretKey, Bucket, Region}`, `AWS:Email:{MailFrom, ReplyTo, HostName, PortNo, SMTPUserName, SMTPPassword}`,
`PushNotification:{SenderID, ServerKey}`, `Stripe:{threeDS, SecretKey}`, `Redis:ConnectionString`,
`Noke:{baseUrl, apiKey, companyId, hardcode, hardcodeUnitNames, ConsecutiveFailedCount, ConsecutiveFailedInMin, BlockIPDurationInMin, UnlockedHistoyInPastDays, HardCodeEmails}`,
`SMS:{AppDownloadUrl, RetryCount}`, `SMSGlobal:{ApiKey, SecretKey, SenderId}`, `TakeCount`,
`Site:{BaseUrl, S3Url, WebUrl}`, `Country:{Name, ShortName, StripeCurrency, Currency}`, `BasicAuth:{UserName, Password}`,
`ExpressConfig:{exUnitStoragePlanName, exUnitNoOfMonths}`.

---

## 6. Background work

- **`QueuedHostedService`** (`MA/Services/QueuedHostedService.cs`): one in-memory queue, one worker. Only use:
  payment receipt email after a successful payment (`PaymentDAL.cs:913`). That job starts with
  `Thread.Sleep(60000)` (`PaymentDAL.cs:1660`), so each receipt blocks the single worker for 60 s; jobs are lost on
  restart.
- Fire-and-forget calls without await (email sends in `PaymentDAL`, Redis `Set`/`Delete`), so errors are invisible.
- **No scheduler.** Hangfire is commented out (`MA/Startup.cs:63-88, 529-543`); `RemoveExpiredNokeShares` and
  `SayHello` are never run. No timers. Webhook processing is synchronous inside the request.

---

## 7. Money, time, multi-country

**Money**
- C# `decimal` everywhere in this project (SiteLink returns strings, parsed with `Convert.ToDecimal`).
- To Stripe: `long.Parse(x.ToString("#.00").Replace(".", ""))` → cents; .NET decimal formatting rounds half away
  from zero.
- Rules: minimum payment 10 (currency-agnostic, hard-coded); per unit ≤ 12 × cached monthly rent; facility total
  ≤ 999,999; voucher discount capped at unit amount; percent voucher = `value/100 × amount` (double → decimal).
- Points: `ceil(multiplier × eligible)`; open-value voucher face value = points.
- Tax: GST comes from SiteLink charges (`dcTax1`, `dcTax2`) for bills/PDFs; Express hard-codes 9% GST.
- Display currency from `Country:Currency` (`S$` / `RM`); notification text hard-codes `$`
  (`PaymentDAL.cs:1173`).

**Time**
- DB timestamps written with `DateTime.UtcNow`; but `DateTime.Now` appears in emails, PDFs (`ToLocalTime()` for invoice
  dates, `DateTime.Now` for "Date.Notice"), Express transaction dates, expiry of points in the old code. The container
  sets `TZ=Asia/Singapore` (`MA/Dockerfile`), so "local" = UTC+8 for both SG and MY.
- SiteLink dates parsed with `DateTimeOffset.Parse(...).DateTime` then sometimes `.ToUniversalTime()` — the result
  depends on server TZ (inferred fragile).
- Point eligibility matches SiteLink payment time and receipt time **to the minute in format `yyyy-MM-dd hh:mm tt`**
  — a time-zone offset difference makes points zero (inferred risk).
- JSON date format bug (§1.4).

**Country (SG vs MY)**
- One code base per country, selected by **branch** + config: `Country:{Name, ShortName, StripeCurrency, Currency}`,
  PDF templates `emailTemplates/{sg|my}/`, cookie domain `extraspaceasia.com.{sg|my}`, CSP domains.
- `mys-yes-production` diverged from SG on 2024-06-26 (merge-base `63a6978e`); last MY commit 2026-08-17
  ("Add earn point api"). `git diff --stat yes-production mys-yes-production -- ExtraSpaceAPI`: 114 files,
  +2,569 / −8,619. Main differences I checked:
  - MY has **no Express module** and no `CustomLogger` email alerts; has a `PaymentVerification` entity.
  - **MY `MakePayment2` is still live** (calls `paymentBL.UnitPayment`), with `Stripe:threeDS = true`, currency `myr`,
    and the card-carrying SiteLink call.
  - MY uses WOGI (`ThirdPartyGift = wogigift`); SG uses UniqGift.
  - MY has the same unsigned webhook, the same Dev Redis endpoints, the same EarnPoints without auth, and the same
    ForgotPassword link leak (MY `AuthenticationBL.cs:733`).
  - MY production config also contains a live Stripe key (checked by prefix only).
  - Big diffs in `PaymentDAL`, `SiteLinkAPIs`, `UniqueGiftAPIs`, `AuthenticationDAL`, `Context.cs` — not reviewed line
    by line.

---

## 8. Security and quality observations

Severity: 🔴 critical/high, 🟠 medium, 🟡 low. All "verified" items were read in code; I did not run anything.

**Secrets and config**
1. 🔴 **Secrets are committed in** `MA/appsettings.json`, `MA/appsettings.Development.json`,
   `MA/appsettings.Staging.json`, **`MA/appsettings.Production.json`** (production DB connection strings, live Stripe
   secret key — checked by prefix only — SiteLink corp credentials, JWT key, AES key material, SendGrid, AWS S3 + SES,
   FCM server key, SMSGlobal, UniqGift, WOGI, Noke API key, Basic auth) and in `MA/log4net.config` (staging DB
   connection string). All files are tracked by git. The same is true on the MY branch. Every one of these must be
   treated as leaked and rotated before or at cutover.
2. 🔴 SiteLink corp username and password are logged in the request body of every `PaymentSimpleWithSource` call
   (`MA/Services/SiteLink/SiteLinkAPIs.cs:179-184`).
3. 🟠 Other secrets/sensitive data in logs: UniqGift Bearer token in headers (`UniqueGiftAPIs.cs:231`); OTP pin in
   `VerifyOTP` request log (`AuthenticationController.cs:191-196`); guest PIN in SMS log (`SMSGlobalService.cs:40`)
   and AWS SMS log (`AWSSMSService.cs:58`); Noke offline keys / unlock commands in `GetLedgers` response log
   (`AccountController.cs:238-243`) and in `api_logs`; reset-password request logged encrypted.

**Authentication / authorization**
4. 🔴 **Password reset takeover**: `POST /v1/Authentication/ForgotPassword` returns the reset link (with the valid
   token) in the API response (`MA/BL/AuthenticationBL.cs:772`). Anyone with the shared app Basic credential (which
   ships in the app and is embedded in the public reset page) can reset any registered customer's SiteLink web
   password knowing only the email. Same in MY.
5. 🔴 **Stripe webhook not verified**: `EventUtility.ParseEvent` without signature (`WebhookController.cs:47-48`), no
   webhook secret in config. A forged `payment_intent.succeeded` for a pending 3DS PaymentIntent id would post a
   payment into SiteLink and award points without money. Impact today is small in SG (MakePayment2 disabled → no new
   Redis keys) but **real in MY**.
6. 🔴 **EarnPoints has no authentication** (`RewardController.cs:63-109`). Points go to the account named by `email`,
   but the eligible amount comes from **any** `ledgerId` the caller supplies (no check that the ledger belongs to that
   email's tenant), and the idempotency key includes the free-form `receiptNo`, so changing `receiptNo` re-awards the
   same payment again (`RewardPointService.cs:75-89`). Points can be redeemed for vouchers with cash value. It also
   tells the caller whether an email is a SiteLink tenant at a location, and creates `user` rows. No rate limit.
7. 🔴 **Dev endpoints in production**: `GET/POST/DELETE /v1/Dev/*Redis` read, write and delete any Redis key with only
   the shared app credential (`DevController.cs:83-147`) — this includes payment de-dup keys and 3DS payment state.
   `GET /v1/Dev/outbound-ip` is anonymous.
8. 🔴 **CORS + cookie = cross-site data access**: any origin is allowed **with credentials**
   (`Startup.cs:92-103`) and the web session cookie is `SameSite=None` (`AuthenticationController.cs:912-930`), and
   `OptionsMiddleware` turns the cookie into a Bearer token. A malicious web page visited by a logged-in web user can
   call the API as that user and read the responses (inferred from config; verify in a browser).
9. 🟠 **Receipt PDF IDOR (likely)**: `DownloadReceiptPdf?receipt_no=&site_id=` looks up the receipt by number at the
   given facility and uses the tenant on that receipt; the caller's user id is only used for logging and the cache key
   (`RedisCahceService.DownloadReceipt` → `SiteLinkAPIs.GetPaymentReceipt`, from line 1589). Receipt numbers are
   sequential. Needs a test to confirm.
10. 🟠 **Express IDOR / takeover**: Express endpoints accept a user id or email in the body/route with only the app
    credential (`ExpressController.cs`); `AddExUser` **updates the password of an existing Express user found by email**
    (`ExpressDAL.cs:363-381`).
11. 🟠 **OTP brute force**: `VerifyOTP` has no attempt limit and is not in the rate-limit rules; 6-digit OTP valid 5
    min. `SetPassword` does not check the pin expiry (only `status == 0`, `AuthenticationBL.cs:292-305`).
12. 🟠 **Rate limiting is weak**: rules list only `/v1/...` paths, so `/v1.1/...` (same actions) is not limited;
    the MakePayment2 rule is written `"*/api/Payment/MakePayment2"` and can never match; counters are in-memory per
    instance; client IP is taken from `X-Real-IP`, which a client may be able to set (inferred, depends on the load
    balancer); quota responses are HTTP 200.
13. 🟡 Swagger UI and JSON are public in production (`Startup.cs:497-502`).
14. 🟡 `Logout` has no `[Authorize]`; JWT refresh lifetime minutes/days mismatch (§3.4); refresh always marks the
    session as `web`.

**Injection**
15. 🔴 **SQL injection (likely)**: user text is concatenated into the WHERE clause passed to the paging stored
    procedure `sp_GetPagingData` (inside the closed DLL): `Post/GetList` `Keyword` (`MA/BL/PostBL.cs:63`, reachable
    with the app credential) and `Reward/GetRewardList` `Category` (`MA/BL/RewardBL.cs:223`), plus raw `SortDir`
    (`RewardBL.cs:226`). The DLL rejects "invalid order", so `SortDir` may be checked; the WHERE string is not. The
    procedure body is not in this repo — confirm with agent C / a test on staging.
16. 🟡 `MobileApiLoggerDAL` builds INSERT SQL by string concatenation (escaped with `MySqlHelper.EscapeString`).
17. 🟡 Email templates and the unlock-history PDF insert user/SiteLink text without HTML encoding.

**Card data / PCI**
18. The server never receives PAN/CVV from the app (Stripe tokens only) — good. But see §5.1: a card-carrying SiteLink
    operation is called with Stripe **test** card numbers, CVV `123` and `bTestMode=true` to record payments (MY live,
    SG disabled). The new system must not copy this (house rule: never call a card-carrying SiteLink operation).

**Correctness / reliability**
19. 🟠 Payment flow wraps Stripe + SiteLink calls inside a DB `TransactionScope` (ReadUncommitted, 15 min); a DB error
    after money moved loses the local record. Return code −14 from SiteLink keeps the Stripe charge without refund.
20. 🟠 Global `StripeConfiguration.ApiKey` is swapped to a facility key during refunds (not thread-safe).
21. 🟠 Redeem uses ReadUncommitted without locks → possible double spend; vendor voucher is issued before the DB
    commit.
22. 🟠 Push uses the shut-down FCM legacy API (inferred broken).
23. 🟡 `GetSummary` also returns Noke units whose user email is empty (`UserBL.cs:854`) — check whether this can show
    another tenant's lock keys.
24. 🟡 Error codes reused for different meanings (709, 711-715); Express returns 200 as success code, others 0.
25. 🟡 Every error also sends an email synchronously (`CustomLogger.cs`), which slows failing requests and can flood
    the mailbox.
26. 🟡 PDF code crashes when the HTML has no `<img>` (null from `SelectNodes`).
27. 🟡 `user_token.expiry_on` uses days where the JWT uses minutes.
28. 🟡 `Bogus` (fake-data library) is a production dependency; `DevBL.UnlockNoke` contains a hard-coded test lock,
    session and a developer email (not routed).

**Dead code**
- `MakePayment`, `MakePayment2` (SG), `UpdateProfile` (NonAction), `GetInvoices` (always empty), `SpaceController`,
  `MetaDataMiddleware`, Hangfire, `AWSSMSService`, SES config, `GetLedgersOld`, `GetPaymentHistory`/`GetPaymentDetail`
  (legacy `user_payment` table), unused SiteLink wrappers (§5.1), `SyncTenantDataAsync` (no caller after
  2025-06-17), old commented payment blocks, `invoice_pdf_old.html` and other `_old` templates.

---

## 9. Recent activity (`git log --since=2025-01-01 -- ExtraSpaceAPI`, 56 commits)

Almost all by one Codigo developer, plus a few by a second developer and one by `extraspace-tech`.

- **2026-07 / 08 — Earn points + payment shutdown**: `feat (API): Add EarnPoints API` (07-21; also extracted
  `RewardPointService`, `PointCalculator`, `SiteLinkUserHydrator`, record-only users), `Fix: EarnPoints adjustment`
  (07-31; optional receiptNo), **`Update: Disable MakePayment2 API`** (08-02), `disable schedule jobs` (08-05; only
  `mobile_api.xml` changed in this folder — the jobs are elsewhere), `earn points accept both in string and int`
  (08-07). MY got "Add earn point api" on 2026-08-17.
- **2026-06**: user id added to add/update card logs.
- **2026-01 → 04**: MasterData intermittent 500 fix, temporary outbound-IP endpoint (01-16, likely for vendor IP
  allow-listing), UniqGift/WOGI integration updates and prod prep (02-03), email template/font updates, getLedger
  update (04-24).
- **2025-08 → 10**: reward point calculation adjustment, getInvoices change, promo-code merge, **rate limit added to
  payment API** (10-09).
- **2025-05 → 06**: SiteLink transaction DB logging fixes, tenant sync moved into login then removed again
  (`TEMP: Remove the single sync function from login`, 06-17), Express unit-size fixes, payment rollback.
- **2025-02 → 03**: new structured logging (`CustomLogger`) with error emails, Noke API key change, UniqGift v3
  integration, removal of tech BCC on emails, reward point calculation fix.

Direction: the app is being reduced to a **loyalty + account viewer**; payments move out of the app; points are now
fed by a partner call (EarnPoints) instead of the app payment flow.

---

## 10. Open questions

1. Who calls `POST /v1/Reward/EarnPoints` (which partner/system, from which IPs)? Is there any network-level protection
   (WAF, IP allow-list at the load balancer) that the code does not show? Should it get an API key?
2. Is the SG in-app payment permanently retired? What replaced it (SiteLink tenant portal, Stripe Checkout in the new
   backend)? Is MY going to keep `MakePayment2`?
3. Does token refresh actually work in production with `Jwt:RefresTokenhExpiry = 1` (1-minute refresh JWT)?
   How does the Flutter app behave after 20 minutes?
4. Body of stored procedures `sp_CheckToken` and `sp_GetPagingData` (agent C) — to confirm session expiry rules and the
   SQL injection.
5. Where is the Redis key `units_information_{locationCode}` written (CMS? job?) and how fresh is it?
6. Who creates notifications other than payments, and who sends push today (given FCM legacy shutdown)?
7. Who removes expired Noke shares now that `RemoveExpiredNokeShares` is not scheduled?
8. Exact JSON names of the envelope (`error_code`, `error_msg`, `data`?) and the real date strings — please capture a
   few live responses before designing the new mobile contract.
9. Is the Express module still used in production (it is SG-only and was last changed 2025-05)?
10. Does the Flutter app still call `GetInvoices`, `GetPaymentHistory`, `GetPaymentDetail`, `GetLedgersOld`,
    `MakePayment`, `MakePayment2`, `UpdateProfile`, Dev endpoints? (Server logs would tell.)
11. Which load balancer sits in front (does it set `X-Real-IP`, does it pass the real client IP for the guest PIN
    lock-out)?
12. Is the hard-coded 9% GST for Express correct for every facility, and should Malaysia (SST) ever use it?
13. Why does `TenantUpdate` write `sGateCode = sAccessCode`? Is that intended by operations?
