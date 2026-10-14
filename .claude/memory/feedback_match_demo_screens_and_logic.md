---
name: feedback-match-demo-screens-and-logic
description: Feature work (S1 onward) must match the demo's web pages and logic; small quality-of-life additions are allowed; read the demo when unsure
metadata:
  type: feedback
---

Owner, 2026-10-13, before starting S1 feature work: "make sure that the webpage is identical to the backend demo and add some QOL feature if you think you'll need it. The logics should be the same too. You can reference to the backend demo if you are unsure while developing."

**Why:** the goal is a functional copy of the demo ([[project-system-landscape]]); the PM and client know the demo's screens, so ours must look and behave the same.

**How to apply:**
- Admin UI pages: same screens, layout, fields, columns, filters, actions and flows as the demo's `admin-ui/` (read its React code, not only the spec). Each design spec lists the demo page it copies.
- Business logic: same results as the demo. Read the spec feature doc AND the cited TS file ([[feedback-reference-first]]).
- Quality-of-life additions are mine to propose without asking first; list each one in the design spec so the owner sees it at the design gate ([[feedback-design-gate-before-code]]).
- My interpretation (not the owner's words): "same logic" does not override the standing rules. Never copy the known demo defects (email-only login, missing ownership checks, payments trusted on the client's word, hard-coded key, billing maths in the browser), money stays exact `decimal`, no card data. Say in the spec where we differ and why.
- Demo vs client artifacts disagreements stay an open PM question; default to the demo until told otherwise.
