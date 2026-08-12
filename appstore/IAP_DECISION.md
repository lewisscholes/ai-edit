# In-app purchase: what the rules actually say

Researched 12 Aug 2026 as requested in HANDOFF 3 §7.3. Sources at the bottom.
**This is a commercial decision for Lewis. Below is the factual position, not a recommendation.**

---

## The default rule — 3.1.1

Digital content or functionality unlocked inside an iOS app must be sold through
Apple's In-App Purchase. Commission is **30%**, or **15%** under the Small Business
Program, which Chop qualifies for while under $1M/year.

At 60–85p a credit, 15% is 9–13p per video off the top.

## The route that fits Chop — 3.1.3(b), multiplatform services

Chop is genuinely multiplatform: the web app exists, works, and already sells credits
through Stripe. The guideline permits users to **access content they bought elsewhere**
inside the iOS app.

**The condition that matters:** the same content must *also* be purchasable via IAP
inside the app. It is not an opt-out — it is "offer both". You may not steer iOS users
away from IAP, and general messaging must not discourage it.

## What changed, and where

**United States storefront:** following the Epic litigation, Apple updated the
guidelines in 2025. Apps on the US storefront **no longer need the External Link
Account entitlement** to include buttons, external links or calls to action pointing
at outside purchasing. This is a genuine, current relaxation.

**European Union:** external purchase links are permitted under an entitlement, with
a Core Technology Commission of 5% on digital goods promoted in-app from June 2025.
You cannot offer both Apple IAP and external payment in the same EU app — it is one
or the other.

**United Kingdom:** currently the standard 15–30%. UK developers are expected to gain
a legal right to steer users to external payment within roughly 12 months under the
CMA's regime, mirroring the EU. **Not yet in force.**

## What this means in practice

Three viable shapes, in increasing order of risk:

**A — No purchases in the app at all.** Credits bought on chopedit.com, consumed
everywhere. Simplest, fastest to approve, zero commission. The risk is 3.1.1: an app
that unlocks paid functionality while offering no way to buy it can attract scrutiny.
3.1.3(b) is the defence, and it is a real one, but it is cleanest when you *also* sell
via IAP.

**B — IAP alongside web purchase.** Squarely inside 3.1.3(b). Costs 15% only on
purchases that actually happen through Apple. Most creators who already have an
account will keep buying on the web. Safest path to approval.

**C — IAP plus an external link.** Legal on the US storefront today. Not yet in the UK.
Adds StoreKit work plus per-storefront conditional logic.

## Practical note on timing

**B and C both require the Paid Applications agreement** — banking details, tax forms,
and Apple's approval — before any IAP product can be created or tested. That is days,
not hours. **A requires none of it.**

If the goal is to get something in review quickly, shipping v1 as A and adding IAP in
1.1 is the pragmatic sequence. It also means the first submission has fewer moving
parts to be rejected over.

## Sources
- App Review Guidelines — https://developer.apple.com/app-store/review/guidelines/
- Guideline updates (US anti-steering) — https://developer.apple.com/news/?id=xqk627qu
- EU DMA terms — https://developer.apple.com/support/dma-and-apps-in-the-eu/
