# Old backend inventory, part 2: the admin CMS (`ExtraSpaceCMS/admin_cms`)

Written 2026-10-09 by a read-only explorer. Source repo: `/Users/waiyanmin/Projects/Extra Space old/extraspace-backend` (git `sgcodigo/extraspace-backend`, branch `yes-production`). Every path below is relative to `ExtraSpaceCMS/admin_cms/` unless it starts with `ExtraSpaceCMS/`.

Scope: only the admin CMS web app. Other parts are covered by other notes:
- `ExtraSpaceAPI/mobile_api/` (mobile API): agent A.
- `ExtraSpaceCMS/Express.Core/` (shared library the CMS calls for the whole "ES Express" area), `es_express`, MySQL data model, DB scripts, CI / infra, config key names: agent C.
- The new Node demo backend: agent D.

When the CMS calls Express.Core, this note names the call and stops there.

How to read the markers:
- "read" = I read the code line. "inferred" = my conclusion from the code, not proven by running it.
- 🔴 = security or compliance problem that the rebuild must not copy.
- No secret values appear in this note. Config is named by key only.

---

## 1. Overview

### 1.1 What the app is

`admin_cms` is the staff back office for two products that share one login:

1. **"YES" CMS** (the old loyalty / member app back office): members (SiteLink tenants who use the mobile app), e-points, rewards and vouchers, payments made in the app, refunds, posts (articles), FAQ, contents (privacy policy, T&C, about us), facility contact cards, feedback, push campaigns, Noke smart-lock control, dashboards, reports, CMS staff accounts, audit log, and the **Hangfire background jobs** (recurring card payments, tenant sync from SiteLink, points, reminders, SiteLink report sync).
2. **"ES Express" CMS** (Area `express`, URL prefix `/express/...`): facilities, floors, units, unit types / sizes / base rates, storage plans, insurance plans, promo codes, members (express app users), rentals, transactions, move-out refunds, Noke locks, FAQ, late fees, regions, privacy policy, T&C, reports, audit trail. Almost all logic is in `ExtraSpaceCMS/Express.Core` repositories (agent C). The Express data lives in a **second MySQL database** (`Express:ConnectionString`).

There is also a third, older block of controllers under `Controllers/ExpressModule/` ("Ex*", menu ids 19–23) that works on `ex_*` tables inside the **YES** database. It looks like an earlier Express prototype (inferred: last code change 2024-11-21, see §9).

Tech: ASP.NET Core 3.1 MVC with Razor views (runtime compilation on), Pomelo EF Core 3.1 on MySQL, Hangfire 1.7 with MySQL storage, StackExchange.Redis, Stripe.net 39.5, WCF SOAP proxies for SiteLink, SendGrid (all mail goes through SendGrid even though the class is named `AWSEmailSevice`), AWS S3, DinkToPdf, ClosedXML, CsvHelper, log4net, AspNetCoreRateLimit, HtmlSanitizer, UAParser, legacy FCM HTTP push, FirebaseAdmin (for Express). Source: `admin_cms.csproj`.

Four closed-source Codigo DLLs are checked in under `Lib/`: `Codigo.AWSS3`, `Codigo.Crypto` (AES encryption + PBKDF2 password hashing), `Codigo.DataContract`, `Codigo.UnitOfWork.MySql` (generic repository, `FromSqlRaw`, `GetPageIndex`). There is **no source** for them in this repo. 🔴 for the rebuild: admin password hashes and every AES-encrypted column (facility Stripe keys, Stripe customer ids, saved card ids) depend on `Codigo.Crypto`. The new system must reproduce the exact algorithm to read existing data (Express.Core has its own `Services/Crypto/AESEncryption` and `PBKDF2Helper` source; agent C should confirm whether it is the same algorithm).

### 1.2 Startup pipeline (`Startup.cs`, `Program.cs`)

Configuration (`Program.cs`): `appsettings.json` + `appsettings.{ASPNETCORE_ENVIRONMENT}.json` (default "Production") + env vars, plus a required `expressSettings.{environment}.json` from the build output folder (comes from Express.Core, agent C).

Services (`Startup.cs:64-300`):
- **Auth: cookie authentication only** (`Startup.cs:110-121`). No ASP.NET Identity, no JWT for the CMS (a `JwtHandler` class exists in `Handlers/JwtClaimTypes.cs` but nothing uses it; the claim-type names are reused for cookie claims). Login path `/account/login`, logout `/logout`, access denied `/access-denied`. Cookie name = host of `site:baseurl`; `SecurePolicy=Always`; `HttpOnly`; `ExpireTimeSpan` 20 minutes (sliding by default). `CookiePolicyOptions.MinimumSameSitePolicy = None` (`Startup.cs:126`), so the auth cookie keeps the framework default SameSite=Lax (inferred).
- Data protection keys are **not persisted** (the `PersistKeysToFileSystem` line is commented out, `Startup.cs:102-103`). In a container every restart makes a new key ring, so all admin cookies and antiforgery tokens die on every deploy, and two instances behind a load balancer cannot read each other's cookies without sticky sessions (inferred).
- **Redis**: one `ConnectionMultiplexer` from `Redis:ConnectionString`, registered as `IDatabase` (`Startup.cs:129-130`). Used only as a cache (no session). Keys written by the CMS: `units_information_{LocationCode}` (3 h TTL), `UnitIdKey_{unitId}`, `stripe_3dpayment_{paymentIntentId}` (5 days). Source: `Services/ScheduleJob.cs:1667,2612,3468`, `Services/RedisCahceService.cs:175`.
- **Two EF Core contexts**: `admin_cms.Entities.Context` on `Database:esConnectionString` (YES DB) and `Express.Core.Entities.Context` on `Express:ConnectionString` (Express DB) (`Startup.cs:132-143`).
- **FirebaseApp** created from file `Express:Firebase:KeyFile` (Express push, `Startup.cs:146-149`).
- **Hangfire** with MySQL storage on `Database:hangfireConnection`, table prefix `hangfire_`, invisibility timeout 4 h (`Startup.cs:163-181`). Hangfire server: Development uses queue `local`; Production calls `services.AddHangfireServer()` **and** `app.UseHangfireServer()` (`Startup.cs:189-192, 409`), so production runs two job servers in one process (inferred: double worker count, no double execution). Staging gets only `app.UseHangfireServer()`.
- **Rate limiting** (AspNetCoreRateLimit, in-memory, per IP) only on `POST /account/login`, `POST /account/otplogin`, `POST /account/otpregenerate`: 10 requests per 15 minutes (`Startup.cs:205-239`). Real IP header = `X-Real-Ip`; `UseForwardedHeaders` is commented out, so behind an AWS ALB all users may share one IP bucket (inferred). Over-limit: JSON 429 for AJAX, else redirect to `/account/error` (`Handlers/RateLimitMiddleware.cs`).
- DI: ~33 DAL + ~30 BL classes, SiteLink, Stripe, S3, SendGrid, FCM, Noke, UniqGift, WOGI, PDF converter, in-memory background queue (`Services/QueuedHostedService.cs`, lost on restart), plus all Express.Core repositories (`Startup.cs:269-293`).
- `XssValidationFilter` registered as a service filter; only `BaseController` applies it.

Middleware order (`Startup.cs:375-470`): `RateLimitMiddleware` → `ResponseMiddleware` (security headers + CSP with per-request nonce; CSP still allows `'unsafe-inline'` and a plain-http staging ELB host, `Handlers/ResponseMiddleware.cs`) → developer page or `/Home/Error` + HSTS → `/robots.txt` handler → `/healthcheck` → HTTPS redirect → static files → cookie policy → authentication → routing → **Hangfire dashboard at `/hangfire`** (filter: authenticated and role "Head Admin", `Handlers/HangFireAuthorizationFilter.cs`; storage connection string hidden) → authorization → culture `en-US` with date format `dd/MM/yyyy` → endpoints. `OptionsMiddleware` (an older per-request session check) is commented out (`Startup.cs:442`).

Routes: conventional `{controller=Home}/{action=Index}/{id?}` plus area route `express/{controller=dashboard}/{action=index}/{id?}`. Most actions use attribute routes.

### 1.3 Areas

One Area: `express` (`Areas/express/`). Its controllers inherit `expressBaseController`, which has **no** per-request account check and **no** XSS filter (see §3.4). Each controller has `[Authorize]` and a fixed `[Route("express/...")]`.

### 1.4 Size

Counts below include `.cs`, `.cshtml`, `.js`, `.html` files and exclude `wwwroot/lib` (24 MB of vendor libraries), `bin`, `obj`.

| Folder | Files | Lines | Notes |
|---|---|---|---|
| `Controllers/` | 32 | 10,539 | 22 YES controllers + 9 `ExpressModule` + `BaseController` |
| `Areas/express/` | 74 | 16,915 | 14 controller files + 60 Razor views |
| `Views/` | 81 | 20,502 | YES Razor views (3 are "Index - Copy" leftovers) |
| `BL/` | 30 | 8,101 | business layer, mostly thin |
| `DAL/` | 33 | 8,887 | EF + raw SQL |
| `Services/` | 15 | 9,369 | `ScheduleJob.cs` alone is 4,901 lines; `SiteLinkAPIs.cs` 2,331 |
| `Entities/` | 112 | 7,972 | EF entities for the YES DB (incl. Hangfire tables) |
| `Model/` | 121 | 3,690 | view models / DTOs |
| `Common/` | 7 | 847 | utilities, enums, loggers |
| `Handlers/` | 7 | 463 | middleware, filters |
| `Connected Services/` | 2 | 5,054 | generated SiteLink SOAP proxies |
| `emailTemplates/` | 30 | 18,956 | HTML mail templates (22 YES + 8 Express) |
| `documents/express/` | 5 | 2,829 | HTML templates for Express PDFs |
| `wwwroot/js` (custom) | 73 | 26,203 | page scripts; includes vendor `adminlte.js` |

Controllers: **44 controller classes** (31 in the main area + 13 in Area `express`, one of them empty), **398 routable actions** (plus one public helper that is routable by accident, see §8). By return type: ~176 render Razor views (some also redirect), ~192 return JSON only (AJAX / DataTables), 9 return files, 21 only redirect.

### 1.5 Layers and request flow

`Controller` → `BL` (thin pass-through, sometimes builds SQL WHERE strings) → `DAL` (EF Core via `IUnitOfWork<Context>`, raw SQL via `FromSqlRaw`, stored procedures, or direct `MySqlCommand`) → MySQL. Side calls go to `Services/*` (SiteLink, Stripe, S3, SendGrid, FCM, Noke, UniqGift, WOGI, Redis).

Typical YES list screen: GET page returns a Razor view; the page's DataTables script POSTs JSON to `.../getlist`; the controller checks permission, the BL builds a SQL WHERE string, the DAL calls the dynamic stored procedure `sp_GetPagingData2` or `GetPageIndex`, and returns `{draw, recordsTotal, recordsFiltered, data}`. "Export" endpoints return JSON and the browser builds the CSV (`wwwroot/js/pages/*.js`, `text/csv`).

Typical Express screen: the controller checks `Utils.IsAuthorize` (Express.Core) and calls an Express.Core repository (`IUnitRepository.List`, etc.), which reads/writes the Express DB.

### 1.6 Endpoints called by the mobile app or third parties

None found. Every action needs a logged-in CMS user except the login / password-reset pages. No webhook, no CORS, no `[ApiController]` in `admin_cms` (grep for `AllowAnonymous`, `EnableCors`, `webhook`). Machine-facing paths are only `/healthcheck` (load balancer), `/robots.txt` (`Disallow: /`) and `/hangfire` (staff). The CMS talks to the mobile app only indirectly: through shared DB tables, Redis keys and push notifications.

---

## 2. Screen and route inventory

