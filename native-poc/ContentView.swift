//  ContentView.swift — ChopNativeVideoPOC
//
//  A deliberately small experiment: can AVFoundation give TikTok-like scrubbing
//  on the exact footage that feels bad in mobile Safari?
//
//  No editing, no cuts, no network, no persistence. Replace the default
//  ContentView.swift with this file, drop the two media files into the project,
//  run on a real iPhone. All numbers are shown on screen.

import SwiftUI
import AVFoundation
import UIKit

// MARK: - Metrics

struct Samples {
    private(set) var values: [Double] = []
    mutating func add(_ ms: Double) { values.append(ms); if values.count > 400 { values.removeFirst() } }
    var count: Int { values.count }
    var median: Double { pct(0.5) }
    var p90: Double { pct(0.9) }
    private func pct(_ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let s = values.sorted()
        return s[min(s.count - 1, Int(Double(s.count) * p))]
    }
}

// MARK: - Engine

final class VideoEngine: NSObject, ObservableObject {

    let player = AVPlayer()

    // What the UI shows. Deliberately NOT the decoder's clock — the stick must
    // sit under the finger even while AVPlayer is still catching up.
    @Published var uiTime: Double = 0
    @Published var duration: Double = 1
    @Published var isPlaying = false
    @Published var sourceName = "loading…"

    // Instrumentation, surfaced on screen so numbers come off the real device.
    @Published var dragSeeks = Samples()
    @Published var exactSeeks = Samples()
    @Published var resumeLatency = Samples()
    @Published var playLatency = Samples()
    @Published var firstFrame = Samples()
    @Published var dragRequested = 0
    @Published var dragIssued = 0
    @Published var dragCollapsed = 0

    private var timeObserver: Any?

    // Apple's "smooth seeking" chase pattern: only ever work toward the newest
    // target, starting the next seek from the previous one's completion.
    private var chaseTime: CMTime = .zero
    private var isSeekInProgress = false
    private var scrubbing = false
    private var resumeAfterScrub = false

    private var pendingPlayStart: CFTimeInterval?
    private var pendingResumeStart: CFTimeInterval?
    private var pendingFrameStart: CFTimeInterval?

    // Detects when a NEW frame is genuinely on screen, rather than trusting
    // "playback started". Cheap: no Metal, no custom renderer.
    private var videoOutput: AVPlayerItemVideoOutput?
    private var displayLink: CADisplayLink?

    override init() {
        super.init()
        player.automaticallyWaitsToMinimizeStalling = false
        player.addObserver(self, forKeyPath: "timeControlStatus", options: [.new], context: nil)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.03, preferredTimescale: 600), queue: .main
        ) { [weak self] t in
            guard let self else { return }
            if !self.scrubbing { self.uiTime = t.seconds }   // finger wins while dragging
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        player.removeObserver(self, forKeyPath: "timeControlStatus")
        displayLink?.invalidate()
    }

    // MARK: Loading

    func load(_ filename: String, ext: String) {
        guard let url = Bundle.main.url(forResource: filename, withExtension: ext) else {
            sourceName = "MISSING FROM BUNDLE: \(filename).\(ext)"
            return
        }
        sourceName = "\(filename).\(ext)"
        let asset = AVURLAsset(url: url)
        let newItem = AVPlayerItem(asset: asset)
        newItem.preferredForwardBufferDuration = 2

        let attrs: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        let out = AVPlayerItemVideoOutput(pixelBufferAttributes: attrs)
        newItem.add(out)
        videoOutput = out

        player.replaceCurrentItem(with: newItem)

        Task {
            let d = try? await asset.load(.duration)
            await MainActor.run { self.duration = max(0.1, d?.seconds ?? 1) }
        }

        displayLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(onFrameTick))
        link.add(to: .main, forMode: .common)
        displayLink = link

        resetMetrics()
    }

    func resetMetrics() {
        dragSeeks = Samples(); exactSeeks = Samples()
        resumeLatency = Samples(); playLatency = Samples(); firstFrame = Samples()
        dragRequested = 0; dragIssued = 0; dragCollapsed = 0
    }

    // MARK: Transport

    func togglePlay() {
        if isPlaying {
            player.pause()
        } else {
            pendingPlayStart = CACurrentMediaTime()
            pendingFrameStart = CACurrentMediaTime()
            player.play()
        }
    }

    // MARK: Scrubbing

    /// Finger moved. UI updates immediately; the decoder gets a tolerant seek
    /// and is allowed to skip every intermediate target.
    func scrub(to seconds: Double) {
        if !scrubbing {
            scrubbing = true
            resumeAfterScrub = isPlaying
            if isPlaying { player.pause() }
        }
        uiTime = min(max(0, seconds), duration)
        dragRequested += 1

        let target = CMTime(seconds: uiTime, preferredTimescale: 600)
        if CMTimeCompare(target, chaseTime) == 0 { return }
        if isSeekInProgress { dragCollapsed += 1 }
        chaseTime = target
        if !isSeekInProgress { issueSeek(tolerant: true) }
    }

    /// Finger lifted. One accurate seek to exactly where they let go, then
    /// resume immediately if we interrupted playback.
    func endScrub(at seconds: Double) {
        let final = CMTime(seconds: min(max(0, seconds), duration), preferredTimescale: 600)
        chaseTime = final
        uiTime = final.seconds
        scrubbing = false

        let t0 = CACurrentMediaTime()
        let wantResume = resumeAfterScrub
        resumeAfterScrub = false
        pendingFrameStart = t0

        player.seek(to: final, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self else { return }
            self.exactSeeks.add((CACurrentMediaTime() - t0) * 1000)
            self.isSeekInProgress = false
            if wantResume {
                self.pendingResumeStart = CACurrentMediaTime()
                self.player.play()
            }
        }
    }

    private func issueSeek(tolerant: Bool) {
        guard player.currentItem?.status == .readyToPlay else { isSeekInProgress = false; return }
        isSeekInProgress = true
        let target = chaseTime
        let t0 = CACurrentMediaTime()
        // Tolerance is the whole trick: during a drag we want the nearest cheap
        // frame, not a frame-accurate decode from the previous keyframe.
        let tol = tolerant ? CMTime(seconds: 0.4, preferredTimescale: 600) : .zero
        dragIssued += 1
        player.seek(to: target, toleranceBefore: tol, toleranceAfter: tol) { [weak self] _ in
            guard let self else { return }
            self.dragSeeks.add((CACurrentMediaTime() - t0) * 1000)
            if CMTimeCompare(target, self.chaseTime) == 0 {
                self.isSeekInProgress = false          // caught up
            } else {
                self.issueSeek(tolerant: tolerant)     // newest target wins
            }
        }
    }

    // MARK: Observation

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == "timeControlStatus" else { return }
        DispatchQueue.main.async {
            let playing = self.player.timeControlStatus == .playing
            self.isPlaying = playing
            if playing {
                if let s = self.pendingPlayStart {
                    self.playLatency.add((CACurrentMediaTime() - s) * 1000); self.pendingPlayStart = nil
                }
                if let s = self.pendingResumeStart {
                    self.resumeLatency.add((CACurrentMediaTime() - s) * 1000); self.pendingResumeStart = nil
                }
            }
        }
    }

    /// "A new frame is actually on screen" — the thing the web version cannot see.
    @objc private func onFrameTick() {
        guard let out = videoOutput, let start = pendingFrameStart else { return }
        let t = player.currentTime()
        if out.hasNewPixelBuffer(forItemTime: t) {
            _ = out.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: nil)
            firstFrame.add((CACurrentMediaTime() - start) * 1000)
            pendingFrameStart = nil
        }
    }
}

