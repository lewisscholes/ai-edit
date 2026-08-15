# App Review Information — paste straight in

Everything below goes into App Store Connect → your app → the version →
**App Review Information**. This section is the single most common cause of a
first rejection.

---

## Sign-In Required
**Yes** — tick it. The app opens directly to a sign-in screen.

## Demo Account

Create this before you submit. A real account, on production, that works.

```
Username:  appreview@chopedit.com
Password:  [set one, no special characters that are awkward to type]
```

**Load it with at least 10 credits before submitting.** A reviewer who signs in,
tries to edit, and hits "out of credits" will reject the build. Set the credits
directly in `chop_profiles`.

Test the credentials yourself on a device that has never signed in, immediately
before you submit.

## Notes

Paste this verbatim:

```
WHAT CHOP DOES
Chop automatically edits talking-head videos. You import footage you have
already filmed, Chop detects silences, filler words and repeated takes, and
removes them. You review every cut before exporting. The finished video saves
to your camera roll.

HOW TO TEST
1. Sign in with the demo account above.
2. Tap the upload area on the dashboard and pick any video from the photo
   library. A short clip of someone speaking works best. Any video will import.
3. Wait for processing (roughly 15 seconds per minute of footage).
4. The editor opens. The timeline shows the clips Chop kept. Pinch to zoom,
   tap a clip to select it, drag the white handles to trim, use Split and
   Delete in the bar below.
5. Tap the green tick in the top right to approve, then Export. The video
   saves to the camera roll.

IN-APP PURCHASES
Credits are consumable in-app purchases. One credit edits one video. New
accounts receive 3 free credits so the full flow can be tested without
purchasing. The demo account has credits already loaded.

ACCOUNT DELETION
Settings > Delete my account. This permanently deletes the account, saved
edits and remaining credits.

PHOTO LIBRARY
The app requests add-only photo library access solely to save finished videos
to the camera roll. Importing uses the system picker, which requires no
library permission.

CONTACT
hello@chopedit.com
```

---

## Other answers you'll be asked

| Field | Answer |
|---|---|
| Category | Photo & Video (primary), Productivity (secondary) |
| Age rating | 4+ — answer "None" to every content question |
| Export compliance | Uses HTTPS only → exemption applies |
| Content rights | You own or have rights to all content |
| Advertising identifier | No |
| Third-party content | No |

Privacy nutrition labels: use `PRIVACY_LABELS.md` — but see the correction below.

---

## Two things to fix before you submit

### 1. Payments — the privacy policy says Stripe, iOS uses Apple

`privacy.html` lists Stripe as the payment processor. On iOS, purchases go
through Apple's in-app purchase system, not Stripe. A reviewer cross-checking
your privacy labels against your policy may flag it.

Add Apple to the provider table in `privacy.html`:

| Apple | In-app purchase processing on iOS |

One line, no re-review needed since it's your own site.

### 2. Who is the developer — you, or the company?

The privacy policy names **ATS Collective Ltd** (company 17374176, registered
office 4 Shrub Road, Hampton Vale, Peterborough PE7 8LW) as the data controller.

Your Apple account is enrolled as **Aaron Tyler Symons**, an individual, with a
DSA trader address in **Manchester**.

So the App Store listing will publicly say one thing and the privacy policy
another. It is unlikely to block this submission, but it is exactly the sort of
inconsistency that gets picked up on a later review, and it undercuts the
privacy policy if a user ever queries it.

Nothing to do today. Resolve it when you convert the account to an Organization
after launch — then everything names ATS Collective Ltd and the addresses match.