Legend:
- Verb: `GET`, `POST`, `PUT`, `DELETE`; `ANY` = `[Route]` with no verb attribute (accepts any verb).
- Permission: `Menu:action` = `GeneralUtility.IsAuthorize` (YES) or `Utils.IsAuthorize` (Express) check inside the action. "auth only" = no permission check, any logged-in CMS user passes. "flag X" = only a boolean claim check.
- Returns: V = Razor view, J = JSON, F = file, R = redirect only.
- AFT = `[ValidateAntiForgeryToken]` present. In the main (YES) area only 8 of 107 write endpoints have it; in Area `express` 84 of 99 have it.
- All main-area controllers except `AuthenticationController` inherit `BaseController` (per-request DB check of account status, password key and role key, §3.4).

### 2.1 Login, password, profile (YES + shared)

`Controllers/AuthenticationController.cs` (class `[Authorize]`, does **not** inherit `BaseController`)

| Verb | Route | Permission | Ret | Purpose |
|---|---|---|---|---|
| ANY | `/account/login` | anonymous | V | Login page (redirects to `/` when already signed in) |
| POST | `/account/loginold` | anonymous, AFT | V/R | 🔴 **Old login without OTP.** Checks password, signs in directly, 10-hour cookie. Not rate-limited. Still live (`:95-230`) |
| POST | `/account/login` | anonymous, AFT | V/R | Checks password, makes a 6-digit OTP, emails it (SendGrid, `otp-email.html`), stores an encrypted `otpToken` cookie, redirects to OTP page |
| ANY | `/account/otplogin` | anonymous | V | OTP entry page |
| POST | `/account/otpregenerate` | anonymous, AFT | J | New OTP, re-email, re-write cookie |
| POST | `/account/otplogin` | anonymous, AFT | V/R | Re-checks password from cookie, compares OTP, builds all claims (§3.2), signs in, records device; redirects to `/` (YES user) or `/express/manage-facilities` (Express-only user) |
| ANY | `/forgot-password` | anonymous | V | Forgot-password page |
| POST | `/forgot-password` | anonymous, AFT | V | Sets `reset_code` (GUID, 4 h expiry) and emails an AES-encrypted reset link (`forgot_password.html`) |
| ANY | `/reset-password/{token}` | anonymous | V | Checks token expiry, shows form |
| POST | `/reset-password/{token}` | anonymous, AFT | V/R | Checks common-password list, sets new PBKDF2 hash + new `password_key`, then signs the user in with a **10-year** cookie (`:713-718`) |
| ANY | `/logout` | auth | R | Deletes the device row, signs out |
| ANY | `/access-denied`, `/account-suspend`, `/error`, `/account/error` | anonymous | V | Static pages (`/account/error` = "too many requests") |

`Controllers/AccountManagementController.cs` (class `[Authorize]`)

| Verb | Route | Permission | Ret | Purpose |
|---|---|---|---|---|
| ANY | `/profile/me` | auth only | V | Own profile |
| POST | `/profile/me` | auth only, AFT | V/R | Update own name / mobile etc. |
| ANY | `/profile/change-password` | auth only | V | Form |
| POST | `/profile/change-password` | auth only, AFT | V/R | Change own password (common-password check; new `password_key` logs out other sessions via `BaseController`) |
| ANY | `/profile/loggedindevices` | auth only | V | List rows in `cms_user_devices` |
| POST | `/devices/logout` | auth only | J | Deletes a device row. Cosmetic only: the device-expiry check in `BaseController` is commented out (`BaseController.cs:83-88`), so the cookie on that device keeps working |

### 2.2 Dashboard (YES) — `Controllers/HomeController.cs`

All are conventional routes `/Home/{Action}` (any verb) except `Index` = `/`. Permission for the Dashboard menu is special: `IsAuthorize` returns true for **any** user with claim `IsYES=True`, whatever the action (`Common/GeneralUtility.cs:146-151`), so the per-widget action names below are decorative. All return JSON except `Index` (V), `Privacy` (V), `Error` (V).

| Action | Params | Nominal permission | Data source |
|---|---|---|---|
| `Index` (`/`) | – | dashboardActiveMember | facility lists |
| `Privacy`, `Error` | – | auth only | template pages |
| `DashboardStatus` | start, end, facilityId | auth only | `sp_DashboardStatus_V2` / SQL |
| `DashboardPaymentGraph` | start, end | dashboardMonthlyPayment | `payment_transaction` |
| `FacilityPaymentGraph` | start, end | dashboardFacilityPayment | `payment_transaction`, `master_facility` |
| `MemberStatusGraph`, `MemberTierGraph` | facilityId | dashboardActiveMember / dashboardMembershipTier | `user`, `user_tenantsite` |
| `TopMemberPayment`, `TopMemberOutstanding`, `TopMemberMostPoint`, `TopMemberMostReward` | JSON body | dashboardT10* | `payment_transaction`, `user`, `point_transaction`, `redeem_reward` |
| `RewardExchangedGraph`, `TopESExchangePoint`, `GetTopVoucherUsed`, `TopRewardUsed`, `RewardExchangedPointGraph`, `GetVoucherRedeemedGraph`, `VoucherUtilisation`, `GetVoucherUsed`, `GetVoucherRedeemed`, `GetVoucherRedeemption` | various | dashboardReward / dashboardVoucher* | `redeem_reward`, `reward`, `reward_category` |
| `TopFacilityPayment`, `TopFacilityMember`, `GetFacilitiesWithMostRewardClaimed` | body | dashboardFacilities | DB + SiteLink `ManagementSummary` |
| `GetSiteLinkDiscounts` | start, end, locationCode | dashboardPayment | SiteLink Reporting `Discounts` / `sitelink_discount_summary` |
| `GetSiteLinkRentalActivity` | body | dashboardRentalActivity | SiteLink `RentalActivity` / `rental_activity_sitelink` |
| `GetMoveInsAndMoveOuts`, `GetOccupancyMoveInsAndMoveOuts` | start, end, locationCode | dashboardFacilities | SiteLink `MoveInsAndMoveOuts`, `OccupancyStatistics`, synced tables |
| `GetSiteLinkMarketingSummary` | body | dashboardMarketingSummary | SiteLink `MarketingSummary` (live) |
| `GetFacilityOverallPerformance`, `GetOtherIncome` | body | dashboardFacilities / dashboardPayment | SiteLink `ManagementSummary`, `sitelink_mgmt_summary_*` |
| `TopPostWithMostView` | body | dashboardT10PostWithMostView | `post`, `post_view` |
| `GetAmountPaidViaRecurring`, `GetUnitTypeWithRecurring`, `GetRecurringCustomers`, `GetMonthlyAmountCollectedViaRecurring` | various | dashboardAmountPaidViaRecurring / dashboardPayment | `payment*`, `user_payment_card`, SiteLink `UnitsInformation_v3` |
| `GetNumberofPointAwardedByCMS`, `GetNumberofPointsExpiring` | body | dashboardAmountPaidViaRecurring / dashboardExpiryPoint | `point_transaction` |
| `GetRentalStorageType` | body | dashboardFacilities | SiteLink `UnitsInformation_v3` (live) |
| `GetTotalRentalCollected`, `GetUnitTypeVsRentalCollected`, `GetStorageRentalAmountvsPaymentModes` | start, end, locationCode | dashboardPayment / dashboardFacilities | SiteLink `Receipts`, `IncomeAnalysis`, `FinancialSummary`; `sitelink_receipts` |
| `GetMerchandiseSummary` | start, end, locationCode | dashboardPayment | SiteLink `MerchandiseSummary` / `sitelink_merchandise_summary` |

Data is scoped by the `Facilities` claim (list of SiteLink site ids from `cms_user_facility`) inside `DAL/DashboardDAL.cs` (60 uses). Several widgets call SiteLink Reporting live on each page load (`BL/DashboardBL.cs`), the rest read tables that the (now disabled) sync jobs fill (§5).

### 2.3 Members (YES) — `Controllers/MemberManagementController.cs`

| Verb | Route | Permission | Ret | Purpose |
|---|---|---|---|---|
| GET | `/member-management` | Member_Management:view | V | Member list page |
| POST | `/member-management/getlist` | Member_Management:view (+status/edit for buttons) | J | Paged list via `sp_GetPagingData2`; filters: keyword, membership date, has storage unit, facility, tier, status |
| ANY | `/member-management/detail/{id}` | Member_Management:view | V | Detail: profile, points, expiring points, space rentals (SiteLink), last payment, last reward |
| POST | `/member-management/detail/{id}` | auth only | V/R | Update member profile (DB) |
| POST | `/member-management/AdjustPoint` | Member_Management:edit_point | J | Add / deduct e-points per facility (§4.4) |
| POST | `/member-management/ChangeStatus` | Member_Management:status | J | Active ↔ Overdue ("suspended"); on Overdue: in-app notice, push, "Your Account is Suspended" email with SiteLink bill |
| POST | `/member-management/suspended` | Member_Management:status | J | Sets status Inactive |
| POST | `/member-management/ChangePassword` | auth only | J | 🔴 Sets the member's **SiteLink web password** through `TenantUpdate` (`BL/MemberBL.cs:251-290`) |
| GET | `/member-management/GetSpaceRental` | auth only | J | Units the member rents (DB) |
| POST | `/member-management/GetSearchList` | Member_Management:view | J | Search SiteLink tenants (`TenantListDetailed_v2` search) to add as member |
| POST | `/member-management/AddMember` | Member_Management:add | J | Create `user` + `user_tenantsite` from a SiteLink tenant (`TenantListDetailed_v2`, `LedgersByTenantID`) |
| POST | `/member-management/ResetPin` | Member_Management:reset_pin | J | Set new gate PIN in SiteLink (`TenantUpdate` with `sGateCode`) |
| POST | `/member-management/TenantAsync` | auth only | J | Queue the tenant-sync Hangfire job now (job body is disabled by config, §5) |
| POST | `/member-management/GetPaymentTransaction` | auth only | J | Member payments |
| POST | `/member-management/GetPointTransaction` | auth only | J | Member point history |
| POST | `/member-management/GetRewardTransaction` | auth only | J | Member wallet / vouchers |
| POST | `/member-management/export` | auth only | J | 🔴 Export all members (name, email, mobile, outstanding, tier, points) — no permission check |
| POST | `/member-management/export-payment` | Payment_Transactions:export | J | Export member payments |

### 2.4 Payments and refunds (YES)

`Controllers/PaymentManagementController.cs`

| Verb | Route | Permission | Ret | Purpose |
|---|---|---|---|---|
| GET | `/payment-transaction` | Payment_Transactions:view | V | Payment list page |
| POST | `/payment-transaction/getlist` | Payment_Transactions:edit (view for list) | J | App payments (`payment`, `payment_facility`, `payment_transaction`), with refund buttons by user flag |
| POST | `/payment-transaction/export` | Payment_Transactions:export | J | Export |
| POST | `/payment-transaction/request-refund` | Payment_Transactions:edit + flag `RefundRequestor` (DB) | J | Create refund request (maker) |
| POST | `/payment-transaction/approve-refund` | Payment_Transactions:edit + flag `RefundApprover` (DB) | J | Approve → Stripe refund (checker) |
| POST | `/payment-transaction/reject-refund` | Payment_Transactions:edit + `RefundApprover` | J | Reject request |
| POST | `/payment-transaction/get-request-refund` | Payment_Transactions:view | J | Show a request |
| POST | `/payment-transaction/cancel-request-refund` | Payment_Transactions:edit + `RefundRequestor` | J | Cancel own request |

`Controllers/PaymentSettingController.cs`

| Verb | Route | Permission | Ret | Purpose |
|---|---|---|---|---|
| ANY | `/payment-setting` | Payment_Setting:view | V | Facility list |
| POST | `/payment-setting/getlist` | Payment_Setting:status | J | `master_facility` list |
| POST | `/payment-setting/PartialChangeStatus` | Payment_Setting:status | J | Toggle `master_facility.allow_partial_payment` (read by the mobile API, inferred) |

