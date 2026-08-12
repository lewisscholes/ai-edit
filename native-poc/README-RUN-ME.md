# ChopNativeVideoPOC — how to run it on your iPhone

You are not an iOS developer and you don't need to be. This is ~15 minutes,
most of which is a download.

**Xcode is not currently installed on this Mac** (only the command line tools),
so step 1 is unavoidable.

---

## 1. Install Xcode

Open the **App Store**, search **Xcode**, install it. It's free and about 7GB,
so start it now and make a coffee.

Open Xcode once when it finishes and accept the licence prompt.

## 2. Create the project

In Xcode: **File → New → Project…**

- Choose **iOS** at the top, then **App**. Click **Next**.
- Product Name: `ChopNativeVideoPOC`
- Interface: **SwiftUI**  ·  Language: **Swift**
- Leave everything else alone. Click **Next**.
- Save it somewhere obvious — your Desktop is fine. Click **Create**.

Letting Xcode create the project itself is deliberate: a hand-written project
file is the classic way to end up with something that won't open.

## 3. Drop in the code

In the left sidebar you'll see a file called **ContentView.swift**. Click it.

Select everything in the editor (**Cmd+A**) and delete it. Then open
`ContentView.swift` from *this* folder, copy all of it, and paste it in.

## 4. Drop in the two videos

Drag these two files from this folder into Xcode's left sidebar, onto the
yellow **ChopNativeVideoPOC** folder:

- `IMG_5521_original.MOV`  (208MB — your real 4K HEVC clip)
- `IMG_5521_proxy.mp4`  (3.5MB — the 540p proxy we generated)

A dialog appears. **Tick "Copy items if needed"**, make sure the target
checkbox is ticked, click **Finish**.

The 208MB file makes the app slow to install the first time. That's expected
and is not what we're measuring.

## 5. Put it on your phone

- Plug your iPhone into the Mac with a cable. Unlock it. Tap **Trust** if asked.
- At the top of the Xcode window there's a dropdown that probably says
  *iPhone 15 Pro* or similar — click it and pick **your actual iPhone** from the
  list (it'll have your name on it).
- Click the **▶ Play** button, top left.

**First time only**, Xcode will complain about signing:

- Click the blue **ChopNativeVideoPOC** at the very top of the left sidebar.
- Choose the **Signing & Capabilities** tab.
- Tick **Automatically manage signing**.
- Team: pick your Apple ID. If there isn't one, click **Add an Account…** and
  sign in with your normal Apple ID. A free account is fine.
- Press **▶** again.

**Then on the iPhone**, the app installs but iOS won't trust it yet:

- Settings → General → **VPN & Device Management**
- Tap your Apple ID under *Developer App* → **Trust**.
- Now open the app from your home screen.

A free Apple ID means the app expires after 7 days. That's fine for this.

---

## 6. The test that matters

There are three things to do, in this order. Hit **Reset** between sources.

**Test A — original 4K.** Leave the picker on *Original 4K HEVC*.
Scrub the timeline hard, back and forth, for 20–30 seconds. Watch whether the
white stick stays under your finger and how far behind the picture is.

**Test B — the proxy.** Switch the picker to *540p proxy* and do exactly the
same. This tells us whether a native app would still want our proxy.

**Test C — the one I actually care about.** Do this **20 times**:

1. Press Play, let it run 3–4 seconds
2. **While it's still playing**, grab the timeline and drag backwards
3. Release
4. Notice how fast the video continues from that point

That's the interaction that feels bad in Safari.

---

## 7. Send me the numbers

At the bottom of the screen are five lines that look like:

```
drag seeks (tolerant) n=118  median 24ms  p90 61ms
exact seek on release n=20   median 88ms  p90 140ms
resume after release  n=20   median 45ms  p90 90ms
play tap -> playing   n=6    median 30ms  p90 55ms
-> first frame shown  n=6    median 48ms  p90 95ms
targets requested 640 · issued 118 · collapsed 522
```

Screenshot that for **each source** and send both, plus one sentence on how it
*felt* versus Chop in Safari. The feel matters as much as the numbers.

---

## What this is and isn't

It is one file and two videos. It plays, it scrubs, it measures. There is no
editing, no cuts, no login, no cloud — deliberately. We're answering one
question: does AVFoundation solve the scrubbing problem that mobile Safari
doesn't. Nothing here is a step toward rebuilding Chop natively; that decision
comes after we see your numbers.
