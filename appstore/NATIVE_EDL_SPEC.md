# Chop native — the edit model, and how it becomes an AVMutableComposition

Read this before writing the player. Everything else in the native app is
conventional iOS work; **this is the part where web and native can silently
disagree**, and a disagreement means the preview and the export don't match.

Derived from `app/index.html` at `37f0066`.

---

## 1. What a job actually contains

A job syncs through `chop_jobs.data` and carries (`cloudStrip()`):

| Field | Meaning |
|---|---|
| `payload` | Deepgram output turned into `segments` and `pairs` — the analysis |
| `choices` | Retake decisions, one per pair: `'a'`, `'b'`, `'both'` or `null` |
| `manuals` | Per-segment manual overrides: `true` = force cut, `false` = force keep, `null` = automatic |
| `settings` | `minSil`, `fillers`, `soft`, `overlapMs`, `startPadMs`, `endPadMs` |
| `manualCuts` | Quick-edit cuts as `{s, e}` in raw seconds |
| `splits` | Quick-edit split points |
| `videoKey`, `proxyKey` | R2 objects for the original and the 540p proxy |
| `rawSec`, `editedSec` | Durations, for display |

A **segment** is `{start, end, kind, text, manual, retake, pair, soft}` where
`kind` is `speech`, `silence` or `filler`.

**The native app must not invent its own edit model.** It reads these fields and
derives the same result the web app would.

---

## 2. Is a segment cut? — port this exactly

Order matters. First match wins.

```
isCut(seg):
  1. retake preview active for seg.pair  -> cut if seg.retake != previewed take
  2. seg.manual is not null              -> return seg.manual
  3. seg.retake is set:
        pair = pairs[seg.pair]
        if pair missing, or choice is null, or choice == 'both'  -> keep
        choice == 'a'  -> cut if seg.retake == 'b'
        choice == 'b'  -> cut if seg.retake == 'a'
  4. kind == 'silence' -> cut if (end - start) >= settings.minSil
  5. kind == 'filler'  -> cut if settings.fillers AND (not seg.soft OR settings.soft)
  6. otherwise         -> keep
```

Rule 3 is the retake logic and it is the product's whole point. An unresolved
pair keeps **both** takes — it never guesses.

## 3. Cut intervals

```
cutIntervals():
  sp = settings.startPadMs / 1000
  ep = settings.endPadMs   / 1000
  rd = raw duration

  a) walk segments in order; for each with isCut(seg) true, append {s,e},
     merging into the previous interval when seg.start <= prev.e + 0.001

  b) pad each interval, but only at boundaries that touch kept footage:
        if iv.s > 0.001      -> s = iv.s + ep
        if iv.e < rd - 0.001 -> e = iv.e - sp
     clamp to [0, rd], drop anything shorter than 0.005s

  c) merge in manualCuts as {s,e} clamped to [0, rd]
     sort the combined list by start, merge overlaps with the same 0.001 tolerance
     drop anything shorter than 0.005s
```

Note the pad signs. `endPadMs` extends the *start* of a cut (keeping more after the
previous clip), `startPadMs` pulls the *end* of a cut back (keeping more before the
next clip). Defaults are `+40ms` and `−40ms`. Getting these backwards shifts every
cut by 80ms and sounds clipped.

## 4. Kept clips — the composition's input

```
keptClips():
  pos = 0
  for each interval iv in cutIntervals():
      if iv.s - pos > 0.01: emit clip {start: pos, end: iv.s}
      pos = iv.e
  if rd - pos > 0.01: emit clip {start: pos, end: rd}
```

Clips shorter than 10ms are dropped. This array, in order, **is the edit**.

---

## 5. Building the composition

```swift
let composition = AVMutableComposition()
let vTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
let aTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!

let asset = AVURLAsset(url: sourceURL)
let srcV = try await asset.loadTracks(withMediaType: .video).first!
let srcA = try await asset.loadTracks(withMediaType: .audio).first!

var cursor = CMTime.zero
for clip in keptClips {
    let start = CMTime(seconds: clip.start, preferredTimescale: 600)
    let dur   = CMTime(seconds: clip.end - clip.start, preferredTimescale: 600)
    let range = CMTimeRange(start: start, duration: dur)

    try vTrack.insertTimeRange(range, of: srcV, at: cursor)
    try aTrack.insertTimeRange(range, of: srcA, at: cursor)
    cursor = cursor + dur
}

vTrack.preferredTransform = try await srcV.load(.preferredTransform)
```

`AVPlayer(playerItem: AVPlayerItem(asset: composition))` then plays the whole edit
as **one continuous asset**. No seeks at cut boundaries — which is the entire reason
for going native.

### Timescale
Use **600** throughout. It divides cleanly by 24, 25, 30 and 60, so clip boundaries
land on frame boundaries at any of the frame rates creators shoot at. Mixing
timescales is how you get single-frame gaps.

### Rotation
iPhone footage carries a rotation in `preferredTransform`. Copy it from the source
track onto the composition track, or portrait video plays sideways. The proxy
encoder already bakes rotation in (handled `-90` correctly), so a proxy-sourced
composition needs no transform — **the original does**.

### Audio crossfades
The web app applies `overlapMs` (default 250ms) as a crossfade at export only, never
in preview. For parity, do the same: play the composition dry, and apply an
`AVMutableAudioMix` with `setVolumeRamp` across clip joins **only when exporting**.
Adding it to preview would change what the creator hears versus what they get.

---

## 6. Two sources, one edit

`pickSource` priority in the web app is **proxy → local original → remote original**.
Native should keep the same idea but for different reasons:

- **Preview** from the 540p proxy where available. It decodes faster and 540×960 is
  sharp on a phone.
- **Export** from the original, always. The web app has a hard guard
  (`CHOP_EXPORT_PROXY_GUARD`) preventing a proxy reaching the renderer. **Port that
  guard.** Shipping a 540p export would be a serious, quiet regression.

Because `keptClips` are raw-timeline seconds, the same array drives both. The proxy
is frame-accurate to the original within 0.069s as measured, which is fine for
preview and irrelevant for export.

---

## 7. What must match the web app exactly

If you change any of these, web and native produce different videos from the same job:

- `isCut` rule order
- the 0.001 merge tolerance and 0.005 minimum interval
- pad direction and the boundary conditions on them
- the 0.01 minimum clip length
- unresolved and `'both'` retakes keeping both takes

**Test for parity, not plausibility.** Take a real job, compute `keptClips` in the
browser console, compute it in Swift, and assert the arrays match to three decimal
places. Do this before building any UI on top.

---

## 8. Export

`AVAssetExportSession` with the composition, preset `AVAssetExportPresetHighestQuality`
or a custom `AVAssetExportSession` configured for 1080p H.264. This replaces both
ffmpeg.wasm and the Modal render for iOS users — faster for them, cheaper for you.

Keep Modal for the web app. Nothing about the backend changes.