### 2.5 Rewards, vouchers, points (YES)

`Controllers/RewardManagementController.cs`

| Verb | Route | Permission | Ret | Purpose |
|---|---|---|---|---|
| ANY | `/reward-management` | Reward_Management:view | V | List page |
| POST | `/reward-management/getlist` | Reward_Management:view | J | List |
| ANY | `/reward-management/create` | Reward_Management:add | V | Form (gift provider from config `ThirdPartyGift` = uniquegift / wogigift) |
| POST | `/reward-management/create` | auth only | V/R | Create reward (start/end datetime check; images to S3 `rewards/`) |
| ANY | `/reward-management/edit/{id}` | Reward_Management:edit | V | Form |
| POST | `/reward-management/edit/{id}` | auth only | V/R | Update reward |
| ANY | `/reward-management/detail/{id}` | Reward_Management:view | V | Detail |
| POST | `/reward-management/ChangeStatus` | Reward_Management:status | J | Activate / deactivate |
| ANY | `/reward-management/getwogiproduct/{productId}` | Reward_Management:view | J | WOGI product lookup (`/products/{id}`) |

`Controllers/FeaturedRewardController.cs`

| Verb | Route | Permission | Ret | Purpose |
|---|---|---|---|---|
| ANY | `/featured-reward` | Reward_Management:view | V | Featured list |
| POST | `/featured-reward/getlist` | Reward_Management:view | J | List |
| POST | `/featured-reward/edit` | Reward_Management:edit | J | Add / remove featured flag |
| POST | `/featured-reward/UpdateSqeuence` | Reward_Management:edit | J | Re-order |

`Controllers/RewardCategoryController.cs`

| Verb | Route | Permission | Ret | Purpose |
|---|---|---|---|---|
| GET | `/reward-category` | Reward_Categories:view | V | List page |
| POST | `/reward-category/getlist` | Reward_Categories:view | J | List |
| GET | `/reward-category/create` | Reward_Categories:add | V | Form |
| POST | `/reward-category/create` | auth only | V/R | Create (icon to S3 `reward-category/icon`) |
| ANY | `/reward-category/edit/{id}` | Reward_Categories:edit | V | Form |
| POST | `/reward-category/edit/{id}` | auth only | V/R | Update |
| ANY | `/reward-category/detail/{id}` | Reward_Categories:view | V | Detail |
| POST | `/reward-category/ChangeStatus` | Reward_Categories:status | J | Toggle |
| POST | `/reward-category/ChangeOrder/{Id}/{Order}` | Reward_Categories:edit | J | Re-order |

### 2.6 Content: posts, tags, FAQ, contents, contacts, feedback (YES)

`Controllers/PostManagementController.cs` (posts are shown as "Articles" in the app since 2025-08-14)

| Verb | Route | Permission | Ret | Purpose |
|---|---|---|---|---|
| ANY | `/post-management` | Post_Management:view | V | List page |
| POST | `/post-management/getlist` | Post_Management:view | J | List |
| ANY | `/post-management/create` | Post_Management:add | V | Form |
| POST | `/post-management/create` | auth only | V/R | Create post (title, author, HTML content, image to S3 `post/`, optional video URL, tags) |
| ANY | `/post-management/edit/{id}` | Post_Management:edit | V | Form |
| POST | `/post-management/edit/{id}` | auth only | V/R | Update |
| ANY | `/post-management/detail/{id}` | Post_Management:view | V | Detail |
| POST | `/post-management/ChangeStatus` | Post_Management:status | J | Publish / unpublish |
| POST | `/PostManagement/CKEditorPhotoUpload` (conventional) | auth only | J | 🔴 Editor image upload to S3 `post/`, public-read, any file type (`:291-325`) |

`Controllers/TagManagementController.cs`: `ANY /tag-management` (view, V), `POST /tag-management/getlist` (view, J), `ANY /tag-management/create` (add, V), `POST /tag-management/create` (auth only, V/R), `ANY /tag-management/edit/{id}` (edit, V), `POST /tag-management/edit/{id}` (auth only), `ANY /tag-management/detail/{id}` (edit, V), `POST /tag-management/ChangeStatus` (status, J). Post tags.

`Controllers/FaqManagementController.cs` (YES FAQ, tables `faq` = topic, `faq_item`): `ANY /faq-management` (view), `POST /faq-management/getlist` (view), `ANY /faq-management/create` (add), `POST /faq-management/create` (auth only), `ANY /faq-management/edit/{id}` (edit), `POST /faq-management/edit/{id}` (auth only), `POST /faq-management/ChangeStatus` (edit, J), `POST /faq-management/delete` (delete, J), `ANY /faq-management/detail/{id}` (view), `POST /faq-management/UpdateSqeuence` (edit, J).

`Controllers/ContentManagementController.cs` (table `contents`: privacy-policy, terms-of-service, about-us, about-membership): `ANY /content-management` (Content_Management:view, V), `ANY /content-management/edit/{id}` (edit, V), `POST /content-management/edit/{id}` (auth only, V/R). Saving inserts a `user_notification` row for every user with push on and sends a legacy FCM push "Our ... has been updated" (`DAL/ContentDAL.cs:115-160`).

`Controllers/ContactManagementController.cs` (table `contact`: per-facility email, phone, UEN, address, image to S3 `contact/`): `ANY /contact-management` (Contact_Us:view), `POST /contact-management/getlist` (view), `ANY /contact-management/create` (add), `POST /contact-management/create` (auth only), `ANY /contact-management/edit/{id}` (edit), `POST /contact-management/edit/{id}` (Contact_Us:**add**), `ANY /contact-management/detail/{id}` (view).

`Controllers/FeedbackController.cs` (app feedback, table `feedback`): `ANY /feedback` (Feedback:view, V), `POST /feedback/getlist` (Feedback:status, J), `POST /feedback/ChangeStatus` (Feedback:status, J).

`Controllers/FeedbackSubjectController.cs` (table `feedback_subject`): `ANY /feedback-subject` (view), `POST /feedback-subject/getlist` (view), `ANY /feedback-subject/create` (add), `POST /feedback-subject/create` (auth only), `ANY /feedback-subject/edit/{id}` (edit), `POST /feedback-subject/edit/{id}` (auth only), `ANY /feedback-subject/detail/{id}` (view), `POST /feedback-subject/ChangeStatus` (status).

### 2.7 Push campaigns (YES) — `Controllers/NotificationManagementController.cs`

| Verb | Route | Permission | Ret | Purpose |
|---|---|---|---|---|
| ANY | `/push-notification-management` | Push_Notifications:view | V | List page |
| POST | `/push-notification-management/getlist` | Feedback_Subject_Management:view (copy-paste bug) | J | List |
| ANY | `/push-notification-management/create` | Push_Notifications:add | V | Form |
| POST | `/push-notification-management/create` | auth only | V/R | Create: title, text, image (S3 `push/`), target facilities, send time. Schedules Hangfire `PushNotificationJob(id)` at `PushDatetime`, or enqueues now (`DAL/PushNotificationDAL.cs:129-138`) |
| ANY | `/push-notification-management/edit/{id}` | Push_Notifications:edit | V | Form |
| POST | `/push-notification-management/edit/{id}` | auth only | V/R | Update; deletes the old Hangfire job and reschedules |
| ANY | `/push-notification-management/detail/{id}` | Push_Notifications:view | V | Detail |
| POST | `/push-notification-management/ChangeStatus` | Push_Notifications:edit | J | Disable → deletes the Hangfire job |

### 2.8 Noke smart locks (YES) — `Controllers/NokeManagementController.cs`

| Verb | Route | Permission | Ret | Purpose |
|---|---|---|---|---|
| GET | `/noke-management` | Noke_Management:view | V | Lock list page + non-unit locks (gates) |
| POST | `/noke-management/getlist` | auth only | J | Lock list (Noke `/user/locks/`); adds "Unlock door" button if claim `IsAbleToRemotelyUnlockUnit` |
| POST | `/noke-management/unlock` | flag `RemotelyUnlockUnit` / `RemotelyUnlockNonUnit` only, and only when `hwType` matches | J | 🔴 Remote unlock (Noke `/lock/unlock/mesh/`). Any other `hwType` value skips both checks (`:91-147`) |
| ANY | `/noke-management/detail/param={param}` | Noke_Management:view | V | Lock detail, unlocked users |
| POST | `/noke-management/detail` | auth only | J | Share list for a lock (Noke `/user/shares/`) |
| POST | `/noke-management/unlockhistory` | auth only | J | Activity (Noke `/activity/search/`) |
| POST | `/noke-management/revokeaccess` | flag `RemotelyUnlockUnit` | J | Revoke a shared user (Noke `/user/share/delete/`) |

### 2.9 Reports and audit (YES)

`Controllers/ReportsController.cs`: `ANY /reports` (Reports:view, V); `POST /reports/download` (Reports:view, F) — form field `model` JSON; types `reward-management` (`sp_RewardReport`) and `storer-management` (`sp_StorerReport`) as CSV; `audit-trial` and `transaction-history` cases are commented out.

`Controllers/AuditLogController.cs`: `ANY /audit-logs` (Audit_Log:view, V), `POST /audit-logs/getlist` (auth only, J), `POST /audit-logs/export` (Payment_Transactions:export — wrong menu, J). Reads `cms_audit_log`.

### 2.10 CMS staff accounts — `Controllers/AdminUserController.cs`

| Verb | Route | Permission | Ret | Purpose |
|---|---|---|---|---|
| ANY | `/cmsaccount-management` | CMS_Account:view | V | Staff list |
| POST | `/cmsaccount-management/getlist` | CMS_Account:view | J | List |
| ANY | `/cmsaccount-management/create` | CMS_Account:add | V | Form |
| POST | `/cmsaccount-management/create` | 🔴 **auth only** | V/R | Create staff: name, email, mobile, role, YES facilities, Express facilities + Express flags, refund/unlock flags, password (`:107-149`) |
| ANY | `/cmsaccount-management/edit/{id}` | CMS_Account:edit | V | Form |
| POST | `/cmsaccount-management/edit/{id}` | 🔴 **auth only** | V/R | Update any staff account incl. role and password (`:212-255`) |
| ANY | `/cmsaccount-management/detail/{id}` | CMS_Account:view | V | Detail |
| POST | `/cmsaccount-management/ChangeStatus` | CMS_Account:status | J | Enable / disable |

There is **no screen to edit roles or permissions**. `cms_role`, `cms_menu`, `cms_menu_permission` are seeded in the DB only (inferred: no controller touches them).

### 2.11 Background-job control — `Controllers/RecurringJobController.cs` (class `[Authorize(Roles = "Head Admin")]`)

All are **GET-style `[Route]` actions that change server state** (register / remove Hangfire recurring jobs) and redirect to `/recurring-jobs`. 🔴 A Head Admin who opens a crafted link changes job schedules (no antiforgery; SameSite=Lax still sends the cookie on top-level GET).

