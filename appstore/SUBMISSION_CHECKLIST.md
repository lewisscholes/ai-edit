# Chop — App Store submission checklist

Tick down. Blockers are marked.

## Blockers — nothing works until these are true
- [ ] **Apple Developer Program enrolled and approved** (£79/yr, Individual not Organisation). Unknown wait, entirely Apple's call.
- [ ] **Privacy policy live at a public URL.** `appstore/privacy.html` is written — copy it to the repo root as `privacy.html`, push, and confirm `https://chopedit.com/privacy.html` loads.
- [ ] **App name confirmed free** on the App Store. "Chop" alone is almost certainly taken.
- [ ] **Xcode installed** (26.6 release, Apple Silicon).

## Backend still to deploy
- [ ] Run `supabase-functions/03-account-deletion.sql` in the SQL editor
- [ ] Deploy `chop-delete-account` edge function, Verify JWT **ON**
- [ ] Test deletion end to end on a throwaway account — Apple will check this

## Assets
- [ ] App icon 1024×1024 PNG, no alpha, no rounded corners (export from `chop-icon.svg`)
- [ ] 3–5 screenshots at 6.9" iPhone (1320×2868), real content not placeholders
- [ ] Optional: 6.5" set if you want older device coverage

## App Store Connect
- [ ] Create app record, bundle ID `com.chopedit.app`
- [ ] Paste metadata from `APP_STORE_METADATA.md`
- [ ] Privacy nutrition labels from `PRIVACY_LABELS.md`
- [ ] Age rating: 4+, all content questions "None"
- [ ] Category: Photo & Video / Productivity
- [ ] Export compliance: HTTPS only, exemption applies
- [ ] **Demo account created with credits loaded**, details in the review notes

## Build — NATIVE, not a wrapper
Capacitor is out. See `WITHDRAWN-capacitor.md`. The iOS editor is a real Swift app
using `AVMutableComposition`. HANDOFF 3 §5 has the reasoning and §7.2 the build order.

- [ ] **Run the POC first** — `~/Desktop/ChopNativeVideoPOC/README-RUN-ME.md` on Lewis's
      Mac. ~15 min. It confirms the assumption the whole plan rests on and nobody has
      run it yet. Highest value per minute of anything on this list.
- [ ] Phase 2: native editor core — player, timeline, scrub, cuts, filmstrip
- [ ] Phase 3: wire to the existing backend (Supabase, R2, Deepgram, Modal — no rewrite)
- [ ] Phase 4: on-device export via `AVAssetExportSession`
- [ ] Phase 5: TestFlight with real affiliates
- [ ] Phase 6: submit

## Decide before building
- [ ] **IAP question** — see `IAP_DECISION.md`. Affects pricing, sign-up flow and
      whether you need the Paid Applications agreement (which takes days).

## Known rejection risks
- Demo account missing — most common first rejection
- Privacy label mismatch
- Vague Info.plist usage strings
- Account deletion — **already built**, backend path `chop-delete-account` is reusable

## Still worth knowing
- Review is typically 24–48h but a first submission often takes longer
- Rejections are normal. Read the reason, fix, resubmit — usually same-day turnaround after the first.
