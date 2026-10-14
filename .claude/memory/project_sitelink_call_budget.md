---
name: project-sitelink-call-budget
description: SiteLink complained about the old app's daily call volume; S1 must keep SiteLink calls low (no bulk per-customer sync jobs)
metadata:
  type: project
---

SiteLink complained about the huge daily number of API calls when the old YES app synced every day (owner, 2026-10-14). The old app then ran its `TenantAsync` job once a month and triggered it by hand when a customer complained.

Cause (read 2026-10-14, `ExtraSpaceCMS/admin_cms/Services/ScheduleJob.cs:1576-1713`): the job loops over **every member** and calls `TenantListDetailed_v2` per member, `LedgersByTenantID` per tenant, `UnitsInformationByUnitID` **per unit** and `TenantInfoByTenantID` — calls grow with members × units. The per-site `UnitsInformationAsync` job (`:3459`) is one call per site and was never the problem.

**Why:** a design that polls SiteLink per customer or every few minutes will draw the same complaint and may get our login throttled.

**How to apply:** S1 refreshes per-customer data only on demand (sign-in, opening My Spaces / Bills with a staleness window, rate-limited pull-to-refresh, right before a payment) and per-site unit data at most nightly + on demand; no scheduled bulk tenant sync (manual, throttled admin action only); a client-side rate limiter and a daily call counter. See [[project-setup-owed]] and `docs/notes/s1-research/s1-design-draft.md` §3.