| Route | Effect (`RecurringJob.AddOrUpdate`, time zone) |
|---|---|
| `ANY recurring-jobs` | View: list of recurring jobs from Hangfire storage + buttons |
| `/recurring-jobs/uniqgift-reward` | `UniqgiftRewards` `Cron.Daily()` (00:00, `TimeZoneInfo.Local`) |
| `/recurring-jobs/offline-payment` | `ThreePMOfflinePayment` daily 15:00 and `NinePMOfflinePayment` daily 21:00 (Local) |
| `/recurring-jobs/tenant/{daily\|minutely\|hourly\|weekly\|monthly\|stop}` | `TenantAsync`: 00:00 / every 15 min / hourly / Sunday 00:00 / 1st of month; `stop` removes it (added 2026-08-02) |
| `/recurring-jobs/invoice/{daily\|minutely\|hourly}` | `PaymentReminder` 09:00 / 15 min / hourly |
| `/recurring-jobs/payment/{daily\|minutely\|hourly\|stop}` | `RecurringPaymentJob` 09:00 / 15 min / hourly, time zone `Asia/Singapore`; `stop` removes it |
| `/recurring-jobs/point-expiry/{daily\|minutely\|hourly}` | `PointExpiryJob` 09:00 |
| `/recurring-jobs/voucher-expiry/{type}/{1\|7}` | `VoucherExpiryJob` (1 day) or `VoucherExpiry7Days`, 09:00 |
| `/recurring-jobs/card-expiry` | `PaymentCardExpiryAlert` `Cron.Monthly()` |
| `/recurring-jobs/tenant-normalization` | `TenantNormalizeAsync` daily 00:00 |
| `/recurring-jobs/noke` | `RecurringRemoveExpiredNokeShares` daily 00:00 |
| `/recurring-jobs/unit-information/{daily\|minutely\|hourly}` | `UnitsInformationAsync` 09:00 / 30 min / hourly |
| `/recurring-jobs/sync-management-summary/{type}` | `syncSiteLinkDashboardManagementDb` 00:00 / 30 min / hourly |
| `/recurring-jobs/sync-movein-moveout-summary/{type}` | `syncSiteLinkMoveInandMoveOutDb` |
| `/recurring-jobs/sync-sl-receipts/{type}` | `syncSiteLinkReceiptsDb` |
| `/recurring-jobs/sync-sl-discount/{type}` | `syncDiscountDb` |
| `/recurring-jobs/sync-sl-merchandise-summary/{type}` | `syncMerchandiseSummaryDb` |
| `/recurring-jobs/sync-sl-rental-activity/{type}` | `syncRentalActivityDb` |
| `/RecurringJob/SendFailureNotification` (conventional) | Public helper accidentally routable; sends the "Hangfire job failure" email to two hard-coded Codigo developer addresses |

Containers set `ENV TZ=Asia/Singapore` (`Dockerfile:8`, `Dockerfile-GithubAction:6`), so `TimeZoneInfo.Local` = Singapore time (inferred from the Dockerfile).

### 2.12 Legacy "Express Import" module (YES DB, `ex_*` tables) — `Controllers/ExpressModule/`

| Controller | Verb + route | Permission | Ret | Purpose |
|---|---|---|---|---|
| `ExImportController` | GET `/eximport` | Express_Import:view | V | Upload page |
| | POST `/exmodule/import` | auth only | J | Read XLSX (ClosedXML): columns SiteID, Type, Unit, UnitTypeID, dcWidth, dcLength, ...; skip unit types in config `NotAllowedUnitTypes`; create `ex_facility`, `ex_units`, `ex_unit_storage_plan` rows |
| | POST `/units/getlist`, `/unittypes/getlist`, `/unitsizes/getlist`, `/storageplan/getlist`, `/unitstorageplan/getlist` | auth only | J | 🔴 Same routes are also declared on the controllers below → ambiguous route match at runtime (inferred) |
| `ExUnitController` (no `[Authorize]`, relies on `BaseController`) | GET `/units`; POST `/units/getlist` | auth only | V / J | `ex_units` list |
| `ExUnitTypeController` | GET `/unittypes` (Ex_Unit_Types:view); POST `/unittypes/getlist`; POST `/unittypes/edit` | view / auth only | V / J / V | Unit types (image to S3 `post/`) |
| `ExUnitSizeController` | GET `/unitsizes` (Ex_Unit_Sizes:view); POST `/unitsizes/getlist` | | V / J | Unit sizes |
| `ExStoragePlanController` | GET `/storageplan` (Ex_Storage_Plan:view); POST `/storageplan/getlist`; POST `/storageplan/edit` | view / auth only | V / J / V | Storage plans |
| `ExUnitStoragePlanController` | GET `/unitstorageplan` (Ex_Unit_Discount_Plan:view); POST `/unitstorageplan/getlist` (edit); GET+POST `/unitstorageplan/create` (add / auth only); GET+POST `/unitstorageplan/edit/{id}` (edit / auth only); POST `/unitstorageplan/edit` (auth only, updates discount); GET `/exunitsize` | | V / J | Unit ↔ storage-plan discount mapping |
| `ExUnitRentalController` | POST `/unitrental` (Express_Import:view); POST `/unitrental/changestatus` (Express_Import:status) | | J | `ex_units` rental status list / change |
| `ExReservationController` | GET `/exreservation` (Ex_Unit_Sizes:view — copy-paste); POST `/exreservation/getlist`; POST `/exreservation/export` (Payment_Transactions:export) | | V / J | Reservations list / export |
| `ExAuditLogController` | GET `/exAuditLog` (Express_Import:view); POST `/exAuditLog/getlist` | | V / J | `ex_audit_log` |

### 2.13 Area `express` (ES Express back office)

Permissions come from the `ExpressMenu` claim (hard-coded per role, §3.3) via Express.Core `Utils.IsAuthorize(menu, action)`; money/refund/unlock actions use boolean claims `EsRefundRequestor`, `EsRefundApprover`, `EsIsAbleToRemotelyUnlockUnit`. All calls go to Express.Core repositories (agent C documents their logic and tables).

`AdminManagementController` — `express/manage-admin`

| Verb | Route | Permission | Ret | Purpose / Express.Core call |
|---|---|---|---|---|
| GET | `audit-trails` | Audit:view | V | Audit trail page (`IAdminManagementRepository.GetOptions`) |
| POST | `audit-trail` | auth only, AFT | J | List (`GetList`) |
| POST | `audit-trail/export` | Audit:export, AFT | F/R | CSV (`DownloadAuditCsv`) |

`DashboardController` — empty class (no actions).

`FacilityManagementController` — `express/manage-facilities`

| Verb | Route | Permission | Ret | Purpose / call |
|---|---|---|---|---|
| ANY | (base) | Facilities:view | V | List page |
| POST | (base) | auth only | J | `IFacilityRepository.List` |
| ANY | `create` | Facilities:add | V | Form (`GetOptions`) |
| POST | `create` | Facilities:add, AFT, no size limit | V/R | `Create` (images, multipart) |
| ANY | `{id}/edit` | Facilities:view | V | `GetEdit` |
| POST | `{id}/edit` | Facilities:edit, AFT | V/R | `Update` |
| POST | `{id}/flow-levels` | Facilities:view | J | Floor list (`FloorLevels`) |
| POST | `{id}/flow-levels/add` | Facilities:add, AFT | J | Add floor |
| PUT | `{id}/flow-levels/edit` | Facilities:edit, AFT | J | Edit floor |
| DELETE | `{id}/flow-levels/{floorId}` | Facilities:edit | J | `RemoveFloorLevels` |
| POST | `{id}/unit-deals` | auth only | J | `GetUnitDeals` |
| POST | `{id}/unit-renals` | auth only | J | `GetUnitRentals` (route typo kept) |
| POST | `{id}/status/{status}` | Facilities:edit | J/R | `Status` |
| POST | `{id}/tax-rates` | auth only | J | Tax-rate list (`TaxRates`) |
| POST | `{id}/tax-rates/add` | Facilities:edit | J | Add tax rate (GST for Express) |

`FaqManagementController` — `express/manage-faqs`: `ANY` (base, FAQs:view, V, writes audit trail), `POST` (base, auth only, J, `ListTopic`), `ANY create/{topic}` (add, V), `POST create/{topic}` (add, AFT), `ANY {id}/edit` (view+edit, V), `POST {id}/edit` (edit, AFT), `POST ordering/faqs` (edit, AFT), `POST ordering/topics` (edit, AFT), `POST {id}/status/{status}` (edit, AFT), `DELETE {id}` (edit, AFT), `POST topic/create` (add, AFT), `ANY topic/edit` (edit, J), `POST topic/edit` (edit, AFT). All via `IFaqRepository` + `SaveAuditTrail`.

`InsurancePlanManagementController` — `express/manage-insurance-plans`: `ANY` (InsurancePlan:view, V), `POST` (view, J, `List`), `ANY create` (**auth only**, V), `POST create` (**auth only**, AFT, `Create`), `ANY {id}/edit` (view+edit, V), `POST {id}/edit` (view+edit, AFT, `Update`), `POST {id}/status/{status}` (edit, AFT).

`MasterSettingManagementController` — `express/master-setting`

| Verb | Route | Permission | Purpose (`IMasterSettingRepository`) |
|---|---|---|---|
| ANY | `units` | MasterUnit:view | Unit master page |
| POST | `units/unit-types` | auth only, AFT | Unit-type list |
| ANY / POST | `units/unit-types/create` | unit_type_add (POST: AFT, 10 MB) | Create unit type (image) |
| ANY / POST | `units/unit-types/{id}/edit` | unit_type_view+edit / unit_type_edit | Edit unit type |
| POST | `units/unit-types/{id}/status/{status}` | auth only, AFT | Toggle |
| DELETE | `units/unit-types/{id}` | unit_type_edit, AFT | Delete |
| POST | `units/unit-sizes` | unit_size_edit, AFT | Unit-size list |
| ANY / POST | `units/unit-sizes/create` | unit_size_add | Create size |
| ANY / POST | `units/unit-sizes/{id}/edit` | unit_size_edit | Edit size |
| POST | `units/unit-sizes/{id}/status/{status}` | unit_size_edit | Toggle |
| DELETE | `units/unit-sizes/{id}` | unit_size_edit | Delete |
| POST | `units/base-rates` | unit_base_rate_view, AFT | Base-rate list |
| ANY / POST | `units/base-rates/create` | unit_base_rate_add | Create base rate |
| ANY / POST | `units/base-rates/{id}/edit` | unit_base_rate_edit | Edit base rate |
| GET / POST | `late-fees` | LateFee:view / LateFee:edit | Late-fee settings |
| ANY | `regions` | Regions:view | Page |
| POST | `regions` | auth only, AFT | List |
| POST | `regions/create`, `regions/edit` | Regions:add / Regions:edit | Create / edit (image 10 MB) |
| DELETE | `regions/{id}` | Regions:edit | Delete |
| GET / POST | `privacy-policy` | PrivacyPolicy:view / edit | Edit Express privacy policy |
| GET / POST | `terms-and-conditions` | TermsConditions:view / edit | Edit Express T&C |

`MemberManagementController` — `express/manage-members` (🔴 almost no permission checks; any logged-in CMS user)

| Verb | Route | Permission | Purpose (`IMemberRepository`) |
|---|---|---|---|
| GET | (base) | Members:view | List page |
| POST | (base) | auth only, AFT | `List` |
| GET / POST | `{id}/details` | auth only (POST AFT) | View / update member (`Details`, `Update`) |
| POST | `{id}/banned`, `{id}/unbanned` | auth only, AFT | Ban / unban |
| POST | `{id}/status/{status}` | auth only, AFT | Change status |
| DELETE | `{id}` | auth only, AFT | Delete member |
| GET | `{userId}/rental-units` | auth only, AFT | Rentals list |
| ANY | `{userId}/rental-units/{rentalId}` | auth only | Rental details view |
| POST | `{userId}/transactions` | auth only, AFT | Payments |
| POST | `{userId}/remarks`; GET+POST `{userId}/remarks/add`; GET+POST `{userId}/remarks/{remarkId}/edit` | auth only | Staff remarks |
| POST | `{userId}/{unitId}/rate-history` | auth only, AFT | Rate history |
| GET | `rental-units/{filename}/download` | Members:member_unit_rental_export | Rental PDFs |
| GET | `rental-units/{rentalId}/reciept-pdf` | auth only | Receipt PDF |
| GET / POST | `unregistered` | auth only | Stripe customers with no app account (`GetUnRegisteredCustomer`) |
| GET | `unregistered/{customerId}` | auth only | Stripe customer detail (`GetCustomerInfo`) |
| POST | `unregistered/options` | auth only | Facility/unit/unit-type pickers |
| GET | `onboard/offline` | auth only | Offline onboarding form |
| POST | `unregistered/{customerId}` | auth only, AFT | Create app user + rental from a Stripe customer (`SaveManualUser`; sends first-time-login email) |
| POST | `onboard/offline` | auth only, AFT | Create offline user + rental (`SaveOfflineManualUser`) |

