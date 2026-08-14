# Chop → native iOS: audit and migration map

**Phase 1 output. No code changed to produce this.**

Sources audited: `app/index.html` (4,944 lines — the whole web app), `index.html`
(landing), `admin.html`, and `native-poc/Chop.swift` (2,485 lines — the native app
so far).

---

## 1. What must not be touched

The AVFoundation editor is the strongest part of the native app and the reason
for the port. **Preserve as-is:**

| Component | Where | Why |
|---|---|---|
| `ChopPlayer.open/rebuild` | Chop.swift | Builds `AVMutableComposition` from kept clips — this is the fix for the seek-per-cut stutter |
| `seek` / `seekExact` / `scrubbing` | Chop.swift | Tolerant seeking; the stick follows the finger |
| `buildStrip` | Chop.swift | Filmstrip via `AVAssetImageGenerator`, off the composition |
| `export` | Chop.swift | On-device 1080p via `AVAssetExportSession`, original-only guard |
| `ChopEdit` (isCut / cutIntervals / keptClips) | Chop.swift | Ported line-for-line from the web; changing it makes web and native disagree |

Anything below that touches these should wrap them, not rewrite them.

---

## 2. Design tokens, lifted from the web

Both themes, straight out of `:root` and `html.dark`.

| Token | Light | Dark |
|---|---|---|
| bg | `#f6f8fb` | `#0e1014` |
| card / panel | `#ffffff` | `#161922` |
| ink | `#101319` | `#e9edf5` |
| muted | `#66707f` | `#8a93a5` |
| line | `#e4e8ef` | `#262c38` |
| blue | `#1a6dff` | `#3b82ff` |
| blue-dk | `#0d4fc4` | `#a5c0ff` |
| blue-soft | `#eaf1ff` | `#1b2a4a` |
| violet | `#7c3aed` | `#b79bff` |
| violet-soft | `#f1e9ff` | `#271e3d` |
| green | `#0e9f6e` | `#3ad39c` |
| green-soft | `#e2f7ee` | `#12291f` |
| rose | `#dc2637` | `#f2596b` |
| amber | `#b45309` | `#f0b35c` |
| soft2 / hover | `#eef1f6` | `#20242f` |
| glass | `rgba(255,255,255,.55)` | `rgba(22,25,34,.55)` |
| glass border | `rgba(255,255,255,.65)` | `rgba(255,255,255,.12)` |

**Note:** the native app currently uses `#151820` for panel and `#262a33` for
line. Both are wrong — should be `#161922` and `#262c38`.

**Type:** system font. Body 14.5px/1.5. Weights are almost entirely **800** and
**700** — the web app is far bolder than SwiftUI's defaults, which is a large
part of why the native app "doesn't look like Chop". Common sizes: 10.5, 11,
11.5, 12, 12.5, 13, 13.5, 14, 15.

**Radii:** 8, 9, 10, 12, 14, 16, 20, 26 (nav pill).

---

## 3. Screen-by-screen map

| Web screen | Native status | Action |
|---|---|---|
| Landing (`index.html`) | Placeholder | **Rebuild** — hero, gradient headline, CTAs, feature cards |
| `viewAuth` | Basic form | **Restyle** to the web's auth card, tabs, benefit panel |
| `viewPsetup` | Emoji-only | **Extend** — photo upload to the avatars bucket |
| `viewHome` | Close | **Polish** — weights, spacing, activity heatmap missing |
| `viewProc` | Done | Matches the six steps |
| `viewEditor` | Native, good | **Keep engine**, restyle chrome to match |
| `viewQueue` | Done | Matches the four buckets |
| `viewLab` | Done, no preview | **Add** the live before/after preview |
| `viewBilling` | Missing | **Blocked** — needs IAP, see §5 |
| `viewSettings` | Thin | **Rebuild** against the web's settings |
| Out-of-credits sheet | Done | Matches |

## 4. Component map

| Web | Native | Status |
|---|---|---|
| `.icard` / `.hero-card` | `statCard` | exists, wrong weights |
| `.glassnav` / `.gbtn` | `ChopGlassNav` | exists |
| `.rk` retake card | `RetakeCard` | exists |
| `.kcard` kanban card | `QueueCard` | exists |
| `.abtn` primary button | inline | **extract to `ChopButton`** |
| `.field` + input | inline | **extract to `ChopTextField`** |
| `.chip` / `.uchip` | inline | **extract to `ChopBadge`** |
| `.toast` | none | **build `ChopToast`** |
| `.kempty` empty state | inline | **extract to `ChopEmptyState`** |
| `.avopt` avatar picker | emoji grid | needs photo support |
| `.pstep` progress step | inline | fine |

## 5. Features not yet native

| Feature | Web | Effort | Note |
|---|---|---|---|
| Activity heatmap | 6-month grid on home | Medium | Pure SwiftUI |
| Cut Lab live preview | before/after with demo segments | Medium | Needs `LP_SEGS` |
| Photo avatar upload | avatars bucket | Medium | Storage API |
| Billing / buy credits | slider + tiers | **Blocked** | Apple requires IAP; needs Paid Apps agreement |
| Bulk import | multi-select | Small | `PhotosPicker` supports it |
| Undo/redo | `snap()` / `applySnap` | Medium | Editor state stack |
| Toasts | everywhere | Small | Currently silent |
| Transcript search | web only | Small | |

## 6. Deliberately not migrated

- ffmpeg.wasm export — replaced by `AVAssetExportSession`
- `coi-serviceworker` / cross-origin isolation — irrelevant natively
- IndexedDB persistence — replaced by the file system
- Proxy playback selection — native decodes the original fine
- The seek-per-cut playback loop — the entire reason for the port

## 7. Order of work

1. **Design system** — `ChopTheme`, corrected tokens, `ChopButton`,
   `ChopTextField`, `ChopCard`, `ChopBadge`, `ChopToast`, `ChopEmptyState`
2. **Landing + auth** — the two screens judged first
3. **Restyle existing screens** against the tokens, especially font weights
4. **Feature parity** — heatmap, Cut Lab preview, photo avatars, toasts, undo
5. **Polish** — animations, empty states, error states
6. **QA** — every flow on device

Billing stays out until the IAP decision is made.
