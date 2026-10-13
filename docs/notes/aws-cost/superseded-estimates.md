# Superseded AWS cost estimates

Moved from the decision log in `.claude/rules/cross-repo.md` on 2026-10-13. The current estimate is v4 (that log, and `aws-cost-estimate-v4.html`).

| Date | Decision | Affected clients | Decided by |
|---|---|---|---|
| 2026-10-09 | **AWS cost estimate v3 (superseded by v4): launch size US$437.36/mo** (prod $316.79 = 2 × 1 vCPU/2 GB Fargate ARM + `db.t4g.medium` Multi-AZ 20 GB; staging $120.57), **budget ceiling ≈ US$500/mo** (+15% buffer for logs, data transfer, t4g burst CPU, unmeasured BizPlus/Cowork load), **expected after 1–2 months of tuning ≈ US$270–330**. Reserve the DB only after the size settles. | none | owner |
| 2026-10-09 | **AWS cost estimate v2** (superseded by v3) (SG + MY on one platform, sized on measured usage; on-demand, before tax): ≈ **US$328/month** (prod $207.08: 2 × 0.5 vCPU/1 GB Fargate ARM, `db.t4g.small` Multi-AZ; staging $120.57); ≈ US$268 with a 1-yr RDS reservation and staging without NAT; a per-country deployment would be ≈ $535. Usage read (aggregates only, owner request) from the OLD production DBs: SG ≈ 3,630 payments, 2,850 paying members, 2,300 sign-ins, 330k SiteLink calls / month; MY ≈ 770, 490, 560, 188k; business data ≈ 1.3 GB. Superseded v1 (SG only, guessed sizing) was ≈ US$448. Prices from AWS's public price list (published 2026-09-11 … 10-08). Page for the client: https://claude.ai/artifact/C63e3WBUBYpEpPnm64cqi7 (owner must share it). | none | prepared for owner |