`NokeManagementController` — `express/manage-noke`: `ANY` (Noke:view, V), `POST` (view, AFT, `List`), `ANY {unitId}/{lockId}/edit` (view, V), `POST {unitId}/{lockId}/battery-records` (view), `POST {unitId}/batter-lastChanged` (auth only), `POST {unitId}/{lockId}/noke-activities` (auth only), `POST {unitId}/{lockId}/lock-shares` (auth only), `POST {unitId}/remote-unlock` (flag `EsIsAbleToRemotelyUnlockUnit`, AFT), `GET {unitId}/{lockId}/download/userHistory` and `.../nokeHistory` (Noke:export, CSV).

`PromoCodeManagementController` — `express/manage-promo-codes`: `ANY` (PromoCodes:view), `POST` (view, `List`), `ANY create` (add), `POST create` (add, AFT), `ANY {id}/details` (view), `ANY {id}/edit` (edit), `POST {id}/edit` (edit, AFT), `GET applicables/{type}` (view), `POST {id}/active`, `{id}/inactive`, `{id}/delete` (edit, AFT), `POST {id}/usage-history` (view).

`ReportGenerationController` — `express/report-generation`: `ANY` (needs one of Reports:customer/unit/ar/receipt_report_export, V), `POST download` (Reports:view) → CSV: `customer-report` (`sp_CustomerReport`), `unit-report` (`sp_UnitReport`), `accounts-receiveble-report` (`IReportRepository.AccountReceivable`), `receipt-coleection-report` (`ReceiptCollectionGenerator`). Note: the per-report export permissions shown in the menu are not checked on download, only `view`.

`StoragePlanManagementController` — `express/manage-storage-plans`: `ANY` (StoragePlan:view), `POST` (view), `ANY create` (add), `POST create` (add, AFT), `ANY {id}/edit` (edit+view), `POST {id}/edit` (edit, AFT), `POST {id}/status/{status}` (edit, AFT).

`TransactionManagementController` — `express/manage-transactions`

| Verb | Route | Permission | Purpose (`ITransactionRepository`) |
|---|---|---|---|
| GET | (base) | Transactions:view | Page |
| POST | (base) | view, AFT | `List` |
| GET | `addmanualtransaciton/{rentalId}` | auth only | Current-month bill for a rental |
| POST | `addmanualtransaciton/{rentalId}` | auth only, AFT | 🔴 Record a manual (offline) payment |
| ANY | `{id}/details` | view | Detail page |
| POST | `{transactionId}/refund-transactions` | flag `EsRefundApprover`, AFT | Stripe refund of a transaction |
| GET | `{transactionId}/refund-transactions` | flag `EsRefundApprover` | Refundable info |
| POST | `export` | Transactions:export, AFT | Export JSON |
| GET | `{rentalId}/{transactionId}/reciept-pdf` | auth only | Receipt PDF |
| GET | `{rentalId}/{refundId}/refund-pdf` | export | Refund PDF |
| POST | `manualtransaction/{rentalId}/refund` | auth only, AFT | 🔴 Refund a manual transaction |

`UnitManagementController` — `express/manage-units`

| Verb | Route | Permission | Purpose (`IUnitRepository`) |
|---|---|---|---|
| ANY | (base) | Units:view | Page |
| POST | (base) | view, AFT | `List` |
| ANY / POST | `create` | Units:add | Create unit |
| ANY / POST | `{id}/edit` | view+edit / edit+unit_change_status | Edit unit |
| POST | `{id}/status/{status}` | unit_change_status | Status |
| POST | `{id}/{status}` | edit | Featured flag |
| POST | `{id}/history` | view | Unit history |
| POST | `{id}/{requestId}/finalise-move-out` | unit_change_status | Finalise a move-out request |
| POST | `{unitId}/force-move-out` | force_moveout | Force move-out |
| GET | `download/template` | add | CSV template |
| POST | `upload/template` | add | Bulk upload units |
| GET | `{unitId}/moveout-refundable` | flag EsRefundRequestor or EsRefundApprover | Refundable amount |
| POST | `{unitId}/request-moveout-refund` | flag EsRefundRequestor | Maker |
| POST | `{unitId}/approve-moveout-refund` | flag EsRefundApprover | Checker → Stripe refund + emails |
| POST | `{unitId}/reject-moveout-refund` | flag EsRefundApprover | Reject |
| POST | `{unitId}/cancel-moveout-refund` | flag EsRefundRequestor | Cancel |
| POST | `change-dontrent-status` | auth only, AFT | "Do not rent" flag |

`wwwroot/js/es-express/unit/*.js` calls `/express/manage-units/moveout/save`, which has no action (dead client code).

---

## 3. Admin users and RBAC

### 3.1 Accounts and tables

- `cms_user`: name, email, mobile, designation, department, `password_hash`, `password_salt` (PBKDF2 via `Codigo.Crypto`), `password_key` (GUID, rotated on every password change), `role_id`, `status`, reset code + expiry + status, flags `refund_requestor`, `refund_approver`, `view_noke_lock`, `remotely_unlock`, `remotely_unlock_unit`, `remotely_unlock_non_unit` (`Entities/CmsUser.cs`).
- `cms_role` (`role_name`, `role_key`), `cms_menu` (id, parent, name, route, level, sort, icon), `cms_menu_permission` (role × menu → comma-separated permission string, e.g. `view,add,edit,status`).
- `cms_user_facility`: which SiteLink sites (YES) a staff member sees.
- `cms_user_express_facilities`: Express facility list (string) + byte flags `requestor`, `approver`, `unlock_unit_remotely`, `unlock_non_unit_remotely`, `es_user_address_editable`.
- `cms_user_devices`: one row per browser (OS/browser from User-Agent, `device_uuid` = AES of the UA string, 20-min expiry that nobody checks).
- `cms_audit_log`: audit trail (§3.5). `key_value` row `common password`: list of banned passwords.

Role names seen in code: Head Admin, Sub Admin, Management, Facility Manager, Customer Service Executive, Marketing, Accounts (`AuthenticationController.cs:816,1037,1255,1419,1554,1674,1837`). Two role GUIDs are hard-coded (`AuthenticationController.cs:160`, `Views/AdminUser/Detail.cshtml:150`).

### 3.2 Login and 2FA

1. `POST /account/login`: find active `cms_user` by email, check PBKDF2 hash (`BL/AuthenticationBL.cs`). No lockout counter; only the IP rate limit.
2. Make a 6-digit OTP with `System.Random` (`Services/PinCodeGenerator.cs`), email it via SendGrid.
3. Store `{id, email, password, pin}` AES-encrypted in cookie `otpToken` (30 min, HttpOnly, Secure, SameSite=None, domain = `extraspaceasia.com.{country}` i.e. the parent domain) (`AuthenticationController.cs:252-280, 1976-1991`). 🔴 The **plain password** travels inside this cookie (encrypted, but to every subdomain).
4. `POST /account/otplogin`: decrypt cookie, re-run password check, compare pin with `string.Equals` (no attempt counter, no server-side store, no OTP expiry other than the cookie lifetime).
5. Build the claims: `UserId`, `UserName`, `Name`, role (both `ClaimTypes.Role` and `Role`), `RoleId`, encrypted `RoleKey` and `PasswordKey`, `Facilities` (JSON list of YES site ids), `IsYES`, `IsES`, `Menu` (JSON of YES menus+permissions from the DB), `ExpressMenu` (JSON, hard-coded per role), unlock flags, refund flags, `EsFacilities`, `EsRefundRequestor/Approver`, `EsIsAbleToRemotelyUnlockUnit/NonUnit`, `EsUserAddressEditable`. The whole permission model rides in the cookie.
6. Sign in (persistent, 20-min sliding), delete + insert the `cms_user_devices` row, write audit "login success".

Other paths: `POST /account/loginold` signs in **without OTP** (🔴 2FA bypass, not rate-limited); `POST /reset-password/{token}` signs in with a 10-year cookie and a smaller claim set.

Password rules: reset form regex = 8–25 chars, at least one lower, one upper, one digit (`Model/RestPasswordModel.cs:14-15`); change-password = 8–25 chars; all paths reject passwords in the `common password` list. Reset token = AES of `{reset_code, email, expiry}`; GET checks expiry, but the POST path (`DAL/AuthenticationDAL.cs:120-148`) does **not** re-check `reset_code_expiry` (bug, inferred: an expired but unused link still works).

### 3.3 Permission model

- **YES menus**: `GeneralUtility.IsAuthorize(claims, Menu, Action)` (`Common/GeneralUtility.cs:141-175`). Passes only if the user has claim `IsYES=True` or role Head Admin / Sub Admin; then looks in the `Menu` claim for the menu id whose permission string **contains** the action name. 🔴 It is a substring test: a role with `edit_point` also passes `edit`; `unit_view` passes `view`. Menu ids: Dashboard 1, Member_Management 2, Reward_Management 3, Payment_Transactions 4, Post_Management 5, Content_Management 6, Contact_Us 7, FAQ_Management 8, Tag_Management 9, Feedback_Subject_Management 10, Reward_Categories 11, CMS_Account 12, Feedback 13, Push_Notifications 14, Audit_Log 15, Payment_Setting 16, Reports 17, Noke_Management 18, Express_Import 19, Ex_Storage_Plan 20, Ex_Unit_Discount_Plan 21, Ex_Unit_Sizes 22, Ex_Unit_Types 23 (`Common/EnumCollection.cs`).
- **Express menus**: `Express.Core.Utils.IsAuthorize` checks `IsES=True` then exact match in the `ExpressMenu` claim. The `ExpressMenu` content is **hard-coded per role name** in `AuthenticationController.checkByRole` (≈1,150 lines). Changing an Express permission needs a code deploy.
- **Facility scope**: YES list and dashboard SQL filters by the `Facilities` claim (`_request.Facilities` in `BL/MemberBL.cs`, `DAL/DashboardDAL.cs`, `DAL/ReportDAL.cs`, `BL/ContactBL.cs`, `BL/PaymentBL.cs`, `BL/PushNotificationBL.cs`). Detail-by-id endpoints do not re-check the facility (e.g. `DAL/MemberDAL.cs:437` loads by id only).
- **Special flags**: refund maker/checker and remote unlock are booleans on `cms_user` / `cms_user_express_facilities`, not menu permissions.
- **Role only**: `/recurring-jobs/*` and `/hangfire` require role "Head Admin".

### 3.4 Per-request session checks

`BaseController.OnActionExecuting` (`Controllers/BaseController.cs:29-118`) runs on every YES action: raw SQL reads `cms_user.status`, `password_key`, `cms_role.role_key` and the device row; suspended → `/account-suspend`; changed password key or role key → `/logout`; no row → `/logout`; unauthenticated → `/account/login`. The device-expiry branch is empty (commented). The Express area controllers (`expressBaseController`) and `AuthenticationController` skip this check, so a disabled or demoted admin keeps using `/express/*` until the cookie expires.

### 3.5 Audit logs

- YES: `LogHelper.WriteAuditLog(menuId, actionId, objectId, message, user)` inserts into `cms_audit_log` with its own MySQL connection (`Common/LogHelper.cs:47-90`). Called on login, logout, create/edit/status/export of most modules. Viewed at `/audit-logs`.
- Express: Express.Core `SaveAuditTrail` / `IAdminManagementRepository` (agent C), viewed at `/express/manage-admin/audit-trails`.
- Legacy Ex module: `ex_audit_log`.
- Technical logs: `ILogger` JSON lines via `CustomLogger.LogInformationWithMetadata` (console, inferred to CloudWatch); log4net ADO appenders write `recurring_payment_log` and `tenant_sync_log` (`log4net.config`); every `LogErrorWithMetadata` also emails `tech@extraspaceasia.com` (de-duplicated 5 min in memory, `Common/CustomLogger.cs:37-100`); `sitelink_transaction` counts every SiteLink call (`Services/SiteLink/SiteLinkAPIs.cs:1970`).

