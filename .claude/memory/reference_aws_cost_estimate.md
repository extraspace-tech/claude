---
name: reference-aws-cost-estimate
description: AWS cost estimate v2 (SG + MY on one platform, sized on measured old-system usage) ≈ US$328/mo, published 2026-10-09 for the client; prices from AWS's public price list.
metadata:
  type: reference
---

- **v3 (CURRENT, page version 3; owner asked for a realistic figure with headroom):**
  - Launch size **$437.36/mo**: prod $316.79 (2 × 1 vCPU / 2 GB tasks $71.96 + `db.t4g.medium` Multi-AZ $148.19; the rest as in v2); staging $120.57.
  - **Budget ceiling ≈ $500/mo**: +15% buffer for logs, data transfer, t4g burst CPU and unmeasured BizPlus/Cowork load. ≈ $5,250/yr at launch size, ≈ $6,040/yr with the buffer.
  - **Expected after 1–2 months of tuning ≈ $270–330**: −$109.71 to the v2 size, −$43.37 for staging without NAT, −$15.84 to −$31.03 for the DB reservation (reserve only after the size settles).
  - Why: launch-time risk is memory (1 GB app servers, 2 GB DB), not load.
- **v2 (superseded by v3, 2026-10-09):** SG + MY on one platform, sized on measured usage. Total **$327.65/mo** (≈ $3,932/yr):
  - Prod **$207.08**: Fargate ARM 2 × 0.5 vCPU / 1 GB $35.98, ALB $21.32, NAT $44.25, IPv4 $10.95, RDS PG `db.t4g.small` Multi-AZ $74.46, 20 GB gp3 Multi-AZ $5.52, 12 secrets $4.80, CloudWatch $8.30, ECR $0.50, SES 10k $1.00.
  - Staging $120.57, unchanged.
  - Savings: RI for `t4g.small` Multi-AZ (1 yr, no upfront, $0.0803/h) −$15.84; staging without NAT −$43.37. Both together: **$268.44**.
  - A separate deployment per country would cost $534.73.
  - Upgrade to `t4g.medium` +$73.73; an extra 0.5 / 1 task +$17.99.
- **Measured usage**: aggregate reads from the old production DBs on 2026-10-09. `mysql-dev` = SG prod, `mysql-prod-my` = MY prod.
  - SG (Oct 2025 – Jul 2026 average; payments fell from Aug 2026 when autopay was switched off): 3,630 payments, 2,850 paying members, 2,300 sign-ins and 330k SiteLink calls per month; peak hour 9,772 calls; 9,097 members; 1.2 GB business data.
  - MY (12-month average): 770 payments, 490 paying members, 560 sign-ins and 188k SiteLink calls per month; peak hour 4,080 calls; 1,712 members; 0.13 GB.
- v1 below (SG only, guessed sizing, $448) is SUPERSEDED.
- Page: https://claude.ai/artifact/C63e3WBUBYpEpPnm64cqi7 (now on version 2). Sharing: the owner has shared it with specific people (status at v2); sharing is changed only from the page's Share menu. Its source HTML was in the session scratchpad, which is temporary.
- **v1 totals (SUPERSEDED)** (USD/month, on-demand, before GST, `ap-southeast-1`, 730 h):

  | Environment | Sizing | Total |
  |---|---|---|
  | **Production** | Fargate ARM 2 × 1 vCPU / 2 GB, ALB, 1 NAT, 3 IPv4, RDS PG `db.t4g.medium` Multi-AZ + 50 GB gp3, Secrets, CloudWatch, ECR, SES | **$327.79** |
  | **Staging** | 1 × 0.5 vCPU / 1 GB, ALB, NAT, `db.t4g.micro` Single-AZ | **$120.57** |
  | **Sum** | | **$448.36** (≈ $5,380/yr) |

- Levers:
  - 1-yr no-upfront RDS RI: −$31.03.
  - Staging without NAT: −$43.37. These two together bring the total to ≈ $374.
  - Production on `db.t4g.small`: −$73.73. All three together bring the total to ≈ $300.
- Later costs:
  - extra app task: +$35.98 each
  - ElastiCache Valkey `cache.t4g.micro`: $14.02 for 1 node, $28.03 for 2
  - `db.m7g.large` Multi-AZ: $341.64
- Unit prices read from `pricing.us-east-1.amazonaws.com/offers/v1.0/aws/<Service>/current/ap-southeast-1/index.json`, versions published 2026-09-11 … 10-08:
  - Fargate ARM: vCPU $0.04045/h, GB $0.00442/h
  - ALB: $0.0252/h, LCU $0.008
  - NAT gateway: $0.059/h and $0.059/GB. It is in the AmazonEC2 file (354 MB). In that file the `sku` line comes BEFORE `usagetype`, so search with `grep -B`.
  - IPv4: $0.005/h
  - RDS PG `t4g.medium` Multi-AZ: $0.203/h, RI $0.1605/h
  - gp3 storage: $0.138 Single-AZ, $0.276 Multi-AZ
  - Secrets Manager: $0.40 per secret
  - CloudWatch Logs: $0.70/GB ingested
  - SES: $0.0001 per recipient
- Not verified: real traffic, internet data transfer, Savings Plan rates, GST, and whether Microsoft 365 needs an extra licence for SSO.

Source of the client page (v3) is saved at `docs/notes/aws-cost/aws-cost-estimate-v3.html`; republish from it with `Artifact` `url` = the page link.
