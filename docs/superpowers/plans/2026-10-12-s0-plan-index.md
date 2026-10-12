# S0 Foundation — plan index

The S0 spec (`docs/superpowers/specs/2026-10-09-s0-foundation-design.md`, approved 2026-10-12) covers six separate subsystems. Each one gets its own plan, and each plan ends with software that builds, passes its tests and can be checked on its own. One plan holding all six would be thousands of lines that no implementer can keep in mind at once.

| Plan | Delivers | Depends on | Can run in parallel with | Status |
|---|---|---|---|---|
| **S0-1** Repo skeleton + AWS network and database | Solution layout, build settings, CDK app with `EsNetwork-<env>` and `EsData-<env>` stacks (VPC, NAT, RDS PostgreSQL 18, bastion, DB secrets, RDS Proxy in production), infra tests. **Staging network + database deployed**, DB users created. | — | — | **written**: `2026-10-12-s0-1-network-database.md` |
| S0-2 API platform | `ExtraSpace.Api` host, error format, pipeline, logging and tracing (§4.4), app-version check, health, OpenAPI, `ExtraSpace.Engines` (Money), `AppDbContext` + conventions + interceptors, architecture test, `docker-compose.yml` (PostgreSQL + Seq), test harness (WebApplicationFactory + Testcontainers) | S0-1 (skeleton files only) | S0-6 infra part | to write next |
| S0-3 Customer identity + jobs + email | `customer*` tables, code flow, JWT + refresh rotation, `/me`, rate limits, Hangfire with roles and job tracing, SES sender + `login-code` template, `IdentityHousekeeping` | S0-2 | S0-4, S0-5 | after S0-2 |
| S0-4 Admin back end | Entra SSO, cookie, CSRF, RBAC, audit filter, staff / roles / audit / permissions endpoints, Hangfire dashboard auth, `xmin` 409 | S0-2 | S0-3, S0-5 | after S0-2 |
| S0-5 Admin UI shell | React 19 + Vite app, layout, Staff / Roles / Audit screens, generated API types | S0-4 contract (OpenAPI) | S0-3 | after S0-4's contract is fixed |
| S0-6 Delivery | Dockerfile, ECR, `EsEdge-<env>` (Route 53, ACM, SES domain), `EsApp-<env>` (ALB, WAF, ECS api/jobs, log groups, saved queries, alarms), `EsCi` (GitHub OIDC roles), GitHub workflows, secret scan; staging deploy and the §11 walk | S0-1; the app parts need S0-2…S0-5 | S0-2…S0-5 for the infra code | after S0-1 |

Rules for every S0 plan (from the workspace rules):

- Code goes to `../CMS`. Implementers are Opus `implementer` subagents; the main session reviews the real diff and gives a verdict per piece.
- **Nobody commits or pushes.** Each task ends with "hand-off": the owner commits. Work happens on a branch per plan (`s0-1-network-database`, …).
- 🔴 `extraspace-tech/cms` is public: no secret, connection string, account id or customer data in any file. Do not push until the repo is private (open item 5), or confirm with the owner.
- AWS changes in the client account `110611798568` run only from the main session, only after the owner's OK, and never touch the client's existing Lambdas and buckets. Production data rules from `.claude/CLAUDE.md` §6 apply.