---

## 4. Feature modules (YES)

Money in the YES code uses C# `decimal`; currency from config `country:currency` / `country:stripecurrency` (`S$` / `sgd` in all committed appsettings). Dates: `DateTime.Now` (container = Singapore time) and `DateTime.UtcNow` are mixed freely.

### 4.1 Members (app users = SiteLink tenants)

- Tables: `user`, `user_tenantsite` (user × SiteLink site × tenant id, `storage_unit` csv, `outstanding_amount`), `user_storage_unit`, `user_device` (push tokens), `user_notification`, `user_payment_card`, `point_transaction`, `redeem_reward`.
- Status values: Overdue 0, Active 1, Inactive 2, Deleted 3 (`EnumCollection.StorerStatus`). CMS "suspend" sets Overdue (with notice + email) or Inactive (`DAL/MemberDAL.cs:137-258`).
- Add member: search SiteLink tenants, create `user` + `user_tenantsite` (`DAL/MemberDAL.cs:498-553`).
- Update profile: DB only (`/member-management/detail/{id}` POST); password change and PIN reset write to **SiteLink** via `TenantUpdate`, which re-sends the full tenant record (read-modify-write of ~50 fields). PIN reset sends `sWebPassword: ""` (`SiteLinkAPIs.cs:786`) — unknown whether SiteLink treats empty as "no change" (open question).
- Tier (months since `membership_date`): Gold > 47, Silver ≥ 12 (jobs) or > 12 (`GeneralUtility.CalculateTier`, dashboard SQL), Blue otherwise. 🔴 The 12-month boundary differs between code paths.

### 4.2 Payments made in the app (read in CMS) and YES refunds

- Tables: `payment` → `payment_facility` (per site, seq_no, status) → `payment_unit` (per unit, SiteLink receipt no, ret code, wallet discount) and `payment_transaction` (type Charge 1 / Refund 2, Stripe id, status). `request_refund` for the maker-checker.
- Transaction status enum: Payment_Success 1, Payment_Failed 2, Pending_Refund_Approval 3, Refund_Request_Rejected 4, Refund_Success 5, Cancel_Request 6, Refund_Failed 7.
- **Refund flow** (`DAL/PaymentDAL.cs:299-820`):
  1. Requestor (flag `refund_requestor`) submits amount + reason. Check: no pending request for the same transaction; amount ≤ charged − already refunded. Status → 3. Emails all approvers who have that facility (`refund_request.html`).
  2. Approver (flag `refund_approver`) approves → `Stripe RefundService.Create` with `PaymentIntent = stripe_id`, amount in cents = `amount.ToString("#.00")` with the dot removed, reason `requested_by_customer`, **API key = that facility's own Stripe secret key** (`master_facility.stripe_secret_key`, AES-decrypted), idempotency key = a new GUID. On success: new Refund `payment_transaction`, status 5, emails customer (`refund_success.html`, BCC facility) and approvers (`refund_approve.html`). On Stripe error: status 7.
  3. Reject → 4; cancel → 6 (facility status back to 1).
  - No check that approver ≠ requestor, and no facility check on the approver (only for who gets emails). No row lock: a double click may double-refund (inferred; Stripe idempotency key differs per click).
  - **SiteLink is not touched** on refund (inferred: staff reverse the ledger by hand in SiteLink).

### 4.3 Recurring card payment (autopay) — see job `RecurringPaymentJob` in §5

Summary of `ScheduleJob.MakePayment` (`Services/ScheduleJob.cs:2397-3112`), for each bill item due **today** (`DueDate == UtcNow.Date`, amount > 0):
1. Load the saved card (`user_payment_card.recurring_card`, AES-encrypted Stripe PaymentMethod id) and Stripe customer id; `GetPaymentMethod`.
2. For non-default sites, clone the PaymentMethod onto the facility's **Stripe connected account** (`StripeAccount` header = `master_facility.stripe_account`, AES). Default site = config `SiteLink:SiteID` (platform account).
3. `PaymentIntent.Create` (confirm=true, off-session future usage, metadata UserId/FacilityName/SiteID/UnitID/UnitName/TenantID, statement suffix "Extra Space Asia"), idempotency key = new `payment_facility.id` (a new GUID each run, so no protection across runs).
4. If `requires_action` and config `stripe:threeds` = true (false in production): confirm with return URL `{site:weburl}/redirect/PaymentStatus`, cache intent in Redis `stripe_3dpayment_{id}` 5 days, email 3-D Secure link (`stripe_3d_confirmation.html`), stop.
5. On Stripe success: record the payment in **SiteLink** with `PaymentSimpleWithSource` (raw SOAP, §7.1) using a **fake test card number per brand** (Visa `4242...`, Mastercard `5555...`, etc.), CVV 123, expiry = today + 1 year, `bTestMode=true`, `iSource=10`. Read `dPaidThru` before and after.
6. If SiteLink fails with `Ret_Code = -14`: user status → Overdue, facility gets "Failed Payment - Sitelink" email, **Stripe is not refunded and the unit stays marked success** (bug, inferred). Other SiteLink failures: Stripe refund using the facility secret key, refund transaction row, unit marked failed.
7. Points: `ceil(amount × tier rate)` (Blue 1.0, Silver 1.2, Gold 1.5), 24-month expiry, "ePoints received".
8. In-app notification + legacy FCM push; receipt email after a 60-second sleep (`successful_payment.html`, BCC facility).
- All of this runs inside one `TransactionScope` (ReadUncommitted, 15-min timeout) that wraps external Stripe and SiteLink calls.

### 4.4 E-points

- Earn: online recurring payment (above), offline SiteLink receipts (`ThreePMOfflinePayment` / `NinePMOfflinePayment`, §5), CMS adjust.
- Rate: 1 point per currency unit × tier multiplier, rounded **up** (`Math.Ceiling`). Expiry 2 years.
- CMS adjust (`DAL/MemberDAL.cs:258-370`): Add → new `point_transaction` type Adjusted (3) with +N, 2-year expiry, in-app notice + push. Deduct → must have ≥ N unexpired points **at that facility**; consumes rows FIFO by expiry (`point_use += ...`) **and** writes a −N Adjusted row (inferred: deduction recorded twice; sums exclude the negative row because they filter `total_points > point_use`). `user.points` recomputed.
- Expiry reminders: `sp_PointExpiry` (DB, agent C) → notice "You have N points expiring in 30 days!", push, email `points_expired.html`.

### 4.5 Rewards and vouchers

- `reward_category` (icon on S3, order, status), `reward` (name, category, exchange points, start/end, validity type, months or fixed expiry, `extraspace_voucher` flag, discount type/value, featured flag + sorting, UniqGift order number / product code / URL), `reward_image`, `redeem_reward` (wallet: voucher id, short URL, auth code, status Active 1 / Used 2 / Expired 3, expiry, site).
- Providers: Extra Space vouchers (internal), **UniqGift** (voucher status check `/gift/vouchers/check`), **WOGI** (product info `/products/{id}`, card info `/cards/{id}`). Redemption itself happens in the mobile API (agent A, inferred).
- Featured rewards list + manual ordering.

### 4.6 Posts / articles, tags, FAQ, contents, contacts, feedback

Simple CRUD with status flags and S3 images (folders `post`, `contact`, `push`, `rewards`, `reward-category/icon`; bucket = `AWS:S3:Bucket`; uploads are public-read). Contents update triggers a push to all opted-in users (§2.6). Feedback comes from the app; CMS only changes its status.

### 4.7 Push campaigns

`PushNotificationJob(id)` (`Services/ScheduleJob.cs:774-878`): one raw SQL batch selects push tokens of opted-in users (all, or users with a tenant at the chosen sites), inserts a `user_notification` row for each user, and sets `push_notification.status = 1`; then sends one legacy FCM request per user (`https://fcm.googleapis.com/fcm/send`, header `key={PushNotification:ServerKey}`), then status = 2. 🔴 Title and text are pasted into the SQL string (injection, and an apostrophe breaks the job). Inferred: Google shut down the legacy FCM HTTP API in 2024, so these pushes may no longer be delivered.

### 4.8 Noke locks (YES)

Lists locks per facility (`master_facility.noke_site_id`), remote unlock, show and revoke shared access, activity history. External: Noke API (`Noke:baseUrl`, headers `Authorization: {Noke:apiKey}`, `CompanyId`), endpoints `/user/locks/`, `/lock/unlock/mesh/`, `/user/shares/`, `/user/share/delete/`, `/activity/search/`. Tables `Noke_Unit`, `Noke_Shares`, `Noke_Pin_Failed`. Each call is logged with a log id (`Services/NokeService.cs`).

### 4.9 Payment settings

Per-facility `allow_partial_payment` flag (§2.4).

### 4.10 Express (Area) modules

Facilities (+ floors, tax rates, status), units (+ status, featured, history, move-out finalise / force, bulk CSV upload, do-not-rent, move-out refund maker-checker), master data (unit types, sizes, base rates, late fees, regions, privacy policy, T&C), storage plans, insurance plans, promo codes (+ applicables, usage history), members (+ ban, status, delete, remarks, rentals, rate history, PDFs, onboarding Stripe-only and offline customers), transactions (+ manual payment, manual refund, Stripe refund, receipt / refund PDF), Noke (battery, activity, shares, remote unlock, CSV), FAQ (topics + items + ordering), reports, audit trail. Business rules (pricing, proration, GST via tax rates, late fees, move-out refunds, Stripe, Noke, FCM v1) live in Express.Core → agent C.

---

## 5. Background jobs (Hangfire, `Services/ScheduleJob.cs`)

How jobs get registered: **not at startup**. A Head Admin opens a `/recurring-jobs/...` link (§2.11), which calls `RecurringJob.AddOrUpdate`. The registration stays in Hangfire MySQL storage (`hangfire_*` tables) across deploys. Hangfire job id = `IScheduleJob.{Method}` (default naming).

How jobs are switched off (commit `cd6cc378`, 2026-08-05 "disable schedule jobs"): each job starts with `if (!IsJobEnabled()) return;` which reads config `jobs:{MethodName}`; missing = enabled, `false` = skip and log (`ScheduleJob.cs:161-172`). `appsettings.json` section `Jobs` now sets five jobs `true` and sixteen `false`. A second flag `EmailReminders:Enabled = false` (`ScheduleJob.cs:178-181`) suppresses reminder/expiry emails only (point expiry, voucher expiry, card expiry, payment reminder, past-due alert); transactional mail still goes out. `appsettings.Production.json` does not override these sections, so the base values apply in production unless env vars override (inferred). Commit `b451d1be` (2026-08-02) added `stop` links that remove the Hangfire registration for `RecurringPaymentJob` and `TenantAsync` (`RecurringJobController.cs:674-688`).

