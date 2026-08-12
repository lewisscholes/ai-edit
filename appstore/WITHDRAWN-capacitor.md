# WITHDRAWN — do not use Capacitor

I wrote a Capacitor wrapping guide before reading HANDOFF 3. **It was wrong. Ignore it.**

Lewis's §5.2 is correct and I should have reached the same conclusion:

- Every browser and web view on iOS is WebKit. A Capacitor wrapper ships the identical
  media stack, so it reproduces the exact seek-per-cut problem it was meant to solve.
- App Store Review Guideline **4.2 (Minimum Functionality)** explicitly targets apps
  that are a repackaged website. It would likely be rejected.

The `CHOP_NATIVE` flag I added to `app/index.html` (commit `eb483a8`) is now dead
code for the iOS route. It is harmless — it only activates inside Capacitor, which
we are not shipping — but it should be stripped when convenient.

**The account deletion work from that same commit stands and is still required**
(Guideline 5.1.1(v)). The backend path (`chop-delete-account`) is reusable from the
native app as-is.