// MARK: - Player view

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerUIView { PlayerUIView(player: player) }
    func updateUIView(_ uiView: PlayerUIView, context: Context) {}
}

final class PlayerUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    init(player: AVPlayer) {
        super.init(frame: .zero)
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        backgroundColor = .black
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - UI

struct ContentView: View {
    @StateObject private var engine = VideoEngine()
    @State private var useProxy = false

    var body: some View {
        VStack(spacing: 12) {

            Picker("Source", selection: $useProxy) {
                Text("Original 4K HEVC").tag(false)
                Text("540p proxy").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: useProxy) { _, proxy in
                engine.load(proxy ? "IMG_5521_proxy" : "IMG_5521_original",
                            ext: proxy ? "mp4" : "MOV")
            }

            PlayerLayerView(player: engine.player)
                .frame(maxWidth: .infinity)
                .frame(height: 360)
                .background(Color.black)

            // Timeline: the stick follows the finger with zero dependence on
            // the decoder — that is the whole point of the experiment.
            GeometryReader { geo in
                let w = max(1, geo.size.width)
                let x = CGFloat(engine.duration > 0 ? engine.uiTime / engine.duration : 0) * w
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.3))
                    RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.5))
                        .frame(width: max(0, x))
                    Rectangle().fill(Color.white).frame(width: 3)
                        .offset(x: max(0, min(w - 3, x)))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in engine.scrub(to: Double(v.location.x / w) * engine.duration) }
                        .onEnded { v in engine.endScrub(at: Double(v.location.x / w) * engine.duration) }
                )
            }
            .frame(height: 54)
            .padding(.horizontal)

            HStack(spacing: 16) {
                Button(engine.isPlaying ? "Pause" : "Play") { engine.togglePlay() }
                    .font(.title2.bold())
                    .frame(width: 130, height: 48)
                    .background(Color.blue).foregroundColor(.white).cornerRadius(12)
                Text(String(format: "%.2f / %.2fs", engine.uiTime, engine.duration))
                    .font(.system(.body, design: .monospaced))
                Spacer()
                Button("Reset") { engine.resetMetrics() }
            }
            .padding(.horizontal)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text(engine.sourceName).font(.caption).foregroundColor(.secondary)
                    row("drag seeks (tolerant)", engine.dragSeeks)
                    row("exact seek on release", engine.exactSeeks)
                    row("resume after release ", engine.resumeLatency)
                    row("play tap -> playing  ", engine.playLatency)
                    row("-> first frame shown ", engine.firstFrame)
                    Text("targets requested \(engine.dragRequested) · issued \(engine.dragIssued) · collapsed \(engine.dragCollapsed)")
                        .font(.system(.caption, design: .monospaced))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }
        }
        .onAppear { engine.load("IMG_5521_original", ext: "MOV") }
    }

    private func row(_ label: String, _ s: Samples) -> some View {
        Text(String(format: "%@ n=%d  median %.0fms  p90 %.0fms", label, s.count, s.median, s.p90))
            .font(.system(.caption, design: .monospaced))
    }
}
