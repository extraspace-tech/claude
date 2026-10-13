# S0-4b Staff sign-in by email code (replaces Entra) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Implementer = Opus `implementer`, reviewer = Opus `code-reviewer`; Task 3 is run by the main session. Agents never commit (memory `feedback-sdd-without-commits`).

**Why:** PM, 2026-10-13: no Microsoft Entra. Admin staff sign in with their email + a one-time code sent by email (owner confirmed "OTP means email"). S0-4 was committed and pushed to `main` as `6a8a16e` on 2026-10-13, so this plan removes the Entra code in a follow-up change.

**Goal:** `POST /admin/api/auth/code` + `POST /admin/api/auth/code/verify` sign a staff member in and set the same admin cookie as before. Everything else of S0-4 stays: cookie, CSRF, permissions, audit, Owner rules, staff / roles / audit endpoints, dashboard, SSM key ring.

**Architecture:**
- `Features/Identity` already owns the code machinery (`LoginCodeService`, `LoginCodeHasher`, table `customer_login_code`). It is generalised **once**: the table becomes `login_code` with a `purpose` column (`Customer` / `Staff`), and Identity exposes `Contracts/ILoginCodes`. Customer sign-in keeps its behaviour and its tests.
- `Features/Admin` uses `ILoginCodes` (allowed: another feature's `Contracts/`), keeps `StaffSignIn` (now by email only) and drops every Entra piece.

**Spec:** S0 spec §6.1 (code rules, reused verbatim), §6.2 (replaced by this plan), `docs/superpowers/plans/2026-10-13-s0-4-admin-backend.md` (decisions 4–7, 9–17 stand; 2, 3, 8 are superseded), `docs/notes/cms/built-so-far.md`, ledger `.superpowers/sdd/2026-10-13-s0-4-admin-backend/progress.md`.

**Clients affected:**
- **Admin UI (S0-5):** a login screen (email, then code) instead of a redirect; on 401 show that screen. No `/auth/login`.
- **Flutter:** none (customer routes, statuses and limits unchanged).
- **S0-6:** no Entra settings or secret; staff codes need the SES sender like customer codes. **Client IT:** no Entra app registration.

## Global Constraints

All Global Constraints of the S0-4 plan apply (repo `../CMS`, **branch `s0-4b-staff-email-code` cut from `main` at `6a8a16e`** — the only git write allowed is that `git switch -c` in Task 1 — no other git writes, no secrets, no network in tests, no `.md` in CMS, LF, `public` request DTOs, never weaken a test, Owners collection rule). In addition:

- **Local database only:** this plan allows `dotnet ef database update <migration> --project src/ExtraSpace.Api --connection "Host=localhost;Port=5433;Database=extraspace;Username=postgres"` against the local Docker database (it already has `AdminTables` applied; only ever update forward to the new migration). Never any other database. No `docker compose`, no user-secrets, no AWS.
- **Spec values stay (§6.1):** 6 digits, valid 10 minutes, 5 attempts, one send per email per 60 s and 5 per hour, per IP 20 code requests and 30 checks per hour.
- 🔴 Never log a code, a cookie, a CSRF token or an unmasked email.

## Review Focus

1. 🔴 **Cross-purpose codes.** A code requested through `/api/v1/auth/code` for an address must never verify on `/admin/api/auth/code/verify` for the same address, and the reverse. Expected: 400 `INVALID_CODE`. Pinned by Task 2 `A_customer_code_does_not_sign_in_staff` and Task 1 `A_staff_code_does_not_sign_in_a_customer`.
2. **Probing for staff addresses.** `POST /admin/api/auth/code` must answer 202 for every valid email and send mail only to an active staff member (or a bootstrap address while no Owner exists). Pinned by `An_unknown_email_gets_202_and_no_email`.
3. **A staff member deactivated between code request and verify** must not sign in. Pinned by `A_staff_member_deactivated_after_the_code_was_sent_is_refused`.
4. **Customer flow unchanged.** Every existing S0-3 test passes without edits to its assertions (table/entity renames in test helpers only).
5. **No Entra left:** no `OpenIdConnect` reference, package, setting, test helper or log override anywhere.

## Decisions (owner to confirm with the plan)

1. **One code engine, in Identity, with a purpose.** `customer_login_code` → `login_code`; new column `purpose text` (`Customer` | `Staff`); unique index `(purpose, email)` replaces the unique `email`. The hash covers the purpose (`purpose:email:code`) and the advisory lock is `login-code:<purpose>:<email>`, so a customer code and a staff code for one address are separate rows that cannot stand in for each other.
2. **Contract** (`Features/Identity/Contracts/LoginCodes.cs`):

   ```csharp
   public enum LoginCodePurpose { Customer, Staff }

   public interface ILoginCodes
   {
       /// <summary>Creates a code and queues its email, or throws 429 RATE_LIMITED (per-email limits, S0 spec §6.1).</summary>
       Task SendAsync(LoginCodePurpose purpose, string email, string? ip, CancellationToken cancellationToken);

       /// <summary>
       /// Checks the code. A wrong code counts an attempt and throws 400 INVALID_CODE / TOO_MANY_ATTEMPTS. On a match it marks
       /// the code used and runs <paramref name="onVerified"/> in the SAME transaction; if that throws, the code stays unused.
       /// </summary>
       Task<T> VerifyAsync<T>(LoginCodePurpose purpose, string email, string code,
           Func<CancellationToken, Task<T>> onVerified, CancellationToken cancellationToken);
   }
   ```

   The customer flow passes "find or create the customer, start the session" as `onVerified`, so it stays one transaction as in S0-3.
3. **Staff routes** (anonymous, on the `/admin/api/auth` group):
   - `POST /code { email }` → always **202**. Per-IP limit 20/hour. An email is sent only when the address is an active staff member, or a bootstrap address while no active Owner exists. For any other address nothing is stored and nothing is sent.
   - `POST /code/verify { email, code }` → **204** + the admin cookie. Per-IP limit 30/hour. Errors as for customers: 400 `INVALID_CODE` / `TOO_MANY_ATTEMPTS` / `VALIDATION_FAILED`, 429 `RATE_LIMITED`. A person who may no longer sign in → 403 `FORBIDDEN` (the code stays unused).
   - `GET /auth/login`, the callback, `ADMIN_SIGNIN_UNAVAILABLE` and the Production "Entra settings" start-up check are removed.
4. **`StaffSignIn.ResolveAsync(email, cancellationToken)`**: by email only; `entra_object_id` is dropped from `staff_user`. It joins the caller's transaction when there is one. Bootstrap rule unchanged (only while no active Owner exists, under the `staff-owners` lock).
5. **Display name.** Entra supplied it; now the admin types it: optional `displayName` (max 200) on `POST /staff` and `PATCH /staff/{id}`.
6. **Company-domain limit (recommended, new):** setting `Admin:AllowedEmailDomains` (list; empty = any). When set, adding staff with another domain → 400 `VALIDATION_FAILED`, and such an address never gets a code (bootstrap included). With email codes the admin is as safe as the staff mailbox; this keeps personal mailboxes out. S0-6 sets it to the client's domain.
7. **dev-login is removed** (changes S0-4 decision 9). In Development the code is printed in the console (`Email:Transport=Log`), so local work signs in the real way and one risky route disappears. Tests keep the test-only sign-in route and read codes from `FakeEmailTransport`. Development cookie names (`es-admin` / `es-csrf`, plain http) stay.
8. **Same email template** `login-code` for both purposes.
9. **One new migration `StaffEmailCode`** on top of the committed `AdminTables` (never rewrite a pushed migration): rename `customer_login_code` → `login_code`, add `purpose`, swap the unique index, drop `staff_user.entra_object_id` and its index. Task 1 creates it; Task 2 extends it (remove + re-add is allowed only for this uncommitted migration).
10. **Login CSRF** (an attacker signing a victim's browser into the attacker's staff account) is accepted: it needs a valid code for a staff account, the cookie is `SameSite=Lax`, and the routes take JSON only.

---

### Task 1: One code engine with a purpose (Identity)

**Files:**
- Create: `src/ExtraSpace.Api/Features/Identity/Contracts/LoginCodes.cs` (decision 2)
- Rename/modify: `CustomerLoginCode.cs` → `LoginCode.cs` (entity `LoginCode`, + `LoginCodePurpose Purpose`), `IdentityEntityConfigurations.cs` (table `login_code`, `Purpose` `.HasConversion<string>()` max 20, unique `(Purpose, Email)`, index `ExpiresAt`), `LoginCodeHasher.cs` (`Hash(purpose, email, code)` / `Matches(...)`), `LoginCodeService.cs`, `IdentityEndpoints.cs`, `CustomerAuth.cs` (register `ILoginCodes`), `IdentityHousekeepingJob.cs` (entity rename only)
- Create: migration `StaffEmailCode` (Task 2 extends it with the `entra_object_id` drop)
- Tests: existing Identity tests (renames in helpers only); new facts in `tests/ExtraSpace.Api.Tests/Features/Identity/LoginCodeTests.cs`

**Steps:**
- [ ] `LoginCodeService` implements `ILoginCodes`:
  - `SendAsync` = today's `RequestAsync` with `purpose` in the lock key, the row lookup and the hash. Keep the limit maths and the "one 429 with the longer wait" rule exactly.
  - `VerifyAsync<T>` = today's first half of `VerifyAsync` (lock, `FOR UPDATE` read by purpose + email, expiry / consumed / attempts checks, wrong code → count, **commit**, throw). On a match: `row.ConsumedAt = now`, `var result = await onVerified(ct)`, `SaveChangesAsync`, `CommitAsync`, return. Every success path commits; the wrong-code path commits before it throws (engineering checklist §2).
  - The customer part moves to a small method used by the endpoint: `VerifyCustomerAsync(email, code, ip, userAgent)` = `VerifyAsync(Customer, …, onVerified: find-or-create customer + tokens.StartSession)`. Log lines `Customer {customerId} created / signed in` stay, after the commit. `Login code {codeId} requested for {email}` gains `{purpose}`.
  - The raw SQL reads become `SELECT * FROM login_code WHERE purpose = {purpose text} AND email = {address} FOR UPDATE`.
- [ ] First step of the task: `git status --short` must be empty and HEAD `6a8a16e`; then `git switch -c s0-4b-staff-email-code`.
- [ ] `dotnet ef migrations add StaffEmailCode --project src/ExtraSpace.Api --output-dir Platform/Data/Migrations`: rename the table, add `purpose` (existing rows → `Customer`), swap the unique index. Strip the BOM.
- [ ] New tests in `LoginCodeTests`:
  - `A_staff_code_does_not_sign_in_a_customer`: `ILoginCodes.SendAsync(Staff, email)`, read the code from the fake transport, `POST /api/v1/auth/code/verify` → 400 `INVALID_CODE`.
  - `One_address_can_hold_a_customer_code_and_a_staff_code`: both rows exist; each verifies only for its purpose.
  - `A_failed_onVerified_leaves_the_code_unused`: `VerifyAsync` with a callback that throws → the same code verifies afterwards.
- [ ] `dotnet build src/ExtraSpace.Api/ExtraSpace.Api.csproj` (0 warnings) and the full `dotnet test tests/ExtraSpace.Api.Tests`. Every S0-3 test must pass with unchanged assertions; if one needs a changed assertion, stop and report.

---

### Task 2: Staff code sign-in; remove Entra and dev-login (Admin)

**Files:**
- Modify: `Features/Admin/StaffAuth.cs` (remove the OIDC scheme, both OIDC event handlers, the redaction regex, the Production check, the Entra constants; add rate-limit policies `admin-auth-code` 20/h and `admin-auth-verify` 30/h per IP, same partition key as `CustomerAuth`), `AdminOptions.cs` (remove `EntraOptions`; add `AllowedEmailDomains`), `StaffSignIn.cs`, `AdminEndpoints.cs`, `AdminDtos.cs`, `AdminErrors.cs` (remove `SignInUnavailable`), `StaffService.cs` (display name, domain check), `StaffUser.cs` + `AdminEntityConfigurations.cs` (drop `EntraObjectId`), `AdminSetup.cs`
- Modify: `appsettings.json` (remove `Admin:Entra` and the `OpenIdConnect` Serilog override; add `"AllowedEmailDomains": []`), `ExtraSpace.Api.csproj` + `Directory.Packages.props` (remove `Microsoft.AspNetCore.Authentication.OpenIdConnect`)
- Migrations: extend the uncommitted `StaffEmailCode` (step below); never touch `AdminTables`
- Tests: delete `StaffAuthEventsTests.cs`, `DevLoginTests.cs`, the Entra tests in `AdminLoginTests.cs`, `UseTestEntra` (and its use in `ApiDocsTests`); rewrite `StaffSignInTests.cs`; new `StaffCodeSignInTests.cs`; adjust `AdminAuthTests` (the 503 test goes), `StaffEndpointsTests` (display name, domain)

**Steps:**
- [ ] `StaffSignIn`:
  - `Task<bool> MaySignInAsync(string email, ct)`: domain allowed AND (active staff row, OR bootstrap address with no staff row while no active Owner exists). No lock, no writes.
  - `Task<Guid?> ResolveAsync(string email, ct)`: today's logic without `objectId` / `name`; domain check first; uses `db.Database.CurrentTransaction` when present, else begins and commits its own. Bootstrap under `StaffLocks.OwnersAsync`. Keep the three log lines (masked email only).
- [ ] Endpoints (`/admin/api/auth`, both `.AllowAnonymous()`, cast rule ASP0016 kept in mind):

  ```csharp
  private static async Task<Accepted> RequestCode(StaffCodeBody body, HttpContext http, StaffSignIn signIn, ILoginCodes codes, CancellationToken cancellationToken)
  {
      var email = body.Email!.Trim().ToLowerInvariant();
      if (await signIn.MaySignInAsync(email, cancellationToken))
          await codes.SendAsync(LoginCodePurpose.Staff, email, http.Connection.RemoteIpAddress?.ToString(), cancellationToken);
      return TypedResults.Accepted((string?)null);
  }

  private static async Task<NoContent> VerifyCode(StaffVerifyBody body, HttpContext http, StaffSignIn signIn, ILoginCodes codes, CancellationToken cancellationToken)
  {
      var email = body.Email!.Trim().ToLowerInvariant();
      var staffId = await codes.VerifyAsync(LoginCodePurpose.Staff, email, body.Code!,
          async ct => await signIn.ResolveAsync(email, ct) ?? throw AdminErrors.NoAccess(), cancellationToken);
      await http.SignInAsync(StaffAuth.CookieScheme, StaffAuth.PrincipalFor(staffId));
      return TypedResults.NoContent();
  }
  ```

  A per-email 429 from `SendAsync` is returned as is (it can only happen for a real staff address; accepted: the 60 s gap already tells nothing an attacker could use beyond "a code was requested"). Report it if you see a cheap way to keep even that silent without hiding real limits from staff.
  - Bodies (`public`): `StaffCodeBody { [Required, EmailAddress, MaxLength(254)] Email }`, `StaffVerifyBody { Email; [Required, RegularExpression("^[0-9]{6}$")] Code }`.
  - Remove `Login`, `DevLogin`, `DevLoginBody`, the `IHostEnvironment` parameter of `MapAdminEndpoints` if it is no longer used (then fix `Program.cs`).
- [ ] `StaffService`: `AddStaffBody.DisplayName` / `UpdateStaffBody.DisplayName` (`[MaxLength(200)]`, trimmed, empty → null on add; on PATCH null = unchanged); domain check on add → `AdminErrors.Invalid("This email domain is not allowed.")`. Audit rows record `displayName` like any field.
- [ ] Migration: if Task 1's `StaffEmailCode` was applied to the local database, first `dotnet ef database update AdminTables --connection "<local>"`; then `dotnet ef migrations remove` (removes only `StaffEmailCode`; `AdminTables` must stay byte-identical — check with `git diff --stat -- '*AdminTables*'`, empty), `dotnet ef migrations add StaffEmailCode …`; check the script (`dotnet ef migrations script AdminTables StaffEmailCode`): `customer_login_code` renamed to `login_code` (data kept, existing rows `Customer`), unique `(purpose, email)`, `entra_object_id` and its index dropped, nothing else. Strip the BOM. `dotnet ef database update --connection "<local>"`.
- [ ] Tests (each required):
  - `StaffCodeSignInTests`: `A_staff_member_signs_in_with_an_emailed_code` (202 → code from `api.Emails` → 204 → `/me` 200, cookie attributes as before); `An_unknown_email_gets_202_and_no_email` (no email, no `login_code` row); `An_inactive_staff_member_gets_202_and_no_email`; `A_customer_code_does_not_sign_in_staff` (customer route sends the code for a staff address → admin verify 400 `INVALID_CODE`); `A_wrong_code_five_times_locks_the_code`; `A_staff_member_deactivated_after_the_code_was_sent_is_refused` (403, then reactivated → the same code still works); `A_bootstrap_address_becomes_owner_at_first_sign_in` and `Bootstrap_gets_no_code_once_an_owner_exists` (collection `Owners`); `A_disallowed_domain_gets_no_code` (own host with `Admin:AllowedEmailDomains:0=example.test`, role `Api`); `Sign_in_writes_no_audit_row`; `The_sign_in_flow_logs_no_code_cookie_or_raw_email`.
  - `StaffSignInTests`: unknown, inactive, bootstrap yes/no, last sign-in recorded, masked refusal line, disallowed domain.
  - `StaffEndpointsTests`: display name on add and patch (audited), disallowed domain → 400.
  - `AdminAuthTests`: a 401 test that `/admin/api/auth/login` no longer exists (404).
- [ ] `grep -ri "entra\|openidconnect\|dev-login\|DevLogin" src tests` → the only hits allowed are `entra_object_id` in the committed `AdminTables` migration and in `StaffEmailCode` (the drop) and the model snapshot must have none. Report the output.
- [ ] `dotnet build ExtraSpace.slnx` (0 warnings, 0 errors); `dotnet test tests/ExtraSpace.Api.Tests`.

---

### Task 3: Review, walk, script, docs (main session)

- [ ] Code review (Opus `code-reviewer`) of Tasks 1–2 against the Review Focus; read the full diff of `LoginCodeService`, `StaffSignIn` and the two endpoints yourself.
- [ ] Local walk (`dev-walker`, Development, code read from the app console): request code → verify → `/me`; unknown email 202 with no console email; wrong code; role + staff write with CSRF; audit; dashboard; logout. Also one customer sign-in (`/api/v1/auth/code` → verify → `/me`) to prove S0-3 still works. Kill the app.
- [ ] New script `docs/migrations/2026-10-13-staff-email-code.sql` (`dotnet ef migrations script AdminTables StaffEmailCode --idempotent`, BOM stripped); `2026-10-13-admin-tables.sql` stays and runs before it.
- [ ] Docs: S0 spec §5.1 (`login_code`, `staff_user` without `entra_object_id`), §6.1 "As built" (engine + purpose), §6.2 rewritten for email codes, §12 item 2 closed; `built-so-far.md` S0-3 and S0-4 sections; guide §7; plan index (S0-4 row, S0-5 / S0-6 carry-overs: login screen, no Entra settings, `Admin__AllowedEmailDomains__0`); `.claude/rules/cms.md` and `.claude/CLAUDE.md` where they name Entra; `cross-repo.md` decision line with the as-built facts; memory.
- [ ] Verdict per task, counts, commit message (owner commits).