| Job | Schedule when registered | What it does | External calls | Idempotency | Status now |
|---|---|---|---|---|---|
| `ThreePMOfflinePayment` | daily 15:00 SGT | For each facility, SiteLink receipts from yesterday 21:00 to today 14:59 (skips Credit, Security Deposit, Applied Refund, Internet Payment, Call Center); award points to the matching member; email `successful_offline_payment.html` | SiteLink Reporting `Receipts` | Checks a `point_transaction` with description `"{LocationCode} - ePoints received - Offline payment receipt {receiptNo}"` | **Enabled** |
| `NinePMOfflinePayment` | daily 21:00 SGT | Same, window yesterday 21:00 to today 20:59 (overlaps the 15:00 run; the description check prevents double points) | same | same | **Enabled** |
| `PointExpiryJob` | daily 09:00 | `sp_PointExpiry` → notice + push "points expiring in 30 days" + email | FCM legacy, SendGrid | none (runs daily; relies on SP selecting a single day, inferred) | **Enabled** (email part off) |
| `UniqgiftRewards` | daily 00:00 | Refresh status / expiry of active UniqGift vouchers in `redeem_reward` | UniqGift `/gift/vouchers/check` | overwrite | **Enabled** |
| `WogigiftRewards` | none (no route registers it) | Refresh WOGI card status / expiry | WOGI `/cards/{id}` | overwrite | Enabled by config, but runs only if an older registration still exists in storage (inferred) |
| `PaymentReminder` | daily 09:00 (route `invoice`) | SiteLink invoices of last 30 days for users without autopay; new-invoice notice when invoice updated yesterday; reminder emails at due −15/−5/+5 days (SG) or −7/−1/+5/+14 (MY) | SiteLink `TenantInvoicesByTenantID`, `ChargesAndPaymentsByLedgerID`; SendGrid; FCM | none (date-match) | Disabled |
| `RecurringInvoiceJob` | none (no route) | Older version of the reminder job | same | none | Disabled (dead) |
| `RecurringPaymentJob` | daily 09:00 Asia/Singapore | Autopay: charge saved card for each unit due today, record in SiteLink, points, emails (§4.3) | Stripe, SiteLink `PaymentSimpleWithSource`, SendGrid, FCM, Redis | Weak: new idempotency key per run; second run same day charges again if SiteLink balance is still open (inferred) | **Disabled** (config + stop link) |
| `PaymentCardExpiryAlert` | monthly | Cards expiring next month → notice, push, email | FCM, SendGrid | none | Disabled |
| `VoucherExpiryJob` / `VoucherExpiry7Days` | daily 09:00 | `sp_VoucherExpiry(duration 1 / 7)` → notice, push, email from rewards@ | FCM, SendGrid | none | Disabled |
| `TenantAsync` | daily 00:00 (or 15 min / hourly / weekly / monthly) | For each non-deleted user (3 customer emails hard-coded as excluded), pull tenants by email, ledgers, outstanding balance; rewrite `user_tenantsite`, profile fields, status Active / Inactive | SiteLink `TenantListDetailed_v2`, `LedgersByTenantID`, `ChargesAndPaymentsByLedgerID` | overwrite (delete + insert) | **Disabled** (config + stop link) |
| `TenantNormalizeAsync` → `TenantDetailAsync(take, skip)` | daily 00:00 | Enqueues batches of `TakeCount` (100) users; rebuilds tenant sites, storage units (Redis `UnitIdKey_*`), profile from SiteLink, membership date | SiteLink `TenantListDetailed_v2`, `LedgersByTenantID`, `UnitsInformationByUnitID`, `TenantInfoByTenantID`, bills | overwrite | Disabled (`TenantDetailAsync` itself has no toggle) |
| `UnitsInformationAsync` | daily 09:00 / 30 min / hourly | Cache SiteLink units per facility in Redis `units_information_{LocationCode}` (3 h TTL) | SiteLink `UnitsInformation_v3` | overwrite | **Disabled** (inferred: mobile readers of this key now fall back or see nothing — agent A to confirm) |
| `RecurringRemoveExpiredNokeShares` | daily 00:00 | Delete expired Noke shared access (owner shares to guests) | Noke `/user/share/delete/` | checks share exists | **Disabled** 🔴 (inferred: expired guest shares are no longer revoked automatically) |
| `syncSiteLinkDashboardManagementDb` | daily 00:00 | Yesterday's ManagementSummary per facility → `sitelink_mgmt_summary_rental_activity / receipts / unit_activity`, then back-fill up to 3 missing days from 2024-01-01 | SiteLink Reporting `ManagementSummary` | skip if a row exists for date + location | Disabled |
| `syncSiteLinkMoveInandMoveOutDb` | daily 00:00 | MoveIns/MoveOuts → `sitelink_rental_activity_sqft_movein_and_moveout`, `..._total_...` | Reporting `MoveInsAndMoveOuts` | same | Disabled |
| `syncSiteLinkReceiptsDb` | daily 00:00 | Receipts → `sitelink_receipts` | Reporting `Receipts` | same | Disabled |
| `syncDiscountDb` | daily 00:00 | Discounts → `sitelink_discount_summary` | Reporting `Discounts` | same | Disabled |
| `syncMerchandiseSummaryDb` | daily 00:00 | → `sitelink_merchandise_summary` | Reporting `MerchandiseSummary` | same | Disabled |
| `syncRentalActivityDb` | daily 00:00 | → `rental_activity_sitelink` | Reporting `RentalActivity` | same | Disabled |
| `PushNotificationJob(id)` | delayed job at the push time | Admin push campaign (§4.7) | FCM legacy | `push_notification.status` 0 → 1 → 2 | **Always on** (no toggle) |

In Development the sync jobs use the hard-coded location code `L018`. Job failures in the controller send mail to two hard-coded developer addresses; `SendFailureNotification` calls itself in its own `catch` (possible infinite recursion, `RecurringJobController.cs:715-718`). An in-memory `BackgroundTaskQueue` sends receipt emails; queued items are lost on restart.

Not known from code: which recurring jobs are registered in production storage right now (the `mysql-dev` MCP failed to connect in this session).

---

## 6. Reports, exports, imports, PDFs, emails

Reports and exports:

| Name | Where | Format | Source | Users |
|---|---|---|---|---|
| Reward report | `POST /reports/download` type `reward-management` | CSV (CsvHelper) | `sp_RewardReport` | YES staff with Reports:view |
| Storer (member) report | type `storer-management` | CSV | `sp_StorerReport` | same |
| Audit / transaction reports | commented out | XLSX (ClosedXML) code kept | SQL | – |
| Member list, member payments, payment list, audit log, Ex reservations | `.../export` endpoints | JSON → CSV in browser | DB | YES staff |
| Express customer / unit / AR / receipt-collection | `POST /express/report-generation/download` | CSV | `sp_CustomerReport`, `sp_UnitReport` (Express DB), Express.Core `AccountReceivable`, `ReceiptCollectionGenerator` | Express staff |
| Express audit trail, Noke user history, Noke activity | Express endpoints | CSV | Express.Core | Express staff |
| Express unit template | `GET /express/manage-units/download/template` | CSV | Express.Core | Express staff |

Imports: legacy Ex XLSX import (`POST /exmodule/import`); Express unit CSV upload (`POST /express/manage-units/upload/template`, Express.Core).

PDFs:
- YES payment receipt PDF: HTML from `SiteLinkAPIs.GetPaymentReceiptPdf` (template `emailTemplates/receipt_pdf.html`) → DinkToPdf A4; the attachment line is commented out, so receipts are emailed **without** the PDF (`ScheduleJob.cs:3159-3204`).
- Express PDFs (receipt, refund, ad-hoc refund, move-out refund, move-out additional charge) are rendered by Express.Core `PdfGenerator` from `documents/express/*.html` in this project's content root.
- Native `libwkhtmltox.{dll,dylib,so}` are checked into the project root.

Email (all via SendGrid, `Services/AWSEmailSevice.cs:56-180`; default From/ReplyTo from `SENDGRID:*`; some mails use `billing@` or `rewards@extraspaceasia.com` and reply-to / BCC the facility email). Templates in `emailTemplates/`:

| Template | Used by |
|---|---|
| `otp-email.html`, `forgot_password.html` | Admin login / reset |
| `invoice_email.html`, `payment_reminder.html`, `payment_due_alert.html` | Reminder jobs |
| `successful_payment.html`, `successful_offline_payment.html`, `unsuccessful_payment.html`, `unsuccessful_sitelink_payment.html`, `stripe_3d_confirmation.html` | Autopay / offline points |
| `refund_request.html`, `refund_approve.html`, `refund_success.html` | YES refunds (request/approve also used by Express.Core `UnitRepository`) |
| `suspend_account.html` | Member suspend, payment job |
| `card_expire_alert.html`, `points_expired.html`, `voucher_expired.html` | Expiry jobs |
| `error_notification.html`, `hangfire_job_failure_notification.html` | Ops alerts |
| `receipt_pdf.html` | Receipt PDF body |
| `invoice_pdf.html`, `receipt_email.html` | Not referenced (dead) |
| `express/first_time_login_*.html`, `express/moveout_*.html` | Express.Core (`MemberRepository`, `UnitRepository`, `TransactionRepository`) |

---

## 7. External integrations from the CMS

### 7.1 SiteLink (SMD CCWs 3.5, `https://api.smdservers.net/CCWs_3.5/`)

Credentials: config `SiteLink:sCorpCode`, `SiteLink:sCorpUserName`, `SiteLink:sCorpPassword`, default `SiteLink:sLocationCode`, default site `SiteLink:SiteID`. Generated WCF proxies in `Connected Services/` plus one raw SOAP call. Wrapper: `Services/SiteLink/SiteLinkAPIs.cs`.

CallCenterWs operations used: `TenantListDetailed_v2` (sync, search, add member), `LedgersByTenantID`, `ChargesAndPaymentsByLedgerID`, `ChargesAllByLedgerID`, `TenantInfoByTenantID`, `TenantInvoicesByTenantID`, `UnitsInformation_v3`, `UnitsInformationByUnitID`, `PaymentsByLedgerID`, **`TenantUpdate`** (profile, web password, gate PIN), **`PaymentSimpleWithSource`** (autopay). Wrappers with no outside caller (inferred unused): `PaymentMultipleWithSource`, `PaymentSimpleWithSource` (proxy version), `TenantLogin`, `SiteInformation`, `FormsRetrieve`, `LedgerStatementByLedgerID`, `CustomerAccountsBalanceDetails`.

ReportingWs operations used: `ManagementSummary`, `MoveInsAndMoveOuts`, `Receipts`, `Discounts`, `MerchandiseSummary`, `RentalActivity`, `MarketingSummary`, `IncomeAnalysis`, `OccupancyStatistics`, `FinancialSummary` (inside `GetStorageRentalAmountvsPaymentModes`). `UnitPayments` has a wrapper but no caller (inferred unused).

🔴 **Card-carrying operation**: `PaymentSimpleWithSource` is sent as hand-built SOAP XML with `sCreditCardNumber`, `sCreditCardCVV` (123), `dExpirationDate`, `iCreditCardType`, `bTestMode=true` (`SiteLinkAPIs.cs:135-201`, card numbers chosen in `ScheduleJob.cs:2745-2766`). The numbers are public Stripe test numbers, not real cards, but the call is still a card-carrying operation, and the rebuild rule is "never call a card-carrying SiteLink operation; use `iPayMethod = 2`". 🔴 The same method **logs the full SOAP body, which contains `sCorpPassword`**, at Information level (`SiteLinkAPIs.cs:155-160`).

### 7.2 Stripe (Stripe.net 39.5, `Services/StripePayment/StripePaymentService.cs`)

APIs: `PaymentIntent` create / confirm / get, `PaymentMethod` get / create (clone to connected account), `Refund` create. Keys: platform key `Stripe:SecretKey`; per facility `master_facility.stripe_secret_key`, `stripe_publish_key`, `stripe_account` (connected account id), all AES-encrypted in the DB. No Stripe customers are created and no webhook is handled in the CMS (Express.Core `IStripeCustomerService` is registered for Express — agent C). 🔴 Each call sets the **global static** `StripeConfiguration.ApiKey` (lines 31, 48, 65, 82, 98, 111, 127), so two concurrent requests with different facility keys can use each other's key (race, inferred).

### 7.3 Other services

