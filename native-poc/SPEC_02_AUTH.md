# SPEC 02 — Auth (Sign In / Sign Up / Reset / New password)

Extracted from `app/index.html`. Every value below is copied from source, not
described. Build SwiftUI from this file; do not re-read the HTML while building.

**Source:** `#viewAuth`, lines 803–831. Logic: `setAuthMode()` line 4272,
`authGo()` line 4287. CSS lines 216–262.

---

## Structure

One screen, four modes. `.authsplit` is a 2-column grid on desktop; at ≤760px
it becomes one column and **the gradient benefits panel stacks UNDER the form**
(source comment: "keep the sell on mobile"). Phone order is therefore:

```
authcard
├── authform      ← white/card panel
│   ├── authlogo  52×52 Chop mark, centred, margin-bottom 18
│   ├── h2        authTitle
│   ├── p.authsub authSub
│   ├── .atabs    [Sign in] [Create account]
│   ├── .field    Email
│   ├── .field    Password
│   ├── .field    New password        (mode `new` only)
│   ├── button.abtn                    authGo
│   ├── #authForgot                    (mode `in` only)
│   ├── #authBack                      (modes `reset`, `new`)
│   ├── .aerr                          error text
│   ├── .anote                         success note
│   └── .freebadge                     (modes `in`, `up`)
└── .abenefit     ← gradient panel, BELOW the form on phone
```

## Mode table

| mode | authTitle | authSub | button | tabs | forgot | back | freebadge | npRow |
|---|---|---|---|---|---|---|---|---|
| `in` | Welcome back | Sign in to keep chopping. | Sign in | Sign in on | shown | — | shown | — |
| `up` | Create your account | Three free videos are waiting. | Create account | Create account on | — | — | shown | — |
| `reset` | Reset your password | We'll email you a link to set a new one. | Send reset link | neither | — | shown | — | — |
| `new` | Choose a new password | Enter a new password for your account. | Save new password | neither | — | shown | — | shown |

The raw HTML defaults are `Welcome to Chop` / `Sign in to keep chopping.`, but
`setAuthMode('in')` overwrites the title with **Welcome back** before paint.
Use `Welcome back`.

## Fixed copy

- Tabs: `Sign in` · `Create account`
- Labels: `Email` · `Password` · `New password`
- Placeholders: `you@example.com` · `••••••••` (both password fields)
- `#authForgot`: `Forgot your password?`
- `#authBack`: `Back to sign in`
- `.freebadge`: `✦ New accounts get 3 free videos`

## Benefits panel (`.abenefit`)

- Background `linear-gradient(135deg,#1a6dff,#7c3aed)`, white text
- 44px white grid overlay at 9% opacity (`::before`)
- Top-right: 24×24 Chop mark on `rgba(255,255,255,.2)` + wordmark `Chop`, 800/14
- h3 (phone 21px, 1.2, −.01em): `Post more.` / `Edit nothing.` — two lines
- Four `li`, phone 13px, each with a 30×30 `rgba(255,255,255,.16)` circle icon:

| icon | text |
|---|---|
| scissors | Dead air, filler words and retakes cut automatically — in seconds |
| filmstrip | Retakes shown side by side — nothing is ever deleted without you |
| download arrow | Renders on your device — post straight to TikTok, Reels or Shorts |
| lightning bolt | Start with 3 free videos — no card, no subscription |

Icons are inline SVG paths, 16×16, stroked white. **Do not substitute SF
Symbols.** Paths are at `app/index.html` lines 824–827.

## Error strings (`.aerr`)

| Trigger | Text |
|---|---|
| reset, no email | Enter your email address. |
| in/up, missing field | Enter your email and a password. |
| new, password < 6 | Use at least 6 characters. |
| reset send failed | Couldn't send that — try again. |
| new save failed | Couldn't save that — try again. |
| SDK unreachable | Couldn't reach the sign-in service — refresh to retry. |
| generic fallback | That didn't work — try again. |
| `user_already_exists` | That email already has a Chop account. Sign in instead — your credits are waiting. |
| `invalid_credentials` (mode `in`) | No account matches that email and password. Check them, or create an account. |
| password too short (server) | Pick a password with at least 6 characters. |
| invalid email format | That doesn't look like a valid email address. |
| rate limited | Too many attempts — wait a minute and try again. |

`user_already_exists` also switches to mode `in` and preserves the typed email.

## Notes (`.anote`, green)

- After reset send: `Check your inbox — we've sent you a link to set a new password.`
- Sign-up with confirmation required: `Almost there — check your inbox and confirm your email, then sign in.` — then switches to mode `in`.

## Behaviour

- `authGo` is disabled while in flight; `.abtn:disabled` is opacity .55
- Enter in the password field submits
- `Forgot your password?` trims the email field, then switches to `reset`
- `Back to sign in` clears `_recovering` and switches to `in`
- Every mode change clears `.aerr` and hides `.anote`
- Sign in → `signInWithPassword`; sign up → `signUp`; both then `routeAuth(session)`

## Metrics

| Element | Value |
|---|---|
| card | `--card` bg, 1px `--line`, r20, max-width 440 on phone |
| authform padding | 26 × 24 (phone) |
| logo | 52×52, centred, mb 18 |
| h2 | 21px, centred, mb 4 |
| authsub | 13.5px `--mut`, centred, mb 22 |
| atabs | `--soft2` bg, r12, pad 4, gap 4, mb 20 |
| atabs button | flex 1, pad 9, r9, 800/13.5, `--mut` |
| atabs button.on | `--card` bg, `--ink`, subtle shadow |
| field | mb 14; label 700/12.5, mb 6 |
| input | pad 12/14, 1.5px `--line`, r11, `--bg` fill |
| input:focus | border `--blue`, bg `--card` |
| abtn | full width, pad 14, r12, `--blue`, white, 800/15, mt 6 |
| aerr | `--rose`, 600/12.5, centred, mt 10, min-height 18 |
| anote | `--green-soft` bg, `--green`, 700/12.5, pad 10/14, r11, mt 12 |
| freebadge | `--mut`, 600/12, centred, mt 16 |

App tokens (`ChopColor`), **not** landing tokens.

---

## Checklist before locking

- [ ] All four modes reachable and titled correctly
- [ ] Benefits panel renders **below** the form
- [ ] Four bullets use the real SVG icons
- [ ] Every error string above reachable
- [ ] Tab switch clears error and note
- [ ] Compared against the live site on device
