# Chop — App Store Connect metadata

Fill the bracketed bits, paste the rest straight in.

---

## App name (30 char limit) — DECIDED
```
Chop Editor
```
11 characters. Confirm it's free on the App Store before creating the record.

Home screen name is separate and already set to `Chop` via CFBundleDisplayName —
"Chop Editor" would truncate under the icon, "Chop" won't.

The App Store name is NOT permanent. It can be changed with any future version
submission. Only the bundle ID (`com.chopedit.chop`) is fixed forever.

## Subtitle (30 char limit)
```
Don't edit, just film
```

## Promotional text (170 char limit, editable without a review)
```
First 100 creators get 10 free credits. Drop in raw footage, get back a clean cut in seconds — dead air, filler words and bad takes gone.
```

## Keywords (100 chars, comma separated, NO spaces after commas)
```
video,auto edit,tiktok,ugc,creator,silence remover,filler words,retake,talking head,shorts,reels
```
96 characters.

"chop" and "editor" are deliberately absent — Apple already indexes the app name,
so repeating them wastes the allowance. Don't add competitor names; that's a
rejection risk.

## Description
```
Film it once. Chop does the editing.

Chop watches your talking-head footage and cuts out everything that slows it down — the dead air, the ums and uhs, and the takes where you fluffed your line. What's left is a tight, postable video, ready in seconds.

THE BIT NOBODY ELSE GETS RIGHT
Said the same line three times? Other auto-editors quietly keep the last take and get it wrong embarrassingly often. Chop finds every repeated take, lines them up side by side, and lets you pick. Nothing is ever cut without you seeing it first.

HOW IT WORKS
1. Drop in your raw footage
2. Chop finds the pauses, filler words and retakes
3. Review the cuts and pick your best takes
4. Export a clean MP4 and post it

BUILT FOR CREATORS WHO POST DAILY
• A TikTok-style timeline you can actually use with your thumbs — pinch to zoom, drag to trim, split and restore
• Bulk upload, so a week of filming gets queued in one go
• Your cutting style saved once and applied to everything
• Works across your phone and desktop, picking up where you left off

WHAT IT'S FOR
Product reviews, hauls, storytimes, UGC — if you're talking to camera, Chop understands it.

Start with 3 free videos. No subscription.
```

## What's New (first release)
```
First release. Automatic cutting of dead air, filler words and retakes, a thumb-friendly timeline, and exports ready to post.
```

## Support URL
`https://chopedit.com`

## Marketing URL (optional)
`https://chopedit.com`

## Privacy Policy URL
`https://chopedit.com/privacy.html`

---

## App Review notes

**OUT OF DATE — do not use this section. Use `REVIEW_NOTES.md` instead.**

This was written before the native rebuild, when credits were sold on the web
only. It states *"The app contains no in-app purchases. Credits are not sold in
the app."* That is now false — the iOS app ships StoreKit 2 with five consumable
credit packs. Saying otherwise in the review notes misrepresents the app, and
Apple tests the purchase flow, so it would be caught.

Use `appstore/REVIEW_NOTES.md`.

## Age rating
4+. Answer "None" to every content question. Chop has no user-generated content shared between users, no web browsing, no gambling, no contests.

## Category
Primary: **Photo & Video**
Secondary: **Productivity**

## Export compliance
Uses HTTPS only. Answer: yes it uses encryption, and yes it qualifies for the exemption (standard encryption only).

## Content rights
No third-party content. Answer "No".