| Service | Config keys | Use |
|---|---|---|
| AWS S3 | `AWS:S3:AccessKey`, `AWS:S3:SecretKey`, `AWS:S3:Bucket`, `AWS:S3:Region`; public base URL `site:s3url`; Express base `Express:AWS:S3BaseUrl` | Image uploads (folders `post`, `contact`, `push`, `rewards`, `reward-category/icon`), public-read ACL |
| SendGrid | `SENDGRID:ApiKey`, `MailFrom`, `SenderName`, `ReplyTo` | All CMS email |
| AWS SES SMTP | `AWS:Email:*` | Config present; code path not used (inferred) |
| FCM legacy | `PushNotification:SenderID`, `PushNotification:ServerKey` | YES push |
| Firebase Admin | `Express:Firebase:KeyFile` (`express.firebase.{env}.json` committed) | Express push via Express.Core |
| Noke | `Noke:baseUrl`, `apiKey`, `companyId`, `hardcode`, `ConsecutiveFailedCount`, `ConsecutiveFailedInMin`, `BlockIPDurationInMin`, `TimeoutInMilliSec`, `AdminEmail` | Locks |
| UniqGift | `UniqueGift:baseURL`, `email`, `password`, `cryptoKey`, `orderNumber` (+ `authURL`, `scope`, `clientId`, `clientSecret` read by code) | Vouchers |
| WOGI | `WogiGift:baseURL`, `username`, `password` | Gift cards |
| Redis | `Redis:ConnectionString` | Cache |
| MySQL | `Database:esConnectionString`, `Database:hangfireConnection`, `Database:LogConnectionString`, `Express:ConnectionString` | DBs |
| Other app keys | `AES:*`, `Jwt:*` (unused), `site:baseurl`, `site:weburl`, `country:*`, `stripe:threeDS`, `ThirdPartyGift`, `TakeCount`, `NotAllowedUnitTypes`, `Jobs:*`, `EmailReminders:Enabled` | – |

---

## 8. Security and quality observations

Secrets and data in the repo (values not copied here):
- 🔴 `appsettings.json`, `appsettings.Development.json`, `appsettings.Staging.json`, `appsettings.Production.json` contain real-looking values for DB connection strings, AES password / salt / IV, SiteLink corporate password, Stripe secret key, SendGrid key, AWS keys, FCM server key, Noke key, UniqGift and WOGI credentials, Redis (≈19–22 non-empty secret fields per file).
- 🔴 `log4net.config:8,54,91` — DB connection strings with password.
- 🔴 `Common/LogHelper.cs:66` — a **production RDS host, user and password in a code comment**.
- 🔴 `express.firebase.production.json`, `express.firebase.staging.json` — Firebase service-account private keys.
- 🔴 `wwwroot/secure/keys/key-*.xml` — ASP.NET data-protection key files inside `wwwroot`, so `UseStaticFiles` serves them to anyone (inferred; they are not the active key ring because persistence is commented out).
- 🔴 `Services/ScheduleJob.cs:1237` — three real customer email addresses hard-coded as a tenant-sync blocklist (PII in source).

Card data:
- 🔴 SiteLink `PaymentSimpleWithSource` with card fields and test numbers (§7.1). No real PAN is handled by the CMS: cards are Stripe PaymentMethods; only brand + last 4 are stored (`payment.last_four_digits`).

Authentication and authorization:
- 🔴 `POST /account/loginold` bypasses OTP and the rate limit (`AuthenticationController.cs:95-230`).
- 🔴 Plain password inside the `otpToken` cookie scoped to the parent domain (`:252-257, 1976-1991`). OTP uses `System.Random`, no attempt counter.
- 🔴 Missing permission checks on write endpoints: YES staff create/edit (`AdminUserController.cs:107,212` → any logged-in user can create a Head Admin), every YES Create/Edit POST (contact, content, FAQ, feedback subject, notification, post, reward, reward category, tag), member update / SiteLink password change / member export (`MemberManagementController.cs:182,359,717`), Noke list / detail / history, audit-log list, CKEditor upload, legacy Ex module. In Area `express`: whole `MemberManagementController` (delete, ban, status, onboarding), manual transaction add/refund (`TransactionManagementController.cs:62-75,184-193`), insurance plan create, do-not-rent, several list endpoints.
- 🔴 Permission check is a substring match (`GeneralUtility.cs:160-161`); Dashboard permission ignores the action.
- Express area skips the per-request account check (§3.4); disabled admins keep Express access until cookie expiry.
- Noke unlock claim check is conditional on the client-sent `hwType` (`NokeManagementController.cs:102-116`).
- Refund maker and checker can be the same person; approver not limited to their facility.
- Reset-password POST does not re-check expiry (`DAL/AuthenticationDAL.cs:120-148`); reset signs in with a 10-year cookie.
- `/devices/logout` does not end the session.

CSRF:
- 🔴 99 of 107 YES write endpoints have no antiforgery token and there is no global `AutoValidateAntiforgeryToken`. Protection relies on SameSite=Lax (inferred) — weak against any same-site subdomain of `extraspaceasia.com.sg`. `/recurring-jobs/*` change state on GET.

Injection:
- 🔴 SQL injection: member list keyword and sort direction concatenated into the WHERE / ORDER BY passed to `sp_GetPagingData2` (`BL/MemberBL.cs:162-206`); `facilityId` string pasted into dashboard SQL (`DAL/DashboardDAL.cs:396, 428, 601, 628, 659, 685, 710`); `search/sortCol/sortDir` in exports (`DAL/MemberDAL.cs:741,777`, `DAL/PaymentDAL.cs:272`, `DAL/ReportDAL.cs:65,126`); push title/text in `ScheduleJob.cs:789-806`. `BaseController` builds SQL with string interpolation from claims (`BaseController.cs:46-48`, low risk because values come from the encrypted cookie).
- 76 raw-SQL call sites in total (`FromSqlRaw`, `MySqlCommand`).

XSS:
- `ViewBag.message` rendered with `Html.Raw` on ~60 views and often contains `ex.Message` (reflected XSS if an exception echoes input).
- `Views/MemberManagement/Detail.cshtml:147` renders SiteLink `CompanyName` raw (stored XSS from SiteLink data).
- Express views embed `Newtonsoft.Json.JsonConvert.SerializeObject(Model)` inside `<script>` without HTML escaping (`Areas/express/Views/MemberManagement/Details.cshtml:659`, `RentalDetails.cshtml:371`, `UnregisteredDetail.cshtml:805`, `PromoCodeManagement/*.cshtml`) — stored XSS from member-entered names (inferred).
- `XssValidationFilter` only inspects a parameter literally named `model`, only top-level properties, and HTML-encodes into the stored data; Area `express` does not use it. CSP allows `'unsafe-inline'` scripts and a plain-http staging host.

Uploads: CKEditor upload accepts any extension, stores public-read with `image/jpeg` content type, no permission check (`PostManagementController.cs:291-325`). Several Express uploads disable request size limits (`[DisableRequestSizeLimit]`, `int.MaxValue` form limits).

Money / jobs bugs (inferred from code):
- SiteLink `-14` failure keeps Stripe money without refund and marks the unit successful (`ScheduleJob.cs:2840-2878`).
- External Stripe / SiteLink calls inside a 15-minute `TransactionScope` (ReadUncommitted).
- Stripe idempotency keys are new GUIDs per attempt (no protection against re-runs or double clicks).
- Global `StripeConfiguration.ApiKey` race (§7.2).
- Tier boundary at 12 months inconsistent (§4.1).
- `ToString("#.00")` for cents; `#,##00.00` in emails prints "05.00" for small amounts.
- Production runs two Hangfire servers in one process; `TimeZoneInfo.Local` jobs depend on container TZ.
- `SendFailureNotification` recursion; receipt emails `Thread.Sleep(60000)` in the in-memory queue.

Dead code and leftovers: `JwtHandler`, `OptionsMiddleware`, `Areas/express/Controllers/DashboardController` (empty), `Views/Dev/Index.cshtml` (no controller), three `Index - Copy.cshtml` views, `invoice_pdf.html`, `receipt_email.html`, `RecurringInvoiceJob`, `WogigiftRewards` (no registration route), many unused SiteLink wrappers, `es_receipts[A4029].zip` (empty, 22 bytes), duplicate legacy Ex routes, JS calling non-existent `/express/manage-units/moveout/save`, commented-out XLSX report code.

---

## 9. Recent activity (git, `ExtraSpaceCMS/admin_cms`, since 2025-01-01)

565 commits since 2025-01-01 (authors: kyawzinhtet / kyaw zin htet ≈357, waiyanmin-codigo 204, others 4). Per month: 2025-01 95, 02 122, 03 40, 04 16, 05 43, 06 38, 07 84, 08 69, 09 21, 10 18, 11 3, 12 1; 2026-01 1, 02 11, 03 1, 08 2. The code first appears 2020-05-28.

Themes:
- **2025-01 → 2025-07: ES Express go-live work** — storage plans, promo codes, manual / offline onboarding, month-off, address edit, rental pdfs, "Tenant Async background job interval" and cron changes (2025-06-17).
- **2025-07 → 2025-10: YES dashboard rebuild** — new SiteLink sync tables and jobs, MySQL 8 fixes, voucher utilisation, PMT_Credit handling, "Internet payment only to YES", "Post → Article" rename (2025-08-14), time-zone and UTC fixes for data pulls (2025-10-03 … 10-30), "no active ledger → outstanding zero" (2025-10-17), "Manual Tenant Async removed, error log email update" (2025-09-29).
- 2025-12-19: NRIC, DOB, phone, address columns added (Express members).
- 2026-02-09 … 02-11: font changes for CMS and emails; "removed the unnecessary routes" (2026-02-11).
- 2026-03-11: "API Uniqgift prod deployment prep."
- **2026-08-02** `b451d1be`: stop action for recurring payment and tenant sync jobs.
- **2026-08-05** `cd6cc378` "disable schedule jobs": only ThreePMOfflinePayment, NinePMOfflinePayment, PointExpiryJob, UniqgiftRewards, WogigiftRewards stay enabled; reminder emails off.
- Legacy `Controllers/ExpressModule` last changed 2024-11-21; Area `express` last changed 2026-02-11.

---

## 10. Open questions

1. Which recurring jobs are registered in **production** Hangfire storage today, and when did each last run? (Needs a read of `hangfire_set` / `hangfire_hash` / `hangfire_job`; the DB MCP was down.)
2. Autopay (`RecurringPaymentJob`) is off since 2026-08-05. Who charges autopay customers now — nobody, SiteLink, or the new Node backend? Do customers know?
3. Tenant sync and SiteLink report sync are off. Is the YES dashboard expected to be stale? Does anything else keep `user_tenantsite` / `outstanding_amount` current?
4. Expired Noke guest shares are no longer removed. Is that accepted?
5. Is the legacy FCM push (YES campaigns, payment notices) still delivering anything after Google's 2024 shutdown?
6. Does SiteLink `TenantUpdate` with `sWebPassword=""` (PIN reset) clear the tenant's web password?
7. Is SiteLink's `bTestMode=true` + test card number the agreed way to post Stripe payments into SiteLink (how does accounting see these receipts)? The rebuild must use `iPayMethod = 2` instead.
8. YES refunds go to Stripe only. Who reverses the SiteLink ledger, and how?
9. Malaysia: the code has an `MY` branch (reminder days) but every committed appsettings is Singapore. Is there a separate MY deployment and config?
10. Is the legacy `ExpressModule` (`ex_*` tables, menus 19–23) still used by anyone?
11. Should `/account/loginold` exist? Is it called by anything?
12. How many CMS containers run in production (cookie / data-protection behaviour, double Hangfire servers)?
13. Do we need to keep reading old AES-encrypted columns and PBKDF2 admin hashes? If yes we need the `Codigo.Crypto` algorithm parameters (agent C: compare with Express.Core crypto source).
14. Role and Express permissions are hard-coded or DB-seeded with no editor. Should the rebuild add role management, or keep a fixed matrix? Which of the seven role names are in active use?
15. Are the committed secrets (appsettings, log4net, LogHelper comment, Firebase keys) still valid? They should be rotated before or during cutover.
