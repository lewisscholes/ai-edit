# Web → SwiftUI mapping (verbatim from source)

Every string below is copied out of `index.html` (landing) or `app/index.html`
(the app). Nothing here is written by me. If a string isn't in this file, it
doesn't go in the app.

---

## 1. Landing — `index.html` → `ChopLandingView`

| Element | Exact web copy |
|---|---|
| Nav brand | `Chop` |
| Nav links | `Features` · `Pricing` · `FAQ` |
| Nav CTA | `Start chopping` |
| Eyebrow | `Built for TikTok Shop affiliates` |
| Headline line 1 | `Don't edit,` |
| Headline line 2 (gradient italic) | `just film.` |
| Sub | `Chop cuts the dead air, filler words and messed-up takes out of your talking-head videos — automatically. Film once, review in seconds, post everywhere.` |
| Primary CTA | `Chop your first video free` |
| Secondary CTA | `See how it works` |
| Under CTAs | `3 free videos · no card · works on your phone` |
| Section 2 eyebrow | `The transform` |
| Section 2 heading | `Watch a video chop itself.` |
| Section 2 sub | `One upload in, one clean cut out — no timeline scrubbing, no scissor work.` |
| Section 3 eyebrow | `What it does` |
| Section 3 heading | `More videos posted. Zero evenings lost.` |
| Section 3 sub | `The three things that used to eat your editing time — handled.` |
| Feature 01 label | `01 / ONE UPLOAD` |
| Feature 01 title | `Dead air, gone before you've made a brew` |
| Feature 01 body | `Drop in raw footage and Chop strips every awkward pause and filler word automatically. You just watch the runtime fall.` |

**Note:** the landing has an animated hero mock (Raw/Edited pill, toolbar
`Retakes · Cuts · Script · Text · Image · Caps`, a retake card reading
`Retake 1 · 88% match` / `Keeping Take 2`, and a marquee of
`✂ um removed`, `✂ 2.4s silence cut`, `✓ retake matched`, `▶ 1080p export`,
`✂ uhh removed`, `✓ AI picked the better take`, `✂ 1.8s pause cut`,
`▶ posted to TikTok`).

## 2. Auth — `viewAuth` → `ChopAuthView`

| Element | Exact web copy |
|---|---|
| Title (initial) | `Welcome to Chop` |
| Title (sign in) | `Welcome back` |
| Title (sign up) | `Create your account` |
| Title (reset) | `Reset your password` |
| Title (new password) | `Choose a new password` |
| Sub (sign in) | `Sign in to keep chopping.` |
| Sub (sign up) | `Three free videos are waiting.` |
| Sub (reset) | `We'll email you a link to set a new one.` |
| Sub (new password) | `Enter a new password for your account.` |
| Tabs | `Sign in` · `Create account` |
| Field labels | `Email` · `Password` · `New password` |
| Placeholders | `you@example.com` · `••••••••` |
| Button (sign in) | `Sign in` |
| Button (sign up) | `Create account` |
| Button (reset) | `Send reset link` |
| Button (new password) | `Save new password` |
| Link | `Forgot your password?` |
| Link | `Back to sign in` |
| Badge | `✦ New accounts get 3 free videos` |
| Side panel heading | `Post more.` / `Edit nothing.` |
| Side bullet 1 | `Dead air, filler words and retakes cut automatically — in seconds` |
| Side bullet 2 | `Retakes shown side by side — nothing is ever deleted without you` |
| Side bullet 3 | `Renders on your device — post straight to TikTok, Reels or Shorts` |
| Side bullet 4 | `Start with 3 free videos — no card, no subscription` |

**Flow:** one screen, two tabs. Reset and new-password are modes of the same
screen, not separate screens.

## 3. Dashboard — `viewHome` → `ChopDashboardView`

| Element | Exact web copy |
|---|---|
| Title (no profile) | `Dashboard` |
| Title (with profile) | `Hey {firstName}, let's chop 👋` |
| Sub | `An overview of how your chopping is going.` |
| Card 1 label | `Time saved editing` |
| Card 2 label | `Videos edited` |
| Card 3 label | `Saved vs. manual editing` + sub `at $30/h` |
| Card 4 label | `Day streak` |
| Drop zone heading | `Drop your videos here to edit` |
| Drop zone link | `or click to browse` |
| Drop zone note | `MP4 or MOV · up to 2 GB each (1 GB on mobile)` |
| Run button | `Start chopping` |
| Section heading | `Consistency` |
| Ring tier (0) | `Getting started` |
| Ring sub | `Active {n} / 30 days · {s}-day streak` |
| Ring peak | `Peak day: —` |
| Activity heading | `Activity` |
| Activity stats | `Current streak` · `Longest streak` |
| Activity footer | `Last 6 months` · `Less` · `More` |
| Edits heading | `Your edits` |
| Edits empty | `Videos you edit will show up here.` |

**Note:** the money card says **`$0` at `$30/h`** — dollars, not pounds. I had
changed it to £. Reverting to match.

## 4. Corrections needed to what I already built

| Where | I wrote | Web actually says |
|---|---|---|
| Auth sub | "Sign in with your Chop account" | `Sign in to keep chopping.` |
| Auth toggle | "Create an account instead" | tabs: `Sign in` / `Create account` |
| Landing bullets | invented three | four, listed above, on the auth side panel |
| Landing CTA 2 | "Sign in" | `See how it works` |
| Money card | `£0` at `at £30/h` | `$0` at `at $30/h` |
| Drop note | "straight from your camera roll" | `MP4 or MOV · up to 2 GB each (1 GB on mobile)` |
| Empty state | "No edits yet / Videos you chop will show up here." | `Videos you edit will show up here.` |
| Dashboard title | "Your videos" | `Dashboard` / `Hey {name}, let's chop 👋` |
