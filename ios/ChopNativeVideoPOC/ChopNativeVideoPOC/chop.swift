//  Chop.swift — the native app, step 1: sign in and list your jobs.
//
//  Talks to the same Supabase project the web app uses. No backend changes:
//  same accounts, same chop_jobs rows, same analysis.

import SwiftUI
import Combine
import AVFoundation
import Photos
import UIKit
import PhotosUI
import StoreKit
import AuthenticationServices
import CryptoKit
import Security

// MARK: - Keychain (stay signed in)

/// Minimal Keychain wrapper — holds the Supabase refresh token so the session
/// survives app restarts. Standard practice: token lives in the Keychain,
/// session silently restores on launch, sign-out wipes it.
enum ChopKeychain {
    private static let service = "com.chopedit.session"

    static func set(_ value: String, _ key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: key,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
    }
}

let SB_URL  = "https://vcrforlyuhapvkewsogq.supabase.co"
let SB_ANON = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZjcmZvcmx5dWhhcHZrZXdzb2dxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAzODk4NzAsImV4cCI6MjA5NTk2NTg3MH0.lcFC5aJFUGYrj4iw8oJ8R1bci4y_-aYKyQg8v9zrMqQ"


// MARK: - Brand

private func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
    func c(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xff) / 255,
                green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
    return Color(UIColor { $0.userInterfaceStyle == .dark ? c(dark) : c(light) })
}

// MARK: - Chop design system
//
// Tokens lifted verbatim from :root and html.dark in app/index.html so the
// native app and the web app cannot drift apart.

// Light mode = clean white (the original web palette). Purple is gone — the
// old violet slot carries TikTok pink, with cyan as a second accent. Dark mode
// keeps the midnight palette, and the editor always runs dark.
enum ChopColor {
    static let bg         = dyn(0xf6f8fb, 0x0e1014)
    static let card       = dyn(0xffffff, 0x161922)
    static let ink        = dyn(0x101319, 0xe9edf5)
    static let muted      = dyn(0x66707f, 0x8a93a5)
    static let line       = dyn(0xe4e8ef, 0x262c38)
    static let blue       = dyn(0x1a6dff, 0x3b82ff)
    static let blueDk     = dyn(0x0d4fc4, 0xa5c0ff)
    static let blueSoft   = dyn(0xeaf1ff, 0x1b2a4a)
    static let violet     = dyn(0xfe2c55, 0xff5c7d)   // TikTok pink (ex-violet)
    static let violetSoft = dyn(0xffe4ea, 0x3a1d26)
    static let green      = dyn(0x0e9f6e, 0x3ad39c)
    static let greenSoft  = dyn(0xe2f7ee, 0x12291f)
    static let rose       = dyn(0xdc2637, 0xf2596b)
    static let roseSoft   = dyn(0xffe9ec, 0x331a1f)
    static let amber      = dyn(0xb45309, 0xf0b35c)
    static let amberSoft  = dyn(0xfff4dd, 0x2c2212)
    static let soft2      = dyn(0xeef1f6, 0x20242f)
    static let hover      = dyn(0xf2f5f9, 0x20242f)
    static let tkCyan     = dyn(0x14c9c4, 0x25f4ee)   // TikTok cyan accent
}

/// The web app is very bold — 83 uses of weight 800, 37 of 700, almost nothing
/// regular. Matching that is most of what makes it read as Chop.
enum ChopFont {
    /// Editorial serif for hero titles — the onboarding's Georgia voice.
    static func serif(_ s: CGFloat) -> Font { .custom("Georgia-Bold", size: s) }
    static func serifItalic(_ s: CGFloat) -> Font { .custom("Georgia-BoldItalic", size: s) }
    static func h1(_ s: CGFloat = 30) -> Font { .system(size: s, weight: .bold) }
    static func h2(_ s: CGFloat = 21) -> Font { .system(size: s, weight: .bold) }
    static let cardBig   = Font.system(size: 30, weight: .bold)
    static let cardLabel = Font.system(size: 13, weight: .heavy)
    static let body      = Font.system(size: 14.5, weight: .regular)
    static let bodyBold  = Font.system(size: 14.5, weight: .heavy)
    static let label     = Font.system(size: 12.5, weight: .heavy)
    static let small     = Font.system(size: 11.5, weight: .semibold)
    static let tiny      = Font.system(size: 10.5, weight: .heavy)
}

enum ChopRadius {
    static let sm: CGFloat = 9
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let pill: CGFloat = 26
}

// purple is out — the brand gradient is now a blue sweep
let chopGradient = LinearGradient(colors: [ChopColor.blue, Color(red: 78/255, green: 141/255, blue: 1)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)

/// The wordmark: heavy lowercase "chop" with the bottom sliced clean off,
/// the cut band drifting away like a dropped frame. No icon, pure type.
struct ChopWordmark: View {
    var size: CGFloat = 24
    var color: Color = ChopColor.ink

    var body: some View {
        let base = Text("chop")
            .font(.system(size: size, weight: .black))
            .kerning(-size * 0.045)
            .foregroundStyle(color)
        return ZStack {
            base
                .clipShape(SliceBand(top: true))
            base
                .clipShape(SliceBand(top: false))
                .offset(x: size * 0.045, y: size * 0.02)
                .rotationEffect(.degrees(2), anchor: .bottomLeading)
        }
        .fixedSize()
        .accessibilityLabel("Chop")
    }

    /// top = everything above the slice line · bottom = the drifting band
    private struct SliceBand: Shape {
        let top: Bool
        func path(in r: CGRect) -> Path {
            var p = Path()
            if top {
                p.addRect(CGRect(x: r.minX, y: r.minY,
                                 width: r.width, height: r.height * 0.72))
            } else {
                p.addRect(CGRect(x: r.minX, y: r.minY + r.height * 0.76,
                                 width: r.width, height: r.height * 0.5))
            }
            return p
        }
    }
}

// ---- reusable components ----

struct ChopButton: View {
    enum Kind { case primary, gradient, secondary, ghost, danger }
    let title: String
    var icon: String? = nil
    var kind: Kind = .primary
    var loading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if loading { ProgressView().tint(fg) }
                else if let icon { Image(systemName: icon).font(.system(size: 14, weight: .bold)) }
                Text(title).font(.system(size: 15, weight: .heavy))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(fg)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: ChopRadius.md))
            .overlay(RoundedRectangle(cornerRadius: ChopRadius.md)
                .stroke(kind == .secondary ? ChopColor.line : .clear, lineWidth: 1))
        }
        .disabled(loading)
    }

    @ViewBuilder private var bg: some View {
        switch kind {
        case .primary:   ChopColor.blue
        case .gradient:  chopGradient
        case .secondary: ChopColor.card
        case .ghost:     Color.clear
        case .danger:    ChopColor.roseSoft
        }
    }
    private var fg: Color {
        switch kind {
        case .primary, .gradient: return .white
        case .danger:             return ChopColor.rose
        default:                  return ChopColor.ink
        }
    }
}

struct ChopCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .background(ChopColor.card)
            .clipShape(RoundedRectangle(cornerRadius: ChopRadius.lg))
            .overlay(RoundedRectangle(cornerRadius: ChopRadius.lg)
                .stroke(ChopColor.line, lineWidth: 1))
    }
}

struct ChopField: View {
    let label: String
    var placeholder = ""
    var secure = false
    var prefix: String? = nil
    var contentType: UITextContentType? = nil   // password manager / autofill hints
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(ChopFont.label).foregroundStyle(ChopColor.ink)
            HStack(spacing: 0) {
                if let prefix {
                    Text(prefix).font(ChopFont.bodyBold)
                        .foregroundStyle(ChopColor.muted).padding(.leading, 14)
                }
                Group {
                    if secure { SecureField(placeholder, text: $text) }
                    else { TextField(placeholder, text: $text) }
                }
                .font(ChopFont.body)
                .textContentType(contentType)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
            .background(ChopColor.bg)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11)
                .stroke(ChopColor.line, lineWidth: 1.5))
        }
    }
}

struct ChopBadge: View {
    let text: String
    var tint: Color = ChopColor.blue
    var soft: Color = ChopColor.blueSoft
    var body: some View {
        Text(text)
            .font(ChopFont.tiny)
            .foregroundStyle(tint)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(soft, in: Capsule())
    }
}

struct ChopEmptyState: View {
    let icon: String
    let title: String
    var note: String? = nil
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(ChopColor.muted)
            Text(title).font(.system(size: 16, weight: .heavy)).foregroundStyle(ChopColor.ink)
            if let note {
                Text(note).font(ChopFont.small).foregroundStyle(ChopColor.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }
}

/// The web app toasts constantly; the native app was silent.
@MainActor
final class ChopToasts: ObservableObject {
    static let shared = ChopToasts()
    @Published var message: String?
    @Published var bigMessage: String?   // the centre-screen green celebration
    private var task: Task<Void, Never>?
    private var bigTask: Task<Void, Never>?
    func show(_ m: String) {
        message = m
        task?.cancel()
        task = Task { try? await Task.sleep(nanoseconds: 2_600_000_000); message = nil }
    }
    /// Big, green, dead-centre — for the moments that matter (Ready to export).
    func showBig(_ m: String) {
        bigMessage = m
        bigTask?.cancel()
        bigTask = Task { try? await Task.sleep(nanoseconds: 2_200_000_000); bigMessage = nil }
    }
}

struct ChopToastHost: ViewModifier {
    @ObservedObject private var toasts = ChopToasts.shared
    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content
            if let m = toasts.message {
                Text(m)
                    .font(ChopFont.small).foregroundStyle(ChopColor.ink)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(ChopColor.line, lineWidth: 1))
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let m = toasts.bigMessage {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36, weight: .bold))
                    Text(m)
                        .font(.system(size: 16.5, weight: .heavy))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 28).padding(.vertical, 24)
                .background(ChopColor.green, in: RoundedRectangle(cornerRadius: 22))
                .shadow(color: ChopColor.green.opacity(0.45), radius: 20, y: 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)   // dead centre
                .transition(.scale(scale: 0.82).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .animation(.spring(duration: 0.28), value: toasts.message)
        .animation(.spring(duration: 0.32, bounce: 0.35), value: toasts.bigMessage)
    }
}
extension View { func chopToasts() -> some View { modifier(ChopToastHost()) } }

/// System · Light · Dark, remembered between launches.
enum ChopTheme: String, CaseIterable {
    case system, light, dark
    var scheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark:  return .dark
        default:     return nil
        }
    }
    static var current: ChopTheme {
        // cream editorial is the default face of the app now
        ChopTheme(rawValue: UserDefaults.standard.string(forKey: "chopTheme") ?? "light") ?? .light
    }
    static func set(_ t: ChopTheme) { UserDefaults.standard.set(t.rawValue, forKey: "chopTheme") }
}


extension Color {
    static let chopBg     = ChopColor.bg
    static let chopPanel  = ChopColor.card
    static let chopLine   = ChopColor.line
    static let chopInk    = ChopColor.ink
    static let chopMuted  = ChopColor.muted
    static let chopBlue   = ChopColor.blue
    static let chopViolet = ChopColor.violet
    static let chopGreen  = ChopColor.green
}

// MARK: - Model

struct ChopJob: Identifiable {
    var id: String { name }
    let name: String
    let status: String
    let videoKey: String?
    let rawSec: Double
    let editedSec: Double
    let hasAnalysis: Bool
    let data: [String: Any]

    /// The web app stores a JPEG data URL on each job. Decode it so the list
    /// shows real frames rather than a placeholder.
    var thumbnail: UIImage? {
        guard let t = data["thumb"] as? String, t != "err",
              let comma = t.firstIndex(of: ","),
              let d = Data(base64Encoded: String(t[t.index(after: comma)...])) else { return nil }
        return UIImage(data: d)
    }

    var savedPct: Int {
        guard rawSec > 0, editedSec > 0 else { return 0 }
        return Int(((rawSec - editedSec) / rawSec) * 100)
    }

    /// Undecided retakes — same maths as the web's jobStats(): total pairs
    /// minus non-null choices.
    var pendingRetakes: Int {
        let payload = data["payload"] as? [String: Any]
        let total = (payload?["pairs"] as? [[String: Any]])?.count ?? 0
        let decided = ((data["choices"] as? [Any]) ?? []).filter { !($0 is NSNull) }.count
        return max(0, total - decided)
    }
}


// MARK: - The edit
//
// Ported from app/index.html so native and web agree exactly. If these rules
// drift, the preview and the export stop matching. See appstore/NATIVE_EDL_SPEC.md.

struct ChopSettings {
    var minSil: Double = 0.4
    var fillers: Bool = true
    var soft: Bool = false
    var startPadMs: Double = 40
    var endPadMs: Double = -40

    init() {}
    init(_ d: [String: Any]?) {
        guard let d = d else { return }
        if let v = d["minSil"] as? Double { minSil = v }
        if let v = d["fillers"] as? Bool { fillers = v }
        if let v = d["soft"] as? Bool { soft = v }
        if let v = d["startPadMs"] as? Double { startPadMs = v }
        if let v = d["endPadMs"] as? Double { endPadMs = v }
    }
}

struct ChopSegment {
    var start: Double
    var end: Double
    var kind: String
    var soft: Bool
    var retake: String?
    var pair: Int?
    var manual: Bool?
    var text: String = ""
}

struct ChopClip { var start: Double; var end: Double }

/// One matched retake: two takes of the same line. Chop never picks for you —
/// an unresolved pair keeps BOTH takes, exactly as the web app does.
struct ChopPair: Identifiable {
    let id: Int
    var sim: Double
    var weak: Bool
    var choice: String?          // "a", "b", "both", or nil = undecided
    var aText: String = ""
    var bText: String = ""
    var aLen: Double = 0
    var bLen: Double = 0
    var complete: Bool = false   // both takes found in the segment list
}

struct ChopEdit {
    var segments: [ChopSegment] = []
    var choices: [String?] = []
    var settings = ChopSettings()
    var manualCuts: [ChopClip] = []
    var manualKeeps: [ChopClip] = []   // footage dragged BACK from any cut — wins over the auto-editor
    var rawDur: Double = 0
    var pairs: [ChopPair] = []

    init(job: ChopJob) {
        let d = job.data
        settings = ChopSettings(d["settings"] as? [String: Any])

        if let arr = d["choices"] as? [Any] {
            choices = arr.map { $0 as? String }
        }
        let manuals = d["manuals"] as? [Any]

        if let payload = d["payload"] as? [String: Any],
           let segs = payload["segments"] as? [[String: Any]] {
            for (i, sg) in segs.enumerated() {
                var m: Bool? = nil
                if let manuals = manuals, i < manuals.count { m = manuals[i] as? Bool }
                segments.append(ChopSegment(
                    start: (sg["start"] as? Double) ?? 0,
                    end:   (sg["end"] as? Double) ?? 0,
                    kind:  (sg["kind"] as? String) ?? "speech",
                    soft:  (sg["soft"] as? Bool) ?? false,
                    retake: sg["retake"] as? String,
                    pair:  sg["pair"] as? Int,
                    manual: m,
                    text: (sg["text"] as? String) ?? ""
                ))
            }
        }
        if let payload = d["payload"] as? [String: Any],
           let rawPairs = payload["pairs"] as? [[String: Any]] {
            for (i, rp) in rawPairs.enumerated() {
                var pr = ChopPair(
                    id: i,
                    sim: (rp["sim"] as? Double) ?? 0,
                    weak: (rp["weak"] as? Bool) ?? false,
                    choice: (i < choices.count) ? choices[i] : nil
                )
                if let a = segments.first(where: { $0.retake == "a" && $0.pair == i }),
                   let b = segments.first(where: { $0.retake == "b" && $0.pair == i }) {
                    pr.aText = a.text; pr.bText = b.text
                    pr.aLen = a.end - a.start; pr.bLen = b.end - b.start
                    pr.complete = true
                } else {
                    // malformed pair: keep everything rather than guess
                    pr.choice = "both"
                }
                pairs.append(pr)
            }
        }

        if let mc = d["manualCuts"] as? [[String: Any]] {
            manualCuts = mc.compactMap {
                guard let s = $0["s"] as? Double, let e = $0["e"] as? Double else { return nil }
                return ChopClip(start: s, end: e)
            }
        }
        if let mk = d["manualKeeps"] as? [[String: Any]] {
            manualKeeps = mk.compactMap {
                guard let s = $0["s"] as? Double, let e = $0["e"] as? Double else { return nil }
                return ChopClip(start: s, end: e)
            }
        }
        rawDur = max(job.rawSec, segments.last?.end ?? 0)
    }

    /// Newest intent wins: cutting a range removes it from any earlier keeps.
    mutating func carveKeeps(for cut: ChopClip) {
        var out: [ChopClip] = []
        for k in manualKeeps {
            if cut.end <= k.start + 0.001 || cut.start >= k.end - 0.001 { out.append(k); continue }
            if cut.start > k.start + 0.005 { out.append(ChopClip(start: k.start, end: cut.start)) }
            if cut.end < k.end - 0.005 { out.append(ChopClip(start: cut.end, end: k.end)) }
        }
        manualKeeps = out
    }

    /// MULTI-TAKE (additive, Lewis 18 Aug): the marked segments of one pair,
    /// merged into per-take time ranges. Segments belong to the same take when
    /// the gap between them is under 0.18s — the finest utterance split the
    /// server uses, so a bigger gap can only be a boundary between two takes.
    /// Detection and payload are untouched; this only READS the marks.
    func takeRanges(for pairIdx: Int) -> [(lo: Double, hi: Double)] {
        let marked = segments.filter { $0.pair == pairIdx && $0.retake != nil }
                             .sorted { $0.start < $1.start }
        var out: [(lo: Double, hi: Double)] = []
        for sg in marked {
            if let last = out.last, sg.start - last.hi < 0.18 {
                out[out.count - 1].hi = sg.end
            } else {
                out.append((sg.start, sg.end))
            }
        }
        return out
    }

    func isCut(_ sg: ChopSegment) -> Bool {
        if let m = sg.manual { return m }
        if let take = sg.retake, let p = sg.pair {
            let choice = (p < pairs.count) ? pairs[p].choice : nil
            // MULTI-TAKE pick: "k<i>" keeps ONLY take i of this pair and cuts
            // every other take. Legacy "a"/"b"/"both" behaviour below is
            // byte-identical — fresh 2-take pairs never produce "k" choices.
            if let c = choice, c.hasPrefix("k"), let ki = Int(c.dropFirst()) {
                let ranges = takeRanges(for: p)
                if ki < ranges.count {
                    let r = ranges[ki]
                    return !(sg.start >= r.lo - 0.01 && sg.start <= r.hi + 0.01)
                }
            }
            guard let c = choice, c != "both" else { return false }
            return c == "a" ? (take == "b") : (take == "a")
        }
        if sg.kind == "silence" { return (sg.end - sg.start) >= settings.minSil }
        if sg.kind == "filler"  { return settings.fillers && (!sg.soft || settings.soft) }
        return false
    }

    func cutIntervals() -> [ChopClip] {
        let sp = settings.startPadMs / 1000
        let ep = settings.endPadMs / 1000
        var ivs: [ChopClip] = []
        for sg in segments where isCut(sg) {
            if var last = ivs.last, sg.start <= last.end + 0.001 {
                last.end = max(last.end, sg.end)
                ivs[ivs.count - 1] = last
            } else {
                ivs.append(ChopClip(start: sg.start, end: sg.end))
            }
        }
        var padded: [ChopClip] = []
        for iv in ivs {
            var s = iv.start, e = iv.end
            if iv.start > 0.001 { s = iv.start + ep }
            if iv.end < rawDur - 0.001 { e = iv.end - sp }
            s = max(0, s); e = min(rawDur, e)
            if e - s > 0.005 { padded.append(ChopClip(start: s, end: e)) }
        }
        var merged = padded
        if !manualCuts.isEmpty {
            var all = padded + manualCuts.map { ChopClip(start: max(0, $0.start), end: min(rawDur, $0.end)) }
            all.sort { $0.start < $1.start }
            var out: [ChopClip] = []
            for iv in all {
                if var last = out.last, iv.start <= last.end + 0.001 {
                    last.end = max(last.end, iv.end)
                    out[out.count - 1] = last
                } else { out.append(iv) }
            }
            merged = out
        }
        // manual keeps: footage the creator dragged back out of a cut —
        // it wins over EVERYTHING (silence, filler, retake, manual trim)
        if !manualKeeps.isEmpty {
            var result: [ChopClip] = []
            for iv in merged {
                var pieces = [iv]
                for k in manualKeeps {
                    var next: [ChopClip] = []
                    for p in pieces {
                        if k.end <= p.start + 0.001 || k.start >= p.end - 0.001 { next.append(p); continue }
                        if k.start > p.start + 0.005 { next.append(ChopClip(start: p.start, end: k.start)) }
                        if k.end < p.end - 0.005 { next.append(ChopClip(start: k.end, end: p.end)) }
                    }
                    pieces = next
                }
                result.append(contentsOf: pieces)
            }
            merged = result
        }
        return merged.filter { $0.end - $0.start > 0.005 }
    }

    func keptClips() -> [ChopClip] {
        var clips: [ChopClip] = []
        var pos: Double = 0
        for iv in cutIntervals() {
            if iv.start - pos > 0.01 { clips.append(ChopClip(start: pos, end: iv.start)) }
            pos = iv.end
        }
        if rawDur - pos > 0.01 { clips.append(ChopClip(start: pos, end: rawDur)) }
        return clips
    }
}

// MARK: - API

@MainActor
final class ChopAPI: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var busy = false
    @Published var error = ""
    @Published var note = ""                 // green .anote panel, web parity
    @Published var wantsSignInMode = false   // user_already_exists → flip to Sign in, keep email
    @Published var signedIn = false
    @Published var jobs: [ChopJob] = []
    @Published var credits: Int = 0
    @Published var editorOpen = false   // hides the glass nav while editing
    @Published var openJob: ChopJob?    // set after import → root presents the editor directly
    @Published var goToQueue = false    // approved a video → root flips to the Queue tab
    var localImports: [String: URL] = [:]   // job name → file already on the phone: editor opens with zero download
    var importActive = false                // an upload/analysis is running — background work must stay out of its way
    @Published var profileName = ""
    @Published var profileTiktok = ""
    @Published var profileAvatar = ""

    private(set) var accessToken = ""
    private(set) var userId = ""
    /// Supabase access tokens die after ~1 hour. Every Bearer call — including
    /// the presign that starts an upload — 401s on a stale one, which is
    /// exactly the intermittent "Upload failed" after the app sat open/idle.
    /// We track expiry and proactively re-exchange the refresh token well
    /// before the hour is up (see ensureFreshToken).
    private var tokenExpiresAt = Date.distantPast
    private var tokenRefreshing = false
    func noteTokenLife(_ obj: [String: Any]) {
        let secs = (obj["expires_in"] as? Double) ?? 3600
        tokenExpiresAt = Date().addingTimeInterval(secs)
    }

    /// Web-parity auth error strings — SPEC_02_AUTH.md, do not paraphrase.
    static func mapAuthError(_ raw: String, mode: String) -> String {
        let r = raw.lowercased()
        if r.contains("already registered") || r.contains("user_already_exists") || r.contains("already exists") {
            return "That email already has a Chop account. Sign in instead — your credits are waiting."
        }
        if r.contains("invalid login credentials") || r.contains("invalid_credentials") || r.contains("invalid_grant") {
            return "No account matches that email and password. Check them, or create an account."
        }
        if r.contains("at least 6") || r.contains("password should be") {
            return "Pick a password with at least 6 characters."
        }
        if r.contains("validate email") || r.contains("valid email") || r.contains("invalid email") || (r.contains("email") && r.contains("invalid")) {
            return "That doesn't look like a valid email address."
        }
        if r.contains("rate limit") || r.contains("too many") {
            return "Too many attempts — wait a minute and try again."
        }
        if r.contains("offline") || r.contains("network") || r.contains("timed out") || r.contains("could not connect") || r.contains("cannot connect") {
            return "Couldn't reach the sign-in service — refresh to retry."
        }
        return "That didn't work — try again."
    }

    func signIn(creating: Bool = false) async {
        error = ""; note = ""; busy = true
        defer { busy = false }

        let path = creating ? "\(SB_URL)/auth/v1/signup" : "\(SB_URL)/auth/v1/token"
        guard var comps = URLComponents(string: path) else { return }
        if !creating { comps.queryItems = [URLQueryItem(name: "grant_type", value: "password")] }
        guard let url = comps.url else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(SB_ANON, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "email": email.trimmingCharacters(in: .whitespaces),
            "password": password
        ])

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                error = "Unexpected response"; return
            }
            let rawError = (obj["error_description"] as? String)
                ?? (obj["access_token"] == nil ? (obj["msg"] as? String) ?? (obj["error"] as? String) : nil)
            if let raw = rawError {
                let mapped = ChopAPI.mapAuthError(raw, mode: creating ? "up" : "in")
                error = mapped
                if mapped.hasPrefix("That email already has a Chop account") { wantsSignInMode = true }
                return
            }
            if creating, obj["access_token"] == nil {
                // confirmation-required signup: green note + flip to Sign in (web parity)
                note = "Almost there — check your inbox and confirm your email, then sign in."
                wantsSignInMode = true
                return
            }
            guard let token = obj["access_token"] as? String,
                  let user = obj["user"] as? [String: Any],
                  let uid = user["id"] as? String else {
                error = "That didn't work — try again."; return
            }
            if let rt = obj["refresh_token"] as? String { ChopKeychain.set(rt, "chop-refresh") }
            accessToken = token
            userId = uid
            noteTokenLife(obj)
            signedIn = true
            await loadProfile()
            await loadJobs()
        } catch {
            self.error = "Couldn't reach the sign-in service — refresh to retry."
        }
    }

    /// Silent session restore on launch — the "stay signed in" everyone expects.
    /// Exchanges the Keychain refresh token for a fresh session; a dead or
    /// revoked token just falls back to the sign-in screen.
    @Published var restoring = false
    func restoreSession() async {
        guard !signedIn, let rt = ChopKeychain.get("chop-refresh") else { return }
        restoring = true
        defer { restoring = false }
        guard var comps = URLComponents(string: "\(SB_URL)/auth/v1/token") else { return }
        comps.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        guard let url = comps.url else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(SB_ANON, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": rt])
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = obj["access_token"] as? String,
              let user = obj["user"] as? [String: Any],
              let uid = user["id"] as? String else {
            ChopKeychain.delete("chop-refresh")   // stale — sign in normally
            return
        }
        if let newRT = obj["refresh_token"] as? String { ChopKeychain.set(newRT, "chop-refresh") }
        accessToken = token
        userId = uid
        noteTokenLife(obj)
        signedIn = true
        await loadProfile()
        await loadJobs()
    }

    /// Mid-session token refresh — the fix for the intermittent "Upload failed".
    /// Supabase access tokens last ~1 hour; if the app stays open (or comes back
    /// from the background) past that, presign/putFile and every other Bearer
    /// call 401s. Called on a timer and on foregrounding: when the token is
    /// within 15 minutes of dying, silently exchange the refresh token for a
    /// fresh one. Failure is deliberately quiet — the current token stays, we
    /// retry on the next tick, and we NEVER sign the user out from here (a
    /// network blip must not nuke a session). Single-flight so ticks can't race.
    func ensureFreshToken() async {
        guard signedIn, !tokenRefreshing,
              Date() > tokenExpiresAt.addingTimeInterval(-15 * 60),
              let rt = ChopKeychain.get("chop-refresh") else { return }
        tokenRefreshing = true
        defer { tokenRefreshing = false }
        guard var comps = URLComponents(string: "\(SB_URL)/auth/v1/token") else { return }
        comps.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        guard let url = comps.url else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(SB_ANON, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": rt])
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = obj["access_token"] as? String else { return }
        if let newRT = obj["refresh_token"] as? String { ChopKeychain.set(newRT, "chop-refresh") }
        accessToken = token
        noteTokenLife(obj)
    }

    // MARK: social sign-in --------------------------------------------------
    // Both roads end in the same Supabase session as email sign-in.
    // Requires the providers to be switched on in Supabase → Auth → Providers
    // (Apple: services ID + key · Google: client ID/secret) — flag for Aaron.

    private func adoptSession(token: String, uid: String, refresh: String? = nil) async {
        if let refresh { ChopKeychain.set(refresh, "chop-refresh") }
        accessToken = token
        tokenExpiresAt = Date().addingTimeInterval(3600)   // Supabase default hour
        userId = uid
        signedIn = true
        await loadProfile()
        await loadJobs()
    }

    /// Native Sign in with Apple → exchange the identity token with Supabase.
    func signInWithApple() async {
        error = ""; busy = true
        defer { busy = false }
        do {
            let (idToken, nonce) = try await AppleSignInCoordinator.shared.run()
            guard var comps = URLComponents(string: "\(SB_URL)/auth/v1/token") else { return }
            comps.queryItems = [URLQueryItem(name: "grant_type", value: "id_token")]
            guard let url = comps.url else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue(SB_ANON, forHTTPHeaderField: "apikey")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: [
                "provider": "apple", "id_token": idToken, "nonce": nonce,
            ])
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = obj["access_token"] as? String,
                  let user = obj["user"] as? [String: Any],
                  let uid = user["id"] as? String else {
                error = "Apple sign-in isn't available yet — use email below."
                return
            }
            await adoptSession(token: token, uid: uid,
                               refresh: obj["refresh_token"] as? String)
        } catch is CancellationError {
            // user closed the sheet — say nothing
        } catch let e as ASAuthorizationError where e.code == .canceled {
            // user closed the sheet — say nothing
        } catch {
            self.error = "Apple sign-in isn't available yet — use email below."
        }
    }

    /// Google through Supabase's hosted OAuth in a system web session.
    /// Tokens come back on the chopedit:// callback fragment.
    func signInWithGoogle() async {
        error = ""; busy = true
        defer { busy = false }
        guard let url = URL(string:
            "\(SB_URL)/auth/v1/authorize?provider=google&redirect_to=chopedit://auth-callback")
        else { return }
        do {
            let cb: URL = try await withCheckedThrowingContinuation { cont in
                let s = ASWebAuthenticationSession(url: url, callbackURLScheme: "chopedit") { u, e in
                    if let u { cont.resume(returning: u) }
                    else { cont.resume(throwing: e ?? URLError(.userCancelledAuthentication)) }
                }
                s.presentationContextProvider = WebAuthCoordinator.shared
                s.start()
            }
            var frag: [String: String] = [:]
            for pair in (cb.fragment ?? "").split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 { frag[String(kv[0])] = String(kv[1]) }
            }
            guard let token = frag["access_token"] else {
                error = "Google sign-in isn't available yet — use email below."
                return
            }
            let refresh = frag["refresh_token"]
            // who is this? ask Supabase with the fresh token
            var req = URLRequest(url: URL(string: "\(SB_URL)/auth/v1/user")!)
            req.setValue(SB_ANON, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let uid = obj["id"] as? String else {
                error = "Google sign-in isn't available yet — use email below."
                return
            }
            await adoptSession(token: token, uid: uid, refresh: refresh)
        } catch let e as ASWebAuthenticationSessionError where e.code == .canceledLogin {
            // user closed the sheet — say nothing
        } catch {
            self.error = "Google sign-in isn't available yet — use email below."
        }
    }

    /// A password-reset link from the email opened the app: adopt the
    /// recovery session carried in the URL fragment so updatePassword works.
    /// Signed OUT on purpose — the auth screen's "new password" stage shows.
    func adoptRecovery(token: String, refresh: String?) {
        accessToken = token
        tokenExpiresAt = Date().addingTimeInterval(3600)
        if let refresh { ChopKeychain.set(refresh, "chop-refresh") }
        signedIn = false
    }

    /// Change the account email. Supabase emails a confirmation link to the
    /// new address; the change lands once it's clicked.
    func updateEmail(_ newEmail: String) async -> Bool {
        guard let url = URL(string: "\(SB_URL)/auth/v1/user") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue(SB_ANON, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["email": newEmail])
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    /// Save a new password mid-recovery (mode `new`). PUT /auth/v1/user.
    func updatePassword(_ newPassword: String) async -> Bool {
        guard let url = URL(string: "\(SB_URL)/auth/v1/user") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue(SB_ANON, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["password": newPassword])
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    func loadJobs() async {
        error = ""; busy = true
        defer { busy = false }

        let path = "\(SB_URL)/rest/v1/chop_jobs?select=name,data,ts&user_id=eq.\(userId)&order=ts.desc"
        guard let url = URL(string: path) else { return }

        var req = URLRequest(url: url)
        req.setValue(SB_ANON, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                error = "Couldn't read your jobs"; return
            }
            jobs = rows.compactMap { row in
                guard let name = row["name"] as? String,
                      let d = row["data"] as? [String: Any] else { return nil }
                let payload = d["payload"] as? [String: Any]
                return ChopJob(
                    name: name,
                    status: (d["status"] as? String) ?? "unknown",
                    videoKey: d["videoKey"] as? String,
                    rawSec: (d["rawSec"] as? Double) ?? 0,
                    editedSec: (d["editedSec"] as? Double) ?? 0,
                    hasAnalysis: (payload?["segments"] as? [[String: Any]])?.isEmpty == false,
                    data: d
                )
            }
            // 7-day Downloaded clean-up — once per session, out of imports' way
            if !cleanedOldDownloads, !importActive {
                Task { await self.cleanOldDownloads() }
            }
            // any card still missing a preview frame? fill it in quietly —
            // but NEVER while an import is running (it would fight the audio
            // upload for bandwidth and slow the whole edit down), and never
            // retry a job we already attempted this session
            if !backfillingThumbs, !importActive,
               jobs.contains(where: { $0.thumbnail == nil
                   && !thumbBackfillAttempted.contains($0.name)
                   && (($0.data["proxyKey"] as? String) ?? $0.videoKey) != nil }) {
                Task { await self.backfillThumbs() }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// One-time backfill: any job saved without a preview frame (all the
    /// pre-existing ones) gets a real frame pulled from its cloud copy and
    /// written back to the row — so the grid stops showing placeholders and
    /// the web app benefits too. AVAssetImageGenerator streams just the bytes
    /// it needs over HTTP; it does not download the whole video.
    private var backfillingThumbs = false
    private var thumbBackfillAttempted = Set<String>()   // once per job per session — no retry storms
    func backfillThumbs() async {
        guard !backfillingThumbs, !importActive else { return }
        backfillingThumbs = true
        defer { backfillingThumbs = false }
        var wroteAny = false
        for job in jobs where job.thumbnail == nil {
            if importActive { break }   // an import just started — get out of its way
            guard !thumbBackfillAttempted.contains(job.name) else { continue }
            thumbBackfillAttempted.insert(job.name)
            guard let key = (job.data["proxyKey"] as? String) ?? job.videoKey,
                  let signed = await presignGet(key) else { continue }
            let asset = AVURLAsset(url: signed)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 540, height: 540)
            let dur = CMTimeGetSeconds((try? await asset.load(.duration)) ?? .zero)
            let t = CMTime(seconds: dur > 2 ? 1.0 : max(0.1, dur * 0.25), preferredTimescale: 600)
            guard let cg = try? await gen.image(at: t).image,
                  let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.55) else { continue }
            var d = job.data
            d["thumb"] = "data:image/jpeg;base64," + jpeg.base64EncodedString()
            guard let url = URL(string: "\(SB_URL)/rest/v1/chop_jobs?user_id=eq.\(userId)&name=eq.\(job.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? job.name)") else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "PATCH"
            req.setValue(SB_ANON, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["data": d])
            _ = try? await URLSession.shared.data(for: req)
            wroteAny = true
        }
        if wroteAny { await loadJobs() }
    }

    /// Signed DELETE URL — used only by the 7-day Downloaded clean-up.
    func presignDelete(_ key: String) async -> URL? {
        guard let url = URL(string: "\(SB_URL)/functions/v1/ai-edit") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(SB_ANON, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["action": "presign_delete", "key": key])
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let s = obj["url"] as? String else { return nil }
        return URL(string: s)
    }

    /// 7-day rule: anything sitting in Downloaded for over a week is removed —
    /// cloud files first, then the row — so storage and the app stay clean.
    /// Runs once per session, never while an import is busy.
    private var cleanedOldDownloads = false
    func cleanOldDownloads() async {
        guard !cleanedOldDownloads else { return }
        cleanedOldDownloads = true
        let cutoff = Date().timeIntervalSince1970 * 1000 - 7 * 24 * 3600 * 1000
        var removedAny = false
        for job in jobs where job.status == "exported" || job.status == "downloaded" {
            guard let ms = job.data["statusAt"] as? Double, ms < cutoff else { continue }
            for key in [job.videoKey, job.data["proxyKey"] as? String].compactMap({ $0 }) {
                if let del = await presignDelete(key) {
                    var req = URLRequest(url: del)
                    req.httpMethod = "DELETE"
                    _ = try? await URLSession.shared.data(for: req)
                }
            }
            guard let url = URL(string: "\(SB_URL)/rest/v1/chop_jobs?user_id=eq.\(userId)&name=eq.\(job.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? job.name)") else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "DELETE"
            req.setValue(SB_ANON, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: req)
            removedAny = true
        }
        if removedAny { await loadJobs() }
    }

    /// Ask the existing ai-edit edge function for a signed R2 URL.
    func presignGet(_ key: String) async -> URL? {
        guard let url = URL(string: "\(SB_URL)/functions/v1/ai-edit") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(SB_ANON, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["action": "presign_get", "key": key])
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let s = obj["url"] as? String else { return nil }
            return URL(string: s)
        } catch { return nil }
    }

    private func edge(_ body: [String: Any]) async -> [String: Any]? {
        guard let url = URL(string: "\(SB_URL)/functions/v1/ai-edit") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue(SB_ANON, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch { return nil }
    }

    /// Signed PUT target for a new upload. Returns (uploadUrl, key).
    func presignPut(filename: String) async -> (URL, String)? {
        guard let o = await edge(["action": "presign", "filename": filename]),
              let u = o["uploadUrl"] as? String, let k = o["key"] as? String,
              let url = URL(string: u) else { return nil }
        return (url, k)
    }

    // RELIABILITY WRAPPERS (Lewis 18 Aug: "make sure 'Upload failed' doesn't
    // happen again"). The import path had ZERO retries — one transient network
    // blip on the phone, or one 502 while the edge function cold-starts (both
    // observed in today's logs), instantly failed the whole import. These wrap
    // the locked calls with 3 attempts and short backoff (0.8s, then 2s), and
    // refresh the auth token before asking for a presign. The wrapped
    // functions are untouched; a first-attempt success behaves exactly as the
    // old single attempt did — same speed, no extra network when healthy.
    func presignPutRetrying(filename: String) async -> (URL, String)? {
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: attempt == 1 ? 800_000_000 : 2_000_000_000) }
            await ensureFreshToken()
            if let r = await presignPut(filename: filename) { return r }
        }
        return nil
    }
    func putFileRetrying(_ local: URL, to signed: URL) async -> Bool {
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: attempt == 1 ? 800_000_000 : 2_000_000_000) }
            if await putFile(local, to: signed) { return true }
        }
        return false
    }
    func startProcessingRetrying(key: String) async -> String? {
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: attempt == 1 ? 800_000_000 : 2_000_000_000) }
            if let id = await startProcessing(key: key) { return id }
        }
        return nil
    }

    func startProcessing(key: String) async -> String? {
        guard let o = await edge(["action": "process", "key": key]) else { return nil }
        return o["jobId"] as? String
    }

    /// Poll until Deepgram + retake matching are done. Returns the payload.
    func awaitAnalysis(jobId: String) async -> [String: Any]? {
        // 1s polls (was 2s): analysis lands up to a second sooner, same ~8min cap
        for _ in 0..<480 {
            guard let s = await edge(["action": "status", "jobId": jobId]) else { return nil }
            let st = s["status"] as? String
            if st == "done" { return s }
            if st == "error" { return nil }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return nil
    }

    /// Write the job into chop_jobs so the web app sees it too.
    func saveJob(name: String, payload: [String: Any], rawSec: Double, videoKey: String?,
                 thumb: String? = nil) async {
        var data: [String: Any] = [
            "status": "review",
            "payload": payload,
            "rawSec": rawSec,
            "editedSec": 0,
            "statusAt": Int(Date().timeIntervalSince1970 * 1000)
        ]
        if let videoKey = videoKey { data["videoKey"] = videoKey }
        if let thumb = thumb { data["thumb"] = thumb }   // same data-URL format the web stores

        guard let url = URL(string: "\(SB_URL)/rest/v1/chop_jobs") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(SB_ANON, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "user_id": userId, "name": name, "data": data,
            "ts": Int(Date().timeIntervalSince1970 * 1000)
        ])
        _ = try? await URLSession.shared.data(for: req)
    }

    /// Straight PUT of a local file to a signed URL.
    func putFile(_ local: URL, to signed: URL) async -> Bool {
        var req = URLRequest(url: signed)
        req.httpMethod = "PUT"
        req.timeoutInterval = 600
        do {
            let (_, resp) = try await URLSession.shared.upload(for: req, fromFile: local)
            return (resp as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
        } catch { return false }
    }

    /// Credits live on chop_profiles — the same row the web app reads.
    func loadProfile() async {
        let path = "\(SB_URL)/rest/v1/chop_profiles?select=name,credits,tiktok,avatar&id=eq.\(userId)"
        guard let url = URL(string: path) else { return }
        var req = URLRequest(url: url)
        req.setValue(SB_ANON, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        guard let row = rows.first else {
            // No profile row yet (brand-new account): show defaults, never
            // whatever the previous signed-in user left behind.
            profileName = ""; profileTiktok = ""; profileAvatar = ""
            return
        }
        credits = (row["credits"] as? Int) ?? 0
        profileName = (row["name"] as? String) ?? ""
        profileTiktok = (row["tiktok"] as? String) ?? ""
        profileAvatar = (row["avatar"] as? String) ?? ""
    }

    /// One credit per video, same as the web app.
    func spendCredit() async {
        let next = max(0, credits - 1)
        credits = next
        guard let url = URL(string: "\(SB_URL)/rest/v1/chop_profiles?id=eq.\(userId)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue(SB_ANON, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["credits": next])
        _ = try? await URLSession.shared.data(for: req)
    }

    /// Add purchased credits — same chop_profiles row the web app reads,
    /// so the balance syncs to web instantly.
    func addCredits(_ n: Int) async {
        let next = credits + n
        credits = next
        guard let url = URL(string: "\(SB_URL)/rest/v1/chop_profiles?id=eq.\(userId)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue(SB_ANON, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["credits": next])
        _ = try? await URLSession.shared.data(for: req)
    }

    /// Send the reset email — same Supabase endpoint the web app calls, so it
    /// goes out through Resend with the branded template.
    func sendPasswordReset(email: String) async -> Bool {
        // redirect_to = the app's own scheme: tapping the email link bounces
        // through Supabase verify and lands back INSIDE the app with a
        // recovery session, where the "Choose a new password" stage takes over.
        guard let url = URL(string: "\(SB_URL)/auth/v1/recover?redirect_to=chopedit%3A%2F%2Fauth-callback") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(SB_ANON, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email])
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    /// Upload a photo to the avatars bucket, same path the web app writes to.
    /// Returns the public URL to store on the profile.
    func uploadAvatar(_ jpeg: Data) async -> String? {
        let path = "\(userId)/avatar.jpg"
        guard let url = URL(string: "\(SB_URL)/storage/v1/object/avatars/\(path)") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(SB_ANON, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.setValue("true", forHTTPHeaderField: "x-upsert")
        req.httpBody = jpeg
        guard let (_, resp) = try? await URLSession.shared.upload(for: req, from: jpeg),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
        return "\(SB_URL)/storage/v1/object/public/avatars/\(path)?v=\(Int(Date().timeIntervalSince1970))"
    }

    /// Write the profile back — same chop_profiles row the web app uses.
    func saveProfile(name: String, tiktok: String, avatar: String) async -> Bool {
        guard let url = URL(string: "\(SB_URL)/rest/v1/chop_profiles") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(SB_ANON, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "id": userId, "name": name,
            "tiktok": tiktok.replacingOccurrences(of: "@", with: ""),
            "avatar": avatar
        ])
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return false }
        await loadProfile()
        return true
    }

    /// Read-modify-write on a job's data blob — always fetches the FRESH row
    /// first so concurrent writers (edit saves, status moves, video sync,
    /// thumb backfill) can never clobber each other, and SERIALISED per job so
    /// two writers can't interleave their read and write windows either.
    /// Pass NSNull() as a value to delete a key.
    @MainActor private var mergeChains: [String: Task<Void, Never>] = [:]
    @MainActor
    func mergeJobData(_ name: String, fields: [String: Any]) async {
        let prev = mergeChains[name]
        let task = Task { [weak self] in
            await prev?.value
            await self?.performMerge(name, fields: fields)
        }
        mergeChains[name] = task
        await task.value
    }

    private func performMerge(_ name: String, fields: [String: Any]) async {
        let enc = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        guard let getURL = URL(string: "\(SB_URL)/rest/v1/chop_jobs?select=data&user_id=eq.\(userId)&name=eq.\(enc)") else { return }
        var get = URLRequest(url: getURL)
        get.setValue(SB_ANON, forHTTPHeaderField: "apikey")
        get.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let (gd, _) = try? await URLSession.shared.data(for: get),
              let rows = try? JSONSerialization.jsonObject(with: gd) as? [[String: Any]],
              var d = rows.first?["data"] as? [String: Any] else { return }
        for (k, v) in fields {
            if v is NSNull { d.removeValue(forKey: k) } else { d[k] = v }
        }
        guard let url = URL(string: "\(SB_URL)/rest/v1/chop_jobs?user_id=eq.\(userId)&name=eq.\(enc)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue(SB_ANON, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["data": d, "ts": Int(Date().timeIntervalSince1970 * 1000)])
        _ = try? await URLSession.shared.data(for: req)
    }

    /// Move a job to "Ready to export", same as the web app's green Done button.
    func setStatus(_ job: ChopJob, to status: String) async {
        await mergeJobData(job.name, fields: [
            "status": status,
            "statusAt": Int(Date().timeIntervalSince1970 * 1000),
            "savedLater": NSNull(),   // any status move clears the parked badge
        ])
        await loadJobs()
    }

    /// 'Save for later' from the editor's tick sheet — stays in Ready to
    /// review, just wears the blue parked badge so it's distinguishable.
    func setSavedForLater(_ job: ChopJob) async {
        await mergeJobData(job.name, fields: [
            "savedLater": true,
            "statusAt": Int(Date().timeIntervalSince1970 * 1000),
        ])
        await loadJobs()
    }

    /// Apple require in-app account deletion (5.1.1(v)). Same edge function the
    /// web app calls, so the behaviour is identical.
    func deleteAccount() async -> Bool {
        guard let url = URL(string: "\(SB_URL)/functions/v1/chop-delete-account") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(SB_ANON, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (o["ok"] as? Bool) == true else { return false }
        signOut()
        return true
    }

    /// Chop Bot — one round trip to the chop-assist edge function.
    /// Sends the running conversation, gets the next reply back.
    func askAssist(_ messages: [[String: String]]) async -> String? {
        guard let url = URL(string: "\(SB_URL)/functions/v1/chop-assist") else { return nil }
        await ensureFreshToken()
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(SB_ANON, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["messages": messages])
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reply = o["reply"] as? String, !reply.isEmpty else { return nil }
        return reply
    }

    // MARK: local-import persistence (Lewis 20 Aug — the 'no video track' /
    // 'isn't synced yet' fixes). Imports used to live in tmp, which iOS purges
    // and which never survives a relaunch — a filmed video whose background
    // sync hadn't finished then had NO copy anywhere. Now every import is
    // cloned into Documents/chop-imports (APFS copy-on-write = instant) and
    // the map is rebuilt on launch.

    private var importsDir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("chop-imports", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Clone a picked/filmed file into permanent storage; falls back to the
    /// original URL (the old behaviour, byte-identical) if the clone fails.
    func persistImport(_ url: URL, name: String) -> URL {
        let safe = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        let dest = importsDir.appendingPathComponent(safe + ".mp4")
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch { return url }
    }

    /// On launch: re-point localImports at the surviving permanent copies.
    func rebuildLocalImports() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: importsDir,
                                                                       includingPropertiesForKeys: nil) else { return }
        for f in files {
            let stem = f.deletingPathExtension().lastPathComponent
            guard let name = stem.removingPercentEncoding else { continue }
            if localImports[name] == nil { localImports[name] = f }
        }
    }

    /// Foreground pass: any job whose cloud sync never finished (no videoKey)
    /// but whose file is still on the phone gets re-uploaded quietly. This is
    /// what un-sticks 'isn't synced yet' for good.
    private var resyncing = Set<String>()
    func resyncMissing() {
        for job in jobs where job.videoKey == nil {
            let name = job.name
            guard !resyncing.contains(name),
                  let local = localImports[name],
                  FileManager.default.fileExists(atPath: local.path) else { continue }
            resyncing.insert(name)
            Task { [weak self] in
                guard let self else { return }
                defer { self.resyncing.remove(name) }
                guard let (put, key) = await self.presignPutRetrying(filename: "sync-" + name),
                      await self.putFileRetrying(local, to: put) else { return }
                await self.mergeJobData(name, fields: ["videoKey": key])
                await self.loadJobs()
            }
        }
    }

    /// Background imports in flight — the queue shows these as spinner cards
    /// in Ready to review so nothing ever looks lost.
    @Published var pendingImports: [String] = []

    func signOut() {
        ChopKeychain.delete("chop-refresh")   // an explicit sign-out means OUT
        accessToken = ""; userId = ""; signedIn = false; jobs = []; credits = 0
        // Profile state must die with the session — leaving it made a NEW
        // account on the same phone inherit the previous account's avatar
        // (and then save it as its own).
        profileName = ""; profileTiktok = ""; profileAvatar = ""
        password = ""
    }
}

// MARK: - Dashboard artwork + edit cards (web parity)

/// The web drop-zone cloud: app/index.html line 943, 24×24 viewBox.
struct DropCloudIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24.0
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        var p = Path()
        // cloud outline (approximation of the two-arc path)
        p.move(to: pt(7, 18.5))
        p.addCurve(to: pt(7.9, 9.6), control1: pt(2.6, 18.5), control2: pt(2.9, 10.4))
        p.addCurve(to: pt(18.6, 11), control1: pt(9.6, 5.0), control2: pt(16.6, 5.8))
        p.addCurve(to: pt(18, 18.5), control1: pt(22.2, 11.8), control2: pt(21.6, 18.5))
        p.addLine(to: pt(7, 18.5))
        // up arrow
        p.move(to: pt(12, 15.8)); p.addLine(to: pt(12, 10.8))
        p.move(to: pt(9.4, 13.4)); p.addLine(to: pt(12, 10.8)); p.addLine(to: pt(14.6, 13.4))
        return p
    }
}

/// .ecard — thumbnail card in the "Your edits" grid.
struct EditCard: View {
    let job: ChopJob

    private var thumb: UIImage? {
        guard let s = job.data["thumb"] as? String, s.hasPrefix("data:image"),
              let comma = s.firstIndex(of: ","),
              let d = Data(base64Encoded: String(s[s.index(after: comma)...])) else { return nil }
        return UIImage(data: d)
    }
    private func fmt(_ sec: Double) -> String {
        let t = Int(sec.rounded()); return "\(t / 60):" + String(format: "%02d", t % 60)
    }

    /// Same buckets as the Queue tab, worn as a little badge on the card.
    private var stage: (label: String, tint: Color) {
        switch job.status {
        case "queued", "processing": return ("PROCESSING", ChopColor.muted)
        case "review", "error":      return ("TO REVIEW", ChopColor.blue)
        case "approved":             return ("READY TO EXPORT", ChopColor.green)
        default:                     return ("DOWNLOADED", Color.black.opacity(0.72))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Fixed-ratio cell — the image can never stretch the card (the old
            // .fill ratio let tall frames blow the whole grid apart).
            Color.clear
                .aspectRatio(9.0/13.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    if let img = thumb {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        ZStack {
                            LinearGradient(colors: [Color(red: 0.16, green: 0.19, blue: 0.26),
                                                    Color(red: 0.09, green: 0.10, blue: 0.14)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                            AuthIcon(kind: .filmstrip)
                                .stroke(Color.white.opacity(0.45),
                                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                                .frame(width: 24, height: 24)
                                .frame(width: 46, height: 46)
                                .background(Color.white.opacity(0.08), in: Circle())
                        }
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if job.rawSec > 0 {
                        Text(fmt(job.editedSec > 0 ? job.editedSec : job.rawSec))
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.black.opacity(0.55), in: Capsule())
                            .padding(8)
                    }
                }
                .overlay(alignment: .topLeading) {
                    Text(stage.label)
                        .font(.system(size: 8.5, weight: .heavy))
                        .kerning(0.4)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3.5)
                        .background(stage.tint, in: Capsule())
                        .padding(8)
                }
                .clipped()

            VStack(alignment: .leading, spacing: 2) {
                Text(job.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ChopColor.ink)
                    .lineLimit(1)
                Text(job.rawSec > 0 ? "\(fmt(job.rawSec)) → \(fmt(job.editedSec))" : "—")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ChopColor.muted)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(ChopColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ChopColor.line, lineWidth: 1))
    }
}

// MARK: - Auth artwork (web SVG paths, not SF Symbols — SPEC_02_AUTH)

/// The four benefit icons from app/index.html lines 824–827, redrawn as Paths
/// in a 24×24 space and scaled to the frame.
struct AuthIcon: Shape {
    enum Kind { case scissors, filmstrip, download, bolt }
    let kind: Kind

    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24.0
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        var p = Path()
        switch kind {
        case .scissors:
            p.addEllipse(in: CGRect(x: (6 - 2.4) * s, y: (6.5 - 2.4) * s, width: 4.8 * s, height: 4.8 * s))
            p.addEllipse(in: CGRect(x: (6 - 2.4) * s, y: (17.5 - 2.4) * s, width: 4.8 * s, height: 4.8 * s))
            p.move(to: pt(8, 8.1));  p.addLine(to: pt(19.5, 19))
            p.move(to: pt(8, 15.9)); p.addLine(to: pt(19.5, 5))
        case .filmstrip:
            p.addRoundedRect(in: CGRect(x: 3 * s, y: 4.5 * s, width: 18 * s, height: 15 * s),
                             cornerSize: CGSize(width: 2 * s, height: 2 * s))
            p.move(to: pt(3, 9.5));   p.addLine(to: pt(21, 9.5))
            p.move(to: pt(7.2, 4.5)); p.addLine(to: pt(9.2, 9.5))
            p.move(to: pt(12, 4.5));  p.addLine(to: pt(14, 9.5))
            p.move(to: pt(16.8, 4.5)); p.addLine(to: pt(18.8, 9.5))
        case .download:
            p.move(to: pt(12, 4));   p.addLine(to: pt(12, 14.5))
            p.move(to: pt(8, 10.5)); p.addLine(to: pt(12, 14.5)); p.addLine(to: pt(16, 10.5))
            p.move(to: pt(5, 19.5)); p.addLine(to: pt(19, 19.5))
        case .bolt:
            p.move(to: pt(13, 2.5)); p.addLine(to: pt(5.5, 13.5)); p.addLine(to: pt(11, 13.5))
            p.addLine(to: pt(10, 21.5)); p.addLine(to: pt(18.5, 10.5)); p.addLine(to: pt(13, 10.5))
            p.closeSubpath()
        }
        return p
    }
}

/// 44px grid at 9% white — the web panel's ::before overlay.
// MARK: - Onboarding (3 slides → Get started → welcome)

struct ChopOnboardingView: View {
    let done: () -> Void
    var startPage = 0            // debug screenshots of slides 2/3
    @State private var page = 0
    @State private var loop = false

    var body: some View {
        VStack(spacing: 0) {
            ChopWordmark(size: 34)
                .padding(.top, 58)

            TabView(selection: $page) {
                slide(tag: "Your video, edited in 15 seconds",
                      headline: "Don't edit,", em: "just film.",
                      prop: AnyView(stripProp)).tag(0)
                slide(tag: nil,
                      headline: "Mess up?", em: "Say it again.",
                      prop: AnyView(retakeProp)).tag(1)
                slide(tag: nil,
                      headline: "Post more.", em: "Edit nothing.",
                      prop: AnyView(exportProp)).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(i == page ? ChopColor.ink : ChopColor.ink.opacity(0.22))
                        .frame(width: i == page ? 22 : 7, height: 7)
                }
            }
            .animation(.spring(response: 0.35), value: page)
            .padding(.bottom, 20)

            Button(action: done) {
                Text("Get started")
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 18))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 38)
        }
        .background(ChopColor.bg.ignoresSafeArea())
        .onAppear { if startPage > 0 { page = startPage } }
        .onChange(of: startPage) { _, v in page = v }
    }

    /// The slides live inside a UIPageViewController-backed TabView whose pages
    /// mount AFTER the container's onAppear — so a single `loop = true` fired
    /// there lands before any animated view exists. The pages then mount with
    /// loop already true, never observe a change, and every "looping" prop
    /// renders frozen at its end state (what Lewis saw on device). Each slide
    /// now kicks the trigger when IT appears: drop to false, flip to true on
    /// the next runloop tick, and every mounted prop sees a fresh change and
    /// starts its repeatForever. Swiping back to a slide just restarts the
    /// loops, which is the intended feel anyway.
    private func kickLoop() {
        loop = false
        DispatchQueue.main.async { loop = true }
    }

    private func slide(tag: String?, headline: String, em: String, prop: AnyView) -> some View {
        VStack(spacing: 0) {
            if let tag {
                Text(tag)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(ChopColor.muted)
                    .padding(.top, 16)
            }
            Spacer()
            prop
                .onAppear { kickLoop() }
            Spacer()
            VStack(spacing: -7) {   // tight, wordmark-style leading
                Text(headline)
                    .foregroundStyle(ChopColor.ink)
                Text(em)
                    .foregroundStyle(ChopColor.blue)
            }
            .font(.system(size: 38, weight: .black))
            .kerning(-1.2)
            .multilineTextAlignment(.center)
            .padding(.bottom, 26)
        }
        .padding(.horizontal, 24)
    }

    // slide 1: real creator footage + the timeline cutting itself, live
    private var stripProp: some View {
        VStack(spacing: 0) {
            // the affiliate, filming — real frame in a floating card
            ZStack(alignment: .topLeading) {
                Image("HeroStill")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 208)
                    .offset(y: -34)   // crop the TikTok caption out of frame
                    .frame(width: 208, height: 246)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                HStack(spacing: 5) {
                    Circle().fill(Color(red: 1, green: 0.28, blue: 0.34))
                        .frame(width: 8, height: 8)
                        .opacity(loop ? 1 : 0.25)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: loop)
                    Text("FILMING").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                }
                .padding(.leading, 12).padding(.top, 12)
            }
            .background(RoundedRectangle(cornerRadius: 20).fill(Color.white)
                .padding(-8)
                .shadow(color: .black.opacity(0.16), radius: 22, y: 12))
            .rotationEffect(.degrees(loop ? -1.6 : -0.4))
            .animation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true), value: loop)
            .zIndex(1)

            // the strip pinned under it — the red cut section CLOSES on a loop
            HStack(spacing: 0) {
                footageBlock(a: .leading, w: 76)
                // the doomed section: red-tinted, collapses to nothing
                ZStack {
                    footageBlock(a: .center, w: 40)
                        .saturation(0.2).brightness(-0.15)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(ChopColor.violet.opacity(0.45))
                    Image(systemName: "scissors")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                }
                .frame(width: loop ? 0 : 40, height: 52)
                .clipped()
                .opacity(loop ? 0 : 1)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true).delay(0.6), value: loop)
                // cut badge sits on the join
                cutBadge
                footageBlock(a: .center, w: 96)
                cutBadge
                footageBlock(a: .trailing, w: 70)
            }
            .padding(.top, 18)

            (Text("This video: ").font(.system(size: 13, weight: .bold)).foregroundStyle(ChopColor.muted)
            + Text("−38% shorter").font(.system(size: 13, weight: .heavy)).foregroundStyle(ChopColor.green)
            + Text(" · nothing cut without you").font(.system(size: 13, weight: .bold)).foregroundStyle(ChopColor.muted))
                .padding(.top, 12)
        }
    }

    /// a window into the real footage frame, like the editor's filmstrip
    private func footageBlock(a: Alignment, w: CGFloat) -> some View {
        Image("HeroStill")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: w, height: 52, alignment: a)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            .padding(.horizontal, 1)
    }

    private var cutBadge: some View {
        Image(systemName: "arrowtriangle.right.and.line.vertical.and.arrowtriangle.left.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color(white: 0.12))
            .frame(width: 24, height: 24)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
            .zIndex(2)
            .padding(.horizontal, -10)
    }

    // slide 2: the retake decision
    private var retakeProp: some View {
        VStack(spacing: 12) {
            takeCard(label: "TAKE 1 · first attempt · 2.6s",
                     quote: "“Because as somebody who has struggled with hair—”",
                     pick: false)
                .opacity(loop ? 0.45 : 1)
                .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: loop)
            takeCard(label: "TAKE 2 · final attempt · 7.4s",
                     quote: "“Because as somebody who has struggled with hair thinning for years…”",
                     pick: true)
        }
        .padding(.horizontal, 6)
    }

    private func takeCard(label: String, quote: String, pick: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text(label).font(.system(size: 11.5, weight: .heavy)).foregroundStyle(ChopColor.ink)
                if pick {
                    Text("AI pick").font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(ChopColor.blue)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(ChopColor.blueSoft, in: RoundedRectangle(cornerRadius: 6))
                }
                Spacer()
            }
            Text(quote)
                .font(.custom("Georgia", size: 14.5))
                .foregroundStyle(ChopColor.ink)
                .strikethrough(!pick, color: ChopColor.violet)
            if pick {
                Text("Keep this take")
                    .font(.system(size: 13.5, weight: .heavy)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(ChopColor.blue, in: RoundedRectangle(cornerRadius: 11))
            }
        }
        .padding(13)
        .background(ChopColor.card, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15)
            .stroke(pick ? ChopColor.blue.opacity(0.4) : ChopColor.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.07), radius: 14, y: 8)
    }

    // slide 3: the export finishing itself
    private var exportProp: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(colors: [Color(white: 0.26), Color(white: 0.16)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 46, height: 66)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Serum review.mp4").font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(ChopColor.ink)
                        Text("1:42 → 1:04 · 12 cuts made")
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(ChopColor.muted)
                    }
                    Spacer()
                }
                ZStack {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7).tint(ChopColor.blue)
                        Text("Exporting…").font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(ChopColor.muted)
                        Spacer()
                    }
                    .opacity(loop ? 0 : 1)
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy))
                        Text("Saved to camera roll").font(.system(size: 13.5, weight: .heavy))
                        Spacer()
                    }
                    .foregroundStyle(ChopColor.green)
                    .opacity(loop ? 1 : 0)
                }
                .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: loop)
            }
            .padding(14)
            .background(ChopColor.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(ChopColor.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.07), radius: 16, y: 9)

            HStack(spacing: 9) {
                ForEach(["TikTok", "Reels", "Shorts"], id: \.self) { t in
                    Text(t).font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(ChopColor.ink, in: Capsule())
                }
            }
        }
        .padding(.horizontal, 10)
    }

    private func onboardChip(_ t: String, bg: Color, fg: Color) -> some View {
        Text(t).font(.system(size: 12, weight: .heavy)).foregroundStyle(fg)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(bg, in: Capsule())
    }
}

// MARK: social sign-in plumbing

/// Runs the native Sign in with Apple sheet and returns (identityToken, rawNonce).
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate,
                                    ASAuthorizationControllerPresentationContextProviding {
    static let shared = AppleSignInCoordinator()
    private var cont: CheckedContinuation<(String, String), Error>?
    private var rawNonce = ""

    func run() async throws -> (String, String) {
        try await withCheckedThrowingContinuation { c in
            cont = c
            rawNonce = UUID().uuidString + UUID().uuidString
            let hashed = SHA256.hash(data: Data(rawNonce.utf8))
                .map { String(format: "%02x", $0) }.joined()
            let req = ASAuthorizationAppleIDProvider().createRequest()
            req.requestedScopes = [.email]
            req.nonce = hashed
            let ctrl = ASAuthorizationController(authorizationRequests: [req])
            ctrl.delegate = self
            ctrl.presentationContextProvider = self
            ctrl.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization auth: ASAuthorization) {
        guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
              let data = cred.identityToken,
              let token = String(data: data, encoding: .utf8) else {
            cont?.resume(throwing: URLError(.badServerResponse)); cont = nil; return
        }
        cont?.resume(returning: (token, rawNonce)); cont = nil
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        cont?.resume(throwing: error); cont = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }
}

/// Presentation anchor for the Google web session.
final class WebAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthCoordinator()
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }
}

/// Clean, near-invisible backdrop: white page with the faintest breathing
/// blue glow up top (a touch stronger in dark mode).
struct AuthBackdrop: View {
    @State private var drift = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            ChopColor.bg.ignoresSafeArea()
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                Circle()
                    .fill(ChopColor.blue.opacity(scheme == .dark ? 0.14 : 0.05))
                    .frame(width: w * 1.4)
                    .blur(radius: 70)
                    .offset(y: drift ? -h * 0.5 : -h * 0.42)
                    .animation(.easeInOut(duration: 9).repeatForever(autoreverses: true), value: drift)
            }
        }
        .ignoresSafeArea()
        .onAppear { drift = true }
        .allowsHitTesting(false)
    }
}

struct AuthGridOverlay: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x: CGFloat = 44
        while x < rect.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: rect.height)); x += 44 }
        var y: CGFloat = 44
        while y < rect.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: rect.width, y: y)); y += 44 }
        return p
    }
}

// MARK: - UI

struct ChopRootView: View {
    @StateObject private var api = ChopAPI()
    @Environment(\.scenePhase) private var scenePhase   // token refresh on foreground
    @State private var importMode = 0   // 0 = one video · 1 = bulk (each edited separately) · 2 = combine (stitched into one)
    @State private var showImport = false
    @State private var showImportPicker = false            // photo library, straight from the dashboard
    @State private var importPicks: [PhotosPickerItem] = []
    @State private var showSettings = false
    @State private var showBilling = false
    @State private var showProfileMenu = false   // avatar pop-out (web parity)
    @State private var showAssist = false        // Chop Bot chat sheet
    @State private var showFilm = false          // in-app camera (red ⊕)
    @State private var demoJob: ChopJob? = nil   // -screen editor design preview
    @AppStorage("chopTourSeen") private var tourSeen = false
    @State private var showTour = false          // one-time app tour

    /// Fake processed job pointing at a local test video — design preview only.
    static func makeDemoJob() -> ChopJob {
        func seg(_ s: Double, _ e: Double, _ k: String, text: String = "",
                 retake: String? = nil, pair: Int? = nil, soft: Bool = false) -> [String: Any] {
            var d: [String: Any] = ["start": s, "end": e, "kind": k, "soft": soft]
            if !text.isEmpty { d["text"] = text }
            if let retake { d["retake"] = retake }
            if let pair { d["pair"] = pair }
            return d
        }
        let segments: [[String: Any]] = [
            seg(0, 2.5, "speech", text: "Okay so this is the demo clip for the native editor"),
            seg(2.5, 3.8, "silence"),
            seg(3.8, 4.2, "filler", text: "um"),
            seg(4.2, 9.0, "speech", text: "This serum has honestly changed my whole routine", retake: "a", pair: 0),
            seg(9.0, 10.2, "silence"),
            seg(10.2, 16.0, "speech", text: "This serum has genuinely changed my entire routine", retake: "b", pair: 0),
            seg(16.0, 17.0, "silence"),
            seg(17.0, 24.0, "speech", text: "You only need two drops morning and night"),
            seg(24.0, 25.4, "silence"),
            seg(25.4, 32.0, "speech", text: "And it absorbs in seconds with zero sticky feeling"),
            seg(32.0, 33.0, "silence"),
            seg(33.0, 40.0, "speech", text: "Grab it from the link below while the sale is on"),
            seg(40.0, 41.5, "silence"),
            seg(41.5, 48.0, "speech", text: "Honestly the glow is unreal after a week"),
            seg(48.0, 49.0, "silence"),
            seg(49.0, 56.0, "speech", text: "That's it — don't forget to follow for more"),
            seg(56.0, 60.0, "silence"),
        ]
        let payload: [String: Any] = [
            "segments": segments,
            "pairs": [["sim": 0.88, "weak": false]],
        ]
        return ChopJob(name: "Demo footage.mp4", status: "review", videoKey: nil,
                       rawSec: 60, editedSec: 0, hasAnalysis: true,
                       data: ["payload": payload, "demoPath": "/tmp/chop-demo.mp4"])
    }
    @State private var showOOC = false
    @State private var tab = 0
    @State private var showAuth = false
    @State private var authMode = 0
    @State private var authStage = 0   // 0 auth · 1 reset · 2 new password
    @State private var newPassword = ""
    @State private var authAppeared = false   // entrance animation
    @State private var authGlow = false       // logo breathing glow
    @State private var authIntro = true       // Flow-style welcome before the form
    @State private var seenIntro = UserDefaults.standard.bool(forKey: "chopSeenIntro")
    @State private var introStart = 0   // debug: jump to slide 2/3 for screenshots
    @State private var theme = ChopTheme.current

    var body: some View {
        Group {
            if api.signedIn {
                app
            } else if api.restoring {
                // silent session restore — a beat of brand, never the sign-in flash
                ZStack {
                    Color.chopBg.ignoresSafeArea()
                    ChopWordmark(size: 40)
                }
            } else if !seenIntro {
                // first open: the 3-slide story, then Get started → welcome
                ChopOnboardingView(done: {
                    UserDefaults.standard.set(true, forKey: "chopSeenIntro")
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { seenIntro = true }
                }, startPage: introStart)
            } else {
                NavigationStack { signIn.background(Color.chopBg) }
            }
        }
        .task { await api.restoreSession() }   // stay signed in across launches
        // Keep the hour-limited Supabase token alive for as long as the app is:
        // a re-check every 10 minutes plus one on every return to foreground.
        // This is what stops presign 401ing into "Upload failed" after the app
        // sat open past the token's 1-hour life. No effect on the import path —
        // it just always finds a valid token waiting.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 600 * 1_000_000_000)
                await api.ensureFreshToken()
            }
        }
        .onChange(of: scenePhase) { _, p in
            if p == .active {
                Task { await api.ensureFreshToken() }
                api.resyncMissing()   // finish any interrupted cloud syncs
            }
        }
        .task { api.rebuildLocalImports() }   // survive relaunches
        // Password-reset links (chopedit://auth-callback#access_token=…&type=recovery)
        // open the app here. Adopt the recovery session and jump straight to
        // the "Choose a new password" stage.
        .onOpenURL { url in
            guard url.scheme == "chopedit" else { return }
            var frag: [String: String] = [:]
            for pair in (url.fragment ?? "").split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 { frag[String(kv[0])] = String(kv[1]) }
            }
            guard frag["type"] == "recovery" || frag["type"] == "magiclink",
                  let token = frag["access_token"] else { return }
            api.adoptRecovery(token: token, refresh: frag["refresh_token"])
            seenIntro = true
            authIntro = false
            authStage = 2
            newPassword = ""
            api.error = ""; api.note = ""
        }
        .preferredColorScheme(theme.scheme)
        .tint(ChopColor.blue)
        .chopToasts()
        .onAppear {
            // debug-only: `simctl launch … -screen auth|auth-up|auth-reset` jumps
            // straight to a screen so the review loop can screenshot it
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-screen"), i + 1 < args.count {
                switch args[i + 1] {
                case "intro":      seenIntro = false
                case "intro-2":    seenIntro = false; introStart = 1
                case "intro-3":    seenIntro = false; introStart = 2
                case "auth":       seenIntro = true   // welcome page
                case "auth-in":    seenIntro = true; authIntro = false; authMode = 0
                case "auth-up":    seenIntro = true; authIntro = false; authMode = 1
                case "auth-reset": seenIntro = true; authIntro = false; authStage = 1
                case "dash":       api.signedIn = true; api.profileName = "Lewis"; api.credits = 169
                case "queue":      api.signedIn = true; api.profileName = "Lewis"; api.credits = 169; tab = 1
                case "lab":        api.signedIn = true; api.profileName = "Lewis"; api.credits = 169; tab = 2
                case "proc":       api.signedIn = true; api.profileName = "Lewis"; api.credits = 169; showImport = true
                case "settings":   api.signedIn = true; api.profileName = "Lewis"; api.credits = 169; showSettings = true
                case "billing":    api.signedIn = true; api.profileName = "Lewis"; api.credits = 169; showBilling = true
                case let s where s.hasPrefix("editor"):
                    api.signedIn = true; api.profileName = "Lewis"; api.credits = 169
                    demoJob = ChopRootView.makeDemoJob()
                default: break
                }
            }
        }
    }

    private var reviewCount: Int {
        api.jobs.filter { $0.status == "review" }.count
    }

    private var app: some View {
        ZStack(alignment: .bottom) {
            NavigationStack {
                VStack(spacing: 0) {
                    chopHeader
                    Divider().overlay(Color.chopLine)
                    ZStack {
                        Color.chopBg.ignoresSafeArea()
                        switch tab {
                        case 1: ChopQueueBody(api: api)
                        case 2: ChopLabBody()
                        default: jobList
                        }
                    }
                }
                .background(Color.chopBg)
                .toolbar(.hidden, for: .navigationBar)
                // Dashboard upload → photo library immediately; the processing
                // sheet only appears once videos are actually picked.
                // preferredItemEncoding .current (Lewis 18 Aug, upload speed):
                // the default encoding makes iOS TRANSCODE 4K HEVC to H.264
                // compatibility format before handing the file over — minutes
                // of silent work on a 3-min clip, all spent before our pipeline
                // even starts, posing as "Uploading". .current hands over the
                // original file untouched: no transcode, and the background
                // 4K sync uploads the smaller HEVC file too. AVFoundation
                // reads HEVC natively, so audio extract/thumb/export are
                // unaffected.
                // Selection caps (Lewis 19 Aug): Single 1 · Bulk 30 · Combine 30.
                .photosPicker(isPresented: $showImportPicker, selection: $importPicks,
                              maxSelectionCount: importMode == 0 ? 1 : 30,
                              matching: .videos,
                              preferredItemEncoding: .current)
                .onChange(of: importPicks) { _, items in
                    guard !items.isEmpty else { return }
                    showImport = true
                }
                .sheet(isPresented: $showImport, onDismiss: { importPicks = [] }) {
                    ImportSheet(api: api, initialPicks: importPicks, stitch: importMode == 2)
                }
                .sheet(isPresented: $showSettings) { ChopSettingsView(api: api) { theme = $0 } }
                .sheet(isPresented: $showBilling) { ChopBillingView(api: api) }
                .sheet(isPresented: $showAssist) {
                    ChopBotChat(api: api)
                        .presentationDetents([.fraction(0.8), .large])
                        .presentationDragIndicator(.visible)
                }
                .fullScreenCover(isPresented: $showFilm) {
                    ChopCameraView(api: api)
                }
                .fullScreenCover(item: $demoJob) { j in
                    NavigationStack { ChopPlayerScreen(job: j, api: api) }
                }
                .fullScreenCover(item: $api.openJob) { j in   // straight-to-editor after import
                    NavigationStack { ChopPlayerScreen(job: j, api: api) }
                }
                .sheet(isPresented: $showOOC) { OutOfCreditsSheet() }
                .onChange(of: api.credits) { _, c in if c <= 0 && api.signedIn { showOOC = true } }
                .onChange(of: api.goToQueue) { _, go in
                    // approved in the editor → land on the Queue tab, next video ready
                    if go { tab = 1; api.goToQueue = false }
                }
                .refreshable { await api.loadJobs() }
            }
            if !api.editorOpen {   // web: no Home/Queue/Cuts pill inside the editor
                // V1 bar (Lewis 20 Aug): red ⊕ film button centre, Bot in-bar
                ChopGlassNav(tab: $tab, queueCount: reviewCount,
                             film: { showFilm = true },
                             bot: { showAssist = true })
                    .padding(.horizontal, 14)
                    .padding(.bottom, 2)   // sit just above the home indicator
            }
        }
        // first-launch tour: spotlights on the real controls, short and sharp
        .chopCoach(steps: ChopRootView.tourSteps, active: $showTour)
        .onAppear { if !tourSeen { showTour = true } }
        .onChange(of: showTour) { _, on in if !on { tourSeen = true } }
        .onChange(of: tourSeen) { _, seen in if !seen { showTour = true } }   // Settings → Replay
    }

    static let tourSteps: [ChopCoachStep] = [
        .init(id: "tour-upload",
              title: "Start here",
              text: "Tap, pick a video from your library, and Chop cuts the dead air, filler words and retakes automatically — then drops you straight into the editor."),
        .init(id: "tour-queue",
              title: "Your production line",
              text: "Every video moves through here: Processing → Review → Ready to export → Downloaded. Use Select to export several at once."),
        .init(id: "tour-lab",
              title: "The Cut Lab",
              text: "Your default cutting style — how long a pause survives, filler words, clip pads, one-tap presets. Every new video starts from these settings."),
        .init(id: "tour-credits",
              title: "Credits",
              text: "One credit edits one video, up to 10 minutes. Top up here. Next: open any video and the editor gives you the same quick pointers on its buttons."),
    ]

    private var signIn: some View {
        ZStack {
            AuthBackdrop()   // clean white with a whisper of blue
            if authIntro {
                authIntroView
            } else {
                signInContent
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: authIntro)
    }

    /// The Whisperflow welcome, one for one: wordmark up top, serif title split
    /// over two lines mid-page, Google + Apple buttons, More options, legal.
    private var authIntroView: some View {
        VStack(spacing: 0) {
            ChopWordmark(size: 38)
                .padding(.top, 66)

            Spacer()

            (Text("Get 10 minutes of editing,\ndone in ")
             + Text("15 seconds").foregroundColor(ChopColor.blue))
                .font(.custom("Georgia", size: 31))
                .foregroundStyle(ChopColor.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(7)
                .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 13) {
                Button {
                    Task { await api.signInWithGoogle() }
                } label: {
                    HStack(spacing: 10) {
                        Text("G")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                        Text("Continue with Google")
                            .font(.system(size: 17.5, weight: .bold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 17)
                    .background(ChopColor.card, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20)
                        .stroke(ChopColor.ink.opacity(0.7), lineWidth: 1.5))
                    .foregroundStyle(ChopColor.ink)
                }
                Button {
                    Task { await api.signInWithApple() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "applelogo").font(.system(size: 18, weight: .semibold))
                        Text("Continue with Apple")
                            .font(.system(size: 17.5, weight: .bold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 17)
                    .background(Color(red: 0.16, green: 0.17, blue: 0.20),
                                in: RoundedRectangle(cornerRadius: 20))
                    .foregroundStyle(.white)
                }
                Button {
                    authMode = 0; authIntro = false   // email lives behind More options
                } label: {
                    Text("More options")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(ChopColor.ink)
                        .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 22)

            if !api.error.isEmpty {
                Text(api.error)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(ChopColor.rose)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24).padding(.top, 4)
            }

            Text("By continuing, you acknowledge that you have read\nand agreed to our Terms of Service and Privacy Policy.")
                .font(.system(size: 12.5))
                .foregroundStyle(ChopColor.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
                .padding(.bottom, 36)
        }
    }

    private var signInContent: some View {
        ScrollView {
            VStack(spacing: 16) {

                // back to the welcome screen
                HStack {
                    Button {
                        authIntro = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold))
                            Text("Back").font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(ChopColor.muted)
                    }
                    Spacer()
                }
                .padding(.top, 16)

                // ---- the auth card (web .authform: card bg, 1px line, r20, 26×24) ----
                VStack(spacing: 0) {

                    Rectangle().fill(Color.clear)
                        .frame(height: 46)
                        .frame(maxWidth: .infinity)
                        .overlay(ChopWordmark(size: 40))
                        .padding(.bottom, 14)

                    // no "Welcome back"/sub on the normal form — just the mark.
                    // Reset stages keep their titles so people know where they are.
                    if authStage != 0 {
                        Text(authTitle)
                            .font(.system(size: 21, weight: .heavy))
                            .foregroundStyle(ChopColor.ink)
                            .padding(.bottom, 4)
                        Text(authSub)
                            .font(.system(size: 13.5))
                            .foregroundStyle(ChopColor.muted)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 22)
                    } else {
                        Spacer().frame(height: 8)
                    }

                    if authStage == 0 {
                        HStack(spacing: 4) {
                            authTab("Sign in", 0)
                            authTab("Create account", 1)
                        }
                        .padding(4)
                        .background(ChopColor.soft2, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 20)
                    }

                    VStack(spacing: 14) {
                        if authStage != 2 {
                            ChopField(label: "Email", placeholder: "you@example.com",
                                      contentType: .emailAddress, text: $api.email)
                                .keyboardType(.emailAddress)
                        }
                        if authStage == 0 {
                            // sign-in tab offers saved credentials; create-account
                            // tab makes iOS suggest + save a strong password
                            ChopField(label: "Password", placeholder: "••••••••", secure: true,
                                      contentType: authMode == 1 ? .newPassword : .password,
                                      text: $api.password)
                        }
                        if authStage == 2 {
                            ChopField(label: "New password", placeholder: "••••••••", secure: true,
                                      contentType: .newPassword, text: $newPassword)
                        }
                    }
                    .onSubmit { Task { await runAuth() } }   // Enter submits, web parity

                    ChopButton(title: authButton, kind: .primary, loading: api.busy) {
                        Task { await runAuth() }
                    }
                    .padding(.top, 6)

                    // .aerr — reserved height so the card never jumps
                    Text(api.error)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(ChopColor.rose)
                        .multilineTextAlignment(.center)
                        .frame(minHeight: 18)
                        .padding(.top, 10)

                    // .anote — green success note
                    if !api.note.isEmpty {
                        Text(api.note)
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(ChopColor.green)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 10).padding(.horizontal, 14)
                            .frame(maxWidth: .infinity)
                            .background(ChopColor.greenSoft, in: RoundedRectangle(cornerRadius: 11))
                            .padding(.top, 12)
                    }

                    if authStage == 0 && authMode == 0 {
                        Button("Forgot your password?") {
                            api.email = api.email.trimmingCharacters(in: .whitespaces)
                            authStage = 1; clearAuthMessages()
                        }
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(ChopColor.muted)
                        .padding(.top, 12)
                    }
                    if authStage != 0 {
                        Button("Back to sign in") { authStage = 0; authMode = 0; clearAuthMessages() }
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(ChopColor.muted)
                            .padding(.top, 12)
                    }

                    if authStage == 0 {
                        Text("✦ New accounts get 3 free videos")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ChopColor.muted)
                            .padding(.top, 16)
                    }
                }
                .padding(.vertical, 26).padding(.horizontal, 24)
                .frame(maxWidth: 440)
                .background(ChopColor.card.opacity(0.94), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(ChopColor.line, lineWidth: 1))
                .padding(.top, 14)
                // cinematic entrance: card rises + fades in
                .opacity(authAppeared ? 1 : 0)
                .offset(y: authAppeared ? 0 : 26)

                // ---- .abenefit — gradient sell panel, BELOW the form on phone ----
                authBenefits
                    .frame(maxWidth: 440)
                    .opacity(authAppeared ? 1 : 0)
                    .offset(y: authAppeared ? 0 : 34)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
        }
        .background(Color.clear)
        .onAppear {
            authGlow = true
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) { authAppeared = true }
        }
        .onChange(of: api.wantsSignInMode) { _, flip in
            if flip { authMode = 0; api.wantsSignInMode = false }   // keep the typed email
        }
    }

    private func clearAuthMessages() { api.error = ""; api.note = "" }

    private var authBenefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                HStack(spacing: 7) {
                    Group {
                        if UIImage(named: "ChopMark") != nil {
                            Image("ChopMark").resizable().scaledToFit()
                        } else { RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.2)) }
                    }
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text("Chop").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                }
            }
            Text("Post more.\nEdit nothing.")
                .font(.system(size: 21, weight: .bold))
                .lineSpacing(21 * 0.2)
                .kerning(-0.21)
                .foregroundStyle(.white)
            authBullet(.scissors,  "Dead air, filler words and retakes cut automatically — in seconds")
            authBullet(.filmstrip, "Retakes shown side by side — nothing is ever deleted without you")
            authBullet(.download,  "Renders on your device — post straight to TikTok, Reels or Shorts")
            authBullet(.bolt,      "Start with 3 free videos — no card, no subscription")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                chopGradient
                AuthGridOverlay().stroke(.white.opacity(0.09), lineWidth: 1)   // 44px grid, web ::before
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func authBullet(_ icon: AuthIcon.Kind, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AuthIcon(kind: icon)
                .stroke(.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .frame(width: 16, height: 16)
                .padding(7)
                .background(.white.opacity(0.16), in: Circle())
            Text(text).font(.system(size: 13)).foregroundStyle(.white.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var authTitle: String {
        switch authStage {
        case 1: return "Reset your password"
        case 2: return "Choose a new password"
        default: return authMode == 1 ? "Create your account" : "Welcome back"
        }
    }
    private var authSub: String {
        switch authStage {
        case 1: return "We'll email you a link to set a new one."
        case 2: return "Enter a new password for your account."
        default: return authMode == 1 ? "Three free videos are waiting." : "Sign in to keep chopping."
        }
    }
    private var authButton: String {
        switch authStage {
        case 1: return "Send reset link"
        case 2: return "Save new password"
        default: return authMode == 1 ? "Create account" : "Sign in"
        }
    }

    private func runAuth() async {
        clearAuthMessages()
        if authStage == 1 {
            // mode `reset`
            let e = api.email.trimmingCharacters(in: .whitespaces)
            guard !e.isEmpty else { api.error = "Enter your email address."; return }
            if await api.sendPasswordReset(email: e) {
                api.note = "Check your inbox — we've sent you a link to set a new password."
            } else {
                api.error = "Couldn't send that — try again."
            }
            return
        }
        if authStage == 2 {
            // mode `new`
            guard newPassword.count >= 6 else { api.error = "Use at least 6 characters."; return }
            if await api.updatePassword(newPassword) {
                api.note = "Password updated — sign in with it now."
                newPassword = ""; authStage = 0; authMode = 0
            } else {
                api.error = "Couldn't save that — try again."
            }
            return
        }
        // modes `in` / `up`
        guard !api.email.trimmingCharacters(in: .whitespaces).isEmpty, !api.password.isEmpty else {
            api.error = "Enter your email and a password."; return
        }
        await api.signIn(creating: authMode == 1)
    }

    private func authTab(_ title: String, _ mode: Int) -> some View {
        let on = authMode == mode
        return Button { authMode = mode; clearAuthMessages() } label: {
            Text(title)
                .font(.system(size: 13.5, weight: .heavy))
                .foregroundStyle(on ? ChopColor.ink : ChopColor.muted)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(on ? ChopColor.card : .clear,
                            in: RoundedRectangle(cornerRadius: 9))
                .shadow(color: on ? .black.opacity(0.06) : .clear, radius: 2, y: 1)
        }
    }

    private var chopHeader: some View {
        HStack(spacing: 10) {
            // the chopped wordmark IS the logo now — no icon
            ChopWordmark(size: 24)

            Spacer()

            // tapping the balance goes straight to Billing (Lewis 19 Aug)
            Button { showBilling = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.fill").font(.system(size: 11, weight: .bold))
                    Text("\(api.credits) credits").font(.system(size: 14, weight: .heavy))
                }
                .foregroundStyle(ChopColor.blue)
                .padding(.horizontal, 13).padding(.vertical, 8)
                .background(ChopColor.blueSoft, in: Capsule())
            }
            .buttonStyle(.plain)
            .tourAnchor("tour-credits")

            Button { showProfileMenu = true } label: {
                ZStack {
                    if api.profileAvatar.hasPrefix("http") {
                        AsyncImage(url: URL(string: api.profileAvatar)) { img in
                            img.resizable().scaledToFill()
                        } placeholder: { ChopColor.soft2 }
                    } else {
                        LinearGradient(colors: avatarColours,
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        Text(avatarEmoji).font(.system(size: 17))
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            }
            // web-parity pop-out: Billing · Settings · App tour · Sign out · Dark mode
            .popover(isPresented: $showProfileMenu, arrowEdge: .top) {
                profileMenu.presentationCompactAdaptation(.popover)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    /// The avatar pop-out — same items as the web app's profile menu.
    private var profileMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(api.profileName.isEmpty ? "Your account" : api.profileName)
                    .font(.system(size: 15, weight: .heavy)).foregroundStyle(ChopColor.ink)
                if !api.profileTiktok.isEmpty {
                    Text("@\(api.profileTiktok)").font(.system(size: 12.5))
                        .foregroundStyle(ChopColor.muted)
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
            Rectangle().fill(ChopColor.line).frame(height: 1)

            menuItem("person.crop.circle", "Profile") { menuThen { showSettings = true } }
            menuItem("sparkles", "App tour") {
                showProfileMenu = false
                tab = 0   // the tour's first stop lives on the dashboard
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showTour = true }
            }
            menuItem("creditcard", "Billing") { menuThen { showBilling = true } }
            menuItem("rectangle.portrait.and.arrow.right", "Sign out") {
                showProfileMenu = false
                api.signOut()
            }

            Rectangle().fill(ChopColor.line).frame(height: 1)
            HStack(spacing: 10) {
                Image(systemName: "moon").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ChopColor.ink).frame(width: 20)
                Text("Dark mode").font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(ChopColor.ink)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { theme == .dark },
                    set: { on in
                        theme = on ? .dark : .light
                        ChopTheme.set(theme)
                    }))
                    .labelsHidden()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .frame(width: 240)
        .background(ChopColor.card)
        .preferredColorScheme(theme.scheme)
    }

    private func menuItem(_ icon: String, _ label: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ChopColor.ink).frame(width: 20)
                Text(label).font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(ChopColor.ink)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Close the pop-out, then present a sheet — same-tick presentation clashes.
    private func menuThen(_ then: @escaping () -> Void) {
        showProfileMenu = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: then)
    }

    private var avatarEmoji: String {
        let a = api.profileAvatar
        if a.hasPrefix("e:") {
            let parts = a.split(separator: ":")
            if parts.count > 1 { return String(parts[1]) }
        }
        return "💸"
    }

    private var avatarColours: [Color] {
        let a = api.profileAvatar
        var idx = 0
        if a.hasPrefix("e:") {
            let parts = a.split(separator: ":")
            if parts.count > 2 { idx = Int(parts[2]) ?? 0 }
        }
        return CHOP_AV_COLOURS[idx % CHOP_AV_COLOURS.count]
    }

    /// Single take vs Multi-take — quiet 50/50 chips above the drop zone.
    private func importModeButton(_ title: String, mode: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { importMode = mode }
        } label: {
            Text(title)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(importMode == mode ? ChopColor.blue : ChopColor.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(importMode == mode ? ChopColor.blueSoft : ChopColor.card,
                            in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(importMode == mode ? ChopColor.blue.opacity(0.55) : Color.chopLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func statCard(_ value: String, _ label: String, sub: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(ChopFont.cardBig).foregroundStyle(ChopColor.blue)
            Text(label).font(ChopFont.cardLabel).foregroundStyle(ChopColor.ink)
                .lineLimit(2, reservesSpace: true)   // every card = same height
            if let sub { Text(sub).font(.caption2).foregroundStyle(Color.chopMuted) }
        }
        // no minHeight (Lewis 19 Aug): the cards used to reserve 96pt and sit
        // mostly empty, pushing the upload box down on smaller phones — now
        // they hug their text.
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color.chopPanel)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.chopLine, lineWidth: 1))
    }

    // ---- numbers, derived from the jobs themselves ----
    /// TIME SAVED EDITING (Lewis 19 Aug — the equation):
    /// hand-editing a talking-head video takes roughly 3 minutes per minute
    /// of raw footage (scrubbing, cutting silences/fillers, checking retakes,
    /// tightening ends). Chop leaves ~1 minute of review per video. So:
    ///     time saved = Σ(rawSec × 3) − (videos × 60s review)
    private var savedSeconds: Double {
        let manual = api.jobs.reduce(0.0) { $0 + $1.rawSec * 3 }
        let review = Double(api.jobs.count) * 60
        return max(0, manual - review)
    }
    private var savedLabel: String {
        let m = Int(savedSeconds / 60)
        return m >= 60 ? String(format: "%.1fh", savedSeconds / 3600) : "\(m)m"
    }
    /// SAVED PAYING AN EDITOR (Lewis 19 Aug — the equation):
    ///     (videos edited × £5) − what the credits for those videos cost.
    /// The free 3 credits cost £0; beyond that a credit is priced at the
    /// blended 90p Creator rate until real purchase history is wired in.
    private var moneyLabel: String {
        let n = api.jobs.count
        let earned = Double(n) * 5.0
        let creditCost = Double(max(0, n - 3)) * 0.90
        return "£\(Int(max(0, earned - creditCost)))"
    }

    private var editDays: [String] {
        api.jobs.compactMap { j in
            guard let ms = j.data["statusAt"] as? Double else { return nil }
            let d = Date(timeIntervalSince1970: ms / 1000)
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            return f.string(from: d)
        }
    }
    private var editDayCounts: [String: Int] {
        var out: [String: Int] = [:]
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        for j in api.jobs {
            guard let ms = j.data["statusAt"] as? Double else { continue }
            let k = f.string(from: Date(timeIntervalSince1970: ms / 1000))
            out[k, default: 0] += 1
        }
        return out
    }
    private var longestStreak: Int {
        let keys = editDayCounts.keys.sorted()
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        var best = 0, run = 0
        var prev: Date?
        for k in keys {
            guard let d = f.date(from: k) else { continue }
            if let p = prev, Calendar.current.dateComponents([.day], from: p, to: d).day == 1 { run += 1 }
            else { run = 1 }
            best = max(best, run); prev = d
        }
        return best
    }
    private var activeLast30: Int {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        var n = 0
        for i in 0..<30 {
            let d = Calendar.current.date(byAdding: .day, value: -i, to: Date()) ?? Date()
            if editDayCounts[f.string(from: d)] != nil { n += 1 }
        }
        return n
    }

    private var peakDay: String {
        let names = ["Sundays","Mondays","Tuesdays","Wednesdays","Thursdays","Fridays","Saturdays"]
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        var tally = [Int: Int]()
        for (k, n) in editDayCounts {
            guard let d = f.date(from: k) else { continue }
            tally[Calendar.current.component(.weekday, from: d) - 1, default: 0] += n
        }
        guard let best = tally.max(by: { $0.value < $1.value })?.key else { return "—" }
        return names[best]
    }

    private var streak: Int {
        let set = Set(editDays)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        var n = 0
        var day = Date()
        while set.contains(f.string(from: day)) {
            n += 1
            day = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return n
    }

    private var jobList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {

                Text(api.profileName.isEmpty
                     ? "Dashboard"
                     : "Hey \(api.profileName.split(separator: " ").first.map(String.init) ?? api.profileName), let's chop 👋")
                    .font(ChopFont.h1())
                    .fixedSize(horizontal: false, vertical: true)
                Text("An overview of how your chopping is going.")
                    .font(.subheadline).foregroundStyle(Color.chopMuted)
                    .padding(.bottom, 4)

                // 2x2 — all four cards the SAME compact size (Lewis 19 Aug:
                // the blue hero kept its old 96pt minHeight and towered over
                // the slimmed cards).
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(savedLabel).font(ChopFont.cardBig)
                        Text("Time saved editing").font(ChopFont.cardLabel)
                            .lineLimit(2, reservesSpace: true)   // matches statCard height
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(  // web: linear-gradient(135deg,#1a6dff,#4e8dff) + blue shadow
                        LinearGradient(colors: [Color(red: 0x1a/255, green: 0x6d/255, blue: 1.0),
                                                Color(red: 0x4e/255, green: 0x8d/255, blue: 1.0)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: Color.chopBlue.opacity(0.35), radius: 12, y: 5)

                    statCard("\(api.jobs.count)", "Videos edited")
                }
                HStack(alignment: .top, spacing: 12) {
                    statCard(moneyLabel, "Saved paying an editor")
                    statCard("\(streak)", "Day streak")
                }

                // UPLOAD MODE selector (Lewis 19 Aug: clearer wording, 3 options).
                // Same two locked pipelines as before, now named honestly:
                //   Single  = one video, the untouched original flow
                //   Bulk    = several videos, EACH processed separately
                //             (first in the foreground, rest in background batch)
                //   Combine = several clips stitched into ONE video in selection
                //             order BEFORE the normal pipeline runs
                // Only the labels/selection limit changed — upload, analysis,
                // retakes, editor and export are byte-identical.
                HStack(spacing: 8) {
                    importModeButton("Single", mode: 0)
                    importModeButton("Bulk", mode: 1)
                    importModeButton("Combine", mode: 2)
                }
                .padding(.top, 8)

                // one plain line so nobody has to guess what a mode does
                Text(importMode == 0 ? "One video, one edit."
                     : importMode == 1 ? "Up to 30 videos — each gets its own separate edit."
                     : "Up to 30 clips joined into ONE video, then edited.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ChopColor.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 6)

                Button {
                    // straight to the photo library — no interim "Choose videos" tab
                    if api.credits <= 0 { showImport = true } else { showImportPicker = true }
                } label: {
                    VStack(spacing: 0) {
                        DropCloudIcon()   // the web's cloud SVG, not an SF Symbol
                            .stroke(ChopColor.blue, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                            .frame(width: 26, height: 26)
                            .frame(width: 54, height: 54)
                            .background(ChopColor.blueSoft, in: Circle())
                            .padding(.bottom, 12)
                        Text("Drop your videos here to edit")
                            .font(.system(size: 18, weight: .bold)).foregroundStyle(Color.chopInk)
                        HStack(spacing: 4) {
                            Text("or").font(.system(size: 13)).foregroundStyle(ChopColor.muted)
                            Text("click to browse")
                                .font(.system(size: 13, weight: .bold)).foregroundStyle(ChopColor.blue)
                        }
                        .padding(.top, 6)
                        Text("MP4 or MOV · up to 2 GB each (1 GB on mobile)")
                            .font(.system(size: 13)).foregroundStyle(ChopColor.muted)
                            .padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48).padding(.horizontal, 24)
                    .background(ChopColor.card, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                        .foregroundStyle(Color.chopLine))
                }
                .padding(.top, 8)
                .tourAnchor("tour-upload")

                Text("Consistency").font(ChopFont.h2(24))
                    .foregroundStyle(ChopColor.ink).padding(.top, 28)

                ChopRing(edits: api.jobs.count, active30: activeLast30,
                         streak: streak, peakDay: peakDay)

                ChopActivity(days: editDayCounts, current: streak,
                             longest: longestStreak, active30: activeLast30)
                    .padding(.top, 6)

                // .edits-h — uppercase eyebrow + count pill, web parity
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("YOUR EDITS")
                        .font(.system(size: 12, weight: .heavy))
                        .kerning(1.1)
                        .foregroundStyle(ChopColor.muted)
                    Text("\(api.jobs.count)")
                        .font(.system(size: 11.5, weight: .heavy))
                        .foregroundStyle(ChopColor.blue)
                        .padding(.horizontal, 9).padding(.vertical, 2)
                        .background(ChopColor.blueSoft, in: Capsule())
                    Spacer()
                }
                .padding(.top, 30)

                if api.jobs.isEmpty && !api.busy {
                    Text("Videos you edit will show up here.")
                        .font(ChopFont.small).foregroundStyle(ChopColor.muted)
                        .padding(.vertical, 22)
                }

                // One swipeable shelf — sideways scroll, no more endless stacking.
                // Plain HStack + explicit height: a LazyHStack nested inside the
                // page's LazyVStack collapses to zero height and renders nothing.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(api.jobs) { job in
                            NavigationLink { ChopPlayerScreen(job: job, api: api) } label: {
                                EditCard(job: job)
                                    .frame(width: 150)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 274)
                .padding(.horizontal, -16)   // bleed the shelf to the screen edges
            }
            .padding(16)
            .padding(.bottom, 110)
        }
        .background(Color.chopBg)
    }
}


// MARK: - Player

@MainActor
final class ChopPlayer: ObservableObject {
    @Published var status = "Preparing…"
    @Published var ready = false
    @Published var clipCount = 0
    @Published var cutCount = 0
    @Published var duration: Double = 0
    @Published var minSil: Double = 0.4
    @Published var fillers: Bool = true
    @Published var softFillers: Bool = false
    @Published var padStart: Double = 40    // Clip start, ms — web sStart
    @Published var padEnd: Double = -40     // Clip end, ms — web sEnd
    @Published var pairs: [ChopPair] = []
    @Published var segments: [ChopSegment] = []
    @Published var exporting = false
    @Published var exportPct: Double = 0
    @Published var exportMsg = ""
    let player = AVPlayer()

    @Published var time: Double = 0
    @Published var isPlaying = false
    @Published var strip: [UIImage] = []

    // Raw / Edited mode — Edited plays the composition (today's behaviour);
    // Raw plays the FULL original with the cut sections banded in red.
    @Published var showEdited = true
    @Published var rawDuration: Double = 0
    @Published var editedDuration: Double = 0
    @Published var videoAspect: CGFloat = 9.0 / 16.0   // display aspect after rotation — the zoom cage
    @Published var rawCuts: [(start: Double, end: Double)] = []   // red bands, raw time

    private var localURL: URL?
    private var edit: ChopEdit?
    private var composition: AVMutableComposition?
    private var timeObserver: Any?
    private var stripTask: Task<Void, Never>?

    // ---- persistence: EVERYTHING the editor changes is saved to the job ----
    private var jobName: String?          // nil in demo mode = never persist
    private weak var apiRef: ChopAPI?
    private var saveTask: Task<Void, Never>?

    /// Same keys the web app reads/writes (manuals, choices, settings,
    /// manualCuts, splits) plus iOS's manualKeeps and zooms, plus the real
    /// editedSec so the dashboard's "1:42 → 1:04" is truthful.
    func persistEdit() async {
        guard let name = jobName, let api = apiRef, let e = edit else { return }
        let fields: [String: Any] = [
            "manuals": segments.map { $0.manual.map { $0 as Any } ?? NSNull() },
            "choices": pairs.map { $0.choice.map { $0 as Any } ?? NSNull() },
            "settings": ["minSil": minSil, "fillers": fillers, "soft": softFillers,
                         "startPadMs": padStart, "endPadMs": padEnd],
            "manualCuts": e.manualCuts.map { ["s": $0.start, "e": $0.end] },
            "manualKeeps": e.manualKeeps.map { ["s": $0.start, "e": $0.end] },
            "splits": splits,
            "zooms": zooms.map { ["s": $0.start, "e": $0.end, "z": Double($0.scale),
                                  "x": Double($0.ox), "y": Double($0.oy)] },
            "rotations": rotations.map { ["s": $0.start, "e": $0.end, "q": $0.q] },
            "kfZooms": kfZooms.map { ["s": $0.start, "e": $0.end, "z": Double($0.scale),
                                      "x": Double($0.ax), "y": Double($0.ay)] },
            "editedSec": editedDuration,
        ]
        await api.mergeJobData(name, fields: fields)
    }
    /// Debounced: fires ~1.5s after the last change, so slider drags and
    /// rapid-fire edits collapse into one write.
    func scheduleSave() {
        guard jobName != nil else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await self?.persistEdit()
        }
    }

    /// Undo stack, same idea as the web app's snap()/applySnap.
    private struct Snapshot {
        var pairs: [ChopPair]
        var segments: [ChopSegment]
        var manualCuts: [ChopClip]
        var manualKeeps: [ChopClip] = []
        var minSil: Double
        var fillers: Bool
        var soft: Bool
        var splits: [Double] = []
        var zooms: [(start: Double, end: Double, scale: CGFloat, ox: CGFloat, oy: CGFloat)] = []
        var rotations: [(start: Double, end: Double, q: Int)] = []
        var kfZooms: [(start: Double, end: Double, scale: CGFloat, ax: CGFloat, ay: CGFloat)] = []
    }
    private var past: [Snapshot] = []
    private var future: [Snapshot] = []
    @Published var canUndo = false
    @Published var canRedo = false

    /// Downloads the source once, then plays the edit as a single composition.
    func open(job: ChopJob, api: ChopAPI) async {
        // demo mode (design preview only): local file, no network — additive branch
        if let demo = job.data["demoPath"] as? String {
            let e = ChopEdit(job: job)
            minSil = e.settings.minSil
            fillers = e.settings.fillers
            softFillers = false   // soft-fillers option removed from the product
            padStart = e.settings.startPadMs
            padEnd = e.settings.endPadMs
            edit = e
            pairs = e.pairs
            segments = e.segments
            localURL = URL(fileURLWithPath: demo)
            rebuild()
            return
        }
        var e = ChopEdit(job: job)
        // a job with no saved settings inherits the creator's Cut Lab default
        if (job.data["settings"] as? [String: Any]) == nil { e.settings = ChopPresets.saved }
        minSil = e.settings.minSil
        fillers = e.settings.fillers
        softFillers = false   // soft-fillers option removed from the product
        padStart = e.settings.startPadMs
        padEnd = e.settings.endPadMs
        edit = e
        pairs = e.pairs
        segments = e.segments
        // persistence wiring + saved quick-edit state comes back with the job
        jobName = job.name
        apiRef = api
        splits = (job.data["splits"] as? [Double]) ?? []
        if let zs = job.data["zooms"] as? [[String: Any]] {
            zooms = zs.compactMap {
                guard let s = $0["s"] as? Double, let e2 = $0["e"] as? Double,
                      let z = $0["z"] as? Double else { return nil }
                return (s, e2, CGFloat(z),
                        CGFloat(($0["x"] as? Double) ?? 0), CGFloat(($0["y"] as? Double) ?? 0))
            }
        }
        if let rs = job.data["rotations"] as? [[String: Any]] {   // saved rotations come back
            rotations = rs.compactMap {
                guard let s = $0["s"] as? Double, let e2 = $0["e"] as? Double,
                      let q = $0["q"] as? Int else { return nil }
                return (s, e2, q % 4)
            }
        }
        if let ks = job.data["kfZooms"] as? [[String: Any]] {   // keyframe ramps too
            kfZooms = ks.compactMap {
                guard let s = $0["s"] as? Double, let e2 = $0["e"] as? Double,
                      let z = $0["z"] as? Double else { return nil }
                return (s, e2, CGFloat(z),
                        CGFloat(($0["x"] as? Double) ?? 0), CGFloat(($0["y"] as? Double) ?? 0))
            }
        }
        guard !e.segments.isEmpty else { status = "No analysis on this job"; return }

        // PLAYBACK PROXY (additive, Lewis 18 Aug): a 1080p preview copy made in
        // the background the first time a big video opens. PLAYBACK ONLY — the
        // export chain below never sees it (export's original-only guard is
        // untouched). Same model the web already uses (540p proxyKey edits):
        // cut/zoom times are plain seconds, identical on proxy and original.
        let proxy1080 = ChopPlayer.proxyURL(for: job.name)
        if FileManager.default.fileExists(atPath: proxy1080.path) {
            localURL = proxy1080
            rebuild()
            return
        }

        // FAST PATH 1: the file we just imported is still on the phone —
        // open instantly, no network at all.
        if let local = api.localImports[job.name],
           FileManager.default.fileExists(atPath: local.path) {
            localURL = local
            rebuild()
            kickProxy(from: local, name: job.name)   // ready for the next open
            return
        }

        // prefer the 540p proxy — small, fast, and sharp enough on a phone
        guard let key = (job.data["proxyKey"] as? String) ?? job.videoKey else {
            status = "Video isn't synced to the cloud yet"; return
        }

        // FAST PATH 2: downloaded before — reuse the cached copy instead of
        // pulling the whole video down again on every open.
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dest = cacheDir.appendingPathComponent(
            "chop-" + key.replacingOccurrences(of: "/", with: "_") + ".mp4")
        if FileManager.default.fileExists(atPath: dest.path) {
            localURL = dest
            rebuild()
            kickProxy(from: dest, name: job.name)   // no-op if it's already ≤1080p
            return
        }

        status = "Fetching video…"
        guard let signed = await api.presignGet(key) else { status = "Couldn't get the video"; return }

        status = "Downloading…"
        do {
            let (tmp, _) = try await URLSession.shared.download(from: signed)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
        } catch {
            status = "Download failed: \(error.localizedDescription)"; return
        }

        localURL = dest
        rebuild()
        kickProxy(from: dest, name: job.name)
    }

    // MARK: 1080p playback proxy (additive) ---------------------------------
    // 4K editing works, but scrubbing/trim-preview makes the phone decode 4K
    // frames constantly. This makes a 1080p H.264 copy in the background the
    // first time a big video opens; every LATER open plays the proxy instead.
    // Rules: never for export (original-only guard above is untouched), never
    // generated for footage already ≤1080p, silent failure = original keeps
    // playing exactly as today, and it stays out of the way of imports.

    private static var proxyInFlight = Set<String>()

    nonisolated static func proxyURL(for name: String) -> URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let safe = name.replacingOccurrences(of: "/", with: "_")
        return cacheDir.appendingPathComponent("chop-proxy1080-" + safe + ".mp4")
    }

    private func kickProxy(from src: URL, name: String) {
        let dest = ChopPlayer.proxyURL(for: name)
        guard !FileManager.default.fileExists(atPath: dest.path),
              !ChopPlayer.proxyInFlight.contains(name) else { return }
        ChopPlayer.proxyInFlight.insert(name)
        Task.detached(priority: .utility) {
            defer { Task { @MainActor in ChopPlayer.proxyInFlight.remove(name) } }
            let asset = AVURLAsset(url: src)
            // only worth a proxy when the source is actually bigger than 1080p
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let size = try? await track.load(.naturalSize),
                  min(abs(size.width), abs(size.height)) > 1120 else { return }
            guard let ex = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080) else { return }
            let tmp = dest.deletingPathExtension().appendingPathExtension("part.mp4")
            try? FileManager.default.removeItem(at: tmp)
            ex.outputURL = tmp
            ex.outputFileType = .mp4
            ex.shouldOptimizeForNetworkUse = false
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                ex.exportAsynchronously { cont.resume() }
            }
            if ex.status == .completed {
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.moveItem(at: tmp, to: dest)
            } else {
                try? FileManager.default.removeItem(at: tmp)   // silent: original keeps playing
            }
        }
    }


    /// Export from the ORIGINAL, never the proxy, and save to the camera roll.
    /// Mirrors CHOP_EXPORT_PROXY_GUARD in the web app: a 540p export would be a
    /// quiet, serious regression.
    func export(job: ChopJob, api: ChopAPI) async {
        guard let e = edit else { return }
        let kept = e.keptClips()
        guard !kept.isEmpty else { exportMsg = "Nothing to export"; return }

        // LOCAL FIRST — export must NEVER block on cloud sync. A fresh import's
        // original is still on the phone; the old guard demanded videoKey
        // before even looking, which is what threw the 'open it on the web'
        // error while the background sync was still running.
        let localImport: URL? = api.localImports[job.name].flatMap {
            FileManager.default.fileExists(atPath: $0.path) ? $0 : nil
        }
        guard localImport != nil || job.videoKey != nil else {
            exportMsg = "The full-quality video is still syncing — give it a minute and try again."
            return
        }

        exporting = true; exportPct = 0
        defer { exporting = false }

        let local: URL
        if let imported = localImport {
            local = imported                       // zero network, sync irrelevant
        } else {
            let originalKey = job.videoKey!        // guarded above
            let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            let cached = cacheDir.appendingPathComponent(
                "chop-" + originalKey.replacingOccurrences(of: "/", with: "_") + ".mp4")
            if FileManager.default.fileExists(atPath: cached.path) {
                local = cached                     // downloaded before — reuse
            } else {
                exportMsg = "Fetching the original…"
                guard let signed = await api.presignGet(originalKey) else {
                    exportMsg = "Couldn't fetch the original"; return
                }
                exportMsg = "Downloading…"
                do {
                    let (tmp, _) = try await URLSession.shared.download(from: signed)
                    try? FileManager.default.removeItem(at: cached)
                    try FileManager.default.moveItem(at: tmp, to: cached)
                    local = cached                 // cache for every future export
                } catch {
                    exportMsg = "Download failed: \(error.localizedDescription)"; return
                }
            }
        }

        exportMsg = "Building the edit…"
        let src = AVURLAsset(url: local)
        let comp = AVMutableComposition()
        guard let srcV = src.tracks(withMediaType: .video).first,
              let vTrack = comp.addMutableTrack(withMediaType: .video,
                                                preferredTrackID: kCMPersistentTrackID_Invalid) else {
            exportMsg = "No video track"; return
        }
        let srcA = src.tracks(withMediaType: .audio).first
        let aTrack = comp.addMutableTrack(withMediaType: .audio,
                                          preferredTrackID: kCMPersistentTrackID_Invalid)
        var cursor = CMTime.zero
        for clip in kept {
            let range = CMTimeRange(start: CMTime(seconds: clip.start, preferredTimescale: 600),
                                    duration: CMTime(seconds: max(0, clip.end - clip.start),
                                                     preferredTimescale: 600))
            do {
                try vTrack.insertTimeRange(range, of: srcV, at: cursor)
                if let srcA = srcA, let aTrack = aTrack {
                    try aTrack.insertTimeRange(range, of: srcA, at: cursor)
                }
                cursor = CMTimeAdd(cursor, range.duration)
            } catch {
                exportMsg = "Couldn't build the edit"; return
            }
        }
        vTrack.preferredTransform = srcV.preferredTransform

        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("chop-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: out)

        // 1080p, same as the web app. Re-encoding 4K on-device takes minutes
        // and creators post at 1080 anyway.
        let preset = AVAssetExportSession.exportPresets(compatibleWith: comp)
            .contains(AVAssetExportPreset1920x1080)
            ? AVAssetExportPreset1920x1080 : AVAssetExportPresetMediumQuality
        guard let session = AVAssetExportSession(asset: comp, presetName: preset) else {
            exportMsg = "Couldn't start the export"; return
        }
        session.outputURL = out
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        // bake per-clip pinch zooms into the file — what you saw is what you post
        // (and any per-clip rotations — same composition, same fixed canvas)
        if !zooms.isEmpty || !rotations.isEmpty || !kfZooms.isEmpty,
           let compV = comp.tracks(withMediaType: .video).first {
            session.videoComposition = ChopPlayer.zoomComposition(
                track: compV, srcTransform: srcV.preferredTransform,
                srcNatural: srcV.naturalSize, kept: kept,
                zooms: zooms, totalDuration: comp.duration,
                rotations: rotations, kfZooms: kfZooms)
        }

        exportMsg = "Rendering…"
        // iOS suspends us the moment the app goes to the background. This buys
        // extra time; it is not unlimited, so the app should stay open.
        var bgTask = UIBackgroundTaskIdentifier.invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "chop-export") {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
        defer { if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask) } }

        let ticker = Task { [weak self] in
            while !Task.isCancelled {
                let pr = session.progress
                await MainActor.run {
                    self?.exportPct = Double(pr)
                    if pr > 0.9 { self?.exportMsg = "Finishing off…" }
                }
                if pr >= 1 { break }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        await session.export()
        ticker.cancel()

        guard session.status == .completed else {
            exportMsg = "Export failed: \(session.error?.localizedDescription ?? "unknown")"
            return
        }

        exportMsg = "Saving to your camera roll…"
        let ok = await saveToPhotos(out)
        exportMsg = ok ? "Saved to your camera roll" : "Couldn't save — check Photos permission in Settings"
        if ok {
            // big green centre-screen confirmation + the job moves to Downloaded,
            // so the tick can never bounce it back into Ready to export
            await persistEdit()   // the exact edit that was exported is what's saved
            ChopToasts.shared.showBig("Exported to your camera roll")
            await api.setStatus(job, to: "exported")
        } else {
            ChopToasts.shared.show("Couldn't save to Photos")
        }
    }

    /// Video composition that applies each clip's pinch zoom (centre-anchored),
    /// rotation-safe: the base transform reproduces the source orientation and
    /// the zoom is applied on the render canvas about its centre.
    static func zoomComposition(track: AVAssetTrack,
                                srcTransform: CGAffineTransform,
                                srcNatural: CGSize,
                                kept: [ChopClip],
                                zooms: [(start: Double, end: Double, scale: CGFloat, ox: CGFloat, oy: CGFloat)],
                                totalDuration: CMTime,
                                rotations: [(start: Double, end: Double, q: Int)] = [],
                                kfZooms: [(start: Double, end: Double, scale: CGFloat, ax: CGFloat, ay: CGFloat)] = []) -> AVMutableVideoComposition {
        let bounds = CGRect(origin: .zero, size: srcNatural).applying(srcTransform)
        let base = srcTransform.concatenating(
            CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
        // ROTATE v2 (Lewis 18 Aug): the canvas NEVER changes — locked portrait
        // sizing. A rotated clip turns about the canvas centre and fit-scales
        // inside it (letterboxed), per clip, exactly like the preview cage.
        let renderSize = CGSize(width: abs(bounds.width), height: abs(bounds.height))
        let cx = renderSize.width / 2, cy = renderSize.height / 2

        // split the OUTPUT timeline at clip joins and zoom/rotation/keyframe
        // edges, back-to-back so the instructions tile the whole duration
        struct Piece { let start: CMTime; let duration: CMTime; let scale: CGFloat; let q: Int
                       let zox: CGFloat; let zoy: CGFloat   // the clip zoom's freeform offset
                       let k0: CGFloat; let k1: CGFloat     // keyframe ramp scale at piece start/end
                       let kax: CGFloat; let kay: CGFloat } // the ramp's freeform focal point
        // ramped keyframe scale at a RAW moment (1 outside every ramp)
        func kfAt(_ rt: Double) -> CGFloat {
            guard let k = kfZooms.first(where: { rt >= $0.start - 0.0001 && rt <= $0.end + 0.0001 })
            else { return 1 }
            let f = (rt - k.start) / max(k.end - k.start, 0.001)
            return 1 + (k.scale - 1) * CGFloat(min(max(f, 0), 1))
        }
        var pieces: [Piece] = []
        var outCursor = CMTime.zero
        for clip in kept {
            var marks: [Double] = [clip.start, clip.end]
            for z in zooms {
                if z.start > clip.start, z.start < clip.end { marks.append(z.start) }
                if z.end > clip.start, z.end < clip.end { marks.append(z.end) }
            }
            for r in rotations {
                if r.start > clip.start, r.start < clip.end { marks.append(r.start) }
                if r.end > clip.start, r.end < clip.end { marks.append(r.end) }
            }
            for kf in kfZooms {
                if kf.start > clip.start, kf.start < clip.end { marks.append(kf.start) }
                if kf.end > clip.start, kf.end < clip.end { marks.append(kf.end) }
            }
            marks.sort()
            for k in 0..<(marks.count - 1) {
                let s = marks[k], e = marks[k + 1]
                guard e - s > 0.004 else { continue }
                let mid = (s + e) / 2
                let z = zooms.first(where: { mid >= $0.start && mid <= $0.end })
                let q = (rotations.first(where: { mid >= $0.start && mid <= $0.end })?.q ?? 0) % 4
                let kf = kfZooms.first(where: { mid >= $0.start && mid <= $0.end })
                let dur = CMTime(seconds: e - s, preferredTimescale: 600)
                pieces.append(Piece(start: outCursor, duration: dur, scale: z?.scale ?? 1, q: q,
                                    zox: z?.ox ?? 0, zoy: z?.oy ?? 0,
                                    k0: kfAt(s + 0.002), k1: kfAt(e - 0.002),
                                    kax: kf?.ax ?? 0, kay: kf?.ay ?? 0))
                outCursor = CMTimeAdd(outCursor, dur)
            }
        }
        // rounding drift: stretch the final piece to the exact end
        if var last = pieces.popLast() {
            let dur = CMTimeSubtract(totalDuration, last.start)
            last = Piece(start: last.start, duration: dur, scale: last.scale, q: last.q,
                         zox: last.zox, zoy: last.zoy,
                         k0: last.k0, k1: last.k1, kax: last.kax, kay: last.kay)
            pieces.append(last)
        }

        let vc = AVMutableVideoComposition()
        vc.renderSize = renderSize
        vc.frameDuration = CMTime(value: 1, timescale: 30)
        vc.instructions = pieces.map { piece in
            let inst = AVMutableVideoCompositionInstruction()
            inst.timeRange = CMTimeRange(start: piece.start, duration: piece.duration)
            let li = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            // static part: centre-anchored pinch zoom + rotation (old path when
            // neutral), then the keyframe stage scales about ITS OWN freeform
            // focal point — linear in k, so setTransformRamp interpolates it
            // exactly.
            func tf(_ k: CGFloat) -> CGAffineTransform {
                var t = base
                if piece.scale > 1.01 || piece.q != 0 {
                    var m = CGAffineTransform(translationX: -cx, y: -cy)
                    if piece.q != 0 {
                        let fit: CGFloat = piece.q % 2 == 1
                            ? min(renderSize.width / renderSize.height,
                                  renderSize.height / renderSize.width) : 1
                        m = m.concatenating(CGAffineTransform(rotationAngle: CGFloat(piece.q) * .pi / 2))
                             .concatenating(CGAffineTransform(scaleX: fit, y: fit))
                    }
                    if piece.scale > 1.01 {
                        m = m.concatenating(CGAffineTransform(scaleX: piece.scale, y: piece.scale))
                    }
                    t = base.concatenating(m.concatenating(CGAffineTransform(translationX: cx, y: cy)))
                }
                // FREEFORM clip offset (Lewis 18 Aug): slide the zoomed clip
                // anywhere on the canvas — black background allowed. 0/0 = old path.
                if abs(piece.zox) > 0.001 || abs(piece.zoy) > 0.001 {
                    t = t.concatenating(CGAffineTransform(
                        translationX: piece.zox * renderSize.width,
                        y: piece.zoy * renderSize.height))
                }
                if abs(k - 1) > 0.001 {
                    let px = cx + piece.kax * renderSize.width
                    let py = cy + piece.kay * renderSize.height
                    t = t.concatenating(CGAffineTransform(translationX: -px, y: -py))
                         .concatenating(CGAffineTransform(scaleX: k, y: k))
                         .concatenating(CGAffineTransform(translationX: px, y: py))
                }
                return t
            }
            if abs(piece.k1 - piece.k0) > 0.005 {
                li.setTransformRamp(fromStart: tf(piece.k0), toEnd: tf(piece.k1),
                                    timeRange: CMTimeRange(start: piece.start, duration: piece.duration))
            } else {
                li.setTransform(tf(piece.k0), at: piece.start)
            }
            inst.layerInstructions = [li]
            return inst
        }
        return vc
    }

    private func saveToPhotos(_ url: URL) async -> Bool {
        let status = await withCheckedContinuation { (c: CheckedContinuation<PHAuthorizationStatus, Never>) in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { c.resume(returning: $0) }
        }
        guard status == .authorized || status == .limited else { return false }
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }, completionHandler: { done, _ in c.resume(returning: done) })
        }
    }


    private func observeTime() {
        if let t = timeObserver { player.removeTimeObserver(t); timeObserver = nil }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { [weak self] t in
                guard let self else { return }
                if !self.scrubbing { self.time = t.seconds }
                self.isPlaying = self.player.rate > 0
            }
    }

    var scrubbing = false

    func seek(to seconds: Double) {
        let t = CMTime(seconds: max(0, min(duration, seconds)), preferredTimescale: 600)
        time = t.seconds
        // tolerant seek: the stick stays under the finger, the picture catches up
        player.seek(to: t, toleranceBefore: CMTime(seconds: 0.25, preferredTimescale: 600),
                          toleranceAfter:  CMTime(seconds: 0.25, preferredTimescale: 600))
    }

    func seekExact(to seconds: Double) {
        let t = CMTime(seconds: max(0, min(duration, seconds)), preferredTimescale: 600)
        player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // TikTok trim-follow: while a cap is dragged the VIDEO scrubs to the frame
    // under the handle, but `time` is never touched — the strip must stay
    // perfectly still (moving `time` pans the whole timeline: the glitch).
    private var trimPreviewActive = false
    private var lastTrimSeek = Date.distantPast
    func trimPreview(toEditTime t: Double) {
        if !trimPreviewActive {
            trimPreviewActive = true
            scrubbing = true          // mute the clock — seeks must not write `time`
            player.pause()
        }
        // ~12 previews/sec with a whisker of tolerance: smooth pace, no seek spam
        let now = Date()
        guard now.timeIntervalSince(lastTrimSeek) > 0.08 else { return }
        lastTrimSeek = now
        let clamped = max(0, min(t, max(0, duration - 0.02)))
        player.currentItem?.cancelPendingSeeks()
        let tol = CMTime(seconds: 0.04, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: tol, toleranceAfter: tol)
    }
    /// Release: TikTok stillness — the timeline doesn't move a pixel. The
    /// playhead stays where it is; rebuildKeepingTime remaps it into the new
    /// edit, which exactly cancels the content shift on screen. The preview
    /// just returns from the edge frame to the frame under the stick.
    func endTrimPreview() {
        trimPreviewActive = false
        player.currentItem?.cancelPendingSeeks()
        seekExact(to: time)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.scrubbing = false
        }
    }

    func togglePlay() {
        if player.rate > 0 { player.pause() } else {
            if time >= duration - 0.05 { seekExact(to: 0) }
            player.play()
        }
    }

    /// Frames straight off the composition, so the strip shows the EDIT,
    /// not the raw footage — same as the web app's edited view.
    private func buildStrip(_ comp: AVAsset) {
        stripTask?.cancel()
        // keep the old frames on screen while the new ones generate —
        // clearing here made the whole timeline flash blank after every edit
        let total = comp.duration.seconds
        guard total > 0.2 else { return }
        let count = 12
        stripTask = Task.detached(priority: .utility) { [weak self] in
            let gen = AVAssetImageGenerator(asset: comp)
            gen.appliesPreferredTrackTransform = true
            gen.requestedTimeToleranceBefore = CMTime(seconds: 0.4, preferredTimescale: 600)
            gen.requestedTimeToleranceAfter  = CMTime(seconds: 0.4, preferredTimescale: 600)
            gen.maximumSize = CGSize(width: 160, height: 160)
            var out: [UIImage] = []
            for i in 0..<count {
                if Task.isCancelled { return }
                let t = CMTime(seconds: total * (Double(i) + 0.5) / Double(count),
                               preferredTimescale: 600)
                if let cg = try? gen.copyCGImage(at: t, actualTime: nil) {
                    out.append(UIImage(cgImage: cg))
                }
            }
            let done = out
            await MainActor.run { self?.strip = done }
        }
    }

    private func snap() -> Snapshot {
        Snapshot(pairs: pairs, segments: segments,
                 manualCuts: edit?.manualCuts ?? [],
                 manualKeeps: edit?.manualKeeps ?? [],
                 minSil: minSil, fillers: fillers, soft: softFillers,
                 splits: splits, zooms: zooms, rotations: rotations, kfZooms: kfZooms)
    }
    private func apply(_ s: Snapshot) {
        pairs = s.pairs; segments = s.segments
        minSil = s.minSil; fillers = s.fillers; softFillers = s.soft
        splits = s.splits
        zooms = s.zooms   // undo reverts the WHOLE zoom, not a frame of it
        rotations = s.rotations   // rotations undo the same way
        kfZooms = s.kfZooms       // keyframe ramps too
        if var e = edit { e.manualCuts = s.manualCuts; e.manualKeeps = s.manualKeeps; edit = e }
        rebuildKeepingTime()   // undo/redo must not throw the playhead to 0
    }
    /// Call before anything that changes the edit.
    func pushHistory() {
        past.append(snap())
        if past.count > 40 { past.removeFirst() }
        future.removeAll()
        canUndo = true; canRedo = false
    }
    func undo() {
        guard let last = past.popLast() else { return }
        future.append(snap())
        apply(last)
        canUndo = !past.isEmpty; canRedo = true
    }
    func redo() {
        guard let next = future.popLast() else { return }
        past.append(snap())
        apply(next)
        canUndo = true; canRedo = !future.isEmpty
    }

    /// Pick a take for one pair, then rebuild. nil = undecided (keeps both).
    func choose(pair idx: Int, take: String?) {
        guard idx < pairs.count else { return }
        pushHistory()
        pairs[idx].choice = take
        // WEB PARITY (clearRtManuals) — the missing line that let a chosen-away
        // take survive: a Restore from the Cuts list or a transcript tap sets a
        // manual keep flag on the segment, and manual outranks the retake
        // decision in isCut. The choice is the newest intent, so it wins:
        for i in segments.indices where segments[i].pair == idx && segments[i].retake != nil {
            segments[i].manual = nil
        }
        // Same story for reclaimed footage: a manualKeep overlapping the losing
        // take would resurrect it in cutIntervals — carve it off.
        if let t = take, t == "a" || t == "b", var e = edit {
            let loser = (t == "a") ? "b" : "a"
            for sg in segments where sg.pair == idx && sg.retake == loser {
                e.carveKeeps(for: ChopClip(start: sg.start, end: sg.end))
            }
            edit = e
        }
        // MULTI-TAKE pick ("k<i>"): every take of the pair EXCEPT the kept one
        // is a loser — carve keeps off all of them, same rule as above.
        if let t = take, t.hasPrefix("k"), let ki = Int(t.dropFirst()), var e = edit {
            let ranges = e.takeRanges(for: idx)
            for sg in segments where sg.pair == idx && sg.retake != nil {
                let kept = ki < ranges.count
                    && sg.start >= ranges[ki].lo - 0.01 && sg.start <= ranges[ki].hi + 0.01
                if !kept { e.carveKeeps(for: ChopClip(start: sg.start, end: sg.end)) }
            }
            edit = e
        }
        rebuildKeepingTime()
    }

    /// MULTI-TAKE: grouped marked segment indices for one pair — same 0.18s
    /// grouping rule as ChopEdit.takeRanges, but as player.segments indices so
    /// the retake panel can label, preview and choose individual takes.
    func takeGroups(pair idx: Int) -> [[Int]] {
        let marked = segments.indices
            .filter { segments[$0].pair == idx && segments[$0].retake != nil }
            .sorted { segments[$0].start < segments[$1].start }
        var out: [[Int]] = []
        var lastEnd = -1.0
        for i in marked {
            if !out.isEmpty, segments[i].start - lastEnd < 0.18 {
                out[out.count - 1].append(i)
            } else {
                out.append([i])
            }
            lastEnd = segments[i].end
        }
        return out
    }

    var undecided: Int { pairs.filter { $0.complete && $0.choice == nil }.count }

    /// Is this segment currently being cut? Uses the live edit, so it reflects
    /// slider changes and retake choices.
    func cut(_ i: Int) -> Bool {
        guard let e = edit, i < e.segments.count else { return false }
        return e.isCut(e.segments[i])
    }

    /// Tap a line to force it in or out — the web app's manual override.
    func toggleSegment(_ i: Int) {
        guard i < segments.count else { return }
        pushHistory()
        let wasCut = cut(i)
        segments[i].manual = !wasCut
        rebuildKeepingTime()
    }

    /// Where are we in the RAW timeline right now? Manual cuts are expressed in
    /// raw seconds, same as the web app, so everything stays interchangeable.
    var rawTime: Double {
        guard let e = edit else { return 0 }
        var acc = 0.0
        for clip in e.keptClips() {
            let len = clip.end - clip.start
            if time <= acc + len { return clip.start + (time - acc) }
            acc += len
        }
        return e.rawDur
    }

    /// The kept clip under the playhead, as an index into keptClips().
    var clipIndexAtPlayhead: Int? {
        guard let e = edit else { return nil }
        var acc = 0.0
        for (i, clip) in e.keptClips().enumerated() {
            let len = clip.end - clip.start
            if time <= acc + len { return i }
            acc += len
        }
        return nil
    }

    /// Delete the clip under the playhead by adding a manual cut over it.
    func deleteClipAtPlayhead() {
        guard let e = edit, let i = clipIndexAtPlayhead else { return }
        pushHistory()
        let clips = e.keptClips()
        guard i < clips.count else { return }
        var ed = e
        let cut = ChopClip(start: clips[i].start, end: clips[i].end)
        ed.carveKeeps(for: cut)
        ed.manualCuts.append(cut)
        edit = ed
        rebuild()
    }

    /// Trim everything before, or after, the playhead within the current clip.
    func trimAtPlayhead(keepAfter: Bool) {
        guard let e = edit, let i = clipIndexAtPlayhead else { return }
        pushHistory()
        let clips = e.keptClips()
        guard i < clips.count else { return }
        let clip = clips[i]
        let at = rawTime
        guard at > clip.start + 0.05, at < clip.end - 0.05 else { return }
        var ed = e
        let cut = keepAfter ? ChopClip(start: clip.start, end: at)
                            : ChopClip(start: at, end: clip.end)
        ed.carveKeeps(for: cut)
        ed.manualCuts.append(cut)
        edit = ed
        rebuild()
    }

    // MARK: quick-edit bands — ADDITIVE layer over the locked core.
    // Splits are the web's state.splits: pure band boundaries, NO footage
    // change, NO rebuild — which is why Split never jumps.

    @Published var splits: [Double] = []   // raw times

    // MARK: per-clip zoom — TikTok pinch on the video. Raw-time ranges, so
    // zooms survive trims/splits. In-memory for the session, like splits.
    // FREEFORM (Lewis 18 Aug): each zoom also carries an offset — drag the
    // zoomed clip anywhere on the canvas, black background allowed. ox/oy are
    // fractions of the cage size; 0/0 renders byte-identically to before.
    @Published var zooms: [(start: Double, end: Double, scale: CGFloat, ox: CGFloat, oy: CGFloat)] = []

    func zoom(forBand i: Int) -> CGFloat {
        guard i < bands.count else { return 1 }
        let b = bands[i]
        return zooms.first(where: { $0.start < b.end && $0.end > b.start })?.scale ?? 1
    }
    func setZoom(_ scale: CGFloat, forBand i: Int) {
        guard i < bands.count else { return }
        let b = bands[i]
        let old = zooms.first(where: { $0.start < b.end && $0.end > b.start })
        zooms.removeAll { $0.start < b.end && $0.end > b.start }
        let s = min(3, max(1, scale))
        if s > 1.01 { zooms.append((b.start, b.end, s, old?.ox ?? 0, old?.oy ?? 0)) }
        scheduleSave()   // zooms don't rebuild — save them explicitly
    }
    func zoomOffset(forBand i: Int) -> (ox: CGFloat, oy: CGFloat) {
        guard i < bands.count else { return (0, 0) }
        let b = bands[i]
        guard let z = zooms.first(where: { $0.start < b.end && $0.end > b.start }) else { return (0, 0) }
        return (z.ox, z.oy)
    }
    func setZoomOffset(ox: CGFloat, oy: CGFloat, forBand i: Int) {
        guard i < bands.count else { return }
        let b = bands[i]
        guard let zi = zooms.firstIndex(where: { $0.start < b.end && $0.end > b.start }) else { return }
        zooms[zi].ox = min(1.2, max(-1.2, ox))   // anywhere on the canvas
        zooms[zi].oy = min(1.2, max(-1.2, oy))
        scheduleSave()
    }
    /// The zoom in force at a moment of the EDIT — drives playback preview.
    func zoomScale(atEditTime t: Double) -> CGFloat {
        guard let r = raw(fromEdit: t) else { return 1 }
        return zooms.first(where: { r >= $0.start - 0.001 && r <= $0.end + 0.001 })?.scale ?? 1
    }
    /// The zoom offset in force at a moment of the EDIT.
    func zoomOffset(atEditTime t: Double) -> CGSize {
        guard let r = raw(fromEdit: t),
              let z = zooms.first(where: { r >= $0.start - 0.001 && r <= $0.end + 0.001 })
        else { return .zero }
        return CGSize(width: z.ox, height: z.oy)
    }

    // MARK: per-clip ROTATION (Lewis 18 Aug v2) — the exact same shape as
    // per-clip zoom above: raw-time ranges so rotations survive trims/splits,
    // one tap = one undoable action, saved with the job. The video stays in
    // its LOCKED portrait cage — a sideways clip letterboxes inside it.
    @Published var rotations: [(start: Double, end: Double, q: Int)] = []

    func rotationQ(forBand i: Int) -> Int {
        guard i < bands.count else { return 0 }
        let b = bands[i]
        return rotations.first(where: { $0.start < b.end && $0.end > b.start })?.q ?? 0
    }
    /// One tap = this clip turns 90° clockwise; four taps = back to normal.
    func rotate(band i: Int) {
        guard i < bands.count else { return }
        pushHistory()   // one tap = one undoable action (mirrors pinch zoom)
        let b = bands[i]
        let q = (rotationQ(forBand: i) + 1) % 4
        rotations.removeAll { $0.start < b.end && $0.end > b.start }
        if q != 0 { rotations.append((b.start, b.end, q)) }
        scheduleSave()   // rotations don't rebuild — save them explicitly
    }
    /// The rotation in force at a moment of the EDIT — drives the preview.
    func rotationQ(atEditTime t: Double) -> Int {
        guard let r = raw(fromEdit: t) else { return 0 }
        return rotations.first(where: { r >= $0.start - 0.001 && r <= $0.end + 0.001 })?.q ?? 0
    }

    // MARK: KEYFRAME ZOOMS (Lewis 18 Aug) — TikTok-style ramp. Tap the diamond
    // to drop keyframe 1, scrub ahead, tap again: the video zooms IN gradually
    // from 1× at the first keyframe to the target at the second, then snaps
    // back to normal. Pinch (with no clip selected) sets the target. Separate
    // list from the locked per-clip pinch zooms; raw-time ranges like them.
    @Published var kfZooms: [(start: Double, end: Double, scale: CGFloat, ax: CGFloat, ay: CGFloat)] = []
    @Published var kfPending: Double? = nil   // first keyframe dropped (raw time)

    func kfIndex(atEditTime t: Double) -> Int? {
        guard let r = raw(fromEdit: t) else { return nil }
        return kfZooms.firstIndex(where: { r >= $0.start - 0.001 && r <= $0.end + 0.001 })
    }
    /// LOCKED-ON check (Lewis 19 Aug): the ramp whose DIAMOND the playhead is
    /// sitting on (within a small tolerance — the scrub magnet parks it there).
    /// Used so a pinch with a clip selected can still drive the keystone, but
    /// ONLY when the stick is actually on a keystone.
    func kfIndexLocked(atEditTime t: Double, eps: Double = 0.08) -> Int? {
        guard let r = raw(fromEdit: t) else { return nil }
        return kfZooms.firstIndex(where: { abs(r - $0.start) <= eps || abs(r - $0.end) <= eps })
    }
    /// The ramped keyframe scale at an EDIT moment — multiplies the preview.
    func kfScale(atEditTime t: Double) -> CGFloat {
        guard let r = raw(fromEdit: t),
              let k = kfZooms.first(where: { r >= $0.start - 0.001 && r <= $0.end + 0.001 })
        else { return 1 }
        let f = (r - k.start) / max(k.end - k.start, 0.001)
        return 1 + (k.scale - 1) * CGFloat(min(max(f, 0), 1))
    }
    /// FREEFORM (Lewis 18 Aug): the ramp zooms toward a chosen focal point —
    /// dragged while pinching — not just the centre. 0.5/0.5 = centre.
    func kfAnchorUnit(atEditTime t: Double) -> UnitPoint {
        guard let r = raw(fromEdit: t),
              let k = kfZooms.first(where: { r >= $0.start - 0.001 && r <= $0.end + 0.001 })
        else { return .center }
        return UnitPoint(x: 0.5 + Double(k.ax), y: 0.5 + Double(k.ay))
    }
    func setKFTarget(_ s: CGFloat, at i: Int) {
        guard i < kfZooms.count else { return }
        kfZooms[i].scale = min(3, max(1.0, s))   // 1.0 = inert ramp (nothing happens)
        scheduleSave()
    }
    func setKFAnchor(ax: CGFloat, ay: CGFloat, at i: Int) {
        guard i < kfZooms.count else { return }
        kfZooms[i].ax = min(0.5, max(-0.5, ax))
        kfZooms[i].ay = min(0.5, max(-0.5, ay))
        scheduleSave()
    }
    /// Keyframe marker positions in EDIT time — timeline diamonds + scrub magnet.
    var kfMarkersEdit: [Double] {
        var pts: [Double] = []
        for k in kfZooms {
            if let a = editTime(fromRaw: k.start) { pts.append(a) }
            if let b = editTime(fromRaw: k.end) { pts.append(b) }
        }
        if let pnd = kfPending, let a = editTime(fromRaw: pnd) { pts.append(a) }
        return pts
    }
    /// The diamond button — SILENT (Lewis: the timeline icons say it all).
    /// 1st tap arms a keyframe at the playhead; 2nd tap further along
    /// completes the ramp; a tap inside an existing ramp removes it; a tap on
    /// the armed spot cancels it.
    func keyframeTapped() {
        guard showEdited, let r = raw(fromEdit: time) else { return }
        if kfPending == nil,
           let i = kfZooms.firstIndex(where: { r >= $0.start - 0.001 && r <= $0.end + 0.001 }) {
            pushHistory()
            kfZooms.remove(at: i)
            scheduleSave()
            return
        }
        if let a = kfPending {
            if r > a + 0.2 {
                pushHistory()
                kfZooms.removeAll { $0.start < r && $0.end > a }   // no overlaps
                // scale 1.0 = INERT (Lewis): dropping keyframes does nothing
                // visible until the creator pinches to set how far it zooms
                kfZooms.append((a, r, 1.0, 0, 0))
                kfPending = nil
                scheduleSave()
            } else if abs(r - a) <= 0.2 {
                kfPending = nil   // tapped the armed spot — cancel
            }
            // tapped BEFORE the armed keyframe: ignore silently
            return
        }
        kfPending = r
    }

    /// Kept footage subdivided by splits — the web's qeBands(), in raw time.
    var bands: [(start: Double, end: Double)] {
        guard let e = edit else { return [] }
        var out: [(Double, Double)] = []
        for c in e.keptClips() {
            var cur = c.start
            for s in splits.sorted() where s > c.start + 0.02 && s < c.end - 0.02 {
                out.append((cur, s)); cur = s
            }
            out.append((cur, c.end))
        }
        return out
    }

    /// Same bands mapped to EDIT time for drawing + hit-testing.
    var bandSpansEdit: [(start: Double, end: Double)] {
        bands.compactMap { b in
            guard let s = editTime(fromRaw: b.start), let e2 = editTime(fromRaw: b.end) else { return nil }
            return (s, e2)
        }
    }

    func bandIndex(atEditTime t: Double) -> Int? {
        for (i, s) in bandSpansEdit.enumerated() where t >= s.start && t <= s.end { return i }
        return nil
    }

    func raw(fromEdit t: Double) -> Double? {
        guard let e = edit else { return nil }
        var acc = 0.0
        for c in e.keptClips() {
            let l = c.end - c.start
            if t <= acc + l { return c.start + (t - acc) }
            acc += l
        }
        return nil
    }

    func editTime(fromRaw t: Double) -> Double? {
        guard let e = edit else { return nil }
        var acc = 0.0
        for c in e.keptClips() {
            if t >= c.start - 0.001 && t <= c.end + 0.001 { return acc + max(0, t - c.start) }
            acc += c.end - c.start
        }
        return nil
    }

    /// Settings changed from a panel — rebuild without losing the playhead.
    func retune() { rebuildKeepingTime() }

    /// Rebuild but land the playhead back where the finger left it (raw-anchored).
    /// Time is written synchronously and the clock muted briefly, so the UI
    /// never renders a stale frame between rebuild and seek.
    private func rebuildKeepingTime() {
        // raw mode: rebuild() already holds the raw playhead in place
        guard showEdited else { rebuild(); return }
        let anchor = raw(fromEdit: time)
        scrubbing = true
        rebuild()
        let target: Double
        if let a = anchor, let t = editTime(fromRaw: a) {
            target = min(t, max(0, duration - 0.05))
        } else {
            target = min(time, max(0, duration - 0.05))
        }
        time = target
        seekExact(to: target)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.scrubbing = false
        }
    }

    /// Web qeSplit: pure boundary, footage untouched, RIGHT band stays selected.
    /// Returns the index of the right-hand band.
    func splitBand(atEditTime t: Double) -> Int? {
        guard let at = raw(fromEdit: t) else { return nil }
        guard let e = edit,
              e.keptClips().contains(where: { at > $0.start + 0.05 && at < $0.end - 0.05 })
        else { return nil }
        pushHistory()
        splits.append(at)
        scheduleSave()   // splits don't rebuild — save them explicitly
        return bands.firstIndex { abs($0.start - at) < 0.06 }
    }

    /// Web qeDelete: manual cut over the band. The playhead lands EXACTLY on
    /// the join where the two neighbours close together.
    func deleteBand(_ i: Int) {
        let bs = bands; guard i < bs.count, var e = edit else { return }
        pushHistory()
        let b = bs[i]
        let cut = ChopClip(start: b.start, end: b.end)
        e.carveKeeps(for: cut)
        e.manualCuts.append(cut)
        edit = e
        scrubbing = true
        rebuild()
        // the deleted band's end now maps to the join between the neighbours
        let join = editTime(fromRaw: b.end + 0.01)
            ?? editTime(fromRaw: b.start - 0.01)
            ?? min(time, max(0, duration - 0.05))
        let target = max(0, min(join, duration))
        time = target
        seekExact(to: target)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.scrubbing = false
        }
    }

    // How far an edge can be dragged OUT: the whole gap to the neighbouring
    // kept clip (or to the ends of the raw footage) is reclaimable — it makes
    // no difference whether the auto-editor or the creator cut it.
    func bandExtendLeft(_ i: Int) -> Double {
        guard i < bands.count else { return 0 }
        let b = bands[i]
        let prevEnd = i > 0 ? bands[i - 1].end : 0
        return max(0, b.start - prevEnd - 0.01)
    }
    func bandExtendRight(_ i: Int) -> Double {
        guard let e = edit, i < bands.count else { return 0 }
        let b = bands[i]
        let nextStart = i + 1 < bands.count ? bands[i + 1].start : e.rawDur
        return max(0, nextStart - b.end - 0.01)
    }

    /// TikTok caps: drag IN = trim (manual cut over the edge), drag OUT =
    /// extend (shrink the adjacent manual cut back). Playhead stays put.
    func resizeBand(_ i: Int, side: Int, deltaSeconds: Double) {
        let bs = bands; guard i < bs.count, var e = edit, abs(deltaSeconds) > 0.02 else { return }
        let b = bs[i]
        pushHistory()
        if side == 0 {
            if deltaSeconds > 0 {          // trim the front
                let cut = ChopClip(start: b.start, end: min(b.start + deltaSeconds, b.end - 0.05))
                e.carveKeeps(for: cut)     // newest intent wins
                e.manualCuts.append(cut)
            } else {                       // extend the front — reclaim ANY cut footage
                let need = min(-deltaSeconds, bandExtendLeft(i))
                if need > 0.005 {
                    e.manualKeeps.append(ChopClip(start: b.start - need, end: b.start))
                }
            }
        } else {
            if deltaSeconds > 0 {          // trim the back
                let cut = ChopClip(start: max(b.end - deltaSeconds, b.start + 0.05), end: b.end)
                e.carveKeeps(for: cut)
                e.manualCuts.append(cut)
            } else {                       // extend the back — reclaim ANY cut footage
                let need = min(-deltaSeconds, bandExtendRight(i))
                if need > 0.005 {
                    e.manualKeeps.append(ChopClip(start: b.end, end: b.end + need))
                }
            }
        }
        edit = e
        // freeze the clock so the observer can't paint a stale frame mid-swap
        scrubbing = true
        rebuild()
        // TikTok: the cursor lands exactly on the cut you just made
        let edgeRaw = side == 0 ? b.start + deltaSeconds + 0.005
                                : b.end - deltaSeconds - 0.005
        let target = editTime(fromRaw: edgeRaw).map { max(0, min($0, max(0, duration - 0.02))) }
            ?? min(time, max(0, duration - 0.02))
        time = target              // stick lands in the SAME render pass — no flicker
        seekExact(to: target)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.scrubbing = false
        }
    }

    var manualCutCount: Int { edit?.manualCuts.count ?? 0 }

    func undoManualCuts() {
        guard var ed = edit, !ed.manualCuts.isEmpty else { return }
        ed.manualCuts.removeLast()
        edit = ed
        rebuild()
    }

    func clearManual(_ i: Int) {
        guard i < segments.count else { return }
        segments[i].manual = nil
        rebuild()
    }

    /// Jump the player to where a line starts, in EDIT time.
    /// The line's EXACT start is usually shaved by the clip pads (−260ms on
    /// Recommended), so match the first kept moment that OVERLAPS the line —
    /// the old exact-start lookup missed and fell back to 0, restarting the
    /// whole video instead of playing the take.
    func playFrom(segment i: Int) {
        guard let e = edit, i < e.segments.count else { return }
        let seg = e.segments[i]
        var acc = 0.0
        for clip in e.keptClips() {
            let s = max(seg.start, clip.start)
            let en = min(seg.end, clip.end)
            if en - s > 0.02 {   // first kept slice of this line
                seekExact(to: min(acc + (s - clip.start), max(0, duration - 0.02)))
                return
            }
            acc += clip.end - clip.start
        }
        // the whole line is cut — never jump to 0, just say so
        ChopToasts.shared.show("That take is cut from the edit — Keep it to preview")
    }

    /// Recompute the cuts and rebuild the composition. No re-download.
    func rebuild() {
        guard let local = localURL, var e = edit else { return }
        e.settings.minSil = minSil
        e.settings.fillers = fillers
        e.settings.soft = softFillers
        e.settings.startPadMs = padStart
        e.settings.endPadMs = padEnd
        e.pairs = pairs
        e.segments = segments
        edit = e   // manualCuts already live on `e`

        let kept = e.keptClips()
        clipCount = kept.count
        cutCount = max(0, kept.count - 1)
        guard !kept.isEmpty else { status = "Nothing left after cutting"; ready = false; return }

        status = "Building the edit…"
        let src = AVURLAsset(url: local)
        let comp = AVMutableComposition()
        guard let srcV = src.tracks(withMediaType: .video).first,
              let vTrack = comp.addMutableTrack(withMediaType: .video,
                                                preferredTrackID: kCMPersistentTrackID_Invalid) else {
            status = "No video track"; return
        }
        let srcA = src.tracks(withMediaType: .audio).first
        let aTrack = comp.addMutableTrack(withMediaType: .audio,
                                          preferredTrackID: kCMPersistentTrackID_Invalid)

        var cursor = CMTime.zero
        for clip in kept {
            let start = CMTime(seconds: clip.start, preferredTimescale: 600)
            let dur   = CMTime(seconds: max(0, clip.end - clip.start), preferredTimescale: 600)
            let range = CMTimeRange(start: start, duration: dur)
            do {
                try vTrack.insertTimeRange(range, of: srcV, at: cursor)
                if let srcA = srcA, let aTrack = aTrack {
                    try aTrack.insertTimeRange(range, of: srcA, at: cursor)
                }
                cursor = CMTimeAdd(cursor, dur)
            } catch {
                status = "Couldn't build the edit: \(error.localizedDescription)"; return
            }
        }
        vTrack.preferredTransform = srcV.preferredTransform

        let wasPlaying = player.rate > 0
        composition = comp
        editedDuration = cursor.seconds
        rawDuration = src.duration.seconds
        // the cage: the video's true display aspect (rotation applied)
        let vb = CGRect(origin: .zero, size: srcV.naturalSize).applying(srcV.preferredTransform)
        if abs(vb.width) > 1, abs(vb.height) > 1 { videoAspect = abs(vb.width) / abs(vb.height) }
        // the red bands are always derived from the LIVE kept list, so any
        // delete / split / restore / retune redraws them automatically
        rawCuts = ChopPlayer.cutGaps(kept: kept, rawDur: rawDuration)
        if showEdited {
            player.replaceCurrentItem(with: AVPlayerItem(asset: comp))
            duration = editedDuration
            buildStrip(comp)
        } else {
            // stay on the raw footage — refresh the item and let the bands redraw
            let keep = min(time, max(0, rawDuration - 0.05))
            player.replaceCurrentItem(with: AVPlayerItem(asset: src))
            duration = rawDuration
            buildStrip(src)
            seekExact(to: keep)
        }
        ready = true
        status = ""
        observeTime()
        if wasPlaying { player.play() }
        scheduleSave()   // every rebuild = an edit happened → debounced cloud save
    }

    /// Complement of the kept clips over the raw timeline — everything cut out.
    private static func cutGaps(kept: [ChopClip], rawDur: Double) -> [(start: Double, end: Double)] {
        var out: [(start: Double, end: Double)] = []
        var pos = 0.0
        for c in kept.sorted(by: { $0.start < $1.start }) {
            if c.start > pos + 0.05 { out.append((pos, c.start)) }
            pos = max(pos, c.end)
        }
        if rawDur > pos + 0.05 { out.append((pos, rawDur)) }
        return out
    }

    /// Flip between the edit and the full original, keeping the playhead on
    /// the same moment of footage in both directions.
    func setMode(edited: Bool) {
        guard edited != showEdited else { return }
        guard let local = localURL else { showEdited = edited; return }
        let wasPlaying = player.rate > 0
        player.pause()
        if edited {
            let anchorRaw = time   // raw seconds while in raw mode
            showEdited = true
            guard let comp = composition else { return }
            player.replaceCurrentItem(with: AVPlayerItem(asset: comp))
            duration = editedDuration
            buildStrip(comp)
            observeTime()
            let t = editTime(fromRaw: anchorRaw) ?? 0
            seekExact(to: min(t, max(0, duration - 0.05)))
        } else {
            let anchorRaw = raw(fromEdit: time) ?? 0
            showEdited = false
            let src = AVURLAsset(url: local)
            player.replaceCurrentItem(with: AVPlayerItem(asset: src))
            rawDuration = src.duration.seconds
            duration = rawDuration
            buildStrip(src)
            observeTime()
            seekExact(to: min(anchorRaw, max(0, duration - 0.05)))
        }
        if wasPlaying { player.play() }
    }
}

struct ChopPlayerScreen: View {
    let job: ChopJob
    @ObservedObject var api: ChopAPI
    @StateObject private var p = ChopPlayer()
    @State private var panel: String? = "retakes"
    @State private var marking = false
    @State private var selected: Int? = nil   // selected timeline section
    @State private var compact = false        // web body.stagecompact: 50dvh ↔ 24dvh
    @State private var dragShift: CGFloat = 0 // live finger-follow while swiping the video small/big
    @AppStorage("chopEditorTourSeen") private var editorTourSeen = false
    @State private var showEditorTour = false
    @State private var showFinishSheet = false   // tick → export or save for later
    @State private var pinchStart: CGFloat? = nil   // pinch-zoom on the selected clip
    @State private var pinchLive: CGFloat? = nil
    @State private var pinchKF: Int? = nil          // pinch is adjusting this keyframe ramp
    @State private var kfPanStart: (CGFloat, CGFloat)? = nil   // anchor at freeform-drag start
    @State private var kfDragging = false           // show the centre guides
    @State private var kfGuideIdx: Int? = nil       // ramp whose guides are showing
    @State private var clipPanSel: Int? = nil       // clip being freeform-dragged
    @State private var cageSize: CGSize = .zero     // measured cage — pan maths

    /// FREEFORM (Lewis 18 Aug v2): the keyframe ramp a one-finger drag should
    /// pan right now — during a keyframe pinch, or any time the playhead sits
    /// inside a ramp that actually zooms. nil = drags mean swipe-up as usual.
    private var panKF: Int? {
        guard p.showEdited, selected == nil, pinchLive == nil else { return nil }
        if let ki = pinchKF { return ki }
        if let ki = p.kfIndex(atEditTime: p.time), p.kfZooms[ki].scale > 1.01 { return ki }
        return nil
    }
    /// FREEFORM v3: a SELECTED, zoomed clip is draggable anywhere on the
    /// canvas (black background allowed) — including while the pinch is live.
    private var panClip: Int? {
        guard p.showEdited, let sel = selected, sel < p.bands.count,
              p.zoom(forBand: sel) > 1.01 else { return nil }
        return sel
    }
    @Environment(\.dismiss) private var dismiss

    static let tourSteps: [ChopCoachStep] = [
        .init(id: "tour-modes", title: "Two views",
              text: "Edited plays your final cut. Raw shows the full original with everything Chop removed banded in red — and how much time you saved."),
        .init(id: "tour-timeline", title: "The timeline",
              text: "Drag to scrub, pinch to zoom. Tap a clip to select it, then Split, Delete or Restore."),
        .init(id: "tour-retakes", title: "Retakes",
              text: "Repeated takes appear side by side — pick the keeper. The orange badge counts the ones still undecided."),
        .init(id: "tour-cuts", title: "Cuts",
              text: "A cut too tight, or a pause left in? Sliders, clip pads and one-tap presets live here — Recommended ★ is on by default."),
        .init(id: "tour-export", title: "Export",
              text: "Renders the final cut and saves it straight to your camera roll."),
        .init(id: "tour-done", title: "Approve",
              text: "The green tick moves a finished video to Ready to export in the queue. That's the lot — go chop."),
    ]

    private func clock(_ t: Double) -> String {
        let s = Int(t.rounded()); return String(format: "%d:%02d", s / 60, s % 60)
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {

                // ---- video stage: 50% of the screen, 24% when the panel is up ----
                ZStack(alignment: .top) {
                    // THE CAGE (Lewis): the video sits in a frame matching its
                    // true aspect; zoom scales INSIDE that frame and crops at
                    // its edges — never spilling into the letterbox — so the
                    // preview is exactly what the export renders.
                    // ROTATE v2 (18 Aug): per-clip, INSIDE the locked cage — the
                    // portrait frame never changes; a sideways clip letterboxes
                    // within it (rotate + fit-scale before the cage sizing).
                    // rotQ == 0 → both extra modifiers are no-ops and the chain
                    // renders exactly as the locked original.
                    // SMOOTH RAMPS (Lewis 18 Aug v3): while a keyframed video
                    // plays, TimelineView re-samples the ramp maths every
                    // screen frame straight off the player clock — the zoom
                    // climbs continuously (1.1, 1.2, 1.3…) instead of stepping
                    // at the 20Hz publish rate. Paused/keyframe-free videos
                    // don't tick; the chain then renders exactly as before.
                    TimelineView(.animation(minimumInterval: 1.0 / 60,
                                            paused: p.kfZooms.isEmpty || !p.isPlaying)) { _ in
                    let liveT = p.isPlaying && !p.kfZooms.isEmpty
                        ? p.player.currentTime().seconds : p.time
                    let rotQ = p.rotationQ(atEditTime: liveT)
                    let rotFit: CGFloat = rotQ % 2 == 1
                        ? min(p.videoAspect, 1 / p.videoAspect) : 1
                    let zOff = p.zoomOffset(atEditTime: liveT)
                    PlayerLayerView(player: p.player)
                        .rotationEffect(.degrees(Double(rotQ) * 90))
                        .scaleEffect(rotFit)
                        .aspectRatio(p.videoAspect, contentMode: .fit)
                        .background(GeometryReader { cg in   // cage size for the freeform pan maths
                            Color.clear
                                .onAppear { cageSize = cg.size }
                                .onChange(of: cg.size) { _, s in cageSize = s }
                        })
                        .scaleEffect(pinchLive ?? p.zoomScale(atEditTime: liveT))
                        // FREEFORM clip offset — drag the zoomed clip anywhere
                        .offset(x: zOff.width * cageSize.width,
                                y: zOff.height * cageSize.height)
                        // KEYFRAME ramp on top: zooms toward its own focal
                        // point (freeform), ×1 when no keyframes
                        .scaleEffect(p.kfScale(atEditTime: liveT),
                                     anchor: p.kfAnchorUnit(atEditTime: liveT))
                        .animation(.easeInOut(duration: 0.15),
                                   value: pinchLive ?? p.zoomScale(atEditTime: liveT))
                        .animation(.easeInOut(duration: 0.25), value: rotQ)
                        .clipped()   // the cage wall
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                    }

                    // centre guides while freeform-dragging (clip OR keyframe) —
                    // bright when snapped to centre, faint otherwise
                    if kfDragging {
                        let centred: (x: Bool, y: Bool) = {
                            if let sel = clipPanSel {
                                let o = p.zoomOffset(forBand: sel)
                                return (o.ox == 0, o.oy == 0)
                            }
                            if let ki = kfGuideIdx, ki < p.kfZooms.count {
                                return (p.kfZooms[ki].ax == 0, p.kfZooms[ki].ay == 0)
                            }
                            return (false, false)
                        }()
                        ZStack {
                            Rectangle()
                                .fill(Color.white.opacity(centred.x ? 0.95 : 0.25))
                                .frame(width: 1.5)
                            Rectangle()
                                .fill(Color.white.opacity(centred.y ? 0.95 : 0.25))
                                .frame(height: 1.5)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                    }

                    HStack(spacing: 2) {
                        modePill("Raw", on: !p.showEdited)
                        modePill("Edited", on: p.showEdited)
                    }
                    .padding(3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                    .padding(.top, 10)
                    .tourAnchor("tour-modes")

                    // Raw mode: the whole point — how much time Chop is saving
                    if !p.showEdited, p.rawDuration > p.editedDuration + 0.5 {
                        VStack {
                            Spacer()
                            Text("Saving you \(Int((p.rawDuration - p.editedDuration).rounded()))s of dead air & fillers")
                                .font(.system(size: 11.5, weight: .heavy))
                                .foregroundStyle(ChopColor.green)
                                .padding(.horizontal, 13).padding(.vertical, 6)
                                .background(Color(red: 10/255, green: 12/255, blue: 18/255).opacity(0.6), in: Capsule())
                                .overlay(Capsule().stroke(ChopColor.green.opacity(0.4), lineWidth: 1))
                                .padding(.bottom, 12)
                        }
                        .frame(maxHeight: .infinity)
                        .allowsHitTesting(false)
                    }

                    // back (doubles as Queue) top-left · green Done tick top-right
                    HStack(spacing: 6) {
                        glassCircle("arrow.left", enabled: true) { dismiss() }
                        Spacer()
                        Button {
                            doneTapped()
                        } label: {
                            Group {
                                if marking {
                                    ProgressView().scaleEffect(0.65).tint(ChopColor.green)
                                } else {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 15, weight: .heavy))
                                        .foregroundStyle(ChopColor.green)
                                }
                            }
                            .frame(width: 38, height: 38)
                            .background(Color(red: 10/255, green: 12/255, blue: 18/255).opacity(0.5), in: Circle())
                            .background(.ultraThinMaterial, in: Circle())
                        }
                        .disabled(marking)
                        // long-press = approve instantly, no question (power users)
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45)
                            .onEnded { _ in quickApprove() })
                        .tourAnchor("tour-done")
                    }
                    .padding(.top, 10).padding(.horizontal, 10)
                }
                .frame(height: (p.ready ? geo.size.height * (compact ? 0.24 : 0.50)
                                        : geo.size.height * 0.50) + dragShift)
                .clipped()
                .animation(.spring(response: 0.38, dampingFraction: 0.85), value: compact)
                .onTapGesture {
                    if compact { compact = false }        // bring the video back first
                    else if p.ready { p.togglePlay() }    // CapCut: tap preview = play/pause
                }
                // Swipe the video itself small/big — tuned "middle ground" (Lewis,
                // 17 Aug, HTML gesture tuner): 12pt dead zone (minimumDistance),
                // the video FOLLOWS the finger at 0.85×, release commits at 80pt
                // of pull OR a 550pt/s flick — anything less springs back.
                // simultaneousGesture so tap (play/pause) and the LOCKED pinch
                // zoom are untouched; bails the moment a pinch is live.
                .simultaneousGesture(DragGesture(minimumDistance: 12)
                    .onChanged { g in
                        guard p.ready, pinchStart == nil, pinchLive == nil,
                              panKF == nil, panClip == nil else { return }   // freeform pan owns this drag
                        let span = geo.size.height * (0.50 - 0.24)
                        let ty = g.translation.height * 0.85
                        dragShift = compact ? min(span, max(0, ty)) : max(-span, min(0, ty))
                    }
                    .onEnded { g in
                        guard p.ready, pinchStart == nil, pinchLive == nil,
                              panKF == nil, panClip == nil else {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) { dragShift = 0 }
                            return
                        }
                        let pull = abs(g.translation.height) * 0.85
                        let flick = abs(g.predictedEndTranslation.height - g.translation.height) * 4
                        let rightWay = compact ? g.translation.height > 0 : g.translation.height < 0
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                            if rightWay, pull >= 80 || flick >= 550 { compact.toggle() }
                            dragShift = 0
                        }
                    })
                // TikTok: pinch the video to zoom the SELECTED clip only
                .simultaneousGesture(MagnificationGesture()
                    .onChanged { v in
                        // KEYFRAME ZOOM (additive, early return): no clip
                        // selected + playhead inside a ramp → pinch sets the
                        // ramp's TARGET zoom. The locked selected-clip path
                        // below is untouched.
                        // + Lewis 19 Aug: with a clip SELECTED the keystone
                        // still wins — but ONLY when the playhead is locked
                        // right on a keystone diamond (kfIndexLocked). Off the
                        // diamond, the selected-clip pinch behaves exactly as
                        // it always has.
                        if p.showEdited,
                           pinchKF != nil || pinchStart == nil,
                           let ki = pinchKF ?? (selected == nil
                                ? p.kfIndex(atEditTime: p.time)
                                : p.kfIndexLocked(atEditTime: p.time)) {
                            if pinchStart == nil {
                                pinchStart = p.kfZooms[ki].scale
                                pinchKF = ki
                                p.pushHistory()   // one pinch = one undoable action
                            }
                            p.setKFTarget((pinchStart ?? 1.5) * v, at: ki)
                            return
                        }
                        guard p.showEdited, let sel = selected, sel < p.bands.count else { return }
                        if pinchStart == nil {
                            pinchStart = p.zoom(forBand: sel)
                            p.pushHistory()   // one pinch = one undoable action
                        }
                        let s = min(3, max(1, (pinchStart ?? 1) * v))
                        pinchLive = s
                        p.setZoom(s, forBand: sel)
                    }
                    .onEnded { _ in
                        if pinchKF != nil {
                            // silent (Lewis): the timeline diamonds say it all
                            pinchKF = nil; pinchStart = nil
                            kfDragging = false; kfPanStart = nil
                            return
                        }
                        defer { pinchStart = nil; pinchLive = nil }
                        guard p.showEdited, let sel = selected, sel < p.bands.count,
                              pinchStart != nil else { return }
                        let z = p.zoom(forBand: sel)
                        ChopToasts.shared.show(z > 1.01
                            ? String(format: "Zoomed %.1f× — this clip only", z)
                            : "Zoom reset")
                    })
                // FREEFORM PAN (Lewis 18 Aug v2): one-finger drag moves the
                // video whenever the playhead sits inside a ZOOMED keyframe
                // ramp (and during the pinch itself) — the focal point follows
                // the finger, snapping to centre with guide lines. The swipe-up
                // gesture stands down for exactly these drags (guard on panKF)
                // and works normally everywhere else.
                .simultaneousGesture(DragGesture(minimumDistance: 4)
                    .onChanged { g in
                        guard cageSize.width > 1, cageSize.height > 1 else { return }
                        // FREEFORM CLIP PAN (v3): a selected, zoomed clip
                        // follows the finger 1:1 — anywhere on the canvas,
                        // black background allowed. Centre snap + guides.
                        if let sel = clipPanSel ?? panClip {
                            if kfPanStart == nil {
                                p.pushHistory()   // one drag = one undoable action
                                let o = p.zoomOffset(forBand: sel)
                                kfPanStart = (o.ox, o.oy)
                                clipPanSel = sel
                            }
                            kfDragging = true
                            var ox = (kfPanStart?.0 ?? 0) + g.translation.width / cageSize.width
                            var oy = (kfPanStart?.1 ?? 0) + g.translation.height / cageSize.height
                            if abs(ox) < 0.03 { ox = 0 }   // centre snap, both axes
                            if abs(oy) < 0.03 { oy = 0 }
                            p.setZoomOffset(ox: ox, oy: oy, forBand: sel)
                            return
                        }
                        // KEYFRAME focal-point pan (unchanged)
                        guard let ki = kfGuideIdx ?? panKF, ki < p.kfZooms.count else { return }
                        if kfPanStart == nil {
                            p.pushHistory()   // one drag = one undoable action
                            kfPanStart = (p.kfZooms[ki].ax, p.kfZooms[ki].ay)
                            kfGuideIdx = ki
                        }
                        kfDragging = true
                        // finger moves the video by d → the anchor shifts the
                        // other way, scaled by how much the zoom magnifies
                        let mag = max(p.kfZooms[ki].scale - 1, 0.05)
                        var ax = (kfPanStart?.0 ?? 0) - g.translation.width / (mag * cageSize.width)
                        var ay = (kfPanStart?.1 ?? 0) - g.translation.height / (mag * cageSize.height)
                        if abs(ax) < 0.03 { ax = 0 }   // centre snap, both axes
                        if abs(ay) < 0.03 { ay = 0 }
                        p.setKFAnchor(ax: ax, ay: ay, at: ki)
                    }
                    .onEnded { _ in
                        kfDragging = false; kfPanStart = nil
                        kfGuideIdx = nil; clipPanSel = nil
                    })

                if p.ready {
                    playBar
                    ChopTimeline(p: p, selected: $selected)
                        .frame(height: 116)   // TikTok strip + doubled thumb pad
                        .tourAnchor("tour-timeline")
                        .zIndex(2)   // the white selection frame overhangs — draw above neighbours

                    // selection swaps the toolbar for Split/Delete/Restore — web body.qesel
                    if let sel = selected, sel < p.bandSpansEdit.count {
                        selBar(sel)
                    } else {
                        toolbar
                    }

                    // ---- panel: fills the rest; grabber swipes video small/big ----
                    if let panel {
                        VStack(spacing: 0) {
                            // Grabber: bigger target, reacts mid-swipe (no hunting
                            // for a release point), and a plain tap toggles too.
                            Capsule().fill(Color.chopMuted.opacity(0.55))
                                .frame(width: 44, height: 5)
                                .frame(maxWidth: .infinity)
                                .frame(height: 30)   // generous grab zone
                                .background(ChopColor.card)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                                        compact.toggle()
                                    }
                                }
                                .gesture(
                                    // Same tuned feel as swiping the video: 12pt dead
                                    // zone, 0.85× finger-follow, commit at 80pt or a
                                    // 550pt/s flick, spring back otherwise (drag up =
                                    // grow panel = video shrinks live).
                                    DragGesture(minimumDistance: 12)
                                        .onChanged { g in
                                            let span = geo.size.height * (0.50 - 0.24)
                                            let ty = g.translation.height * 0.85
                                            dragShift = compact ? min(span, max(0, ty)) : max(-span, min(0, ty))
                                        }
                                        .onEnded { g in
                                            let pull = abs(g.translation.height) * 0.85
                                            let flick = abs(g.predictedEndTranslation.height - g.translation.height) * 4
                                            let rightWay = compact ? g.translation.height > 0 : g.translation.height < 0
                                            withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                                                if rightWay, pull >= 80 || flick >= 550 { compact.toggle() }
                                                dragShift = 0
                                            }
                                        }
                                )
                            panelBody(panel)
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        Spacer(minLength: 0)
                    }
                } else {
                    Spacer()
                    ProgressView().tint(Color.chopBlue)
                    Text(p.status).font(.footnote).foregroundStyle(Color.chopMuted)
                        .multilineTextAlignment(.center).padding(.top, 8).padding(.horizontal, 24)
                    Spacer()
                }
            }
        }
        .background(Color.chopBg)
        .environment(\.colorScheme, .dark)   // the editor is ALWAYS dark — footage needs contrast
        .toolbar(.hidden, for: .navigationBar)   // no title bar — the editor gets every pixel
        .task { await p.open(job: job, api: api) }
        .task {
            // -screen editor-sel / editor-compact: pose states for design review
            let a = ProcessInfo.processInfo.arguments
            guard let i = a.firstIndex(of: "-screen"), i + 1 < a.count else { return }
            let flag = a[i + 1]
            guard flag.hasPrefix("editor-") else { return }
            while !p.ready { try? await Task.sleep(nanoseconds: 200_000_000) }
            try? await Task.sleep(nanoseconds: 400_000_000)
            if flag == "editor-sel", p.bandSpansEdit.count > 1 { selected = 1 }
            if flag == "editor-compact" { compact = true }
            if flag == "editor-script" { panel = "script" }
        }
        .onChange(of: p.clipCount) { _, _ in selected = nil } // cuts changed (split doesn't rebuild, so it survives)
        .onAppear { api.editorOpen = true }
        .onDisappear {
            api.editorOpen = false; p.player.pause()
            Task { await p.persistEdit() }   // closing the editor flushes everything
        }
        .sheet(isPresented: $showFinishSheet) { finishSheet }
        // first time in the editor: pointer tour on the real buttons
        .chopCoach(steps: ChopPlayerScreen.tourSteps, active: $showEditorTour)
        .onChange(of: p.ready) { _, ready in
            if ready, !editorTourSeen { showEditorTour = true }
        }
        .onChange(of: showEditorTour) { _, on in if !on { editorTourSeen = true } }
    }

    // Split / Delete / Restore stretched across the row — deselect via the
    // thumb pad, duration lives on the clip chip (TikTok style)
    private func selBar(_ sel: Int) -> some View {
        let span = p.bandSpansEdit[sel]
        return HStack(spacing: 8) {
            ctxTool("Split", "scissors") {
                // web qeSplit: split stays visible, RIGHT band stays selected,
                // nothing rebuilds, nothing jumps
                if span.start + 0.05 < p.time, p.time < span.end - 0.05 {
                    selected = p.splitBand(atEditTime: p.time)
                } else {
                    ChopToasts.shared.show("Drag the playhead inside the selected section, then split")
                }
            }
            ctxTool("Delete", "trash") {
                p.deleteBand(sel); selected = nil
            }
            ctxTool("Restore", "arrow.uturn.backward") {
                p.undo(); selected = nil
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ChopColor.card)
    }

    /// Same recipe as the toolbar's tool() squares — one button language
    /// everywhere in the editor (Lewis: no colour tints, exact match).
    private func ctxTool(_ label: String, _ icon: String,
                         _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                Text(label).font(.system(size: 9.5, weight: .semibold))
            }
            .frame(width: 60, height: 52)
            .background(ChopColor.soft2, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Color.chopLine, lineWidth: 1))
            .foregroundStyle(Color.chopMuted)
        }
    }

    /// web .udwrap .iconbtn — 38px glass circle
    private func glassCircle(_ icon: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color(red: 10/255, green: 12/255, blue: 18/255).opacity(0.5), in: Circle())
                .background(.ultraThinMaterial, in: Circle())
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    /// One-tap preset chip inside the Cuts panel's fold.
    private func presetChip(_ label: String, _ s: ChopSettings) -> some View {
        Button {
            p.minSil = s.minSil
            p.fillers = s.fillers
            p.padStart = s.startPadMs
            p.padEnd = s.endPadMs
            p.retune()
            ChopToasts.shared.show("\(label.replacingOccurrences(of: " ★", with: "")) preset applied")
        } label: {
            Text(label)
                .font(.system(size: 12.5, weight: .heavy))
                .foregroundStyle(ChopColor.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(ChopColor.soft2, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.chopLine, lineWidth: 1))
        }
    }

    private func modePill(_ label: String, on: Bool) -> some View {
        Text(label)
            .font(.caption.weight(.bold))
            .foregroundStyle(on ? Color.black : .white)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(on ? Color.white : Color.clear, in: Capsule())
            .onTapGesture {
                selected = nil   // clip selection is an edited-mode tool
                p.setMode(edited: label == "Edited")
            }
    }

    // TikTok play bar: time left · small centred play · undo/redo right
    private var playBar: some View {
        ZStack {
            HStack(spacing: 8) {
                Text("\(clock(p.time)) / \(clock(p.duration))")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.chopMuted)
                if p.editedDuration > 0, job.rawSec > 0 {
                    Text("\(Int((1 - p.editedDuration / job.rawSec) * 100))% shorter")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.chopGreen)
                }
                Spacer()
                // KEYFRAME ZOOM (Lewis 18 Aug): tap = drop keyframe 1, scrub,
                // tap again = the zoom ramps between them. Filled diamond while
                // armed. Works on time, not clips — always white.
                Button { p.keyframeTapped() } label: {
                    Image(systemName: p.kfPending == nil ? "diamond" : "diamond.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.chopInk)
                        .frame(width: 34, height: 34)
                }
                // ROTATE (Lewis 18 Aug v2): rotates the SELECTED clip 90° per
                // tap. White when a clip is selected; faint grey (like a spent
                // undo button) when nothing is selected.
                Button { if let sel = selected { p.rotate(band: sel) } } label: {
                    Image(systemName: "rotate.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selected != nil ? Color.chopInk : Color.chopMuted.opacity(0.45))
                        .frame(width: 34, height: 34)
                }
                .disabled(selected == nil)
                Button { p.undo() } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(p.canUndo ? Color.chopInk : Color.chopMuted.opacity(0.45))
                        .frame(width: 34, height: 34)
                }
                .disabled(!p.canUndo)
                Button { p.redo() } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(p.canRedo ? Color.chopInk : Color.chopMuted.opacity(0.45))
                        .frame(width: 34, height: 34)
                }
                .disabled(!p.canRedo)
            }
            Button { p.togglePlay() } label: {
                Image(systemName: p.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Color.chopInk)
                    .frame(width: 40, height: 34)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 4)
    }

    /// Split, trim and delete at the playhead — the web app's quick-edit tools.
    private var clipTools: some View {
        HStack(spacing: 8) {
            clipTool("Trim start", "arrow.right.to.line", Color.chopInk) { p.trimAtPlayhead(keepAfter: false) }
            clipTool("Trim end", "arrow.left.to.line", Color.chopInk) { p.trimAtPlayhead(keepAfter: true) }
            clipTool("Delete", "trash", ChopColor.rose) { p.deleteClipAtPlayhead() }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    /// web .qtool — soft2 bg, line border, rose for delete
    private func clipTool(_ label: String, _ icon: String, _ tint: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(label).font(.system(size: 11, weight: .semibold))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 9)
            .background(ChopColor.soft2)
            .foregroundStyle(tint)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.chopLine, lineWidth: 1))
        }
    }

    // ---- the icon-square toolbar, same shape as the web editor ----
    // Locked in place: four buttons fit on every phone, so no ScrollView —
    // a stray swipe can no longer drag the row sideways and bounce it back.
    private var toolbar: some View {
        HStack(spacing: 8) {
            // Text/Image/Captions removed for App Store review — Apple
            // rejects visible-but-nonfunctional controls. Re-add at launch
            // (restore the ScrollView + .scrollBounceBehavior(.basedOnSize) then).
            tool("retakes", "rectangle.on.rectangle", "Retakes", badge: p.undecided)
            tool("cuts", "scissors", "Cuts")
            tool("script", "text.alignleft", "Script")
            tool("export", "square.and.arrow.down", "Export")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(ChopColor.card)
        .contentShape(Rectangle())   // swipes on the row's empty space go nowhere
    }

    /// web mobile .rail .rbtn — 64×62 r14 square, icon+label inside,
    /// on = blue-soft bg + blue border + blue text
    private func tool(_ key: String, _ icon: String, _ label: String, badge: Int = 0) -> some View {
        let on = panel == key
        return Button {
            panel = on ? nil : key
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 3) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                    Text(label).font(.system(size: 9.5, weight: .semibold))
                }
                .frame(width: 60, height: 52)
                .background(on ? ChopColor.blueSoft : ChopColor.soft2,
                            in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .stroke(on ? ChopColor.blue : Color.chopLine, lineWidth: 1))
                .foregroundStyle(on ? ChopColor.blue : Color.chopMuted)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.black)
                        .padding(4).background(Color.orange, in: Circle())
                        .offset(x: 4, y: -4)
                }
            }
        }
        .tourAnchor("tour-" + key)
    }

    // ---- persistent Done / Queue pills ----
    /// Green tick on the video — web's approve flow. Back arrow = queue.
    /// Guards shared by tap and long-press. Returns true if the tick may act.
    private func tickGuards() -> Bool {
        // already exported? it lives in Downloaded now — never re-approve it
        let live = api.jobs.first(where: { $0.name == job.name })?.status ?? job.status
        if live == "exported" || live == "downloaded" {
            ChopToasts.shared.show("Already exported — this video is in Downloaded")
            api.goToQueue = true
            dismiss()
            return false
        }
        let pend = p.undecided
        if pend > 0 {
            panel = "retakes"
            ChopToasts.shared.show("\(pend) retake\(pend > 1 ? "s" : "") still need\(pend > 1 ? "" : "s") a decision")
            return false
        }
        return true
    }

    /// Tap = ask the question (export vs save for later).
    private func doneTapped() {
        guard tickGuards() else { return }
        showFinishSheet = true
    }

    /// Long-press = the power-user shortcut: approve instantly, no sheet.
    private func quickApprove() {
        guard tickGuards() else { return }
        approveNow()
    }

    private func approveNow() {
        showFinishSheet = false
        marking = true
        Task {
            await p.persistEdit()   // the edit lands before the status moves
            await api.setStatus(job, to: "approved")
            marking = false
            ChopToasts.shared.showBig("Moved to Ready to export")
            api.goToQueue = true   // straight back to the queue for the next video
            dismiss()
        }
    }

    private func saveForLater() {
        showFinishSheet = false
        Task {
            await p.persistEdit()   // "keeps every change" must be literally true
            await api.setSavedForLater(job)
            ChopToasts.shared.show("Saved for later — waiting in your queue ✓")
            api.goToQueue = true
            dismiss()
        }
    }

    /// The mockup's bottom sheet: "Finished editing?" with the two roads.
    private var finishSheet: some View {
        VStack(spacing: 0) {
            Text("Finished editing?")
                .font(.system(size: 18, weight: .heavy)).foregroundStyle(ChopColor.ink)
                .padding(.top, 24)
            Text("Your changes are saved either way — this just decides where the video goes next.")
                .font(.system(size: 12)).foregroundStyle(ChopColor.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32).padding(.top, 6).padding(.bottom, 18)

            Button(action: approveNow) {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Yes — move to Ready to export")
                            .font(.system(size: 14.5, weight: .heavy))
                        Text("It joins the export queue, next video up")
                            .font(.system(size: 10.5)).opacity(0.8)
                    }
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(14)
                .background(ChopColor.green, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 18)

            Button(action: saveForLater) {
                HStack(spacing: 12) {
                    Image(systemName: "clock")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 38, height: 38)
                        .background(ChopColor.soft2, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Save for later")
                            .font(.system(size: 14.5, weight: .heavy))
                        Text("Keeps every change — come back any time")
                            .font(.system(size: 10.5)).foregroundStyle(ChopColor.muted)
                    }
                    Spacer()
                }
                .foregroundStyle(ChopColor.ink)
                .padding(14)
                .background(ChopColor.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.chopLine, lineWidth: 1))
            }
            .padding(.horizontal, 18).padding(.top, 9)

            Button { showFinishSheet = false } label: {
                Text("Keep editing")
                    .font(.system(size: 12.5, weight: .heavy))
                    .foregroundStyle(ChopColor.muted)
            }
            .padding(.vertical, 14)

            Spacer(minLength: 0)
        }
        .presentationDetents([.height(296)])
        .presentationDragIndicator(.visible)
        .background(ChopColor.bg)
        .environment(\.colorScheme, .dark)   // editor is always dark
    }

    // web renderCuts(): grouped list of everything currently cut, with Restore
    private var cutsList: some View {
        let groups: [(String, [Int])] = {
            var sil: [Int] = [], fil: [Int] = [], ret: [Int] = [], man: [Int] = []
            for (i, s) in p.segments.enumerated() where p.cut(i) {
                if s.kind == "silence" { sil.append(i) }
                else if s.kind == "filler" { fil.append(i) }
                else if s.retake != nil { ret.append(i) }
                else { man.append(i) }
            }
            return [("Silences", sil), ("Filler words", fil),
                    ("Retake cuts", ret), ("Manual cuts", man)].filter { !$0.1.isEmpty }
        }()
        let n = groups.reduce(0) { $0 + $1.1.count }
        let total = groups.flatMap(\.1).reduce(0.0) { $0 + (p.segments[$1].end - p.segments[$1].start) }

        return VStack(alignment: .leading, spacing: 10) {
            Text(n == 0 ? "No cuts at the current settings."
                        : "\(n) cuts · \(String(format: "%.1fs", total)) removed")
                .font(.system(size: 12.5)).foregroundStyle(ChopColor.muted)
                .padding(.top, 4)
            ForEach(groups, id: \.0) { label, idxs in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(label) · \(idxs.count)")
                        .font(.system(size: 12, weight: .heavy)).foregroundStyle(ChopColor.ink)
                        .padding(.top, 6)
                    ForEach(idxs, id: \.self) { i in
                        let s = p.segments[i]
                        HStack(spacing: 10) {
                            Text(clock(s.start))
                                .font(.system(size: 11, weight: .bold).monospacedDigit())
                                .foregroundStyle(ChopColor.muted)
                            Text(s.kind == "silence"
                                 ? "Silence (\(String(format: "%.1fs", s.end - s.start)))"
                                 : s.text)
                                .font(.system(size: 12.5)).foregroundStyle(ChopColor.ink)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Button("Restore") { p.toggleSegment(i) }
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundStyle(ChopColor.green)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(ChopColor.greenSoft, in: Capsule())
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    /// One transcript span, web classes → native styling:
    /// .w.cut.r-filler violet · .r-manual muted · .r-retake rose · .sil chips · .rtag tags
    @ViewBuilder
    private func transcriptSpan(_ i: Int, _ seg: ChopSegment) -> some View {
        let isCut = p.cut(i)
        if seg.kind == "silence" {
            Text("··· \(String(format: "%.1fs", seg.end - seg.start))")
                .font(.system(size: 10.5, weight: .bold))
                .strikethrough(isCut)
                .foregroundStyle(isCut ? ChopColor.amber : ChopColor.muted)
                .padding(.horizontal, 7).padding(.vertical, 1)
                .background(isCut ? ChopColor.amberSoft : ChopColor.soft2,
                            in: RoundedRectangle(cornerRadius: 7))
                .onTapGesture { p.toggleSegment(i) }
        } else if !seg.text.isEmpty {
            let reason: (Color, Color) = seg.kind == "filler"
                ? (ChopColor.violet, ChopColor.violetSoft)
                : (seg.retake != nil ? (ChopColor.rose, ChopColor.roseSoft)
                                     : (ChopColor.muted, ChopColor.soft2))
            let pendingRetake = seg.retake != nil && seg.pair.map { pi in
                pi < p.pairs.count && p.pairs[pi].choice == nil } ?? false

            // retake tag rides ahead of the segment's words
            if let r = seg.retake, let pi = seg.pair {
                Text("R\(pi + 1)·T\(r == "a" ? "1" : "2")")
                    .font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(r == "b" ? ChopColor.green : ChopColor.rose,
                                in: RoundedRectangle(cornerRadius: 5))
                    .onTapGesture { panel = "retakes" }
            }
            // word-level spans so long lines wrap inline, like HTML text
            ForEach(Array(seg.text.split(separator: " ").enumerated()), id: \.offset) { _, word in
                Text(String(word))
                    .font(.system(size: 13.5))
                    .strikethrough(isCut, color: reason.0)
                    .foregroundStyle(isCut ? reason.0 : ChopColor.ink)
                    .padding(.horizontal, 2).padding(.vertical, 1)
                    .background(isCut ? reason.1 : (pendingRetake ? ChopColor.roseSoft : .clear),
                                in: RoundedRectangle(cornerRadius: 5))
                    .onTapGesture {
                        if seg.retake != nil { panel = "retakes" } else { p.toggleSegment(i) }
                    }
            }
        }
    }

    @ViewBuilder
    private func panelBody(_ key: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch key {
                case "retakes":
                    if p.pairs.filter({ $0.complete }).isEmpty {
                        Text("Nothing waiting for review")
                            .font(ChopFont.small).foregroundStyle(ChopColor.muted)
                    } else {
                        ForEach(p.pairs) { pair in
                            if pair.complete { RetakeCard(pair: pair, player: p) }
                        }
                    }
                case "cuts":
                    // web .stat-mini: 1:28 → 1:04 −27%
                    HStack(spacing: 8) {
                        Text(clock(job.rawSec)).font(.system(size: 14, weight: .heavy)).foregroundStyle(ChopColor.ink)
                        Text("→").foregroundStyle(ChopColor.muted)
                        Text(clock(p.duration)).font(.system(size: 14, weight: .heavy)).foregroundStyle(ChopColor.ink)
                        if job.rawSec > 0 {
                            Text("−\(Int((1 - p.duration / job.rawSec) * 100))%")
                                .font(.system(size: 11.5, weight: .heavy)).foregroundStyle(ChopColor.green)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(ChopColor.greenSoft, in: Capsule())
                        }
                        Spacer()
                    }
                    HStack {
                        Text("Remove silences over").font(.subheadline.weight(.bold))
                        Spacer()
                        Text("\(String(format: "%.2f", p.minSil))s")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(ChopColor.blue)
                    }
                    Slider(value: $p.minSil, in: 0.01...2.0, step: 0.01)
                        .tint(Color.chopBlue)
                        .onChange(of: p.minSil) { _, _ in p.retune() }
                    Text("Any pause longer than this is cut automatically. Lower removes more dead air.")
                        .font(.system(size: 12)).foregroundStyle(Color.chopMuted)
                    Toggle(isOn: $p.fillers) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Remove filler words").font(.subheadline.weight(.bold))
                            Text("um, uh, hmm…").font(.system(size: 12)).foregroundStyle(Color.chopMuted)
                        }
                    }
                    .tint(Color.chopBlue)
                    .onChange(of: p.fillers) { _, _ in p.retune() }
                    // Presets & recommendations — tucked in a fold so the
                    // panel stays lean but nobody has to hunt for them
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("One tap sets the silence threshold, fillers and clip pads together. Recommended is the default — the tightest clean cut. Relaxed keeps more breathing room; Snappy suits fast talking heads. Clips feeling too short or too long? Nudge the Clip start / Clip end pads below.")
                                .font(.system(size: 12)).foregroundStyle(Color.chopMuted)
                            presetChip("Recommended ★", ChopPresets.recommended)
                            HStack(spacing: 8) {
                                presetChip("Relaxed", ChopPresets.relaxed)
                                presetChip("Balanced", ChopPresets.balanced)
                                presetChip("Snappy", ChopPresets.snappy)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Presets & recommendations")
                                .font(.subheadline.weight(.bold))
                        }
                        .foregroundStyle(ChopColor.blue)
                    }
                    .tint(ChopColor.blue)
                    // web Clip start / Clip end pads (±300ms, step 10)
                    HStack {
                        Text("Clip start").font(.subheadline.weight(.bold))
                        Spacer()
                        Text(ChopLabBody.ms(p.padStart))
                            .font(.subheadline.monospacedDigit()).foregroundStyle(ChopColor.blue)
                    }
                    Slider(value: $p.padStart, in: -300...300, step: 10)
                        .tint(Color.chopBlue)
                        .onChange(of: p.padStart) { _, _ in p.retune() }
                    Text("Positive keeps a little more before each clip; negative trims tighter.")
                        .font(.system(size: 12)).foregroundStyle(Color.chopMuted)
                    HStack {
                        Text("Clip end").font(.subheadline.weight(.bold))
                        Spacer()
                        Text(ChopLabBody.ms(p.padEnd))
                            .font(.subheadline.monospacedDigit()).foregroundStyle(ChopColor.blue)
                    }
                    Slider(value: $p.padEnd, in: -300...300, step: 10)
                        .tint(Color.chopBlue)
                        .onChange(of: p.padEnd) { _, _ in p.retune() }
                    Text("Positive keeps a little more after each clip; negative trims tighter.")
                        .font(.system(size: 12)).foregroundStyle(Color.chopMuted)
                    cutsList
                case "text", "image", "subtitles":
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Coming soon").font(.subheadline.weight(.bold))
                        Text("We’re building this — it’ll land in a future update.")
                            .font(.system(size: 12.5)).foregroundStyle(Color.chopMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(ChopColor.soft2, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.chopLine, lineWidth: 1))
                case "script":
                    // web .tr-flow: one flowing paragraph — words tappable,
                    // cuts struck through in their reason colour, silences as chips
                    ChopFlow(spacing: 4, lineSpacing: 9) {
                        ForEach(Array(p.segments.enumerated()), id: \.offset) { i, seg in
                            transcriptSpan(i, seg)
                        }
                    }
                default:
                    // Export: full-quality render from the ORIGINAL, saved to Photos
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Export").font(.system(size: 16, weight: .heavy)).foregroundStyle(ChopColor.ink)
                        Text("Renders the edited video at full quality and saves it to your camera roll, ready to post.")
                            .font(.system(size: 12.5)).foregroundStyle(ChopColor.muted)
                        if p.exporting {
                            ProgressView(value: p.exportPct)
                                .tint(ChopColor.blue)
                            Text(p.exportMsg.isEmpty ? "Exporting…" : p.exportMsg)
                                .font(.system(size: 12.5)).foregroundStyle(ChopColor.muted)
                        } else {
                            Button {
                                Task { await p.export(job: job, api: api) }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.down")
                                        .font(.system(size: 13, weight: .bold))
                                    Text("Export video")
                                }
                                .font(.system(size: 14.5, weight: .heavy))
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(ChopColor.blue, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.white)
                            }
                            if !p.exportMsg.isEmpty {
                                Text(p.exportMsg).font(.system(size: 12.5)).foregroundStyle(ChopColor.amber)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ChopColor.card)
    }
}

/// Filmstrip of the EDIT with a centre-locked playhead. Drag to scrub —
/// the stick follows your finger and the picture catches up, which is the
/// behaviour mobile Safari could never manage.
/// Wrapping flow layout — the web's inline transcript paragraph.
struct ChopFlow: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 9

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 350
        let cap = ProposedViewSize(width: w, height: nil)   // nothing may exceed the line
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(cap)
            if x + s.width > w, x > 0 { x = 0; y += rowH + lineSpacing; rowH = 0 }
            x += min(s.width, w) + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: w, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let w = bounds.width
        let cap = ProposedViewSize(width: w, height: nil)
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(cap)
            if x + s.width > w, x > 0 { x = 0; y += rowH + lineSpacing; rowH = 0 }
            v.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                    anchor: .topLeading, proposal: cap)
            x += min(s.width, w) + spacing
            rowH = max(rowH, s.height)
        }
    }
}

/// The web app's TikTok timeline, native: centre-locked stick, the strip pans
/// under it (drag = scrub), pinch = zoom 1–8×, tap = select a band, white
/// selection frame with ‹ › trim caps you can drag from either end.
struct ChopTimeline: View {
    @ObservedObject var p: ChopPlayer
    var selected: Binding<Int?>? = nil

    @State private var zoom: CGFloat = 1.5
    @State private var zoomStart: CGFloat? = nil
    @State private var dragStartTime: Double? = nil
    // live trim: (band, side 0=left/1=right, proposed edge in EDIT time)
    @State private var trimLive: (band: Int, side: Int, t: Double)? = nil
    @State private var trimSnapped = false   // magnetised to the playhead
    @State private var trimAnchorTime: Double? = nil   // playhead when the drag began (magnet target)
    @State private var kfSnapped = false     // scrub stick magnetised to a keyframe diamond
    @State private var baseDur: Double = 0   // pins px-per-second so edits never rescale the strip

    private let stripH: CGFloat = 44   // TikTok strip height
    private let scrubH: CGFloat = 56   // TikTok-sized thumb-scrub pad (doubled)

    /// RAW mode strip: the full original as one continuous band of frames,
    /// with red striped overlays on every cut-out section. Drawn straight
    /// from p.rawCuts, so it redraws the moment any edit changes the cuts.
    private func rawStrip(contentW: CGFloat, pps: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                ForEach(Array(p.strip.enumerated()), id: \.offset) { _, img in
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(width: contentW / CGFloat(max(1, p.strip.count)), height: stripH)
                        .clipped()
                }
            }
            .frame(width: contentW, height: stripH, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.5), lineWidth: 1))

            ForEach(Array(p.rawCuts.enumerated()), id: \.offset) { _, cut in
                let w = max(3, CGFloat(cut.end - cut.start) * pps)
                ZStack {
                    Rectangle().fill(ChopColor.rose.opacity(0.42))
                    if w > 26 {
                        Image(systemName: "scissors")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 2)
                    }
                }
                .overlay(Rectangle().stroke(ChopColor.rose, lineWidth: 1.5))
                .frame(width: w, height: stripH)
                .offset(x: CGFloat(cut.start) * pps)
                .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: p.rawCuts.map(\.start))
    }

    var body: some View {
        GeometryReader { geo in
            let vw = max(1, geo.size.width)
            let dur = max(p.duration, 0.001)
            // px-per-second is pinned to the FIRST duration — trimming must
            // never rescale the strip (TikTok: the timeline doesn't move)
            let pps = vw * zoom / CGFloat(max(baseDur > 0 ? baseDur : dur, 0.001))
            let contentW = CGFloat(dur) * pps
            let spans = p.bandSpansEdit
            let offsetX = vw / 2 - CGFloat(p.time) * pps

            ZStack(alignment: .topLeading) {

                // ---- the strip: bands + white split marks, pans under the stick ----
                ZStack(alignment: .topLeading) {
                    if !p.showEdited {
                        // RAW mode: one continuous strip of the full original,
                        // with everything that's been cut banded in red
                        rawStrip(contentW: contentW, pps: pps)
                    } else {
                    ForEach(Array(spans.enumerated()), id: \.offset) { i, span in
                        // TikTok live trim: the dragged edge moves and the
                        // neighbours on THAT side pull along with it — no gap,
                        // no jump at release. The other side stays rock still.
                        let tl = trimLive
                        let s: Double = (tl?.band == i && tl?.side == 0) ? tl!.t : span.start
                        let e: Double = (tl?.band == i && tl?.side == 1) ? tl!.t : span.end
                        let shift: CGFloat = {
                            guard let tl, tl.band != i, tl.band < spans.count else { return 0 }
                            if tl.side == 0, i < tl.band {   // left cap: left side follows
                                return CGFloat(tl.t - spans[tl.band].start) * pps
                            }
                            if tl.side == 1, i > tl.band {   // right cap: right side follows
                                return CGFloat(tl.t - spans[tl.band].end) * pps
                            }
                            return 0
                        }()
                        let x = CGFloat(s) * pps + shift
                        let bw = max(3, CGFloat(e - s) * pps)

                        // While the LEFT cap is dragged the frames anchor to the
                        // fixed RIGHT edge (and vice versa): the images freeze in
                        // place and the cap simply crops them — TikTok rigid.
                        let anchorRight = (tl?.band == i && tl?.side == 0)
                        bandThumbs(span: (s, e), width: bw, pps: pps, dur: dur,
                                   anchorRight: anchorRight)
                            .frame(width: bw, height: stripH,
                                   alignment: anchorRight ? .trailing : .leading)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.black.opacity(0.5), lineWidth: 1))
                            .offset(x: x)

                        // TikTok transition badge on every cut boundary — ▶|◀
                        // (hidden on the selected clip's own edges to keep it clean)
                        if i > 0, selected?.wrappedValue != i, selected?.wrappedValue != i - 1 {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white)
                                .frame(width: 24, height: 24)
                                .overlay(Image(systemName: "arrowtriangle.right.and.line.vertical.and.arrowtriangle.left.fill")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundStyle(Color(white: 0.12)))
                                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                                .offset(x: x - 12, y: (stripH - 24) / 2)
                                .allowsHitTesting(false)
                        }
                    }

                    // ---- keyframe diamonds (Lewis 18 Aug): markers only ----
                    ForEach(Array(p.kfMarkersEdit.enumerated()), id: \.offset) { _, kt in
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.white)
                            .shadow(color: .black.opacity(0.7), radius: 2)
                            .offset(x: CGFloat(kt) * pps - 4, y: -4)
                            .allowsHitTesting(false)
                    }

                    // ---- TikTok white selection frame + trim caps ----
                    if let sel = selected?.wrappedValue, sel < spans.count {
                        selectionFrame(sel: sel, spans: spans, pps: pps)
                    }
                    }   // end edited-mode strip
                }
                .frame(width: contentW, height: stripH, alignment: .topLeading)
                .coordinateSpace(name: "chopstrip")   // stable space for cap drags
                .offset(x: offsetX)
                // clips slide together smoothly when a section is deleted
                .animation(.easeInOut(duration: 0.25), value: spans.map(\.start))

                // ---- centre-locked stick — runs down through the scrub pad ----
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white)
                    .frame(width: 3, height: stripH + 8 + scrubH)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                    .offset(x: vw / 2 - 1.5, y: -6)
                    .allowsHitTesting(false)
            }
            .frame(height: stripH + scrubH, alignment: .top)
            .contentShape(Rectangle())   // the pad below the strip scrubs too
            // tap a clip = pause + snap to its start (Aaron's behaviour) ·
            // drag = scrub · pinch = zoom. Pan needs 10pt, which keeps pinch easy.
            .gesture(SpatialTapGesture()
                .onEnded { g in
                    guard p.showEdited else { return }   // selection is an edited-mode tool
                    guard let bind = selected else { return }
                    // tap in the thumb-scrub pad = deselect everything
                    guard g.location.y <= stripH else { bind.wrappedValue = nil; return }
                    let t = Double((g.location.x - offsetX) / pps)
                    if t >= 0, t <= p.duration, let i = p.bandIndex(atEditTime: t) {
                        if bind.wrappedValue == i {
                            bind.wrappedValue = nil
                        } else {
                            bind.wrappedValue = i
                            p.player.pause()
                            // TikTok: only jump if the cursor ISN'T already on
                            // this clip — otherwise pause exactly where it is.
                            // When it does jump, snap to the NEAR edge (Aaron,
                            // 18 Aug, per TikTok reference video): tapping an
                            // EARLIER clip lands at its END, a later clip at
                            // its start.
                            let span = p.bandSpansEdit[i]
                            if !(p.time >= span.start && p.time <= span.end) {
                                let target = p.time > span.end
                                    ? max(span.start, span.end - 0.001)
                                    : min(span.start + 0.001, p.duration)
                                p.seekExact(to: target)
                            }
                        }
                    }
                })
            .gesture(panGesture(vw: vw, pps: pps, offsetX: offsetX)
                .simultaneously(with: pinchGesture()))
        }
        .frame(height: stripH + scrubH)
        .padding(.vertical, 8)   // room for the frame's ±7px overhang
        .onChange(of: p.duration) { _, d in if baseDur == 0, d > 0 { baseDur = d } }
        .onAppear { if p.duration > 0 { baseDur = p.duration } }
    }

    // band filmstrip: FIXED-ASPECT tiles (34:56, like the web) that repeat as
    // you zoom — frames never stretch, more tiles just appear
    @ViewBuilder
    private func bandThumbs(span: (start: Double, end: Double),
                            width: CGFloat, pps: CGFloat, dur: Double,
                            anchorRight: Bool = false) -> some View {
        if p.strip.isEmpty {
            LinearGradient(colors: [Color(red: 0.24, green: 0.27, blue: 0.33),
                                    Color(red: 0.15, green: 0.17, blue: 0.21)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            let tileW = stripH * (34.0 / 56.0)      // web thumb aspect
            let count = max(1, Int(ceil(width / tileW)))
            HStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { k in
                    // the frame whose time sits at this tile's centre.
                    // anchorRight (left-cap trim): times count back from the
                    // FIXED end, so the visible tiles never re-map mid-drag.
                    let t = anchorRight
                        ? span.end - (Double(count - k) - 0.5) * Double(tileW / pps)
                        : span.start + (Double(k) + 0.5) * Double(tileW / pps)
                    let idx = min(p.strip.count - 1,
                                  max(0, Int(t / dur * Double(p.strip.count))))
                    Image(uiImage: p.strip[idx]).resizable().scaledToFill()
                        .frame(width: tileW, height: stripH)
                        .clipped()
                }
            }
            .frame(width: width, height: stripH,
                   alignment: anchorRight ? .trailing : .leading)
        }
    }

    // web .qframe: 3px white border, radius 13, ±7 overhang, caps + duration chip
    @ViewBuilder
    private func selectionFrame(sel: Int, spans: [(start: Double, end: Double)], pps: CGFloat) -> some View {
        let span = spans[sel]
        // live trim adjusts the visible edge
        let s = (trimLive?.band == sel && trimLive?.side == 0) ? trimLive!.t : span.start
        let e = (trimLive?.band == sel && trimLive?.side == 1) ? trimLive!.t : span.end
        let x = CGFloat(s) * pps
        let bw = max(6, CGFloat(e - s) * pps)
        let capW: CGFloat = 22

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.white, lineWidth: 3)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)

            // caps
            trimCap(sel: sel, span: span, side: 0, capW: capW, pps: pps)
            trimCap(sel: sel, span: span, side: 1, capW: capW, pps: pps)
                .offset(x: bw + capW)

            // duration chip (web .fdur)
            Text(String(format: "%.1fs", e - s))
                .font(.system(size: 10.5, weight: .heavy)).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Color(red: 16/255, green: 18/255, blue: 24/255).opacity(0.72),
                            in: RoundedRectangle(cornerRadius: 8))
                .offset(x: capW + 6, y: 5)
                .allowsHitTesting(false)
        }
        .frame(width: bw + capW * 2, height: stripH + 14)
        .offset(x: x - capW, y: -7)
    }

    // TikTok cap — drag IN to trim, drag OUT to extend. Reads its position from
    // the strip's own coordinate space, so the moving handle can't jitter.
    // The clip STAYS selected afterwards, like TikTok.
    private func trimCap(sel: Int, span: (start: Double, end: Double),
                         side: Int, capW: CGFloat, pps: CGFloat) -> some View {
        UnevenRoundedRectangle(
            topLeadingRadius: side == 0 ? 13 : 0, bottomLeadingRadius: side == 0 ? 13 : 0,
            bottomTrailingRadius: side == 1 ? 13 : 0, topTrailingRadius: side == 1 ? 13 : 0)
            .fill(Color.white)
            .frame(width: capW, height: stripH + 14)
            .overlay(Image(systemName: side == 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(Color(white: 0.07)))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("chopstrip"))
                    .onChanged { g in
                        var t = Double(g.location.x / pps)
                        if side == 0 {
                            let minT = span.start - p.bandExtendLeft(sel)
                            t = max(0, min(max(t, minT), span.end - 0.08))
                        } else {
                            let maxT = span.end + p.bandExtendRight(sel)
                            t = min(max(min(t, maxT), span.start + 0.08), p.duration + p.bandExtendRight(sel))
                        }
                        // TikTok: the cap magnetises to the playhead for a
                        // frame-perfect cut — keep pulling to push through.
                        // (Anchored at drag start: trim-follow moves p.time
                        // with the handle, so the live value can't be the magnet.)
                        if trimAnchorTime == nil { trimAnchorTime = p.time }
                        let stick = trimAnchorTime ?? p.time
                        if stick > span.start + 0.01, stick < span.end - 0.01,
                           abs(t - stick) * Double(pps) < 8 {
                            if !trimSnapped {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                trimSnapped = true
                            }
                            t = stick
                        } else {
                            trimSnapped = false
                        }
                        trimLive = (sel, side, t)
                        // TikTok trim-follow: the video scrubs WITH the handle,
                        // so you're watching your exact new edge frame
                        p.trimPreview(toEditTime: t)
                    }
                    .onEnded { _ in
                        defer { trimLive = nil; trimSnapped = false; trimAnchorTime = nil }
                        guard let tl = trimLive, tl.band == sel else {
                            p.endTrimPreview(); return
                        }
                        // TikTok stillness: the playhead is NOT moved — the
                        // rebuild remaps it, which cancels the reflow on screen
                        // so the un-dragged side never budges
                        p.endTrimPreview()
                        let delta = tl.side == 0 ? tl.t - span.start : span.end - tl.t
                        // + = trim in, − = extend out; selection is kept
                        p.resizeBand(sel, side: tl.side, deltaSeconds: delta)
                    }
            )
    }

    // drag = pan the strip under the fixed stick (web TikTok navigation)
    private func panGesture(vw: CGFloat, pps: CGFloat, offsetX: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { g in
                guard zoomStart == nil else { return }   // pinching: zoom-only
                guard trimLive == nil else { return }    // trimming: the cursor must hold still
                if dragStartTime == nil { dragStartTime = p.time; p.scrubbing = true }
                var t = max(0, min(p.duration, (dragStartTime ?? 0) - Double(g.translation.width / pps)))
                // keyframe magnet (Lewis 18 Aug): the stick locks onto a
                // diamond when it gets within ~8pt — same feel as the trim
                // caps magnetising to the playhead
                if let kt = p.kfMarkersEdit.min(by: { abs($0 - t) < abs($1 - t) }),
                   abs(kt - t) * Double(pps) < 8 {
                    if !kfSnapped { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                    kfSnapped = true
                    t = kt
                } else {
                    kfSnapped = false
                }
                p.time = t
                p.seek(to: t)
            }
            .onEnded { _ in
                let started = dragStartTime
                dragStartTime = nil
                p.scrubbing = false
                guard zoomStart == nil, started != nil else { return }
                p.seekExact(to: p.time)
            }
    }

    // pinch = zoom, anchored on the stick (time is the anchor by construction)
    // Max zoom scales with video length now (was a hard 8× cap that left 0.2s
    // clips untappable — Lewis 18 Aug): fully zoomed, one second spans ~300pt,
    // so a single frame is ~10pt and a 0.2s clip ~60pt. Zoom-out unchanged.
    private func pinchGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { v in
                if zoomStart == nil { zoomStart = zoom }
                let vw = max(UIScreen.main.bounds.width, 1)
                let maxZoom = max(8, 300 * CGFloat(max(baseDur, 0.001)) / vw)
                zoom = min(maxZoom, max(1, (zoomStart ?? 1.5) * v))
            }
            .onEnded { _ in zoomStart = nil }
    }
}

/// Web renderRetakes() card, one for one: rose-bordered while pending,
/// "Needs decision" chip, take panels with ▶ + full-width blue Keep buttons,
/// AI pick badge on Take 2, Keep both / Not a retake / Reset in the footer.
struct RetakeCard: View {
    let pair: ChopPair
    @ObservedObject var player: ChopPlayer

    private var pending: Bool { pair.choice == nil }

    /// MULTI-TAKE (Lewis 18 Aug): >2 takes matched into this pair — render one
    /// row per take instead of the fixed A/B pair. nil for the classic 2-take
    /// case, which renders exactly as before.
    private var multiGroups: [[Int]]? {
        let g = player.takeGroups(pair: pair.id)
        return g.count > 2 ? g : nil
    }

    private var statusText: String {
        switch pair.choice {
        case nil: return "Needs decision"
        case "both": return pair.weak ? "Dismissed" : (multiGroups != nil ? "Keeping all" : "Keeping both")
        case "a": return "Keeping Take 1"
        case let c? where c.hasPrefix("k"):
            return "Keeping Take \(((Int(c.dropFirst()) ?? 0)) + 1)"
        default: return multiGroups != nil ? "Keeping final take" : "Keeping Take 2"
        }
    }

    private func segIndex(_ key: String) -> Int? {
        player.segments.firstIndex { $0.retake == key && $0.pair == pair.id }
    }

    private func choose(_ take: String?) {
        player.choose(pair: pair.id, take: take)
        if player.undecided == 0, take != nil {
            ChopToasts.shared.show("All retakes reviewed — hit the Done button when you’re happy")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // .rkhead — Retake N · X% match · status chip
            HStack(spacing: 6) {
                Text(pair.weak ? "Possible retake" : "Retake \(pair.id + 1)")
                    .font(.system(size: 15, weight: .heavy)).foregroundStyle(ChopColor.ink)
                Text("\(Int(pair.sim * 100))% match")
                    .font(.system(size: 12.5)).foregroundStyle(ChopColor.muted)
                if pair.weak && pending {
                    Text("CHECK").font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(ChopColor.amber)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(ChopColor.amberSoft, in: RoundedRectangle(cornerRadius: 5))
                }
                Spacer()
                Text(statusText)
                    .font(.system(size: 11.5, weight: .heavy))
                    .foregroundStyle(pending ? ChopColor.rose : ChopColor.green)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(pending ? ChopColor.roseSoft : ChopColor.greenSoft, in: Capsule())
            }

            if let groups = multiGroups {
                // MULTI-TAKE: same take-panel design, one row per take, the
                // final take wears the AI pick badge — creator keeps exactly one.
                ForEach(groups.indices, id: \.self) { i in
                    takeRow(i, groups: groups)
                }
            } else {
                take("a", label: "Take 1 · first attempt", text: pair.aText, len: pair.aLen)
                take("b", label: "Take 2 · final attempt", text: pair.bText, len: pair.bLen)
            }

            // .rkfoot
            HStack(spacing: 14) {
                if pair.weak && pending {
                    Button("✕ Not a retake") { choose("both") }
                        .font(.system(size: 12.5, weight: .bold)).foregroundStyle(ChopColor.muted)
                }
                Button(multiGroups != nil ? "Keep all" : "Keep both") { choose("both") }
                    .font(.system(size: 12.5, weight: .bold)).foregroundStyle(ChopColor.muted)
                if pair.choice != nil {
                    Button("Reset") { choose(nil) }
                        .font(.system(size: 12.5, weight: .bold)).foregroundStyle(ChopColor.muted)
                }
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(ChopColor.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(pending ? ChopColor.rose.opacity(0.55) : ChopColor.green.opacity(0.45),
                    lineWidth: 1))
    }

    /// MULTI-TAKE row — visually identical to take(), but keyed "k<i>" and fed
    /// from the segment group instead of the pair's fixed A/B fields. Legacy
    /// "a"/"b" choices map onto first/last rows so old decisions still light up.
    @ViewBuilder
    private func takeRow(_ i: Int, groups: [[Int]]) -> some View {
        let key = "k\(i)"
        let isLast = i == groups.count - 1
        let chosen = pair.choice == key
            || (isLast && pair.choice == "b") || (i == 0 && pair.choice == "a")
        let dropped = pair.choice != nil && pair.choice != "both" && !chosen
        let segs = groups[i].filter { $0 < player.segments.count }.map { player.segments[$0] }
        let text = segs.map(\.text).filter { !$0.isEmpty }.joined(separator: " ")
        let len = segs.reduce(0.0) { $0 + ($1.end - $1.start) }
        let suffix = i == 0 ? " · first attempt" : (isLast ? " · final attempt" : "")
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Take \(i + 1)\(suffix)")
                    .font(.system(size: 13.5, weight: .heavy)).foregroundStyle(ChopColor.ink)
                Text(String(format: "%.1fs", len))
                    .font(.system(size: 12)).foregroundStyle(ChopColor.muted)
                if isLast {
                    Text("AI pick").font(.system(size: 9.5, weight: .heavy))
                        .foregroundStyle(ChopColor.green)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(ChopColor.greenSoft, in: RoundedRectangle(cornerRadius: 7))
                }
                Spacer()
            }
            Text("\u{201C}\(text)\u{201D}")
                .font(.system(size: 14.5))
                .foregroundStyle(dropped ? ChopColor.muted : ChopColor.ink)
                .strikethrough(dropped)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    if let first = groups[i].first, first < player.segments.count, !player.cut(first) {
                        player.playFrom(segment: first)
                        player.player.play()
                    } else {
                        ChopToasts.shared.show("This take is cut right now — Keep it to preview")
                    }
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(ChopColor.ink)
                        .frame(width: 40, height: 40)
                        .background(ChopColor.soft2, in: RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.chopLine, lineWidth: 1))
                }
                Button {
                    choose(key)
                } label: {
                    Text(chosen ? "✓ Keeping this" : "Keep this take")
                        .font(.system(size: 13.5, weight: .heavy))
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(chosen ? ChopColor.green : ChopColor.blue,
                                    in: RoundedRectangle(cornerRadius: 11))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(12)
        .background(ChopColor.soft2.opacity(dropped ? 0.4 : 1),
                    in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .stroke(chosen ? ChopColor.green : Color.chopLine, lineWidth: chosen ? 1.5 : 1))
        .opacity(dropped ? 0.55 : 1)
    }

    // .take — panel per take: header, quote, ▶ + Keep this take
    @ViewBuilder
    private func take(_ key: String, label: String, text: String, len: Double) -> some View {
        let chosen = pair.choice == key
        let dropped = pair.choice != nil && pair.choice != "both" && pair.choice != key
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(label).font(.system(size: 13.5, weight: .heavy)).foregroundStyle(ChopColor.ink)
                Text(String(format: "%.1fs", len))
                    .font(.system(size: 12)).foregroundStyle(ChopColor.muted)
                if key == "b" {
                    Text("AI pick").font(.system(size: 9.5, weight: .heavy))
                        .foregroundStyle(ChopColor.green)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(ChopColor.greenSoft, in: RoundedRectangle(cornerRadius: 7))
                }
                Spacer()
            }
            Text("\u{201C}\(text)\u{201D}")
                .font(.system(size: 14.5))
                .foregroundStyle(dropped ? ChopColor.muted : ChopColor.ink)
                .strikethrough(dropped)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    if let i = segIndex(key), !player.cut(i) {
                        player.playFrom(segment: i)
                        player.player.play()
                    } else {
                        ChopToasts.shared.show("This take is cut right now — Keep it to preview")
                    }
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(ChopColor.ink)
                        .frame(width: 40, height: 40)
                        .background(ChopColor.soft2, in: RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.chopLine, lineWidth: 1))
                }
                Button {
                    choose(key)
                } label: {
                    Text(chosen ? "✓ Keeping this" : "Keep this take")
                        .font(.system(size: 13.5, weight: .heavy))
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(chosen ? ChopColor.green : ChopColor.blue,
                                    in: RoundedRectangle(cornerRadius: 11))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(12)
        .background(ChopColor.soft2.opacity(dropped ? 0.4 : 1),
                    in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .stroke(chosen ? ChopColor.green : Color.chopLine, lineWidth: chosen ? 1.5 : 1))
        .opacity(dropped ? 0.55 : 1)
    }
}


// MARK: - Import from the phone

@MainActor
final class ChopImporter: ObservableObject {
    /// Same six steps the web app shows, in the same order.
    static let steps = ["Uploading", "Listening to your audio", "Detecting dead air",
                        "Finding filler words", "Matching retakes", "Building your edit"]

    @Published var busy = false
    @Published var step = ""
    @Published var done = false
    @Published var failed = ""
    @Published var syncMsg = ""
    @Published var stepIndex = -1
    @Published var previewFrame: UIImage?   // real frame from the video being chopped

    /// Same pipeline the web app uses: audio out, analyse, save the job,
    /// then the full video in the background so export can use the original.
    func run(pickedURL: URL, name: String, api: ChopAPI) async {
        busy = true; failed = ""; done = false
        api.importActive = true   // pauses background work (thumb backfill) for the duration
        defer { busy = false; api.importActive = false }

        let asset = AVURLAsset(url: pickedURL)
        let rawSec = CMTimeGetSeconds(asset.duration)

        // Dashboard preview — grab a real frame up front so the edits grid
        // never shows a black card for phone imports (web does the same).
        let thumb = await makeThumb(asset)

        // 1. audio only — a fraction of the size, and all Deepgram needs
        stepIndex = 0; step = "Preparing audio…"
        guard let audio = await extractAudio(asset) else {
            failed = "Couldn't read the audio from that clip"; return
        }

        stepIndex = 1; step = "Uploading audio…"
        let audioName = (name as NSString).deletingPathExtension + ".m4a"
        // retrying wrappers (Lewis 18 Aug): identical calls, 3 attempts each —
        // a phone-radio blip or a server cold-start no longer kills the import
        guard let (putURL, key) = await api.presignPutRetrying(filename: audioName),
              await api.putFileRetrying(audio, to: putURL) else {
            failed = "Upload failed"; return
        }

        stepIndex = 2; step = "Transcribing…"
        guard let jobId = await api.startProcessingRetrying(key: key) else {
            failed = "Couldn't start processing"; return
        }

        stepIndex = 4; step = "Finding cuts and retakes…"
        guard let payload = await api.awaitAnalysis(jobId: jobId) else {
            failed = "Analysis failed"; return
        }

        // Save now so the edit is usable immediately. The full video follows in
        // the background — it's only needed for export, not for reviewing.
        stepIndex = 5; step = "Saving…"
        await api.spendCredit()
        // the picked file is already on the phone — let the editor open it
        // instantly instead of waiting for the cloud round-trip.
        // persistImport (Lewis 20 Aug): instant APFS clone into Documents so
        // the copy survives tmp purges and relaunches; falls back to the old
        // tmp URL if the clone ever fails.
        api.localImports[name] = api.persistImport(pickedURL, name: name)
        await api.saveJob(name: name, payload: payload, rawSec: rawSec, videoKey: nil, thumb: thumb)
        await api.loadJobs()
        ChopToasts.shared.show("Chopped ✓")
        stepIndex = 6
        done = true
        step = ""
        busy = false

        Task.detached { [weak self] in
            // retrying wrappers here too — a blip during the background 4K sync
            // used to silently lose videoKey (export then depends on the local
            // copy surviving); 3 attempts each closes that quiet gap as well
            guard let (vPut, vKey) = await api.presignPutRetrying(filename: "sync-" + name) else { return }
            let ok = await api.putFileRetrying(pickedURL, to: vPut)
            guard ok else { return }
            // MERGE, don't overwrite: the old saveJob upsert rebuilt the whole
            // data blob and raced the editor's auto-save — losing videoKey
            // (the 'not synced yet' export bug) or nuking fresh edits.
            await api.mergeJobData(name, fields: ["videoKey": vKey])
            await api.loadJobs()
            await MainActor.run {
                self?.syncMsg = "Full quality video synced — export is ready"
                ChopToasts.shared.show("Full quality video synced")
            }
        }
    }

    /// One real frame as a small JPEG data URL — the exact format the web app
    /// stores on jobs, so the dashboard grid (and the web) can show it.
    private func makeThumb(_ asset: AVAsset) async -> String? {
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 540, height: 540)
        // The default zero seek tolerance forces an exact-frame decode — on 4K
        // clips that's seconds of work, which is the "thumbnail lags behind the
        // processing card" Lewis hit. A ±0.5s window lets AVFoundation decode
        // from the nearest keyframe instead: visually identical thumb, lands
        // near-instantly. (0.5s also keeps us clear of the black frame 0.)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter  = CMTime(seconds: 0.5, preferredTimescale: 600)
        let dur = CMTimeGetSeconds(asset.duration)
        // skip the very first frame — often black while the camera settles
        let t = CMTime(seconds: dur > 2 ? 1.0 : max(0, dur * 0.25), preferredTimescale: 600)
        guard let cg = try? await gen.image(at: t).image else { return nil }
        let ui = UIImage(cgImage: cg)
        previewFrame = ui   // the processing card shows THEIR footage being chopped
        guard let jpeg = ui.jpegData(compressionQuality: 0.55) else { return nil }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }

    /// WEB PARITY (retake fix): the web app sends Deepgram 16 kHz MONO audio;
    /// this used to send the raw 44.1 kHz stereo track. Deepgram's utterance
    /// splitting — which retake detection hangs off — hears those differently,
    /// which is how an obvious retake could be missed on iOS but caught on web.
    /// Now iOS transcodes to the exact same shape (16 kHz mono AAC 48k).
    private func extractAudio(_ asset: AVAsset) async -> URL? {
        guard let track = asset.tracks(withMediaType: .audio).first else { return nil }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("chop-\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: out)
        do {
            let reader = try AVAssetReader(asset: asset)
            let readerOut = AVAssetReaderTrackOutput(track: track, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            guard reader.canAdd(readerOut) else { return await legacyExtractAudio(asset) }
            reader.add(readerOut)

            let writer = try AVAssetWriter(outputURL: out, fileType: .m4a)
            let writerIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 48000,
            ])
            writerIn.expectsMediaDataInRealTime = false
            guard writer.canAdd(writerIn) else { return await legacyExtractAudio(asset) }
            writer.add(writerIn)

            guard reader.startReading(), writer.startWriting() else {
                return await legacyExtractAudio(asset)
            }
            writer.startSession(atSourceTime: .zero)
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                let q = DispatchQueue(label: "chop-audio-transcode", qos: .userInitiated)
                var finished = false   // q is serial — this guard is safe
                writerIn.requestMediaDataWhenReady(on: q) {
                    // NOTE: iOS may invoke this block again after the media is
                    // exhausted — the `finished` guard stops a double resume
                    // (which would crash) and the append-failure path stops a
                    // silent hang if the writer errors mid-stream.
                    while writerIn.isReadyForMoreMediaData {
                        guard !finished else { return }
                        guard let buf = readerOut.copyNextSampleBuffer() else {
                            finished = true
                            writerIn.markAsFinished()
                            c.resume()
                            return
                        }
                        guard writerIn.append(buf) else {
                            finished = true
                            writerIn.markAsFinished()
                            c.resume()
                            return
                        }
                    }
                }
            }
            await writer.finishWriting()
            guard writer.status == .completed, reader.status == .completed,
                  (try? out.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 > 1024 else {
                return await legacyExtractAudio(asset)
            }
            return out
        } catch {
            return await legacyExtractAudio(asset)   // never fail the upload over parity
        }
    }

    /// The old passthrough export — kept as the safety net only.
    private func legacyExtractAudio(_ asset: AVAsset) async -> URL? {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
        else { return nil }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("chop-\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: out)
        session.outputURL = out
        session.outputFileType = .m4a
        await session.export()
        return session.status == .completed ? out : nil
    }
}

// MARK: - Processing stage — V1 "the card gets chopped" (approved mockup).
// Centred wordmark, a big swaying creator card that splits on the brand's
// diagonal slice and comes back smaller after every cutting step, a filmstrip
// losing its red sections, and one step row with a progress bar.

/// The wordmark's diagonal slice as a clip shape: card top piece / bottom piece.
private struct ChopSliceHalf: Shape {
    let top: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        if top {
            p.move(to: .zero)
            p.addLine(to: CGPoint(x: r.maxX, y: 0))
            p.addLine(to: CGPoint(x: r.maxX, y: r.height * 0.50))
            p.addLine(to: CGPoint(x: 0, y: r.height * 0.64))
        } else {
            p.move(to: CGPoint(x: 0, y: r.height * 0.64))
            p.addLine(to: CGPoint(x: r.maxX, y: r.height * 0.50))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: 0, y: r.maxY))
        }
        p.closeSubpath()
        return p
    }
}

struct ChopProcessingStage: View {
    let stepIndex: Int          // ChopImporter.stepIndex, 0…6
    let done: Bool
    var frame: UIImage? = nil   // real frame from the user's own video

    @State private var sway = false
    @State private var pulse = false
    @State private var scan = false
    @State private var split = false
    @State private var sliceGo = false
    @State private var cardScale: CGFloat = 1
    @State private var lastChopped = -1

    private static let info: [(badge: String, name: String, sub: String)] = [
        ("UPLOADING", "Uploading", "Sending your footage up"),
        ("LISTENING", "Listening to your audio", "Every word, every pause"),
        ("DEAD AIR", "Detecting dead air", "Silences get the chop"),
        ("FILLERS", "Finding filler words", "um, uh, hmm — gone"),
        ("RETAKES", "Matching retakes", "Pairing takes — you pick the keeper"),
        ("BUILDING", "Building your edit", "Stitching the keepers together"),
    ]
    private let stripLayout: [Bool] =
        [false, false, true, false, true, false, false, true, false, false, true, false, true, false]

    private var step: Int { min(max(stepIndex, 0), 5) }
    private var cur: (badge: String, name: String, sub: String) {
        done ? ("DONE", "Chopped ✓", "Opening the editor") : Self.info[step]
    }
    private var redKill: Int {
        let reds = stripLayout.filter { $0 }.count
        if done { return reds }
        guard step >= 2 else { return 0 }
        return Int((Double(step - 1) / 4.0 * Double(reds)).rounded())
    }
    private let pink = Color(red: 0xfe/255, green: 0x2c/255, blue: 0x55/255)

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 6)

            ChopWordmark(size: 26)
                .frame(maxWidth: .infinity)   // centred — the only header

            Spacer(minLength: 20)             // matches the mockup's rhythm:

            // ---- the card that gets chopped ----
            ZStack {
                cardHalf(top: true)
                    .offset(x: split ? -9 : 0, y: split ? -7 : 0)
                    .rotationEffect(.degrees(split ? -2.5 : 0))
                cardHalf(top: false)
                    .offset(x: split ? 11 : 0, y: split ? 8 : 0)
                    .rotationEffect(.degrees(split ? 3.2 : 0))
                // blue analysis scanline
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, ChopColor.blue.opacity(0.25), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 186, height: 44)
                    .offset(y: scan ? 130 : -130)
                    .mask(RoundedRectangle(cornerRadius: 20).frame(width: 186, height: 238))
                // pink slice sweep along the cut line
                Rectangle()
                    .fill(pink)
                    .frame(width: 230, height: 2.5)
                    .shadow(color: pink.opacity(0.9), radius: 8)
                    .rotationEffect(.degrees(-4.5))
                    .offset(x: sliceGo ? 250 : -250, y: 14)
                    .opacity(split || sliceGo ? 1 : 0)
            }
            .frame(width: 186, height: 238)   // pin bounds BEFORE the badge, so
            .overlay(alignment: .topLeading) { // it hugs the card corner exactly
                HStack(spacing: 6) {
                    Circle().fill(pink).frame(width: 7, height: 7)
                        .opacity(pulse ? 0.35 : 1)
                        .scaleEffect(pulse ? 0.72 : 1)
                    Text(cur.badge)
                        .font(.system(size: 9.5, weight: .black)).kerning(0.8)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(Color(red: 10/255, green: 12/255, blue: 18/255).opacity(0.6), in: Capsule())
                .padding(12)
            }
            .scaleEffect(cardScale)
            .rotationEffect(.degrees(sway ? 2 : -2))
            .offset(y: sway ? -6 : 0)

            Spacer(minLength: 24)

            // ---- filmstrip: red cuts collapse as the steps land ----
            HStack(spacing: 3) {
                ForEach(Array(stripLayout.enumerated()), id: \.offset) { idx, isRed in
                    let ordinal = stripLayout.prefix(idx + 1).filter { $0 }.count
                    let gone = isRed && ordinal <= redKill
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isRed
                              ? AnyShapeStyle(ChopColor.rose.opacity(0.45))
                              : AnyShapeStyle(LinearGradient(
                                    colors: [Color(red: 0x2b/255, green: 0x35/255, blue: 0x50/255),
                                             Color(red: 0x1d/255, green: 0x24/255, blue: 0x36/255)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing)))
                        .overlay(isRed
                                 ? RoundedRectangle(cornerRadius: 7).stroke(ChopColor.rose, lineWidth: 1.5)
                                 : nil)
                        .frame(maxWidth: gone ? 0.5 : .infinity)
                        .opacity(gone ? 0 : 1)
                }
            }
            .frame(height: 40)
            .animation(.easeInOut(duration: 0.5), value: redKill)
            .padding(.bottom, 16)

            // ---- one step row + progress ----
            HStack(spacing: 10) {
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18)).foregroundStyle(ChopColor.green)
                } else {
                    ProgressView().tint(ChopColor.blue)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(cur.name)
                        .font(.system(size: 13.5, weight: .heavy)).foregroundStyle(ChopColor.ink)
                    Text(cur.sub)
                        .font(.system(size: 10.5)).foregroundStyle(ChopColor.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(ChopColor.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.chopLine, lineWidth: 1))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(ChopColor.soft2)
                    Capsule().fill(ChopColor.blue)
                        .frame(width: geo.size.width *
                               (done ? 1 : CGFloat(step + 1) / 6))
                }
                .animation(.easeInOut(duration: 0.6), value: step)
            }
            .frame(height: 5)
            .padding(.top, 11)

            Text(done ? "100%" : "\(Int(Double(step + 1) / 6 * 100))%")
                .font(.system(size: 10, weight: .heavy)).foregroundStyle(ChopColor.muted)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 5)

            Spacer(minLength: 18)   // breathing room off the bottom edge
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { sway = true }
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) { scan = true }
        }
        .onChange(of: stepIndex) { _, s in
            guard s >= 2, s != lastChopped else { return }
            lastChopped = s
            chop(to: max(0.78, 1 - CGFloat(max(0, s - 1)) * 0.055))
        }
        .onChange(of: done) { _, d in if d { chop(to: 0.74) } }
    }

    /// Pink slice sweeps → halves fly apart on the diagonal → snap back smaller.
    private func chop(to scale: CGFloat) {
        sliceGo = false
        withAnimation(.easeIn(duration: 0.5)) { sliceGo = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            withAnimation(.spring(duration: 0.4, bounce: 0.4)) { split = true }
            try? await Task.sleep(nanoseconds: 620_000_000)
            withAnimation(.spring(duration: 0.45, bounce: 0.35)) {
                split = false
                cardScale = scale
            }
            sliceGo = false
        }
    }

    private func cardHalf(top: Bool) -> some View {
        ZStack {
            if let frame {
                // THEIR footage — the frame we grab for the dashboard thumbnail,
                // shown being chopped up in real time
                Image(uiImage: frame)
                    .resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(red: 0x26/255, green: 0x30/255, blue: 0x4a/255),
                                        Color(red: 0x14/255, green: 0x1a/255, blue: 0x2a/255)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()   // the creator placeholder until the frame lands
                    .fill(RadialGradient(colors: [Color(red: 0x4a/255, green: 0x58/255, blue: 0x78/255),
                                                  Color(red: 0x2a/255, green: 0x34/255, blue: 0x50/255)],
                                         center: UnitPoint(x: 0.38, y: 0.34),
                                         startRadius: 4, endRadius: 46))
                    .frame(width: 70, height: 70)
                    .offset(y: -22)
                RoundedRectangle(cornerRadius: 40)   // shoulders
                    .fill(LinearGradient(colors: [Color(red: 0x3b/255, green: 0x49/255, blue: 0x66/255),
                                                  Color(red: 0x25/255, green: 0x2f/255, blue: 0x49/255)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 118, height: 90)
                    .offset(y: 88)
            }
        }
        .frame(width: 186, height: 238)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .clipShape(ChopSliceHalf(top: top))
        .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
    }
}

/// MULTI-TAKE STITCH (Lewis 18 Aug, additive): joins the picked clips into ONE
/// video, in selection order, BEFORE the pipeline runs — so the locked
/// upload/analysis/retakes/editor/export path processes a perfectly ordinary
/// single video and never knows the difference. Same-shape clips (the normal
/// case: same phone, same orientation) concat LOSSLESSLY via passthrough in a
/// few seconds; mixed shapes fall back to a highest-quality re-encode using
/// the first clip's orientation.
enum ChopStitcher {
    static func stitch(_ urls: [URL]) async -> URL? {
        guard urls.count > 1 else { return urls.first }
        let comp = AVMutableComposition()
        guard let vTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
        let aTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var cursor = CMTime.zero
        var firstTransform: CGAffineTransform? = nil
        var firstSize: CGSize? = nil
        var uniform = true
        for url in urls {
            let asset = AVURLAsset(url: url)
            guard let v = try? await asset.loadTracks(withMediaType: .video).first,
                  let dur = try? await asset.load(.duration) else { return nil }
            let range = CMTimeRange(start: .zero, duration: dur)
            do { try vTrack.insertTimeRange(range, of: v, at: cursor) } catch { return nil }
            if let a = try? await asset.loadTracks(withMediaType: .audio).first {
                try? aTrack?.insertTimeRange(range, of: a, at: cursor)
            }
            let t = (try? await v.load(.preferredTransform)) ?? .identity
            let s = (try? await v.load(.naturalSize)) ?? .zero
            if firstTransform == nil { firstTransform = t; firstSize = s }
            else if t != firstTransform || s != firstSize { uniform = false }
            cursor = CMTimeAdd(cursor, dur)
        }
        vTrack.preferredTransform = firstTransform ?? .identity
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("chop-stitch-\(UUID().uuidString.prefix(8)).mov")
        try? FileManager.default.removeItem(at: out)
        if uniform, let ex = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough) {
            ex.outputURL = out; ex.outputFileType = .mov
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in ex.exportAsynchronously { c.resume() } }
            if ex.status == .completed { return out }
            try? FileManager.default.removeItem(at: out)
        }
        guard let ex2 = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else { return nil }
        ex2.outputURL = out; ex2.outputFileType = .mov
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in ex2.exportAsynchronously { c.resume() } }
        return ex2.status == .completed ? out : nil
    }
}

struct ImportSheet: View {
    @ObservedObject var api: ChopAPI
    @StateObject private var imp = ChopImporter()
    @State private var pickedMany: [PhotosPickerItem] = []
    @State private var preparing = false        // copying from the photo library — busy from frame one
    var initialPicks: [PhotosPickerItem] = []   // videos already chosen on the dashboard
    var stitch = false                          // multi-take: join clips into ONE video first
    @Environment(\.dismiss) private var dismiss

    /// MULTI-TAKE path — loads every pick in selection order, stitches them
    /// into one file, then hands that file to the UNCHANGED single-video
    /// pipeline. Mirrors the single-take completion flow exactly.
    private func runStitched(_ items: [PhotosPickerItem]) async {
        preparing = true
        if imp.stepIndex < 0 { imp.stepIndex = 0 }
        var urls: [URL] = []
        for item in items {
            guard let movie = try? await item.loadTransferable(type: ChopMovie.self) else {
                imp.failed = "Couldn't read one of those videos"; preparing = false; return
            }
            urls.append(movie.url)
        }
        guard let combined = await ChopStitcher.stitch(urls) else {
            imp.failed = "Couldn't combine those videos"; preparing = false; return
        }
        let df = DateFormatter(); df.dateFormat = "d MMM, HH.mm"
        let friendly = "Chop " + df.string(from: Date()) + " (\(urls.count) clips).mp4"
        await imp.run(pickedURL: combined, name: friendly, api: api)
        preparing = false
        if imp.done, let job = api.jobs.first(where: { $0.name == friendly }) {
            dismiss()
            try? await Task.sleep(nanoseconds: 450_000_000)
            if !api.editorOpen, api.openJob == nil { api.openJob = job }
        } else if imp.failed.isEmpty {
            dismiss()
        }
    }

    /// debug: `-screen proc` shows the processing card mid-run for review
    private func debugPreview() {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-screen"), i + 1 < a.count, a[i + 1] == "proc", !imp.busy {
            imp.busy = true; imp.stepIndex = 2
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            let _ = debugPreview()

            if imp.busy || preparing {
                // V1 'the card gets chopped' — approved mockup. Wordmark centred,
                // no headline/subheading, layout pulled in tight.
                ChopProcessingStage(stepIndex: imp.stepIndex, done: imp.done,
                                    frame: imp.previewFrame)
                    .frame(maxWidth: 520, maxHeight: .infinity)
            } else if api.credits <= 0 {
                Image(systemName: "bolt.slash").font(.largeTitle).foregroundStyle(.orange)
                Text("You're out of credits").font(.subheadline.weight(.medium))
                Text("One credit edits one video, any length up to 10 minutes.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Close") { dismiss() }
            } else {
                PhotosPicker(selection: $pickedMany, maxSelectionCount: 30,
                             matching: .videos,
                             preferredItemEncoding: .current) {   // no iOS transcode — see dashboard picker note
                    Label("Choose videos", systemImage: "video.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if !imp.failed.isEmpty {
                    Text(imp.failed).font(.footnote).foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer()
        }
        .padding(24)
        .background(Color.chopBg)
        // mid-processing the sheet can't be swiped away by accident — that
        // looked like the edit was "stuck" when it was actually still running
        .interactiveDismissDisabled(imp.busy || preparing)
        .onAppear {
            // dashboard already picked the videos — start chopping immediately,
            // and show the processing card from the very first frame (the copy
            // out of the photo library takes seconds on big files; without this
            // the idle "Choose videos" page flashes up in the gap)
            if !initialPicks.isEmpty, !imp.busy {
                preparing = true
                imp.stepIndex = 0
                pickedMany = initialPicks
            }
        }
        .onChange(of: pickedMany) { _, items in
            guard !items.isEmpty else { return }
            preparing = true
            if imp.stepIndex < 0 { imp.stepIndex = 0 }
            Task {
                // MULTI-TAKE (Lewis 18 Aug): stitch the clips into one video
                // first, then run the unchanged pipeline once. Single-take
                // continues below exactly as before.
                if stitch, items.count > 1 { await runStitched(items); return }
                // SINGLE-VIDEO batch (Lewis 18 Aug): only the FIRST video runs
                // with the loading screen — the creator drops straight into
                // editing it while videos 2..N chop themselves in the
                // background, one at a time (parallel imports exhaust phone
                // memory), landing in the queue as they finish.
                func batchName(_ n: Int) -> String {
                    let df = DateFormatter(); df.dateFormat = "d MMM, HH.mm"
                    var friendly = "Chop " + df.string(from: Date())
                    if items.count > 1 { friendly += " (\(n + 1))" }
                    return friendly + ".mp4"
                }
                var firstName: String?
                if let item = items.first {
                    if let movie = try? await item.loadTransferable(type: ChopMovie.self) {
                        let friendly = batchName(0)
                        await imp.run(pickedURL: movie.url, name: friendly, api: api)
                        if imp.done { firstName = friendly }
                    } else {
                        imp.failed = "Couldn't read that video"
                    }
                }
                let rest = Array(items.dropFirst())
                if !rest.isEmpty {
                    let apiRef = api
                    // ghost cards for the whole batch — visible in the queue
                    // immediately so nothing looks lost (Lewis 20 Aug)
                    let batchNames = (1...rest.count).map { batchName($0) }
                    apiRef.pendingImports.append(contentsOf: batchNames)
                    Task {   // survives the sheet's dismissal; fresh importer so
                             // its progress never repaints the (closed) sheet
                        let bg = ChopImporter()
                        for (n, item) in rest.enumerated() {
                            let nm = batchName(n + 1)
                            defer { apiRef.pendingImports.removeAll { $0 == nm } }
                            guard let movie = try? await item.loadTransferable(type: ChopMovie.self) else { continue }
                            await bg.run(pickedURL: movie.url, name: nm, api: apiRef)
                        }
                        apiRef.pendingImports.removeAll { batchNames.contains($0) }
                        ChopToasts.shared.show("All videos chopped — waiting in your queue")
                    }
                }
                preparing = false
                // No done screen — the moment the edit is saved, close the sheet
                // and drop straight into the editor for the fresh chop.
                if let firstName, let job = api.jobs.first(where: { $0.name == firstName }) {
                    dismiss()
                    try? await Task.sleep(nanoseconds: 450_000_000)   // let the sheet settle first
                    // never hijack the screen: if they're already editing
                    // another video, this one just waits in the queue
                    if !api.editorOpen, api.openJob == nil { api.openJob = job }
                } else if imp.failed.isEmpty {
                    dismiss()
                }
            }
        }
    }
}

/// PhotosPicker hands back a temporary copy — which is exactly what we want,
/// because it can't go stale underneath us the way a lazy library handle can.
struct ChopMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("chop-in-\(UUID().uuidString).mov")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return ChopMovie(url: dest)
        }
    }
}


// MARK: - Store (StoreKit 2 — consumable credit packs)

/// Product IDs must match App Store Connect exactly when it's set up.
/// Credit count is encoded in the ID so granting never needs a lookup table.
enum ChopPacks {
    // Pricing (Lewis, 18 Aug 26 — matches App Store Connect exactly):
    // 5 = £4.99 (99.8p/video) · 50 = £44.99 (90p) · 100 = £84.99 (85p) ·
    // 150 = £119.99 (80p) · 200 = £149.99 (75p) · 250 = £174.99 (70p).
    static let ids = [
        "com.chopedit.credits.5",
        "com.chopedit.credits.50",
        "com.chopedit.credits.100",
        "com.chopedit.credits.150",
        "com.chopedit.credits.200",
        "com.chopedit.credits.250",
    ]
    static func credits(in productID: String) -> Int {
        Int(productID.split(separator: ".").last.map(String.init) ?? "") ?? 0
    }
}

@MainActor
final class ChopStore: ObservableObject {
    @Published var products: [Product] = []
    @Published var buying = false
    @Published var note = ""
    @Published var lastGranted = 0
    private var updatesTask: Task<Void, Never>?

    /// Load packs. Empty result = ASC not configured yet (or no StoreKit
    /// config attached in dev) — the UI shows an honest fallback.
    func load() async {
        guard products.isEmpty else { return }
        products = ((try? await Product.products(for: ChopPacks.ids)) ?? [])
            .sorted { ChopPacks.credits(in: $0.id) < ChopPacks.credits(in: $1.id) }
        startListener()
    }

    /// Finishes transactions that complete outside the purchase flow
    /// (Ask to Buy approvals, interrupted purchases, cross-device).
    private func startListener() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let t) = update {
                    await self?.grant(t)
                }
            }
        }
    }

    func buy(_ product: Product, api: ChopAPI) async {
        buying = true; note = ""; lastGranted = 0
        defer { buying = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let t)):
                await grant(t, api: api)
            case .success(.unverified):
                note = "Purchase couldn’t be verified — contact support if you were charged."
            case .userCancelled:
                break
            case .pending:
                note = "Purchase pending approval — credits land automatically once approved."
            @unknown default:
                note = "That didn’t work — try again."
            }
        } catch {
            note = "That didn’t work — try again."
        }
    }

    private weak var grantAPI: ChopAPI?
    private func grant(_ t: StoreKit.Transaction, api: ChopAPI? = nil) async {
        if let api { grantAPI = api }
        let n = ChopPacks.credits(in: t.productID)
        if n > 0, let target = grantAPI {
            await target.addCredits(n)
            lastGranted = n
        }
        await t.finish()
    }
}

// MARK: - Billing (web viewBilling parity; StoreKit purchase pending App Store setup)

struct ChopBillingView: View {
    @ObservedObject var api: ChopAPI
    @StateObject private var store = ChopStore()
    @Environment(\.dismiss) private var dismiss
    // V2+V3 hybrid (Lewis-approved): £1 first-chop hero for the easy first
    // purchase, savings ladder for AOV, upgrade bump on 50, value reframe.
    @State private var sel: Int = 5
    @State private var note = ""
    private let packs = [50, 100, 150, 200, 250]   // 5 lives in the hero card

    /// App Store tier prices (Lewis, 18 Aug 26) — MUST match Chop.storekit and
    /// App Store Connect. Totals come from here, per-video is derived, so the
    /// UI always shows exactly what Apple charges. NOTE: web app still runs
    /// the old curve — port when pricing goes live there.
    private func price(_ n: Int) -> Double {
        switch n {
        case 5: return 4.99
        case 50: return 44.99
        case 100: return 84.99
        case 150: return 119.99
        case 200: return 149.99
        case 250: return 174.99
        default: return Double(n)
        }
    }
    private func perCredit(_ n: Int) -> Double { price(n) / Double(max(n, 1)) }
    private func gbp(_ v: Double) -> String { String(format: "£%.2f", (v * 100).rounded() / 100) }
    private func perLabel(_ v: Double) -> String {
        if v >= 1 { return gbp(v) }
        let p = v * 100
        return abs(p - p.rounded()) < 0.05 ? "\(Int(p.rounded()))p" : String(format: "%.1fp", p)
    }

    var body: some View {
        let count = sel
        let total = price(count)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // hero
                    Text("Billing").font(.system(size: 30, weight: .bold)).foregroundStyle(ChopColor.ink)
                    Text("Buy credits to chop your videos. One credit edits one video, any length up to 10 minutes.")
                        .font(.system(size: 15.5)).foregroundStyle(ChopColor.muted)

                    // balance card (web .bal)
                    HStack(spacing: 14) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 17, weight: .bold)).foregroundStyle(ChopColor.blue)
                            .frame(width: 44, height: 44)
                            .background(ChopColor.blueSoft, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(api.credits) credits")
                                .font(.system(size: 17, weight: .heavy)).foregroundStyle(ChopColor.ink)
                            Text("Your current balance")
                                .font(.system(size: 12.5)).foregroundStyle(ChopColor.muted)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(ChopColor.card, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.chopLine, lineWidth: 1))

                    // pricing card — hero, ladder, bump, value reframe
                    VStack(alignment: .leading, spacing: 10) {

                        heroCard

                        HStack(spacing: 10) {
                            Rectangle().fill(Color.chopLine).frame(height: 1)
                            Text("OR STOCK UP & SAVE")
                                .font(.system(size: 9.5, weight: .black)).kerning(0.8)
                                .foregroundStyle(ChopColor.muted)
                                .fixedSize()
                            Rectangle().fill(Color.chopLine).frame(height: 1)
                        }
                        .padding(.vertical, 4)

                        ForEach(packs, id: \.self) { p in
                            packRow(p)
                            if p == 50, sel == 50 { bumpCard }
                        }

                        if sel >= 5 { valueCard(count, total: total) }

                        if store.products.isEmpty {
                            // Purchases go live with the App Store release —
                            // honest state until IAP products exist.
                            Button {
                                note = "Purchases aren’t available in this build yet — they arrive with the App Store release."
                            } label: {
                                Text(count == 5 ? "Start with 5 credits — £4.99"
                                                : "Get \(count) credits — \(gbp(total))")
                                    .font(.system(size: 15, weight: .heavy))
                                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                                    .background(ChopColor.blue, in: RoundedRectangle(cornerRadius: 14))
                                    .foregroundStyle(.white)
                            }
                            .padding(.top, 12)
                            if !note.isEmpty {
                                Text(note).font(.system(size: 12.5)).foregroundStyle(ChopColor.amber)
                            }
                        } else {
                            // live App Store purchase for the selected pack
                            Button {
                                if let product = store.products.first(where: {
                                    ChopPacks.credits(in: $0.id) == count
                                }) {
                                    Task { await store.buy(product, api: api) }
                                } else {
                                    note = "That pack isn't available right now — try another."
                                }
                            } label: {
                                Text(count == 5 ? "Start with 5 credits — £4.99"
                                                : "Get \(count) credits — \(gbp(total))")
                                    .font(.system(size: 15, weight: .heavy))
                                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                                    .background(ChopColor.blue, in: RoundedRectangle(cornerRadius: 14))
                                    .foregroundStyle(.white)
                            }
                            .disabled(store.buying)
                            .padding(.top, 12)
                            if !note.isEmpty {
                                Text(note).font(.system(size: 12.5)).foregroundStyle(ChopColor.amber)
                            }
                            if store.buying {
                                HStack(spacing: 8) {
                                    ProgressView().scaleEffect(0.7).tint(ChopColor.blue)
                                    Text("Completing purchase…")
                                        .font(.system(size: 12.5)).foregroundStyle(ChopColor.muted)
                                }
                            }
                            if store.lastGranted > 0 {
                                Text("✓ \(store.lastGranted) credits added — happy chopping")
                                    .font(.system(size: 13, weight: .bold)).foregroundStyle(ChopColor.green)
                            }
                            if !store.note.isEmpty {
                                Text(store.note).font(.system(size: 12.5)).foregroundStyle(ChopColor.amber)
                            }
                        }
                    }
                    .padding(20)
                    .background(ChopColor.card, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.chopLine, lineWidth: 1))

                    Text("Credits never expire · buy once, chop whenever · VAT included")
                        .font(.system(size: 12.5)).foregroundStyle(ChopColor.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding(20)
            }
            .background(ChopColor.bg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .task { await store.load() }
            .onAppear {
                // returning buyers skip the hook — default straight to the
                // popular pack (default bias works both ways)
                if api.credits > 3 { sel = 100 }
            }
        }
    }

    /// The starter pack — foot-in-the-door, risk reversed (5 @ £4.99).
    private var heroCard: some View {
        Button { withAnimation(.easeInOut(duration: 0.18)) { sel = 5 } } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("FIRST TIME? START HERE")
                    .font(.system(size: 9.5, weight: .black)).kerning(0.8)
                    .foregroundStyle(.white.opacity(0.85))
                HStack(alignment: .firstTextBaseline) {
                    Text("Your first 5 chops")
                        .font(.system(size: 19, weight: .heavy)).foregroundStyle(.white)
                    Spacer()
                    Text("£4.99").font(.system(size: 25, weight: .black)).foregroundStyle(.white)
                }
                Text("Five videos, fully edited — under £1 each. If you don't love it, you've risked a lunch.")
                    .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.88))
            }
            .padding(16)
            .background(LinearGradient(colors: [Color(red: 0x1a/255, green: 0x6d/255, blue: 1.0),
                                                Color(red: 0x4e/255, green: 0x8d/255, blue: 1.0)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(sel == 5 ? Color.white : Color.clear, lineWidth: 2.5))
            .shadow(color: Color.chopBlue.opacity(0.3), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }

    /// One rung of the savings ladder.
    private func packRow(_ p: Int) -> some View {
        let on = sel == p
        let per = perCredit(p)
        let save = Double(p) * 0.998 - price(p)   // vs the starter 99.8p rate
        // Lewis 19 Aug: anchor badges from the approved pricing mockup
        let badge: (String, Color)? = p == 100 ? ("MOST POPULAR", ChopColor.blue)
                                    : p == 250 ? ("BEST VALUE", ChopColor.green) : nil
        return Button { withAnimation(.easeInOut(duration: 0.18)) { sel = p } } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text("\(p) credits")
                            .font(.system(size: 14.5, weight: .heavy)).foregroundStyle(ChopColor.ink)
                        if let badge {
                            Text(badge.0)
                                .font(.system(size: 8.5, weight: .black)).kerning(0.4)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 2.5)
                                .background(badge.1, in: Capsule())
                        }
                    }
                    Text("\(perLabel(per)) per video")
                        .font(.system(size: 10.5)).foregroundStyle(ChopColor.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(gbp(Double(p) * per))
                        .font(.system(size: 15, weight: .heavy)).foregroundStyle(ChopColor.ink)
                    if save > 0 {
                        Text("save \(gbp(save))")
                            .font(.system(size: 9.5, weight: .heavy)).foregroundStyle(ChopColor.green)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(on ? ChopColor.blueSoft : ChopColor.soft2,
                        in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13)
                .stroke(on ? ChopColor.blue : Color.chopLine, lineWidth: on ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    /// The order bump — appears only under a selected 50-pack.
    private var bumpCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Wait — for £40 more you'd get double.")
                .font(.system(size: 12, weight: .heavy)).foregroundStyle(ChopColor.amber)
            Text("100 credits drops you to 85p a video.")
                .font(.system(size: 11.5)).foregroundStyle(ChopColor.muted)
            Button { withAnimation(.easeInOut(duration: 0.18)) { sel = 100 } } label: {
                Text("Upgrade to 100 → £84.99")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color(red: 0x3d/255, green: 0x2e/255, blue: 0x05/255))
                    .padding(.horizontal, 13).padding(.vertical, 8)
                    .background(Color(red: 0xe8/255, green: 0xb9/255, blue: 0x3c/255),
                                in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(ChopColor.amberSoft, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .foregroundStyle(ChopColor.amber.opacity(0.5)))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Value reframe: the price is small next to the editing time it buys.
    private func valueCard(_ n: Int, total: Double) -> some View {
        let hours = Double(n) * 0.25          // ~15 min of manual editing per video
        let worth = hours * 30                // the dashboard's £30/h yardstick
        return (
            Text("≈ \(Int(hours.rounded())) hours of editing saved. ")
                .font(.system(size: 11.5, weight: .heavy)) +
            Text("At £30/h, that's \(gbp(worth)) of editing time for \(gbp(total)).")
                .font(.system(size: 11.5))
        )
        .foregroundStyle(ChopColor.green)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(ChopColor.greenSoft, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Settings

struct ChopSettingsView: View {
    @ObservedObject var api: ChopAPI
    var onThemeChange: ((ChopTheme) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var theme = ChopTheme.current
    @State private var showProfile = false
    @State private var showBilling = false
    @State private var confirming = false
    @State private var deleting = false
    @State private var failed = ""
    @State private var pwSent = false
    @State private var showChangeEmail = false
    @State private var showChangePassword = false
    @State private var newEmail = ""
    @State private var newPw = ""
    @State private var newPw2 = ""
    @State private var acctBusy = false
    @State private var acctError = ""
    @State private var acctNote = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {

                    // header: avatar, name, handle, credits pill
                    VStack(spacing: 8) {
                        ZStack {
                            if api.profileAvatar.hasPrefix("http") {
                                AsyncImage(url: URL(string: api.profileAvatar)) { i in
                                    i.resizable().scaledToFill()
                                } placeholder: { ChopColor.soft2 }
                            } else {
                                LinearGradient(colors: CHOP_AV_COLOURS[0],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                                Text(api.profileAvatar.hasPrefix("e:")
                                     ? String(api.profileAvatar.split(separator: ":")[1]) : "💸")
                                    .font(.system(size: 32))
                            }
                        }
                        .frame(width: 84, height: 84)
                        .clipShape(Circle())
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(ChopColor.blue)
                                .frame(width: 28, height: 28)
                                .background(ChopColor.card, in: Circle())
                                .overlay(Circle().stroke(ChopColor.bg, lineWidth: 2))
                        }
                        .onTapGesture { showProfile = true }

                        Text(api.profileName.isEmpty ? "Your account" : api.profileName)
                            .font(.system(size: 18, weight: .bold)).foregroundStyle(ChopColor.ink)
                        if !api.profileTiktok.isEmpty {
                            Text("@\(api.profileTiktok)").font(ChopFont.small)
                                .foregroundStyle(ChopColor.muted)
                        }
                        HStack(spacing: 5) {
                            Image(systemName: "bolt.fill").font(.system(size: 10, weight: .bold))
                            Text("\(api.credits) credits").font(.system(size: 11.5, weight: .heavy))
                        }
                        .foregroundStyle(ChopColor.blue)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(ChopColor.blueSoft, in: Capsule())
                    }
                    .padding(.vertical, 22)

                    // ONE clean profile group (Aaron 19 Aug): everything about
                    // who you are in a single place.
                    group("Profile") {
                        row("Name", value: api.profileName.isEmpty ? "Not set" : api.profileName, chevron: true) { showProfile = true }
                        divider
                        row("TikTok", value: api.profileTiktok.isEmpty ? "Not set" : "@\(api.profileTiktok)", chevron: true) { showProfile = true }
                        divider
                        row("Photo", action: "Change", chevron: true) { showProfile = true }
                        divider
                        row("Email", value: api.email.isEmpty ? "—" : api.email, chevron: true) {
                            newEmail = ""; acctError = ""; acctNote = ""; showChangeEmail = true
                        }
                        divider
                        row("Password", action: "Change", chevron: true) {
                            newPw = ""; newPw2 = ""; acctError = ""; acctNote = ""; pwSent = false
                            showChangePassword = true
                        }
                    }

                    // Billing/tour/theme all live in the avatar pop-out now —
                    // this page is purely WHO YOU ARE (Aaron 19 Aug).
                    group("Legal") {
                        Link(destination: URL(string: "https://chopedit.com/privacy.html")!) {
                            HStack {
                                Text("Privacy policy").font(ChopFont.body).foregroundStyle(ChopColor.ink)
                                Spacer()
                                Image(systemName: "arrow.up.right").font(.caption)
                                    .foregroundStyle(ChopColor.muted)
                            }
                            .padding(.horizontal, 15).padding(.vertical, 13)
                        }
                    }

                    Button { api.signOut(); dismiss() } label: {
                        Text("Sign out").font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(ChopColor.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(ChopColor.card)
                            .clipShape(RoundedRectangle(cornerRadius: ChopRadius.lg))
                            .overlay(RoundedRectangle(cornerRadius: ChopRadius.lg)
                                .stroke(ChopColor.line, lineWidth: 1))
                    }
                    .padding(.horizontal, 16).padding(.top, 16)

                    Text("DANGER ZONE").font(.system(size: 11, weight: .heavy)).tracking(1.2)
                        .foregroundStyle(ChopColor.rose)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 8)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Delete my account").font(.system(size: 14.5, weight: .heavy))
                            .foregroundStyle(ChopColor.ink)
                        Text("Permanently removes your profile, saved edits and any remaining credits. This cannot be undone.")
                            .font(.system(size: 12)).foregroundStyle(ChopColor.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Button { confirming = true } label: {
                            if deleting { ProgressView() }
                            else {
                                Text("Delete account").font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(ChopColor.rose)
                                    .padding(.horizontal, 15).padding(.vertical, 9)
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .stroke(ChopColor.rose.opacity(0.5), lineWidth: 1))
                            }
                        }
                        .disabled(deleting)
                        if !failed.isEmpty {
                            Text(failed).font(.caption).foregroundStyle(ChopColor.rose)
                        }
                    }
                    .padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ChopColor.roseSoft)
                    .clipShape(RoundedRectangle(cornerRadius: ChopRadius.lg))
                    .overlay(RoundedRectangle(cornerRadius: ChopRadius.lg)
                        .stroke(ChopColor.rose.opacity(0.35), lineWidth: 1))
                    .padding(.horizontal, 16).padding(.bottom, 40)
                }
            }
            .background(ChopColor.bg)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showProfile) { ChopProfileView(api: api) }
            .sheet(isPresented: $showBilling) { ChopBillingView(api: api) }
            .sheet(isPresented: $showChangeEmail) { changeEmailSheet }
            .sheet(isPresented: $showChangePassword) { changePasswordSheet }
            .alert("Delete your account?", isPresented: $confirming) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleting = true
                    Task {
                        let ok = await api.deleteAccount()
                        deleting = false
                        if ok { dismiss() } else { failed = "Couldn't delete the account. Try again." }
                    }
                }
            } message: {
                Text("This permanently removes your profile, saved edits and any remaining credits. It cannot be undone.")
            }
        }
        .preferredColorScheme(theme.scheme)
    }

    // ---- Change email ----
    private var changeEmailSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("We'll email a confirmation link to the new address — the change takes effect once you tap it.")
                    .font(.system(size: 13)).foregroundStyle(ChopColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                ChopField(label: "New email", placeholder: "you@example.com",
                          contentType: .emailAddress, text: $newEmail)
                    .keyboardType(.emailAddress)
                ChopButton(title: "Send confirmation", kind: .primary, loading: acctBusy) {
                    Task {
                        let e = newEmail.trimmingCharacters(in: .whitespaces).lowercased()
                        guard e.contains("@"), e.contains(".") else { acctError = "Enter a valid email address."; return }
                        acctBusy = true; acctError = ""; acctNote = ""
                        let ok = await api.updateEmail(e)
                        acctBusy = false
                        if ok { acctNote = "Check \(e) — tap the link there to confirm the change." }
                        else { acctError = "Couldn't start the change — try again." }
                    }
                }
                if !acctError.isEmpty {
                    Text(acctError).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(ChopColor.rose)
                }
                if !acctNote.isEmpty {
                    Text(acctNote).font(.system(size: 12.5, weight: .bold)).foregroundStyle(ChopColor.green)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(20)
            .background(ChopColor.bg)
            .navigationTitle("Change email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showChangeEmail = false } } }
        }
        .presentationDetents([.medium])
    }

    // ---- Change password ----
    private var changePasswordSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                ChopField(label: "New password", placeholder: "••••••••", secure: true,
                          contentType: .newPassword, text: $newPw)
                ChopField(label: "Repeat new password", placeholder: "••••••••", secure: true,
                          contentType: .newPassword, text: $newPw2)
                ChopButton(title: "Save new password", kind: .primary, loading: acctBusy) {
                    Task {
                        guard newPw.count >= 6 else { acctError = "Use at least 6 characters."; return }
                        guard newPw == newPw2 else { acctError = "Those don't match."; return }
                        acctBusy = true; acctError = ""; acctNote = ""
                        let ok = await api.updatePassword(newPw)
                        acctBusy = false
                        if ok { acctNote = "Password updated ✓"; newPw = ""; newPw2 = "" }
                        else { acctError = "Couldn't save that — try again." }
                    }
                }
                if !acctError.isEmpty {
                    Text(acctError).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(ChopColor.rose)
                }
                if !acctNote.isEmpty {
                    Text(acctNote).font(.system(size: 12.5, weight: .bold)).foregroundStyle(ChopColor.green)
                }
                Button {
                    Task {
                        let e = api.email
                        guard !e.isEmpty else { return }
                        _ = await api.sendPasswordReset(email: e)
                        pwSent = true
                    }
                } label: {
                    Text(pwSent ? "Reset link sent ✓ — check your inbox"
                                : "Forgotten it? Email me a reset link instead")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(pwSent ? ChopColor.green : ChopColor.muted)
                }
                Spacer()
            }
            .padding(20)
            .background(ChopColor.bg)
            .navigationTitle("Change password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showChangePassword = false } } }
        }
        .presentationDetents([.medium])
    }

    private var divider: some View {
        Rectangle().fill(ChopColor.line).frame(height: 1).padding(.leading, 15)
    }

    @ViewBuilder
    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        Text(title.uppercased()).font(.system(size: 11, weight: .heavy)).tracking(1.2)
            .foregroundStyle(ChopColor.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 8)
        VStack(spacing: 0) { content() }
            .background(ChopColor.card)
            .clipShape(RoundedRectangle(cornerRadius: ChopRadius.lg))
            .overlay(RoundedRectangle(cornerRadius: ChopRadius.lg).stroke(ChopColor.line, lineWidth: 1))
            .padding(.horizontal, 16)
    }

    private func row(_ key: String, value: String = "", action: String = "",
                     chevron: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 10) {
                Text(key).font(ChopFont.body).foregroundStyle(ChopColor.muted)
                    .frame(width: 108, alignment: .leading)
                if !value.isEmpty {
                    Text(value).font(ChopFont.body).foregroundStyle(ChopColor.ink).lineLimit(1)
                }
                Spacer()
                if !action.isEmpty {
                    Text(action).font(ChopFont.label).foregroundStyle(ChopColor.blue)
                }
                if chevron {
                    Image(systemName: "chevron.right").font(.caption)
                        .foregroundStyle(ChopColor.muted)
                }
            }
            .padding(.horizontal, 15).padding(.vertical, 13)
        }
    }

    private func staticRow(_ key: String, value: String) -> some View {
        HStack(spacing: 10) {
            Text(key).font(ChopFont.body).foregroundStyle(ChopColor.muted)
                .frame(width: 108, alignment: .leading)
            Text(value).font(ChopFont.body).foregroundStyle(ChopColor.muted).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 15).padding(.vertical, 13)
    }
}


// MARK: - App tour: coach marks pinned to the real buttons.
// Dim the screen, spotlight one control, one sharp line, Next — boom boom boom.
// Skippable, replayable from Settings → App tour.

struct ChopCoachStep {
    let id: String      // matches a .tourAnchor(id) somewhere in the tree
    let title: String
    let text: String
}

struct ChopTourAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>],
                       nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Tag a control so the tour can point at it.
    func tourAnchor(_ id: String) -> some View {
        anchorPreference(key: ChopTourAnchorKey.self, value: .bounds) { [id: $0] }
    }

    /// Attach a coach-mark tour to any container that HOLDS the tagged controls.
    func chopCoach(steps: [ChopCoachStep], active: Binding<Bool>) -> some View {
        modifier(ChopCoachModifier(steps: steps, active: active))
    }
}

struct ChopCoachModifier: ViewModifier {
    let steps: [ChopCoachStep]
    @Binding var active: Bool
    @State private var index = 0

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(ChopTourAnchorKey.self) { prefs in
            if active, index < steps.count {
                // ONE coordinate space for everything (fixes the drifted
                // highlights): the GeometryReader itself ignores the safe
                // areas, so geo covers the full screen, the anchors resolve
                // into that same space, and the dim layer / cutout / stroke /
                // callout all agree. Previously only the dim Path ignored the
                // safe area — its cutout landed a notch-height away from the
                // stroke and the actual control.
                GeometryReader { geo in
                    let step = steps[index]
                    let rect: CGRect = prefs[step.id].map { geo[$0] } ?? .zero

                    ZStack {
                        // dim everything except a rounded cutout on the target
                        Path { p in
                            p.addRect(CGRect(origin: .zero, size: geo.size))
                            if rect != .zero {
                                p.addRoundedRect(in: rect.insetBy(dx: -8, dy: -8),
                                                 cornerSize: CGSize(width: 14, height: 14))
                            }
                        }
                        .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))

                        if rect != .zero {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(ChopColor.blue, lineWidth: 2.5)
                                .frame(width: rect.width + 16, height: rect.height + 16)
                                .position(x: rect.midX, y: rect.midY)
                                .shadow(color: ChopColor.blue.opacity(0.6), radius: 8)
                        }

                        callout(step: step, rect: rect, size: geo.size)
                    }
                    .id(index)   // re-render per step for clean transitions
                    .transition(.opacity)
                }
                .ignoresSafeArea()
            }
        }
        .animation(.easeInOut(duration: 0.22), value: index)
        .animation(.easeInOut(duration: 0.22), value: active)
    }

    private func finish() { active = false; index = 0 }

    private func callout(step: ChopCoachStep, rect: CGRect, size: CGSize) -> some View {
        let cardW: CGFloat = min(300, size.width - 36)
        let below = rect == .zero ? true : rect.midY < size.height * 0.5
        let y: CGFloat = rect == .zero
            ? size.height * 0.5
            : (below ? min(size.height - 110, rect.maxY + 96)
                     : max(110, rect.minY - 96))
        let x = min(max(cardW / 2 + 18, rect == .zero ? size.width / 2 : rect.midX),
                    size.width - cardW / 2 - 18)

        return VStack(alignment: .leading, spacing: 6) {
            Text(step.title)
                .font(.system(size: 15.5, weight: .heavy))
                .foregroundStyle(ChopColor.ink)
            Text(step.text)
                .font(.system(size: 13))
                .foregroundStyle(ChopColor.muted)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
            HStack {
                Button { finish() } label: {
                    Text("Skip")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ChopColor.muted)
                }
                Spacer()
                Button {
                    if index < steps.count - 1 { index += 1 } else { finish() }
                } label: {
                    Text(index < steps.count - 1 ? "Next · \(index + 1) of \(steps.count)" : "Done ✓")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 15).padding(.vertical, 8)
                        .background(ChopColor.blue, in: Capsule())
                }
            }
            .padding(.top, 6)
        }
        .padding(15)
        .frame(width: cardW)
        .background(ChopColor.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.chopLine, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .position(x: x, y: y)
    }
}

// MARK: - Queue

/// Exports a job WITHOUT opening the editor — powers the queue's Select flow.
/// Same recipe as ChopPlayer.export, deliberately duplicated rather than
/// refactored so the editor's proven export path stays untouched.
@MainActor
final class ChopExporter {
    static let shared = ChopExporter()

    func exportToCameraRoll(job: ChopJob, api: ChopAPI) async -> Bool {
        var e = ChopEdit(job: job)
        if (job.data["settings"] as? [String: Any]) == nil { e.settings = ChopPresets.saved }
        let kept = e.keptClips()
        guard !kept.isEmpty else { return false }

        // fresh import still on the phone? zero network — and NEVER blocked
        // on the background sync (videoKey only needed for the cloud path)
        if let imported = api.localImports[job.name],
           FileManager.default.fileExists(atPath: imported.path) {
            return await finishExport(src: AVURLAsset(url: imported), kept: kept, job: job, api: api)
        }
        guard let originalKey = job.videoKey else { return false }
        // reuse the editor's download cache — no double downloads
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let local = cacheDir.appendingPathComponent(
            "chop-" + originalKey.replacingOccurrences(of: "/", with: "_") + ".mp4")
        if !FileManager.default.fileExists(atPath: local.path) {
            guard let signed = await api.presignGet(originalKey) else { return false }
            do {
                let (tmp, _) = try await URLSession.shared.download(from: signed)
                try? FileManager.default.removeItem(at: local)
                try FileManager.default.moveItem(at: tmp, to: local)
            } catch { return false }
        }

        return await finishExport(src: AVURLAsset(url: local), kept: kept, job: job, api: api)
    }

    /// Comp build → 1080p render → camera roll → status flips to Downloaded.
    private func finishExport(src: AVURLAsset, kept: [ChopClip], job: ChopJob, api: ChopAPI) async -> Bool {
        let comp = AVMutableComposition()
        guard let srcV = src.tracks(withMediaType: .video).first,
              let vTrack = comp.addMutableTrack(withMediaType: .video,
                                                preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return false }
        let srcA = src.tracks(withMediaType: .audio).first
        let aTrack = comp.addMutableTrack(withMediaType: .audio,
                                          preferredTrackID: kCMPersistentTrackID_Invalid)
        var cursor = CMTime.zero
        for clip in kept {
            let range = CMTimeRange(start: CMTime(seconds: clip.start, preferredTimescale: 600),
                                    duration: CMTime(seconds: max(0, clip.end - clip.start),
                                                     preferredTimescale: 600))
            do {
                try vTrack.insertTimeRange(range, of: srcV, at: cursor)
                if let srcA, let aTrack { try aTrack.insertTimeRange(range, of: srcA, at: cursor) }
                cursor = CMTimeAdd(cursor, range.duration)
            } catch { return false }
        }
        vTrack.preferredTransform = srcV.preferredTransform

        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("chop-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: out)
        let preset = AVAssetExportSession.exportPresets(compatibleWith: comp)
            .contains(AVAssetExportPreset1920x1080)
            ? AVAssetExportPreset1920x1080 : AVAssetExportPresetMediumQuality
        guard let session = AVAssetExportSession(asset: comp, presetName: preset) else { return false }
        session.outputURL = out
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        // saved pinch zooms travel with the job — bake them in here too,
        // plus the saved rotation (Lewis 18 Aug), same composition builder
        let savedZooms: [(start: Double, end: Double, scale: CGFloat, ox: CGFloat, oy: CGFloat)] =
            ((job.data["zooms"] as? [[String: Any]]) ?? []).compactMap {
                guard let s = $0["s"] as? Double, let e2 = $0["e"] as? Double,
                      let z = $0["z"] as? Double else { return nil }
                return (s, e2, CGFloat(z),
                        CGFloat(($0["x"] as? Double) ?? 0), CGFloat(($0["y"] as? Double) ?? 0))
            }
        let savedRots: [(start: Double, end: Double, q: Int)] =
            ((job.data["rotations"] as? [[String: Any]]) ?? []).compactMap {
                guard let s = $0["s"] as? Double, let e2 = $0["e"] as? Double,
                      let q = $0["q"] as? Int else { return nil }
                return (s, e2, q % 4)
            }
        let savedKFs: [(start: Double, end: Double, scale: CGFloat, ax: CGFloat, ay: CGFloat)] =
            ((job.data["kfZooms"] as? [[String: Any]]) ?? []).compactMap {
                guard let s = $0["s"] as? Double, let e2 = $0["e"] as? Double,
                      let z = $0["z"] as? Double else { return nil }
                return (s, e2, CGFloat(z),
                        CGFloat(($0["x"] as? Double) ?? 0), CGFloat(($0["y"] as? Double) ?? 0))
            }
        if !savedZooms.isEmpty || !savedRots.isEmpty || !savedKFs.isEmpty {
            session.videoComposition = ChopPlayer.zoomComposition(
                track: vTrack, srcTransform: srcV.preferredTransform,
                srcNatural: srcV.naturalSize, kept: kept,
                zooms: savedZooms, totalDuration: comp.duration,
                rotations: savedRots, kfZooms: savedKFs)
        }
        await session.export()
        guard session.status == .completed else { return false }

        let ok = await savePhotos(out)
        if ok { await api.setStatus(job, to: "exported") }   // → Downloaded column
        return ok
    }

    private func savePhotos(_ url: URL) async -> Bool {
        let status = await withCheckedContinuation { (c: CheckedContinuation<PHAuthorizationStatus, Never>) in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { c.resume(returning: $0) }
        }
        guard status == .authorized || status == .limited else { return false }
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }, completionHandler: { done, _ in c.resume(returning: done) })
        }
    }
}

struct ChopQueueBody: View {
    @ObservedObject var api: ChopAPI
    @State private var expandedCols: Set<Int> = []   // See more / See less, per column
    @State private var selectMode = false            // Ready to export: pick & batch-export
    @State private var picked: Set<String> = []
    @State private var exportingBatch = false
    @State private var batchNote = ""

    private func exportPicked(_ list: [ChopJob]) async {
        exportingBatch = true
        defer { exportingBatch = false }
        let chosen = list.filter { picked.contains($0.name) }
        var okCount = 0
        for (n, job) in chosen.enumerated() {
            batchNote = "Exporting \(n + 1) of \(chosen.count)…"
            if await ChopExporter.shared.exportToCameraRoll(job: job, api: api) { okCount += 1 }
        }
        picked = []; selectMode = false
        if okCount > 0 {
            ChopToasts.shared.showBig(okCount == 1
                ? "Exported to your camera roll"
                : "\(okCount) videos exported to your camera roll")
        } else {
            ChopToasts.shared.show("Export failed — open the video and try from the editor")
        }
    }

    private func bucket(_ j: ChopJob) -> Int {
        switch j.status {
        case "queued", "processing": return 0
        case "review", "error":      return 1
        case "approved":             return 2
        default:                     return 3
        }
    }

    // web copy, verbatim — app/index.html renderKanban()
    private let titles = ["Processing", "Ready to review", "Ready to export", "Downloaded"]
    private let empties = [
        "Nothing processing — drop more videos on the dashboard",
        "Nothing waiting for review",
        "Press the green Done button in the editor to move a video here",
        "Exported videos land here so you never download twice"
    ]

    var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    Text("Review queue")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(ChopColor.ink)
                        .padding(.bottom, 4)

                    ForEach(0..<4, id: \.self) { i in
                        let list = api.jobs.filter { bucket($0) == i }
                        // .kcol — soft2 column container, uppercase header + count pill
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                if i == 0 && !list.isEmpty { ProgressView().controlSize(.mini) }
                                Text(titles[i].uppercased())
                                    .font(.system(size: 12, weight: .heavy))
                                    .kerning(0.96)
                                    .foregroundStyle(ChopColor.muted)
                                Text("\(list.count)")
                                    .font(.system(size: 11, weight: .heavy))
                                    .foregroundStyle(ChopColor.ink)
                                    .padding(.horizontal, 9).padding(.vertical, 1)
                                    .background(ChopColor.card, in: RoundedRectangle(cornerRadius: 10))
                                Spacer()
                                if i == 2, !list.isEmpty {
                                    Button {
                                        selectMode.toggle(); picked = []
                                    } label: {
                                        Text(selectMode ? "Cancel" : "Select")
                                            .font(.system(size: 12.5, weight: .heavy))
                                            .foregroundStyle(ChopColor.blue)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(exportingBatch)
                                }
                            }
                            // ghost cards (Lewis 20 Aug): background imports
                            // show HERE with a spinner the moment ✓ is tapped,
                            // unclickable until processing lands them for real
                            if i == 1 {
                                ForEach(api.pendingImports, id: \.self) { name in
                                    HStack(spacing: 11) {
                                        ProgressView()
                                            .controlSize(.small)
                                            .frame(width: 44, height: 44 * 16 / 9)
                                            .background(ChopColor.soft2, in: RoundedRectangle(cornerRadius: 8))
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(name)
                                                .font(.system(size: 12.5, weight: .bold))
                                                .lineLimit(1).foregroundStyle(Color.chopInk)
                                            Text("Chopping — nearly there…")
                                                .font(.system(size: 11)).foregroundStyle(ChopColor.muted)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(10)
                                    .background(ChopColor.card.opacity(0.65))
                                    .clipShape(RoundedRectangle(cornerRadius: 13))
                                    .overlay(RoundedRectangle(cornerRadius: 13)
                                        .stroke(Color.chopLine, lineWidth: 1))
                                }
                            }
                            if list.isEmpty && (i != 1 || api.pendingImports.isEmpty) {
                                Text(empties[i])
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(ChopColor.muted)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 18).padding(.horizontal, 6)
                            } else if !list.isEmpty {
                                // Long columns fold away: 3 cards by default,
                                // See more opens up to 10, anything past 10 scrolls.
                                let expanded = expandedCols.contains(i)
                                let visible = expanded ? list : Array(list.prefix(3))
                                let rows = VStack(alignment: .leading, spacing: 12) {
                                    ForEach(visible) { job in
                                        if i == 2 && selectMode {
                                            // select mode: tap toggles the tick, nothing navigates
                                            Button {
                                                if picked.contains(job.name) { picked.remove(job.name) }
                                                else { picked.insert(job.name) }
                                            } label: {
                                                HStack(spacing: 10) {
                                                    Image(systemName: picked.contains(job.name)
                                                          ? "checkmark.circle.fill" : "circle")
                                                        .font(.system(size: 21))
                                                        .foregroundStyle(picked.contains(job.name)
                                                                         ? ChopColor.green : ChopColor.muted)
                                                    QueueCard(job: job, current: false)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(exportingBatch)
                                        } else {
                                            NavigationLink { ChopPlayerScreen(job: job, api: api) } label: {
                                                QueueCard(job: job, current: false)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                if expanded && list.count > 10 {
                                    ScrollView(showsIndicators: true) { rows }
                                        .frame(height: 10 * 78 + 9 * 12)   // ~10 cards tall, rest scrolls
                                } else {
                                    rows
                                }
                                if list.count > 3 {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            if expanded { expandedCols.remove(i) }
                                            else { expandedCols.insert(i) }
                                        }
                                    } label: {
                                        HStack(spacing: 5) {
                                            Text(expanded ? "See less" : "See more (\(list.count - 3) more)")
                                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                                .font(.system(size: 10, weight: .heavy))
                                        }
                                        .font(.system(size: 12.5, weight: .heavy))
                                        .foregroundStyle(ChopColor.blue)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 9)
                                        .background(ChopColor.card, in: RoundedRectangle(cornerRadius: 11))
                                    }
                                    .buttonStyle(.plain)
                                }
                                if i == 2, selectMode {
                                    Button {
                                        Task { await exportPicked(list) }
                                    } label: {
                                        HStack(spacing: 7) {
                                            if exportingBatch {
                                                ProgressView().tint(.white).scaleEffect(0.8)
                                            } else {
                                                Image(systemName: "square.and.arrow.down")
                                                    .font(.system(size: 13, weight: .bold))
                                            }
                                            Text(exportingBatch ? batchNote
                                                 : "Export \(picked.count) video\(picked.count == 1 ? "" : "s")")
                                        }
                                        .font(.system(size: 13.5, weight: .heavy))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(picked.isEmpty && !exportingBatch
                                                    ? AnyShapeStyle(ChopColor.muted.opacity(0.5))
                                                    : AnyShapeStyle(ChopColor.green),
                                                    in: RoundedRectangle(cornerRadius: 12))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(picked.isEmpty || exportingBatch)
                                }
                            }
                        }
                        .padding(14)
                        .background(ChopColor.soft2, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding(16)
                .padding(.bottom, 110)
            }
    }
}

struct QueueCard: View {
    let job: ChopJob
    var current: Bool = false

    // web kanbanCard() sub line, verbatim construction
    private func fmt(_ sec: Double) -> String {
        let t = Int(sec.rounded()); return "\(t / 60):" + String(format: "%02d", t % 60)
    }
    private var subLine: String {
        if job.status == "processing" { return "processing…" }
        if job.status == "queued" { return "waiting" }
        if job.status == "error" { return (job.data["err"] as? String) ?? "failed" }
        var s = "\(fmt(job.rawSec)) → \(fmt(job.editedSec))"
        let pending = job.pendingRetakes
        s += pending > 0 ? " · \(pending) retake\(pending > 1 ? "s" : "") to decide" : " · no retakes pending"
        if job.videoKey == nil { s += " · sync queued" }
        return s
    }
    private var chip: (String, Color, Color)? {   // text, fg, bg
        switch job.status {
        case "processing": return ("PROCESSING", ChopColor.muted, ChopColor.card)
        case "queued":     return ("QUEUED", ChopColor.muted, ChopColor.card)
        case "error":      return ("FAILED", ChopColor.rose, ChopColor.roseSoft)
        case "review":
            if current { return ("EDITING NOW", ChopColor.blue, ChopColor.blueSoft) }
            if (job.data["savedLater"] as? Bool) == true {
                return ("SAVED FOR LATER", ChopColor.blue, ChopColor.blueSoft)
            }
            return ("NEEDS REVIEW", ChopColor.amber, ChopColor.amberSoft)
        case "approved":   return ("APPROVED", ChopColor.green, ChopColor.greenSoft)
        case "exported":   return ("EXPORTED", ChopColor.green, ChopColor.greenSoft)
        default:           return nil
        }
    }
    private var sinceLine: String? {   // .kwhen — "In this column since 18:42 · 14 Aug"
        guard let ms = job.data["statusAt"] as? Double else { return nil }
        let d = Date(timeIntervalSince1970: ms / 1000)
        let t = DateFormatter(); t.dateFormat = "HH:mm"
        let dd = DateFormatter(); dd.dateFormat = "d MMM"
        return "In this column since \(t.string(from: d)) · \(dd.string(from: d))"
    }

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                LinearGradient(colors: [Color(red: 0.24, green: 0.27, blue: 0.33),
                                        Color(red: 0.13, green: 0.14, blue: 0.17)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if let img = job.thumbnail {
                    Image(uiImage: img).resizable().scaledToFill()
                }
            }
            .frame(width: 44, height: 44 * 16 / 9)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(job.name)
                    .font(.system(size: 12.5, weight: .bold))
                    .lineLimit(1).foregroundStyle(Color.chopInk)
                Text(subLine)
                    .font(.system(size: 11))
                    .foregroundStyle(ChopColor.muted)
                    .lineLimit(2)
                if let c = chip {
                    Text(c.0)
                        .font(.system(size: 9.5, weight: .heavy))
                        .foregroundStyle(c.1)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(c.2, in: RoundedRectangle(cornerRadius: 9))
                }
                if let since = sinceLine {
                    Text(since).font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ChopColor.muted)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.chopMuted)
        }
        .padding(10)
        .background(ChopColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.chopLine, lineWidth: 1))
    }
}

// MARK: - Cut Lab defaults

/// The three presets from the web app, plus whatever the creator saves.
/// Stored on the device like the web app's localStorage chopDefaults.
enum ChopPresets {
    /// THE default (Lewis): every video uses this until the creator saves
    /// their own — silences 0.01s, both clip pads at −260ms.
    static let recommended = ChopSettings(minSil: 0.01, fillers: true, soft: false, startPadMs: -260, endPadMs: -260)
    static let relaxed  = ChopSettings(minSil: 0.7,  fillers: true, soft: false, startPadMs: 60, endPadMs: 0)
    static let balanced = ChopSettings(minSil: 0.4,  fillers: true, soft: false, startPadMs: 40, endPadMs: -40)
    static let snappy   = ChopSettings(minSil: 0.05, fillers: true, soft: false, startPadMs: 0,  endPadMs: -140)

    static var saved: ChopSettings {
        let d = UserDefaults.standard
        guard d.object(forKey: "chopMinSil") != nil else { return recommended }
        return ChopSettings(minSil: d.double(forKey: "chopMinSil"),
                            fillers: d.bool(forKey: "chopFillers"),
                            soft: false,   // soft-fillers option removed from the product
                            startPadMs: d.double(forKey: "chopStartPad"),
                            endPadMs: d.double(forKey: "chopEndPad"))
    }

    static func save(_ s: ChopSettings) {
        let d = UserDefaults.standard
        d.set(s.minSil, forKey: "chopMinSil")
        d.set(s.fillers, forKey: "chopFillers")
        d.set(s.soft, forKey: "chopSoft")
        d.set(s.startPadMs, forKey: "chopStartPad")
        d.set(s.endPadMs, forKey: "chopEndPad")
    }

    static func name(_ s: ChopSettings) -> String {
        if s.matches(recommended) { return "Recommended" }
        if s.matches(relaxed)  { return "Relaxed" }
        if s.matches(balanced) { return "Balanced" }
        if s.matches(snappy)   { return "Snappy" }
        return "Custom"
    }
}

extension ChopSettings {
    init(minSil: Double, fillers: Bool, soft: Bool, startPadMs: Double, endPadMs: Double) {
        self.init()
        self.minSil = minSil; self.fillers = fillers; self.soft = soft
        self.startPadMs = startPadMs; self.endPadMs = endPadMs
    }
    func matches(_ o: ChopSettings) -> Bool {
        abs(minSil - o.minSil) < 0.001 && fillers == o.fillers && soft == o.soft
            && abs(startPadMs - o.startPadMs) < 0.5 && abs(endPadMs - o.endPadMs) < 0.5
    }
}

struct ChopLabBody: View {
    @State private var s = ChopPresets.saved
    @State private var savedNote = false

    // Four presets (Lewis 19 Aug): Relaxed dropped, Recommended renamed —
    // TikTok Affiliate is THE default. Short descriptions, thin cards.
    private let presetMeta: [(String, String, ChopSettings?)] = [
        ("TikTok Affiliate", "For TikTok Shop affiliates — 0.01s silences, −260ms clip pads.", ChopPresets.recommended),
        ("Balanced", "Silences over 0.4s, fillers removed.",          ChopPresets.balanced),
        ("Snappy",   "TikTok-tight — 0.05s silences, tight clip ends.", ChopPresets.snappy),
        ("Custom",   "Your own recipe from the sliders below.",       nil)
    ]

    var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {

                    // .hero — web parity
                    Text("Cut Lab")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(ChopColor.ink)
                    Text("Dial in your cutting style once — every video you drop gets chopped with these settings automatically.")
                        .font(.system(size: 15.5)).foregroundStyle(Color.chopMuted)
                        .padding(.bottom, 6)

                    // .presets — 2×2 grid incl. Custom, DEFAULT badge on the saved one
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                        ForEach(0..<presetMeta.count, id: \.self) { i in
                            presetCard(presetMeta[i].0, presetMeta[i].1, presetMeta[i].2)
                        }
                    }
                    .padding(.top, 6)

                    // .labcard — Fine-tune
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Fine-tune").font(.system(size: 16, weight: .bold)).foregroundStyle(ChopColor.ink)
                        Text("These become your defaults for every new video. You can still tweak any single video in the editor.")
                            .font(.system(size: 12.5)).foregroundStyle(ChopColor.muted)
                            .padding(.bottom, 4)

                        slider("Remove silences over", value: $s.minSil,
                               range: 0.01...2.0, step: 0.01, fmt: { String(format: "%.2fs", $0) },
                               note: "Any pause longer than this is cut automatically.")

                        toggleRow("Remove filler words", "um, uh, hmm…", $s.fillers)

                        slider("Clip start", value: $s.startPadMs,
                               range: -300...300, step: 10, fmt: { Self.ms($0) },
                               note: "Positive keeps a little more before each clip.")

                        slider("Clip end", value: $s.endPadMs,
                               range: -300...300, step: 10, fmt: { Self.ms($0) },
                               note: "Negative trims tighter after each clip.")

                        // .savebar
                        HStack(spacing: 10) {
                            Button {
                                ChopPresets.save(s); savedNote = true
                            } label: {
                                Text("Save as my default")
                                    .font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                                    .background(ChopColor.blue, in: RoundedRectangle(cornerRadius: 12))
                            }
                            Button {
                                s = ChopPresets.recommended; savedNote = false
                            } label: {
                                Text("Reset to TikTok Affiliate")
                                    .font(.system(size: 13, weight: .bold)).foregroundStyle(ChopColor.ink)
                                    .padding(.vertical, 13).padding(.horizontal, 20)
                                    .background(ChopColor.soft2, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding(.top, 8)

                        if savedNote {
                            Text("Saved — every new video will use these settings")
                                .font(.caption).foregroundStyle(Color.chopGreen)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(24)
                    .background(ChopColor.card, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.chopLine, lineWidth: 1))

                    ChopLabPreview(settings: s)
                }
                .padding(16)
                .padding(.bottom, 110)
            }
    }

    static func ms(_ v: Double) -> String {
        let i = Int(v)
        return i >= 0 ? "+\(i)ms" : "−\(abs(i))ms"
    }

    private func toggleRow(_ title: String, _ sub: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(ChopColor.ink)
                Text(sub).font(.system(size: 12)).foregroundStyle(ChopColor.muted)
            }
            Spacer()
            Toggle("", isOn: binding).labelsHidden().tint(Color.chopBlue)
        }
        .padding(.vertical, 6)
        .overlay(Rectangle().fill(ChopColor.line).frame(height: 1), alignment: .bottom)
    }

    private func presetCard(_ title: String, _ desc: String, _ v: ChopSettings?) -> some View {
        let isCustom = v == nil
        let on = isCustom ? ChopPresets.name(s) == "Custom" : s.matches(v!)
        let isDefault = isCustom ? ChopPresets.name(ChopPresets.saved) == "Custom"
                                 : ChopPresets.saved.matches(v!)
        return Button {
            // Custom is tappable too (it read as dead before): it selects
            // your saved recipe if that IS custom, otherwise it just arms
            // the sliders below — either way the card responds.
            if let v { s = v } else if ChopPresets.name(ChopPresets.saved) == "Custom" { s = ChopPresets.saved }
            savedNote = false
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(ChopColor.ink)
                Text(desc).font(.system(size: 11.5)).foregroundStyle(ChopColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(ChopColor.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(on ? ChopColor.blue : Color.chopLine, lineWidth: 1.5))
            .shadow(color: on ? ChopColor.blue.opacity(0.13) : .clear, radius: 11, y: 4)
            .overlay(alignment: .topTrailing) {
                if isDefault {
                    Text("DEFAULT")
                        .font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 2)
                        .background(ChopColor.blue, in: Capsule())
                        .offset(x: -12, y: -10)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.subheadline.weight(.bold))
            content()
        }
        .padding(14)
        .background(Color.chopPanel)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.chopLine, lineWidth: 1))
    }

    private func slider(_ label: String, value: Binding<Double>,
                        range: ClosedRange<Double>, step: Double,
                        fmt: @escaping (Double) -> String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text(fmt(value.wrappedValue))
                    .font(.subheadline.monospacedDigit()).foregroundStyle(Color.chopMuted)
            }
            Slider(value: value, in: range, step: step).tint(Color.chopBlue)
                .onChange(of: value.wrappedValue) { _, _ in savedNote = false }
            Text(note).font(.caption2).foregroundStyle(Color.chopMuted)
        }
    }
}


// MARK: - Profile

let CHOP_AVATARS = ["💸","🏦","🛍️","🛒","💰","📦","🎁","🏷️","💳","✨"]
let CHOP_AV_COLOURS: [[Color]] = [
    [Color(red:0.10,green:0.43,blue:1.00), Color(red:0.49,green:0.23,blue:0.93)],
    [Color(red:0.94,green:0.39,blue:0.48), Color(red:0.98,green:0.64,blue:0.36)],
    [Color(red:0.05,green:0.62,blue:0.43), Color(red:0.22,green:0.85,blue:0.66)],
    [Color(red:0.49,green:0.23,blue:0.93), Color(red:0.88,green:0.31,blue:0.68)],
    [Color(red:0.96,green:0.62,blue:0.04), Color(red:0.94,green:0.27,blue:0.27)]
]


/// Centre-crop to a square and compress, matching the web app's 160px canvas.
func squareJPEG(_ img: UIImage, side: CGFloat = 320) -> Data? {
    let w = img.size.width, h = img.size.height
    let s = min(w, h)
    let rect = CGRect(x: (w - s) / 2, y: (h - s) / 2, width: s, height: s)
    guard let cg = img.cgImage?.cropping(to: rect) else { return img.jpegData(compressionQuality: 0.85) }
    let square = UIImage(cgImage: cg, scale: img.scale, orientation: img.imageOrientation)
    let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
    let out = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: fmt).image { _ in
        square.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
    }
    return out.jpegData(compressionQuality: 0.85)
}

struct ChopProfileView: View {
    @ObservedObject var api: ChopAPI
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var tiktok = ""
    @State private var avatar = "e:💸:0"
    @State private var saving = false
    @State private var failed = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("This is how you'll show up on Chop.")
                        .font(.footnote).foregroundStyle(Color.chopMuted)

                    field("Your name") {
                        TextField("Creator name", text: $name)
                            .textFieldStyle(.plain).padding(12)
                            .background(Color.chopBg).clipShape(RoundedRectangle(cornerRadius: 11))
                            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.chopLine, lineWidth: 1))
                    }

                    field("TikTok handle") {
                        HStack(spacing: 0) {
                            Text("@").foregroundStyle(Color.chopMuted).padding(.leading, 12)
                            TextField("bestshopfinds", text: $tiktok)
                                .textFieldStyle(.plain)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(12)
                        }
                        .background(Color.chopBg).clipShape(RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.chopLine, lineWidth: 1))
                    }

                    field("Profile picture") {
                        HStack(spacing: 14) {
                            ZStack {
                                if let photo {
                                    Image(uiImage: photo).resizable().scaledToFill()
                                } else if avatar.hasPrefix("http") {
                                    AsyncImage(url: URL(string: avatar)) { img in
                                        img.resizable().scaledToFill()
                                    } placeholder: { ChopColor.soft2 }
                                } else {
                                    LinearGradient(colors: CHOP_AV_COLOURS[0],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                                    Text(avatar.hasPrefix("e:")
                                         ? String(avatar.split(separator: ":")[1]) : "💸")
                                        .font(.system(size: 26))
                                }
                            }
                            .frame(width: 72, height: 72)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(ChopColor.line, lineWidth: 1))

                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Text(photo == nil && !avatar.hasPrefix("http")
                                     ? "Upload a photo" : "Change photo")
                                    .font(ChopFont.label).foregroundStyle(ChopColor.blue)
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                    .background(ChopColor.blueSoft, in: Capsule())
                            }
                            Spacer()
                        }
                        .padding(.bottom, 10)

                        Text("or pick an icon").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ChopColor.muted).padding(.bottom, 4)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
                                  spacing: 10) {
                            ForEach(Array(CHOP_AVATARS.enumerated()), id: \.offset) { i, em in
                                let key = "e:\(em):\(i)"
                                let on = avatar == key
                                let cols = CHOP_AV_COLOURS[i % CHOP_AV_COLOURS.count]
                                Text(em)
                                    .font(.system(size: 22))
                                    .frame(width: 52, height: 52)
                                    .background(LinearGradient(colors: cols,
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(on ? Color.white : Color.clear, lineWidth: 2.5))
                                    .onTapGesture { avatar = key; photo = nil }
                            }
                        }
                    }

                    Button {
                        saving = true
                        Task {
                            var av = avatar
                            if let photo, let jpeg = squareJPEG(photo) {
                                if let url = await api.uploadAvatar(jpeg) { av = url }
                                else { failed = "Couldn't upload that photo"; saving = false; return }
                            }
                            let ok = await api.saveProfile(name: name, tiktok: tiktok, avatar: av)
                            saving = false
                            if ok { dismiss() } else { failed = "Couldn't save — try again." }
                        }
                    } label: {
                        if saving { ProgressView().frame(maxWidth: .infinity) }
                        else { Text("Save changes").frame(maxWidth: .infinity) }
                    }
                    .buttonStyle(.borderedProminent).tint(Color.chopBlue)
                    .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)

                    if !failed.isEmpty {
                        Text(failed).font(.footnote).foregroundStyle(.red)
                    }
                }
                .padding(16)
            }
            .background(Color.chopBg)
            .navigationTitle("Your profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let d = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: d) { photo = img }
            }
        }
        .onAppear {
            name = api.profileName
            tiktok = api.profileTiktok
            if !api.profileAvatar.isEmpty { avatar = api.profileAvatar }
        }
    }

    @ViewBuilder
    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.caption.weight(.bold)).foregroundStyle(Color.chopMuted)
            content()
        }
    }
}


// MARK: - Out of credits
//
// No purchase path in the iOS build: Apple require digital goods to go through
// In-App Purchase, and steering people to the web is a rejection risk. This
// sheet explains the position without pointing anywhere.

struct OutOfCreditsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Capsule().fill(Color.chopLine).frame(width: 38, height: 4).padding(.top, 10)

            Image(systemName: "bolt.slash.fill")
                .font(.system(size: 34)).foregroundStyle(.orange).padding(.top, 8)

            Text("You're out of credits").font(.title3.weight(.bold))
            Text("One credit chops one video, any length up to 10 minutes. Add more to your Chop account and they'll appear here automatically.")
                .font(.footnote).foregroundStyle(Color.chopMuted)
                .multilineTextAlignment(.center).padding(.horizontal, 8)

            VStack(spacing: 8) {
                tier("10 credits", "10 videos · £1.00 each", "£10", best: false)
                tier("50 credits", "50 videos · 85p each", "£42.50", best: true)
                tier("100 credits", "100 videos · 75p each", "£75", best: false)
            }
            .padding(.top, 4)

            Text("Credits never expire.")
                .font(.caption2).foregroundStyle(Color.chopMuted)

            Button("Not right now") { dismiss() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.chopMuted)
                .padding(.top, 2)

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 20)
        .background(Color.chopBg)
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    private func tier(_ title: String, _ sub: String, _ price: String, best: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.subheadline.weight(.bold))
                    if best {
                        Text("BEST VALUE")
                            .font(.system(size: 8, weight: .black))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(chopGradient, in: Capsule())
                            .foregroundStyle(Color.chopInk)
                    }
                }
                Text(sub).font(.caption2).foregroundStyle(Color.chopMuted)
            }
            Spacer()
            Text(price).font(.subheadline.weight(.bold))
        }
        .padding(12)
        .background(Color.chopPanel)
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13)
            .stroke(best ? Color.chopBlue : Color.chopLine, lineWidth: best ? 1.5 : 1))
    }
}


// MARK: - Glass nav
//
// The web app's floating pill nav: Dashboard · Queue · Cut Lab, frosted, sat
// 22px off the bottom. It's the single biggest thing that makes Chop look like
// Chop, so it's worth matching properly.

struct ChopGlassNav: View {
    @Binding var tab: Int
    let queueCount: Int
    var film: () -> Void = {}   // the red + (TikTok-style camera)
    var bot: () -> Void = {}    // Chop Bot chat

    // Apple Files-style pill (Lewis 19 Aug): airy, thin icons with the label
    // UNDERNEATH, soft blue tint on the active tab.
    // V1 layout (Lewis 20 Aug, approved mockup): Home · Queue · red ⊕ FILM ·
    // Cuts · Bot — the + button opens the in-app camera, Chop Bot moved INTO
    // the bar as a normal item.
    var body: some View {
        HStack(spacing: 2) {
            item(0, "house", "Home", 0)
            item(1, "tray.full", "Queue", queueCount)
            plusButton
            item(2, "scissors", "Cuts", 0)
            botItem
        }
        .padding(.horizontal, 10).padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
    }

    /// The red circle + with TikTok's dual-tone wing discs peeking behind.
    private var plusButton: some View {
        Button(action: film) {
            ZStack {
                Circle().fill(Color(red: 0x7c/255, green: 0xc7/255, blue: 1.0))
                    .frame(width: 40, height: 40).offset(x: -7)
                Circle().fill(Color(red: 1.0, green: 0x8f/255, blue: 0xa3/255))
                    .frame(width: 40, height: 40).offset(x: 7)
                Circle().fill(Color(red: 1.0, green: 0x2d/255, blue: 0x55/255))
                    .frame(width: 46, height: 46)
                    .shadow(color: Color(red: 1.0, green: 0x2d/255, blue: 0x55/255).opacity(0.45),
                            radius: 7, y: 3)
                Image(systemName: "plus")
                    .font(.system(size: 21, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 62, height: 48)
        }
        .buttonStyle(.plain)
    }

    private var botItem: some View {
        Button(action: bot) {
            VStack(spacing: 2) {
                Image(systemName: "face.smiling")
                    .font(.system(size: 17, weight: .regular))
                Text("Bot").font(.system(size: 10.5, weight: .semibold)).fixedSize()
            }
            .foregroundStyle(Color.chopMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func item(_ i: Int, _ icon: String, _ label: String, _ badge: Int) -> some View {
        let on = tab == i
        return Button { tab = i } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .regular))
                Text(label)
                    .font(.system(size: 10.5, weight: on ? .bold : .semibold))
                    .fixedSize()
            }
            .foregroundStyle(on ? Color.chopBlue : Color.chopMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(on ? Color.chopBlue.opacity(0.12) : .clear, in: Capsule())
            .overlay(alignment: .topTrailing) {
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 9.5, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(Color(red: 1, green: 0.23, blue: 0.19), in: Capsule())
                        .offset(x: -14, y: 2)
                }
            }
        }
        .tourAnchor(i == 1 ? "tour-queue" : i == 2 ? "tour-lab" : "tour-dash")
    }
}

// MARK: - In-app filming (Lewis 20 Aug, approved v2 mockup — TikTok model).
// Each press-to-pause burst records its OWN clip file; finish stitches them
// through the LOCKED ChopStitcher + ChopImporter pipeline exactly like the
// Combine upload mode — the auto-edit never knows the video wasn't uploaded.

@MainActor
final class ChopCamera: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    private let movieOut = AVCaptureMovieFileOutput()
    @Published var ready = false
    @Published var denied = false
    @Published var recording = false
    @Published var front = true          // talking-head default
    @Published var torchOn = false
    @Published var takes: [(url: URL, sec: Double, front: Bool)] = []
    private var takeStart: Date? = nil
    private var takeFront = false   // which camera THIS take is using

    var totalSec: Double { takes.reduce(0) { $0 + $1.sec } + liveSec }
    var liveSec: Double { takeStart.map { -$0.timeIntervalSinceNow } ?? 0 }

    func start() async {
        let cam = await AVCaptureDevice.requestAccess(for: .video)
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        guard cam, mic else { denied = true; return }
        session.beginConfiguration()
        session.sessionPreset = .high
        attachCamera()
        if let m = AVCaptureDevice.default(for: .audio),
           let mIn = try? AVCaptureDeviceInput(device: m), session.canAddInput(mIn) {
            session.addInput(mIn)
        }
        if session.canAddOutput(movieOut) { session.addOutput(movieOut) }
        session.commitConfiguration()
        let s = session
        DispatchQueue.global(qos: .userInitiated).async { s.startRunning() }
        ready = true
    }

    private var videoDevice: AVCaptureDevice? = nil   // the live camera
    private var oneX: CGFloat = 1     // zoom factor that means "1×" (virtual back = ~2)
    private var pinchBase: CGFloat? = nil

    private func attachCamera() {
        for inp in session.inputs {
            if let d = inp as? AVCaptureDeviceInput, d.device.hasMediaType(.video) {
                session.removeInput(d)
            }
        }
        let pos: AVCaptureDevice.Position = front ? .front : .back
        // BACK = the dual-lens VIRTUAL device (Lewis 20 Aug): pinch ramps the
        // zoom factor smoothly through 0.5×→1×→tele — TikTok's mechanism —
        // with ZERO session reconfig (the old lens swap froze the screen when
        // combined with the torch). Falls back to the plain wide lens on
        // hardware without an ultra-wide.
        let kind: AVCaptureDevice.DeviceType = front ? .builtInWideAngleCamera
                                                     : .builtInDualWideCamera
        guard let dev = AVCaptureDevice.default(kind, for: .video, position: pos)
                     ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: pos),
              let inp = try? AVCaptureDeviceInput(device: dev), session.canAddInput(inp) else { return }
        session.addInput(inp)
        videoDevice = dev

        if front {
            // FRONT FOV (Lewis 20 Aug v2 — 'still not as wide as TikTok'):
            // consider EVERY 16:9 format at ≥1080p30, not just exactly 1080p,
            // and take the widest field of view the sensor offers.
            oneX = 1
            let wide = dev.formats.filter { f in
                let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
                let ar = Double(d.width) / Double(d.height)
                return d.height >= 1080 && abs(ar - 16.0 / 9.0) < 0.05 &&
                       f.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 }
            }.max(by: { $0.videoFieldOfView < $1.videoFieldOfView })
            if let f = wide, f.videoFieldOfView > dev.activeFormat.videoFieldOfView + 0.1,
               (try? dev.lockForConfiguration()) != nil {
                session.sessionPreset = .inputPriority
                dev.activeFormat = f
                dev.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                dev.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
                dev.unlockForConfiguration()
            }
        } else {
            if session.sessionPreset != .high { session.sessionPreset = .high }
            // on the virtual device, "1×" lives at the switch-over factor
            oneX = CGFloat(dev.virtualDeviceSwitchOverVideoZoomFactors.first?.doubleValue ?? 1)
            if (try? dev.lockForConfiguration()) != nil {
                dev.videoZoomFactor = oneX
                dev.unlockForConfiguration()
            }
        }
        configureOutputConnection()
    }

    /// TikTok pinch: two fingers in → 0.5×, out → zoom in. Back camera only.
    func pinchZoom(_ scale: CGFloat) {
        guard !front, let dev = videoDevice else { return }
        if pinchBase == nil { pinchBase = dev.videoZoomFactor }
        let target = min(max((pinchBase ?? oneX) * scale, dev.minAvailableVideoZoomFactor),
                         min(dev.maxAvailableVideoZoomFactor, oneX * 6))
        if (try? dev.lockForConfiguration()) != nil {
            dev.videoZoomFactor = target
            dev.unlockForConfiguration()
        }
    }
    func pinchEnded() { pinchBase = nil }

    /// ONE place that pins the recording orientation. Called after every
    /// camera attach/flip AND before every take.
    /// NEVER MIRRORED (Lewis 20 Aug — the flipped/distorted mixed-camera bug):
    /// front-mirrored files carry a negative-determinant transform; the
    /// stitcher applies clip 1's transform to EVERY clip (so a back take after
    /// a front take came out flipped) and the editor's rotation maths only
    /// speaks 0/90/180/270 (the distortion). Files are now always plain
    /// portrait — the viewfinder still previews the front camera mirrored,
    /// like every camera app, but what's SAVED is standard.
    func configureOutputConnection() {
        guard let conn = movieOut.connection(with: .video) else { return }
        if conn.isVideoOrientationSupported { conn.videoOrientation = .portrait }
        if conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = false
        }
    }

    func flip() {
        guard !recording else { return }
        session.beginConfiguration()
        front.toggle()
        if front { setTorch(false) }
        attachCamera()
        session.commitConfiguration()
    }

    /// Torch = the back camera's light — always addressed on the LIVE device
    /// (the freeze came from locking a different device than the session's).
    func setTorch(_ on: Bool) {
        torchOn = on
        guard !front, let dev = videoDevice,
              dev.hasTorch, (try? dev.lockForConfiguration()) != nil else { return }
        dev.torchMode = on ? .on : .off
        dev.unlockForConfiguration()
    }

    func startTake() {
        guard ready, !recording else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chopcam-\(UUID().uuidString).mov")
        configureOutputConnection()
        takeFront = front
        movieOut.startRecording(to: url, recordingDelegate: self)
        takeStart = Date()
        recording = true
    }

    /// Belt & braces for the sideways-take bug: if any take's orientation
    /// metadata differs from the first's, re-render the odd ones upright
    /// BEFORE the stitcher (which by design uses the first clip's transform
    /// for the lot). Matching takes pass through untouched — zero cost on the
    /// normal path.
    static func normalized(_ items: [(url: URL, front: Bool)]) async -> [URL] {
        guard !items.isEmpty else { return [] }
        // a take's signature: its transform AND its oriented display size —
        // front and back cameras record different resolutions, and a size
        // mismatch through the stitcher is the distortion Lewis saw
        func sig(_ u: URL) async -> (t: CGAffineTransform, disp: CGSize) {
            let a = AVURLAsset(url: u)
            guard let tr = try? await a.loadTracks(withMediaType: .video).first,
                  let p = try? await tr.load(.preferredTransform),
                  let n = try? await tr.load(.naturalSize) else { return (.identity, .zero) }
            let r = CGRect(origin: .zero, size: n).applying(p)
            return (p, CGSize(width: abs(r.width), height: abs(r.height)))
        }
        let first = await sig(items[0].url)
        var out: [URL] = []
        for (i, item) in items.enumerated() {
            let s = i == 0 ? first : await sig(item.url)
            let sameT = abs(s.t.a - first.t.a) < 0.01 && abs(s.t.b - first.t.b) < 0.01
                     && abs(s.t.c - first.t.c) < 0.01 && abs(s.t.d - first.t.d) < 0.01
            let sameSize = abs(s.disp.width - first.disp.width) < 2
                        && abs(s.disp.height - first.disp.height) < 2
            // FRONT takes ALWAYS re-render (Lewis 20 Aug): the mirror gets
            // baked into the PIXELS so the saved video matches the mirrored
            // viewfinder — with clean plain metadata the editor understands.
            if !item.front && sameT && sameSize {
                out.append(item.url)
            } else {
                out.append(await uprightRender(item.url, target: first.disp, mirror: item.front) ?? item.url)
            }
        }
        return out
    }

    /// Re-encode one take upright at the TARGET display size (the first
    /// take's) — aspect-fill, centred — so every take enters the stitcher with
    /// identical geometry.
    private static func uprightRender(_ url: URL, target: CGSize, mirror: Bool = false) async -> URL? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let nat = try? await track.load(.naturalSize),
              let tf = try? await track.load(.preferredTransform),
              let dur = try? await asset.load(.duration) else { return nil }
        // oriented (display) size of this take
        let r = CGRect(origin: .zero, size: nat).applying(tf)
        let disp = CGSize(width: abs(r.width), height: abs(r.height))
        let canvas = target.width > 1 && target.height > 1 ? target : disp

        let comp = AVMutableVideoComposition()
        comp.renderSize = canvas
        comp.frameDuration = CMTime(value: 1, timescale: 30)
        let inst = AVMutableVideoCompositionInstruction()
        inst.timeRange = CMTimeRange(start: .zero, duration: dur)
        let li = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        // own transform → origin, then aspect-FILL scale into the target,
        // centred (never squashed — the distortion fix)
        let s = max(canvas.width / disp.width, canvas.height / disp.height)
        var t = tf
            .concatenating(CGAffineTransform(translationX: -r.minX, y: -r.minY))
            .concatenating(CGAffineTransform(scaleX: s, y: s))
            .concatenating(CGAffineTransform(translationX: (canvas.width - disp.width * s) / 2,
                                             y: (canvas.height - disp.height * s) / 2))
        if mirror {   // bake the selfie mirror into the pixels, metadata stays clean
            t = t.concatenating(CGAffineTransform(scaleX: -1, y: 1))
                 .concatenating(CGAffineTransform(translationX: canvas.width, y: 0))
        }
        li.setTransform(t, at: .zero)
        inst.layerInstructions = [li]
        comp.instructions = [inst]

        guard let ex = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { return nil }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("chopcam-fix-\(UUID().uuidString).mov")
        ex.outputURL = out
        ex.outputFileType = .mov
        ex.videoComposition = comp
        await ex.export()
        return ex.status == .completed ? out : nil
    }

    func stopTake() {
        guard recording else { return }
        movieOut.stopRecording()
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection],
                                error: Error?) {
        Task { @MainActor in
            let sec = self.takeStart.map { -$0.timeIntervalSinceNow } ?? 0
            self.takeStart = nil
            self.recording = false
            if sec > 0.2, FileManager.default.fileExists(atPath: outputFileURL.path) {
                self.takes.append((outputFileURL, sec, self.takeFront))
            } else {
                try? FileManager.default.removeItem(at: outputFileURL)
            }
        }
    }

    func deleteLast() {
        guard let t = takes.popLast() else { return }
        try? FileManager.default.removeItem(at: t.url)
    }
    func discardAll() {
        takes.forEach { try? FileManager.default.removeItem(at: $0.url) }
        takes = []
    }
    func shutdown() {
        setTorch(false)
        let s = session
        DispatchQueue.global(qos: .userInitiated).async { s.stopRunning() }
    }
}

/// Live viewfinder.
struct ChopCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    final class V: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    }
    func makeUIView(context: Context) -> V {
        let v = V()
        let l = v.layer as! AVCaptureVideoPreviewLayer
        l.session = session
        l.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: V, context: Context) {}
}

struct ChopCameraView: View {
    @ObservedObject var api: ChopAPI
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cam = ChopCamera()
    @StateObject private var imp = ChopImporter()

    @State private var maxSec: Double = 60
    @State private var countdownArmed = false
    @State private var countNum: Int? = nil
    @State private var grid = false
    @State private var delArmed = false
    @State private var confirmDiscard = false
    @State private var confirmDelete = false   // TikTok "Discard the last clip?"
    @State private var confirmFinish = false   // ✓ → "Send to edit / Continue filming"
    @State private var preparing = false

    private let rose = Color(red: 1.0, green: 0x2d/255, blue: 0x55/255)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if cam.ready { ChopCameraPreview(session: cam.session).ignoresSafeArea() }

            if grid { gridLines }

            cameraUI

            // sent-to-edit message — BIG and readable (Lewis), 5 seconds.
            // ALWAYS in the hierarchy, faded in/out via opacity: an inserted
            // view gets dropped by the alert's dismiss transaction (invisible-
            // banner bug), and a delayed insert felt laggy — opacity does
            // neither, so it appears the instant Send to edit is tapped.
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Color.chopGreen)
                Text(banner ?? "")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 24).padding(.vertical, 22)
            .frame(maxWidth: 310)
            .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 22))
            .opacity(banner == nil ? 0 : 1)
            .scaleEffect(banner == nil ? 0.92 : 1)
            .animation(.spring(duration: 0.28), value: banner == nil)
            .allowsHitTesting(false)
            .zIndex(10)   // always above the camera UI

            if let n = countNum {
                Color.black.opacity(0.35).ignoresSafeArea()
                Text("\(n)")
                    .font(.system(size: 110, weight: .black))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 20)
            }

            if cam.denied { deniedView }
        }
        .statusBarHidden()
        // TikTok pinch-zoom (Lewis 20 Aug): two fingers in → 0.5×, out → tele.
        // Simultaneous so buttons/taps keep working exactly as before.
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { v in cam.pinchZoom(v) }
                .onEnded { _ in cam.pinchEnded() }
        )
        .task { await cam.start() }
        .onDisappear { cam.shutdown() }
        .alert("Delete this video?", isPresented: $confirmDiscard) {
            Button("Delete takes", role: .destructive) {
                cam.discardAll(); cam.shutdown(); dismiss()
            }
            Button("Keep filming", role: .cancel) {}
        } message: {
            Text("You've filmed \(cam.takes.count) take\(cam.takes.count == 1 ? "" : "s"). Going back deletes them — this can't be undone.")
        }
        .alert("Discard the last clip?", isPresented: $confirmDelete) {
            Button("Discard", role: .destructive) { cam.deleteLast() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("All done?", isPresented: $confirmFinish) {
            Button("Send to edit") { finish() }   // synchronous — fires instantly
            Button("Continue filming", role: .cancel) {}
        }
    }

    // MARK: pieces

    private var cameraUI: some View {
        // TimelineView drives the live ring/timer every frame while recording
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !cam.recording)) { _ in
            let total = cam.totalSec
            ZStack {
                // top bar — hidden while recording, like TikTok
                if !cam.recording {
                    VStack {
                        HStack {
                            Button {
                                if cam.takes.isEmpty { cam.shutdown(); dismiss() }
                                else { confirmDiscard = true }
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 17, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .frame(width: 38, height: 38)
                                    .background(.black.opacity(0.45), in: Circle())
                            }
                            Spacer()
                            HStack(spacing: 0) {
                                Text("Film with ").foregroundStyle(.white)
                                Text("chop").foregroundStyle(Color(red: 0x7c/255, green: 0xb0/255, blue: 1.0))
                            }
                            .font(.system(size: 13.5, weight: .heavy))
                            .padding(.horizontal, 15).padding(.vertical, 8)
                            .background(.black.opacity(0.45), in: Capsule())
                            Spacer()
                            Color.clear.frame(width: 38, height: 38)
                        }
                        .padding(.horizontal, 18).padding(.top, 12)
                        Spacer()
                    }

                    // right rail — TikTok style: bare white icons, no circles
                    VStack(spacing: 22) {
                        railTool("arrow.triangle.2.circlepath.camera", "Flip", on: false) { cam.flip() }
                        railTool(cam.torchOn ? "bolt.fill" : "bolt.slash.fill", "Flash", on: cam.torchOn) { cam.setTorch(!cam.torchOn) }
                        railTool("timer", "3s", on: countdownArmed) { countdownArmed.toggle() }
                        railTool("grid", "Grid", on: grid) { grid.toggle() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 16).padding(.top, 64)
                }

                VStack(spacing: 0) {
                    Spacer()

                    // timer
                    if cam.recording || !cam.takes.isEmpty {
                        Text(Self.fmt(total))
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 5)
                            .padding(.bottom, 10)
                    }

    // duration pills — visible whenever not recording (Lewis 20 Aug:
                    // they used to vanish after the first take, which read as
                    // broken); a cap smaller than what's already filmed is
                    // dimmed and inert
                    if !cam.recording {
                        HStack(spacing: 6) {
                            durPill("10m", 600); durPill("60s", 60); durPill("15s", 15)
                        }
                        .padding(.bottom, 14)
                    }

                    // record row: ⊥upload · [ring+button] · ✕ · ✓
                    ZStack {
                        recordButton(total: total)
                        if !cam.recording && !cam.takes.isEmpty {
                            HStack {
                                Spacer()
                                // TikTok's exact backspace-tag delete button →
                                // confirmation popup, no two-tap arming
                                Button { confirmDelete = true } label: {
                                    Image(systemName: "delete.left.fill")
                                        .font(.system(size: 30, weight: .semibold))
                                        .foregroundStyle(.white, .black.opacity(0.55))
                                        .shadow(color: .black.opacity(0.35), radius: 5)
                                        .frame(width: 54, height: 48)
                                }
                                Button { confirmFinish = true } label: {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 18, weight: .heavy))
                                        .foregroundStyle(.white)
                                        .frame(width: 48, height: 48)
                                        .background(rose, in: Circle())
                                }
                                .padding(.trailing, 26)
                            }
                        }
                    }
                    .padding(.bottom, 36)
                }
            }
        }
    }

    private func recordButton(total: Double) -> some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.28), lineWidth: 5)
                .frame(width: 100, height: 100)
            // live progress ring
            Circle().trim(from: 0, to: min(total / maxSec, 1))
                .stroke(rose, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 100, height: 100)
            // white take markers
            ForEach(Array(takeBounds().enumerated()), id: \.offset) { _, f in
                Circle().trim(from: max(0, f - 0.006), to: f)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 7))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 100, height: 100)
            }
            Button {
                if cam.recording { cam.stopTake(); return }
                guard cam.totalSec < maxSec else { return }
                delArmed = false
                if countdownArmed { runCountdown() } else { cam.startTake() }
            } label: {
                ZStack {
                    Circle().fill(cam.recording ? .white : rose)
                        .frame(width: 74, height: 74)
                        .overlay(Circle().stroke(rose.opacity(cam.recording ? 0 : 0.35), lineWidth: 6).padding(-6))
                    RoundedRectangle(cornerRadius: 8).fill(rose)
                        .frame(width: cam.recording ? 30 : 0, height: cam.recording ? 30 : 0)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: cam.recording)
            }
            .buttonStyle(.plain)
        }
        .onChange(of: cam.recording) { _, rec in
            // auto-stop at the cap
            if rec {
                Task {
                    while cam.recording {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        if cam.totalSec >= maxSec { cam.stopTake(); break }
                    }
                }
            }
        }
    }

    private func takeBounds() -> [Double] {
        var acc = 0.0
        return cam.takes.map { t in acc += t.sec; return min(acc / maxSec, 1) }
    }

    private func runCountdown() {
        Task {
            for n in [3, 2, 1] {
                countNum = n
                try? await Task.sleep(nanoseconds: 900_000_000)
            }
            countNum = nil
            cam.startTake()
        }
    }

    /// ✓ = fire-and-forget (Lewis 20 Aug: affiliates bulk-film). The takes are
    /// handed to a BACKGROUND import — stitch, upload, auto-edit — and land in
    /// the queue on their own while the camera stays open for the next video.
    /// SYNCHRONOUS front half (Lewis: 'all functions fire right away'): the
    /// banner, the ghost card and the take capture happen in the alert button's
    /// own transaction — nothing waits on a scheduled Task, so the first send
    /// can't swallow its UI.
    private func finish() {
        guard !cam.takes.isEmpty else { return }
        let items = cam.takes.map { (url: $0.url, front: $0.front) }
        let urls = cam.takes.map { $0.url }
        cam.takes = []          // camera is instantly ready for the next video
        delArmed = false
        let df = DateFormatter(); df.dateFormat = "d MMM, HH.mm.ss"
        let friendly = "Chop " + df.string(from: Date()) + " (filmed).mp4"
        let apiRef = api
        apiRef.pendingImports.append(friendly)   // ghost card in the queue NOW
        showBanner("Sent to edit 🎬\nYour video will be in Ready to review in your Queue when it's done.")
        Task.detached(priority: .userInitiated) {
            // straighten any take whose orientation metadata drifted, then the
            // LOCKED stitch + import pipeline, same as the Combine upload mode
            let fixed = await ChopCamera.normalized(items)
            guard let combined = await ChopStitcher.stitch(fixed) else {
                await MainActor.run {
                    apiRef.pendingImports.removeAll { $0 == friendly }
                    ChopToasts.shared.show("Couldn't combine those takes")
                }
                return
            }
            let bg = await MainActor.run { ChopImporter() }
            await bg.run(pickedURL: combined, name: friendly, api: apiRef)
            let ok: Bool = await MainActor.run {
                apiRef.pendingImports.removeAll { $0 == friendly }
                // a failed background run used to vanish SILENTLY (and delete
                // the takes) — now it says so and keeps the files for retry
                if !bg.done {
                    ChopToasts.shared.show(bg.failed.isEmpty
                        ? "Couldn't process \(friendly) — try filming again"
                        : bg.failed)
                }
                return bg.done
            }
            if ok { urls.forEach { try? FileManager.default.removeItem(at: $0) } }
        }
    }

    @State private var banner: String? = nil
    private func showBanner(_ s: String) {
        banner = s   // instant — the card is opacity-driven, nothing to drop
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)   // 5s, Lewis's spec
            banner = nil
        }
    }

    private func durPill(_ label: String, _ sec: Double) -> some View {
        let on = maxSec == sec
        let allowed = sec > cam.totalSec   // can't pick a cap below what's filmed
        return Button {
            guard allowed else { return }
            maxSec = sec
        } label: {
            Text(label)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(on ? Color.black : .white.opacity(allowed ? 0.9 : 0.35))
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(on ? AnyShapeStyle(.white) : AnyShapeStyle(.black.opacity(0.35)), in: Capsule())
                .contentShape(Capsule())   // the whole pill is tappable, not just the text
        }
        .buttonStyle(.plain)
    }

    // TikTok-style rail buttons: bare white glyphs with a soft shadow — no
    // circle backgrounds (Lewis 20 Aug). Active = warm yellow tint.
    private func railTool(_ icon: String, _ label: String, on: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .regular))
                Text(label).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(on ? Color(red: 1.0, green: 0.85, blue: 0.3) : .white)
            .shadow(color: .black.opacity(0.55), radius: 4, y: 1)
            .frame(width: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }


    private var gridLines: some View {
        GeometryReader { g in
            Path { p in
                for f in [1.0/3.0, 2.0/3.0] {
                    p.move(to: CGPoint(x: g.size.width * f, y: 0))
                    p.addLine(to: CGPoint(x: g.size.width * f, y: g.size.height))
                    p.move(to: CGPoint(x: 0, y: g.size.height * f))
                    p.addLine(to: CGPoint(x: g.size.width, y: g.size.height * f))
                }
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 1)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var deniedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.slash").font(.largeTitle).foregroundStyle(.white)
            Text("Chop needs the camera and mic")
                .font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
            Text("Turn them on in Settings → Chop to film in the app.")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
            }
            .font(.system(size: 14, weight: .heavy))
            Button("Close") { dismiss() }
                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.7))
        }
        .padding(30)
        .background(Color.black.opacity(0.85).ignoresSafeArea())
    }

    private static func fmt(_ s: Double) -> String {
        let t = Int(s)
        return String(format: "%02d:%02d", t / 60, t % 60)
    }
}

// MARK: - Chop Bot (Lewis 19 Aug): the onboarding helper.
// A detached circle beside the nav pill — Lewis's robot artwork with a
// breathing glow and a pulsing ring — opening a chat sheet backed by the
// chop-assist edge function.

struct ChopBotButton: View {
    let tap: () -> Void
    @State private var glow = false

    var body: some View {
        Button(action: tap) {
            ZStack {
                if UIImage(named: "chopbot") != nil {
                    Image("chopbot").resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [Color(red: 0x1a/255, green: 0x6d/255, blue: 1.0),
                                            Color(red: 0x4e/255, green: 0x8d/255, blue: 1.0)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "face.smiling")
                        .font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                }
            }
            .frame(width: 50, height: 50)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
            // breathing glow
            .shadow(color: Color.chopBlue.opacity(glow ? 0.75 : 0.35),
                    radius: glow ? 16 : 8, y: 4)
            // inviting ring that pulses outward
            .overlay(
                Circle()
                    .stroke(Color.chopBlue.opacity(glow ? 0 : 0.55), lineWidth: 2)
                    .scaleEffect(glow ? 1.5 : 1.0)
            )
            .offset(y: glow ? -2 : 0)   // gentle bob
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }
}

struct ChopBotChat: View {
    @ObservedObject var api: ChopAPI
    @Environment(\.dismiss) private var dismiss
    @State private var msgs: [(role: String, text: String)] = [
        ("assistant", "Hey, this is Chop Bot 🤖 Is there anything I can help you with?")
    ]
    @State private var draft = ""
    @State private var thinking = false
    @State private var showChips = true
    @FocusState private var focused: Bool

    private let chips = ["How do credits work?", "Bulk vs Combine?", "How do I export?"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(msgs.enumerated()), id: \.offset) { _, m in
                                bubble(m.role, m.text)
                            }
                            if showChips {
                                FlowChips(chips: chips) { c in Task { await send(c) } }
                            }
                            if thinking {
                                HStack(spacing: 4) {
                                    ForEach(0..<3, id: \.self) { _ in
                                        Circle().fill(ChopColor.muted.opacity(0.5))
                                            .frame(width: 7, height: 7)
                                    }
                                }
                                .padding(14)
                                .background(ChopColor.soft2, in: RoundedRectangle(cornerRadius: 18))
                            }
                            Color.clear.frame(height: 6).id("end")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                    }
                    .onChange(of: msgs.count) { _, _ in
                        withAnimation { proxy.scrollTo("end", anchor: .bottom) }
                    }
                }

                HStack(spacing: 8) {
                    TextField("Message Chop Bot…", text: $draft)
                        .focused($focused)
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .background(ChopColor.soft2, in: Capsule())
                        .onSubmit { Task { await send(draft) } }
                    Button {
                        Task { await send(draft) }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(ChopColor.blue, in: Circle())
                    }
                    .disabled(thinking || draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 10)
            }
            .background(ChopColor.bg)
            .navigationTitle("Chop Bot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }

    @ViewBuilder
    private func bubble(_ role: String, _ text: String) -> some View {
        HStack {
            if role == "user" { Spacer(minLength: 40) }
            Text(text)
                .font(.system(size: 14.5))
                .foregroundStyle(role == "user" ? .white : ChopColor.ink)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(role == "user" ? AnyShapeStyle(ChopColor.blue)
                                           : AnyShapeStyle(ChopColor.soft2),
                            in: RoundedRectangle(cornerRadius: 18))
            if role != "user" { Spacer(minLength: 40) }
        }
    }

    private func send(_ text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !thinking else { return }
        draft = ""
        showChips = false
        msgs.append(("user", t))
        thinking = true
        let history = msgs.map { ["role": $0.role, "content": $0.text] }
        let reply = await api.askAssist(history)
        thinking = false
        msgs.append(("assistant",
                     reply ?? "Hmm, I couldn't reach base just then — give it another go in a second, or email hello@chopedit.com and a human will help."))
    }
}

/// The suggested-question chips under Chop Bot's greeting.
struct FlowChips: View {
    let chips: [String]
    let tap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(chips, id: \.self) { c in
                Button { tap(c) } label: {
                    Text(c)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ChopColor.blue)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(ChopColor.blueSoft, in: Capsule())
                        .overlay(Capsule().stroke(ChopColor.blue.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}


// MARK: - Welcome
//
// The landing page, natively. New users land here rather than on a bare
// sign-in form, which is what made the app feel like it started mid-sentence.

struct ChopWelcomeView: View {
    @ObservedObject var api: ChopAPI
    @Binding var showAuth: Bool
    @Binding var authMode: Int

    var body: some View {
        FallbackWelcome(showAuth: $showAuth, authMode: $authMode)
    }
}

// MARK: - Landing page
//
// Reconstructed section-by-section from index.html. Section order there is:
//   nav → hero (+ phone) → marquee → transform → features(#feat)
//   → pricing(#price) → faq(#faq) → launch offer → footer
//
// The landing has its own palette and is dark-only — its tokens are NOT the
// app's tokens (landing --srf is #0f1117; the app's card is #161922), so it
// deliberately does not use ChopColor.

func lc(_ hex: UInt32, _ a: Double = 1) -> Color {
    Color(.sRGB,
          red: Double((hex >> 16) & 0xff) / 255,
          green: Double((hex >> 8) & 0xff) / 255,
          blue: Double(hex & 0xff) / 255,
          opacity: a)
}

enum LandColor {
    static let bg   = lc(0x08090c)
    static let srf  = lc(0x0f1117)
    static let srf2 = lc(0x141821)
    static let ln   = lc(0x1d2230)
    static let ln2  = lc(0x2a3142)
    static let tx   = lc(0xe9edf5)
    static let mu   = lc(0x8b93a5)
    static let blue = lc(0x3b82f6)
    static let vio  = lc(0x8b5cf6)
    static let grn  = lc(0x34d399)
    static let rose = lc(0xfb7185)
    static let note = lc(0x6d7688)
    static let bl2  = lc(0x7ea6ff)
}

let landGrad = LinearGradient(colors: [LandColor.blue, LandColor.vio],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
/// `em` on the landing: Georgia italic 500 with a 92deg #60a5fa→#a78bfa wash.
let landEmGrad = LinearGradient(colors: [lc(0x60a5fa), lc(0xa78bfa)],
                                startPoint: .leading, endPoint: .trailing)

// MARK: Chop mark
//
// The nav/footer logo, drawn from the same geometry as the inline <svg>:
// a 64×64 r16 tile, a 14.25r circle stroked 9.13 with dasharray 67.1/22.4
// rotated 52°, and a 3.8-tall band rotated -30° masked out of it.

struct ChopMarkView: View {
    var size: CGFloat = 26
    /// The footer uses a flat #3b82f6 tile rather than the gradient.
    var flat: Color? = nil

    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 64
            let tile = Path(roundedRect: CGRect(x: 0, y: 0, width: 64 * s, height: 64 * s),
                            cornerRadius: 16 * s)
            if let flat {
                ctx.fill(tile, with: .color(flat))
            } else {
                ctx.fill(tile, with: .linearGradient(
                    Gradient(colors: [LandColor.blue, LandColor.vio]),
                    startPoint: .zero, endPoint: CGPoint(x: 64 * s, y: 64 * s)))
            }
            // 67.1 of a 89.54 circumference = 269.7°, offset by the 52° rotation.
            var arc = Path()
            arc.addArc(center: CGPoint(x: 32 * s, y: 32 * s), radius: 14.25 * s,
                       startAngle: .degrees(52), endAngle: .degrees(321.7),
                       clockwise: false)
            ctx.drawLayer { l in
                l.stroke(arc, with: .color(.white),
                         style: StrokeStyle(lineWidth: 9.13 * s, lineCap: .round))
                let band = Path(CGRect(x: -12 * s, y: 30.2 * s, width: 89 * s, height: 3.8 * s))
                    .applying(CGAffineTransform(translationX: 32 * s, y: 32 * s)
                        .rotated(by: -30 * .pi / 180)
                        .translatedBy(x: -32 * s, y: -32 * s))
                l.blendMode = .destinationOut
                l.fill(band, with: .color(.black))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: Page background
//
// body: a 44px grid (the ≤640px size) in --ln, under two radial washes and a
// bottom fade, all of which sit above the grid and below the content.

struct LandBackdrop: View {
    var body: some View {
        Canvas { ctx, sz in
            let step: CGFloat = 44
            var g = Path()
            var x: CGFloat = -1
            while x < sz.width { g.move(to: CGPoint(x: x, y: 0)); g.addLine(to: CGPoint(x: x, y: sz.height)); x += step }
            var y: CGFloat = -1
            while y < sz.height { g.move(to: CGPoint(x: 0, y: y)); g.addLine(to: CGPoint(x: sz.width, y: y)); y += step }
            ctx.stroke(g, with: .color(LandColor.ln), lineWidth: 1)
        }
        .background(LandColor.bg)
        .overlay(alignment: .top) {
            GeometryReader { p in
                ZStack {
                    RadialGradient(colors: [LandColor.blue.opacity(0.16), .clear],
                                   center: UnitPoint(x: 0.5, y: -0.08),
                                   startRadius: 0, endRadius: p.size.width * 0.7)
                    RadialGradient(colors: [LandColor.vio.opacity(0.12), .clear],
                                   center: UnitPoint(x: 0.9, y: 0.2),
                                   startRadius: 0, endRadius: p.size.width * 0.5)
                }
                .frame(height: p.size.height)
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: Shared bits

/// .eyeb — 700 11px mono, .16em tracking, uppercase, --mu.
struct LandEyebrow: View {
    let text: String
    var color: Color = LandColor.mu
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .tracking(1.76)
            .foregroundStyle(color)
    }
}

/// h2 — clamp(28px,8.4vw,36px), 800, -.03em, with an optional trailing `em`.
struct LandH2: View {
    let plain: String
    var em: String? = nil
    var align: TextAlignment = .center
    var body: some View {
        let s: CGFloat = 32
        Group {
            if let em {
                (Text(plain).foregroundColor(LandColor.tx)
                 + Text(em).font(.custom("Georgia", size: s).italic()))
                .font(.system(size: s, weight: .bold))
                .tracking(-0.03 * s)
                .foregroundStyle(landEmGrad)
            } else {
                Text(plain)
                    .font(.system(size: s, weight: .bold))
                    .tracking(-0.03 * s)
                    .foregroundStyle(LandColor.tx)
            }
        }
        .multilineTextAlignment(align)
        .lineSpacing(1)
    }
}

/// .lead — 15px on mobile, --mu.
struct LandLead: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(LandColor.mu)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
    }
}

/// .card — the 1px --ln bordered panel with a top-lit white wash.
struct LandCard<C: View>: View {
    var border: Color = LandColor.ln
    var pad: CGFloat = 18
    @ViewBuilder var content: C
    var body: some View {
        content
            .padding(pad)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [.white.opacity(0.045), .white.opacity(0.012)],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(border, lineWidth: 1))
    }
}

/// .btn — 700 14.5px, r10, 12/22. .big is 15/30 at 16px r12.
enum LandBtn { case white, ghost, blue }

struct LandButton: View {
    let title: String
    var kind: LandBtn = .white
    var big = false
    var fill = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: big ? 16 : 14.5, weight: .bold))
                .foregroundStyle(fg)
                .frame(maxWidth: fill ? .infinity : nil)
                .padding(.vertical, big ? 15 : 12)
                .padding(.horizontal, big ? 30 : 22)
                .background(bg, in: RoundedRectangle(cornerRadius: big ? 12 : 10))
                .overlay(RoundedRectangle(cornerRadius: big ? 12 : 10)
                    .stroke(kind == .ghost ? LandColor.ln2 : .clear, lineWidth: 1))
                .shadow(color: kind == .blue ? LandColor.blue.opacity(0.35) : .clear,
                        radius: 14, y: 8)
        }
        .buttonStyle(.plain)
    }

    private var fg: Color {
        switch kind {
        case .white: return lc(0x08090c)
        case .ghost: return LandColor.tx
        case .blue:  return .white
        }
    }
    /// Must be a ShapeStyle, not a View — .background(_:in:) takes a style.
    private var bg: AnyShapeStyle {
        switch kind {
        case .white: return AnyShapeStyle(Color.white)
        case .ghost: return AnyShapeStyle(Color.white.opacity(0.02))
        case .blue:  return AnyShapeStyle(landGrad)
        }
    }
}

/// CSS `flex: n` in a row — proportional widths, which layoutPriority is not.
/// Every filmstrip on the page uses this.
struct LandFlexRow<C: View>: View {
    let flexes: [CGFloat]
    var spacing: CGFloat = 3
    @ViewBuilder var cell: (Int) -> C

    var body: some View {
        GeometryReader { g in
            let total = max(0.0001, flexes.reduce(0, +))
            let avail = max(0, g.size.width - spacing * CGFloat(max(0, flexes.count - 1)))
            HStack(spacing: spacing) {
                ForEach(flexes.indices, id: \.self) { i in
                    cell(i).frame(width: avail * flexes[i] / total)
                }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }
}

/// Wrapping run of inline text and .cut chips, for the raw-footage card.
struct LandFlow: Layout {
    var hSpacing: CGFloat = 4
    var vSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW, x > 0 { x = 0; y += rowH + vSpacing; rowH = 0 }
            x += s.width + hSpacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + vSpacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + hSpacing
            rowH = max(rowH, s.height)
        }
    }
}

// MARK: - The page

struct FallbackWelcome: View {
    @Binding var showAuth: Bool
    @Binding var authMode: Int

    @State private var offer: LandOfferState = .init()
    @Environment(\.openURL) private var openURL

    /// Every landing CTA points at /app/?signup=1 — natively, the create-account tab.
    private func signup() { authMode = 1; showAuth = true }
    private func signin() { authMode = 0; showAuth = true }

    var body: some View {
        ZStack(alignment: .top) {
            LandBackdrop()

            GeometryReader { screen in
                ScrollViewReader { sp in
                    let jump: (String) -> Void = { key in
                        withAnimation(.easeInOut) { sp.scrollTo(key, anchor: .top) }
                    }
                    ScrollView {
                        VStack(spacing: 0) {
                            LandHero(signup: signup, jump: jump)
                            LandMarquee().padding(.top, 46)
                            LandTransform().padding(.top, 64)
                            LandFeatures().padding(.top, 64).id("feat")
                            LandPricing(signup: signup).padding(.top, 64).id("price")
                            LandFAQ().padding(.top, 64).id("faq")
                            LandOffer(state: offer, signup: signup).padding(.top, 64)
                            LandFooter(signin: signin, jump: jump).padding(.top, 64)
                        }
                        .padding(.top, 84)   // clear the fixed nav bar
                        // pin everything to the phone's width — a wide child (the
                        // marquee) must never stretch the page past the screen
                        .frame(width: screen.size.width)
                        .clipped()
                    }
                    .overlay(alignment: .top) {
                        LandNav(signup: signup)
                    }
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .task { offer = await LandOfferState.load() }
    }
}

// MARK: nav
//
// At ≤640px .nl is display:none, so on a phone the bar is only the mark,
// the wordmark, and the white "Start chopping" pill.

struct LandNav: View {
    let signup: () -> Void
    var body: some View {
        HStack(spacing: 9) {
            ChopMarkView(size: 26)
            Text("Chop")
                .font(.system(size: 16.5, weight: .heavy))
                .foregroundStyle(LandColor.tx)
            Spacer(minLength: 8)
            LandButton(title: "Start chopping", kind: .white, action: signup)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial)
        .background(LandColor.bg.opacity(0.72))
        .overlay(alignment: .bottom) { Rectangle().fill(LandColor.ln).frame(height: 1) }
    }
}

// MARK: hero

struct LandHero: View {
    let signup: () -> Void
    let jump: (String) -> Void

    /// h1 is clamp(42px, 13vw, 56px); the phone is min(74vw, 252px). Both need
    /// the live width, but the hero must still size to its content, so the
    /// width is read from a zero-height probe rather than wrapping the stack.
    @State private var w: CGFloat = 393

    var body: some View {
        let h1 = min(56, max(42, w * 0.13))
        VStack(spacing: 0) {
            LandEyebrow(text: "Built for TikTok Shop affiliates")

            VStack(spacing: 0) {
                Text("Don't edit,")
                    .foregroundStyle(LandColor.tx)
                Text("just film.")
                    .font(.custom("Georgia", size: h1).italic())
                    .foregroundStyle(landEmGrad)
            }
            .font(.system(size: h1, weight: .heavy))
            .tracking(-0.035 * h1)
            .padding(.top, 20)

            Text("Chop cuts the dead air, filler words and messed-up takes out of your talking-head videos — automatically. Film once, review in seconds, post everywhere.")
                .font(.system(size: 16.5))
                .foregroundStyle(LandColor.mu)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 20)

            VStack(spacing: 10) {
                LandButton(title: "Chop your first video free", kind: .blue, big: true, fill: true, action: signup)
                LandButton(title: "See how it works", kind: .ghost, big: true, fill: true) { jump("feat") }
            }
            .padding(.top, 26)

            Text("3 free videos · no card · works on your phone")
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(LandColor.note)
                .padding(.top, 16)

            LandPhone(width: min(w * 0.74, 252))
                .padding(.top, 40)
                .background(alignment: .bottom) {
                    RadialGradient(colors: [LandColor.blue.opacity(0.22), .clear],
                                   center: .center, startRadius: 0, endRadius: 160)
                    .frame(height: 220).offset(y: 20).allowsHitTesting(false)
                }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .background(alignment: .top) {
            GeometryReader { p in
                Color.clear.onAppear { w = p.size.width }
                    .onChange(of: p.size.width) { nw in w = nw }
            }
            .frame(height: 0)
        }
    }
}

// MARK: the phone mockup

struct LandPhone: View {
    var width: CGFloat = 252

    var body: some View {
        let s = width / 252
        VStack(spacing: 0) {
            // .pv — the preview well
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    Group {
                        if UIImage(named: "HeroStill") != nil {
                            Image("HeroStill").resizable().scaledToFill()
                        } else {
                            lc(0x131824)
                        }
                    }
                    .frame(width: (width - 18 * s), height: (width - 18 * s) * 13 / 9)
                    .clipShape(RoundedRectangle(cornerRadius: 14 * s))

                    HStack(spacing: 0) {
                        Text("Raw")
                            .padding(.horizontal, 10 * s).padding(.vertical, 3 * s)
                            .foregroundStyle(.white.opacity(0.65))
                        Text("Edited")
                            .padding(.horizontal, 10 * s).padding(.vertical, 3 * s)
                            .foregroundStyle(lc(0x0b0d12))
                            .background(.white, in: RoundedRectangle(cornerRadius: 11 * s))
                    }
                    .font(.system(size: 9 * s, weight: .heavy))
                    .padding(2 * s)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13 * s))
                    .overlay(RoundedRectangle(cornerRadius: 13 * s)
                        .stroke(.white.opacity(0.16), lineWidth: 1))
                    .padding(.top, 9 * s)
                }
            }
            .padding(.horizontal, 9 * s).padding(.top, 9 * s).padding(.bottom, 7 * s)
            .background(lc(0x0d1016))

            // .pbar — transport
            HStack(spacing: 7 * s) {
                Text("▶").font(.system(size: 8 * s))
                    .foregroundStyle(.white)
                    .frame(width: 19 * s, height: 19 * s)
                    .background(LandColor.blue, in: Circle())
                Text("0:00")
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(lc(0x232936)).frame(height: 3 * s)
                        Circle().fill(.white).frame(width: 10 * s, height: 10 * s)
                            .offset(x: g.size.width * 0.22 - 5 * s)
                    }
                    .frame(height: g.size.height, alignment: .center)
                }
                .frame(height: 10 * s)
                Text("0:14")
            }
            .font(.system(size: 9.5 * s, weight: .bold))
            .foregroundStyle(LandColor.mu)
            .padding(.horizontal, 11 * s).padding(.vertical, 8 * s)
            .overlay(alignment: .top) { Rectangle().fill(lc(0x171c26)).frame(height: 1) }

            // .ptl — filmstrip with playhead
            ZStack(alignment: .leading) {
                LandFlexRow(flexes: [2, 0.6, 2.4, 2, 0.6, 2], spacing: 3 * s) { i in
                    stripCell(s: s, cut: i == 1 || i == 4, sel: i == 2)
                }
                GeometryReader { g in
                    Rectangle().fill(.white)
                        .frame(width: 2 * s)
                        .cornerRadius(1 * s)
                        .offset(x: g.size.width * 0.47)
                }
            }
            .frame(height: 36 * s)
            .padding(.horizontal, 11 * s).padding(.top, 10 * s).padding(.bottom, 8 * s)
            .background(lc(0x0d1016))

            // .ptools
            HStack(spacing: 5 * s) {
                tool("🎬", "Retakes", s: s, on: true)
                tool("✂", "Cuts", s: s)
                tool("📄", "Script", s: s)
                tool("T", "Text", s: s)
                tool("🖼", "Image", s: s)
                tool("💬", "Caps", s: s)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11 * s).padding(.top, 6 * s).padding(.bottom, 9 * s)
            .background(lc(0x0d1016))
            .clipped()

            // .pcard
            VStack(alignment: .leading, spacing: 5 * s) {
                HStack(spacing: 0) {
                    Text("Retake 1 · 88% match")
                        .font(.system(size: 8.5 * s, weight: .heavy))
                        .foregroundStyle(LandColor.tx)
                    Spacer(minLength: 4)
                    Text("Keeping Take 2")
                        .font(.system(size: 7 * s, weight: .heavy))
                        .foregroundStyle(LandColor.grn)
                        .padding(.horizontal, 7 * s).padding(.vertical, 2 * s)
                        .background(lc(0x0f2a20), in: RoundedRectangle(cornerRadius: 7 * s))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Take 1 · first attempt · 3.0s")
                        .foregroundStyle(LandColor.mu)
                    Text("\"Forty seven percent off this viral Medicube black…\"")
                        .strikethrough()
                        .foregroundStyle(lc(0x5b6472))
                }
                .font(.system(size: 8 * s))
            }
            .padding(.horizontal, 11 * s).padding(.vertical, 9 * s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(lc(0x12161f), in: RoundedRectangle(cornerRadius: 12 * s))
            .overlay(RoundedRectangle(cornerRadius: 12 * s).stroke(lc(0x1f2532), lineWidth: 1))
            .padding(.horizontal, 11 * s).padding(.bottom, 11 * s)
        }
        .background(lc(0x0b0d12))
        .clipShape(RoundedRectangle(cornerRadius: 28 * s))
        .padding(9 * s)
        .background(lc(0x0b0d12), in: RoundedRectangle(cornerRadius: 36 * s))
        .overlay(RoundedRectangle(cornerRadius: 36 * s).stroke(lc(0x262c3a), lineWidth: 1))
        .frame(width: width + 18 * s)
        .shadow(color: .black.opacity(0.7), radius: 45, y: 40)
    }

    @ViewBuilder
    private func stripCell(s: CGFloat, cut: Bool = false, sel: Bool = false) -> some View {
        let base = RoundedRectangle(cornerRadius: 7 * s)
        Group {
            if cut {
                base.fill(LandColor.rose.opacity(0.34))
            } else if sel {
                base.fill(LinearGradient(colors: [lc(0x2c3f66), lc(0x1c2740)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(base.stroke(lc(0x7aa2ff, 0.85), lineWidth: 2))
            } else {
                base.fill(LinearGradient(colors: [lc(0x333c50), lc(0x212734)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
    }

    private func tool(_ glyph: String, _ label: String, s: CGFloat, on: Bool = false) -> some View {
        VStack(spacing: 2 * s) {
            Text(glyph).font(.system(size: 12 * s))
            Text(label).font(.system(size: 6.5 * s, weight: .heavy))
        }
        .foregroundStyle(on ? lc(0x8fb1ff) : LandColor.mu)
        .frame(width: 41 * s, height: 41 * s)
        .background(on ? lc(0x16233c) : lc(0x151a24), in: RoundedRectangle(cornerRadius: 11 * s))
        .overlay(RoundedRectangle(cornerRadius: 11 * s)
            .stroke(on ? lc(0x2f5cb8) : lc(0x232936), lineWidth: 1))
    }
}

// MARK: marquee

struct LandMarquee: View {
    private let items: [(String, Color)] = [
        ("✂ um removed", LandColor.rose),
        ("✂ 2.4s silence cut", LandColor.rose),
        ("✓ retake matched", LandColor.grn),
        ("▶ 1080p export", LandColor.bl2),
        ("✂ uhh removed", LandColor.rose),
        ("✓ AI picked the better take", LandColor.grn),
        ("✂ 1.8s pause cut", LandColor.rose),
        ("▶ posted to TikTok", LandColor.bl2)
    ]
    @State private var w: CGFloat = 0

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let dx = w > 0 ? -CGFloat(t.truncatingRemainder(dividingBy: 28) / 28) * w : 0
            HStack(spacing: 0) {
                row.background(GeometryReader { g in
                    Color.clear.onAppear { w = g.size.width }
                })
                row
            }
            .offset(x: dx)
        }
        .frame(height: 40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .background(LandColor.srf.opacity(0.7))
        .overlay(alignment: .top) { Rectangle().fill(LandColor.ln).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(LandColor.ln).frame(height: 1) }
    }

    private var row: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                Text(items[i].0)
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(items[i].1)
                    .padding(.horizontal, 15)
                    .fixedSize()
            }
        }
    }
}

// MARK: the transform

struct LandTransform: View {
    var body: some View {
        VStack(spacing: 0) {
            LandEyebrow(text: "The transform")
            LandH2(plain: "Watch a video ", em: "chop itself.").padding(.top, 14)
            LandLead(text: "One upload in, one clean cut out — no timeline scrubbing, no scissor work.")
                .padding(.top, 14)

            VStack(spacing: 0) {
                LandCard {
                    VStack(alignment: .leading, spacing: 0) {
                        header("Raw footage", "1:42", tint: LandColor.tx)
                        rawBody.padding(.top, 13)
                    }
                }
                LandArrow().padding(.vertical, 14)
                LandCard(border: LandColor.blue.opacity(0.5)) {
                    VStack(alignment: .leading, spacing: 0) {
                        header("Chopped", "0:58", tint: LandColor.tx)
                        Text("This is the gadget everyone's talking about — it literally peels everything in seconds, and it's on offer right now, so grab it from my showcase.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(LandColor.tx)
                            .lineSpacing(6)
                            .padding(.top, 13)
                        HStack(spacing: 7) {
                            Text("✓ 44 seconds of dead weight removed")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(LandColor.grn)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(LandColor.grn.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                        .padding(.top, 13)
                        LandMini().padding(.top, 13)
                    }
                }
            }
            .padding(.top, 32)
        }
        .padding(.horizontal, 18)
    }

    private func header(_ l: String, _ r: String, tint: Color) -> some View {
        HStack(spacing: 0) {
            Text(l.uppercased())
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .tracking(1.47)
                .foregroundStyle(LandColor.mu)
            Spacer(minLength: 6)
            Text(r).font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
        }
    }

    /// .dl with inline .cut chips. Animation `cutaway`: plain → struck → faded.
    /// Tokens rather than a literal ViewBuilder run, which caps at 10 children.
    private enum RawTok {
        case word(String)
        case cut(String, Double)   // text, animation-delay
    }

    private static let rawTokens: [RawTok] = [
        .word("Okay so"),
        .cut("um", 0),
        .word("this is the gadget everyone's talking about"),
        .cut("··· 2.4s pause", 0.6),
        .word("it literally peels"),
        .cut("wait let me start again", 1.2),
        .word("it literally peels everything in seconds"),
        .cut("uhh", 1.8),
        .word("and it's on offer right now"),
        .cut("··· 1.8s pause", 2.4),
        .word("so grab it from my showcase.")
    ]

    private var rawBody: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            LandFlow(hSpacing: 4, vSpacing: 7) {
                ForEach(Array(Self.rawTokens.enumerated()), id: \.offset) { _, tok in
                    switch tok {
                    case .word(let w):        word(w)
                    case .cut(let c, let d):  chip(c, phase(t, d))
                    }
                }
            }
        }
    }

    private func word(_ s: String) -> some View {
        Text(s).font(.system(size: 13)).foregroundStyle(lc(0xb9c1d1))
    }

    /// 0 = plain, 1 = struck through, 2 = faded out.
    private func phase(_ t: TimeInterval, _ delay: Double) -> Int {
        let p = (t - delay).truncatingRemainder(dividingBy: 7)
        let x = p < 0 ? p + 7 : p
        let pct = x / 7 * 100
        if pct < 18 { return 0 }
        if pct < 60 { return 1 }
        if pct < 88 { return 2 }
        return 0
    }

    private func chip(_ s: String, _ ph: Int) -> some View {
        Text(s)
            .font(.system(size: 13, weight: .semibold))
            .strikethrough(ph == 1)
            .foregroundStyle(LandColor.rose)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(LandColor.rose.opacity(0.13), in: RoundedRectangle(cornerRadius: 5))
            .opacity(ph == 2 ? 0.12 : 1)
            .animation(.easeInOut(duration: 0.5), value: ph)
    }
}

/// .arrow — rotated 90° at ≤900px, pulsing 2.4s.
struct LandArrow: View {
    @State private var big = false
    var body: some View {
        Text("→")
            .font(.system(size: 17, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(landGrad, in: Circle())
            .rotationEffect(.degrees(90))
            .scaleEffect(big ? 1.09 : 1)
            // value-scoped repeatForever (same pattern as the hero) — the old
            // onAppear+withAnimation form dies silently on device when the
            // appear transaction merges with the screen transition.
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: big)
            .onAppear { big = true }
    }
}

/// .mini — the chopped card's condensed strip, rose gaps blinking 2.2s.
struct LandMini: View {
    @State private var dim = false
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<8, id: \.self) { i in
                let gap = (i == 1 || i == 4 || i == 6)
                RoundedRectangle(cornerRadius: 5)
                    .fill(gap ? AnyShapeStyle(LandColor.rose)
                              : AnyShapeStyle(LinearGradient(colors: [lc(0x333c50), lc(0x212734)],
                                                             startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .frame(maxWidth: gap ? 7 : .infinity)
                    .opacity(gap && dim ? 0.35 : 1)
            }
        }
        .frame(height: 24)
        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: dim)
        .onAppear { dim = true }
    }
}

// MARK: features (#feat)

struct LandFeatures: View {
    var body: some View {
        VStack(spacing: 0) {
            LandEyebrow(text: "What it does")
            VStack(spacing: 0) {
                Text("More videos posted.").foregroundStyle(LandColor.tx)
                Text("Zero evenings lost.")
                    .font(.custom("Georgia", size: 32).italic())
                    .foregroundStyle(landEmGrad)
            }
            .font(.system(size: 32, weight: .heavy))
            .tracking(-0.96)
            .multilineTextAlignment(.center)
            .padding(.top, 14)

            LandLead(text: "The three things that used to eat your editing time — handled.")
                .padding(.top, 14)

            VStack(spacing: 14) {
                LandFeat(n: "01 / ONE UPLOAD",
                         title: "Dead air, gone before you've made a brew",
                         copy: "Drop in raw footage and Chop strips every awkward pause and filler word automatically. You just watch the runtime fall.") {
                    VizTimeline()
                }
                LandFeat(n: "02 / THE CHOP DIFFERENCE",
                         title: "Retakes reviewed in seconds, not minutes",
                         copy: "Said the line three times? Chop lines every version up side by side and suggests the keeper. Nothing is ever cut without you.") {
                    VizRetakes()
                }
                LandFeat(n: "03 / QUICK EDIT",
                         title: "Director's cut, in your thumbs",
                         copy: "A TikTok-style timeline with frame-perfect control: pinch to zoom, split, trim and snap cuts to the exact frame. The final say is always yours.") {
                    VizQuickEdit()
                }
            }
            .padding(.top, 32)
        }
        .padding(.horizontal, 18)
    }
}

struct LandFeat<V: View>: View {
    let n: String
    let title: String
    let copy: String
    @ViewBuilder var viz: V

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(n)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.54)
                .foregroundStyle(LandColor.blue)
            Text(title)
                .font(.system(size: 19, weight: .heavy))
                .tracking(-0.19)
                .foregroundStyle(LandColor.tx)
                .fixedSize(horizontal: false, vertical: true)
            Text(copy)
                .font(.system(size: 14))
                .foregroundStyle(LandColor.mu)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            viz
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LandColor.srf, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(LandColor.ln, lineWidth: 1))
    }
}

/// .viz shell — #0b0d12, --ln, r14, min-height 132.
struct VizBox<C: View>: View {
    @ViewBuilder var content: C
    var body: some View {
        VStack(spacing: 9) { content }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 132)
            .background(lc(0x0b0d12), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(LandColor.ln, lineWidth: 1))
    }
}

private func vizLabel(_ l: String, _ r: String? = nil, rGreen: Bool = true) -> some View {
    HStack(spacing: 0) {
        Text(l)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1)
            .foregroundStyle(LandColor.mu)
        if let r {
            Spacer(minLength: 6)
            Text(r)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(rGreen ? LandColor.grn : LandColor.mu)
        }
    }
}

struct VizTimeline: View {
    @State private var collapsed = false
    var body: some View {
        VizBox {
            vizLabel("YOUR TIMELINE", "−38%")
            LandFlexRow(flexes: (0..<7).map { (i: Int) -> CGFloat in i % 2 == 1 ? (collapsed ? 0.02 : 2) : 3 }, spacing: 4) { i in
                let gap = i % 2 == 1
                RoundedRectangle(cornerRadius: 7)
                    .fill(gap ? AnyShapeStyle(LandColor.rose.opacity(0.3))
                              : AnyShapeStyle(LinearGradient(colors: [lc(0x333c50), lc(0x212734)],
                                                             startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .opacity(gap && collapsed ? 0.5 : 1)
            }
            .frame(height: 40)
            // the plain .animation(value:) here OVERRODE the repeatForever from
            // onAppear — the strip collapsed once and froze. The repeat now
            // lives in the modifier itself.
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: collapsed)
            vizLabel("1:42", "0:58", rGreen: false)
        }
        .onAppear { collapsed = true }
    }
}

struct VizRetakes: View {
    @State private var lit = false
    var body: some View {
        VizBox {
            vizLabel("RETAKE 1 · 96% MATCH")
            take("\"It's the pink numbers. How many…\"", len: "3.4s", pick: false)
            take("\"It's the pink numbers.\"", len: "1.8s", pick: true)
        }
        .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: lit)
        .onAppear { lit = true }
    }

    private func take(_ s: String, len: String, pick: Bool) -> some View {
        HStack(spacing: 9) {
            Text(s).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(lc(0xc3cbdb)).lineLimit(1)
            if pick {
                Text("AI PICK")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(lc(0x04241a))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(LandColor.grn, in: RoundedRectangle(cornerRadius: 7))
            }
            Spacer(minLength: 4)
            Text(len).font(.system(size: 10.5)).foregroundStyle(LandColor.mu)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(pick && lit ? LandColor.blue.opacity(0.16) : lc(0x141922),
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(pick ? LandColor.blue : lc(0x232a38), lineWidth: 1))
    }
}

struct VizQuickEdit: View {
    @State private var tight = false
    var body: some View {
        VizBox {
            vizLabel("QUICK EDIT", "frame-perfect")
            GeometryReader { g in
                let W = g.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LinearGradient(colors: [lc(0x333c50), lc(0x212734)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(height: 48)
                    Rectangle().fill(.white).frame(width: 3, height: 68).cornerRadius(3)
                        .offset(x: W * 0.52)
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white, lineWidth: 3)
                        .frame(width: W * (tight ? 0.30 : 0.46), height: 58)
                        .overlay(alignment: .leading) { handle("‹") }
                        .overlay(alignment: .trailing) { handle("›") }
                        .offset(x: W * (tight ? 0.26 : 0.16))
                }
                .frame(height: g.size.height, alignment: .center)
            }
            .frame(height: 58)
            // same override bug as VizTimeline — one-shot .animation(value:)
            // beat the repeatForever, so the trim demo ran once and froze.
            .animation(.easeInOut(duration: 2.25).repeatForever(autoreverses: true), value: tight)
            vizLabel("pinch · split · trim · snap")
        }
        .onAppear { tight = true }
    }

    private func handle(_ g: String) -> some View {
        Text(g).font(.system(size: 10, weight: .heavy))
            .foregroundStyle(lc(0x111111))
            .frame(width: 14, height: 58)
            .background(.white, in: RoundedRectangle(cornerRadius: 8))
            .offset(x: g == "‹" ? -3 : 3)
    }
}

// MARK: pricing (#price)

struct LandPricing: View {
    let signup: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            LandEyebrow(text: "Pricing")
            LandH2(plain: "One credit. ", em: "One video.").padding(.top, 14)
            LandLead(text: "No subscriptions, no tiers to decode. Buy credits, chop videos. The more you buy, the cheaper each one gets.")
                .padding(.top, 14)

            VStack(spacing: 16) {
                LandPrice(name: "STARTER", amount: "£1", unit: "/video", per: "under 50 credits",
                          bullets: ["Everything included", "1080p exports", "Works on your phone"],
                          mid: false, signup: signup)
                LandPrice(name: "CREATOR", amount: "90p", unit: "/video", per: "50+ credits",
                          bullets: ["Everything included", "Bulk upload queue", "Cross-device sync"],
                          mid: true, signup: signup)
                LandPrice(name: "PRO", amount: "85p", unit: "/video", per: "100+ credits · drops to 70p",
                          bullets: ["Everything included", "Best rate per video", "For daily posters"],
                          mid: false, signup: signup)
            }
            .padding(.top, 32)

            (Text("Every new account starts with ")
             + Text("3 free videos").foregroundColor(LandColor.tx).bold()
             + Text(". Credits never expire."))
                .font(.system(size: 13))
                .foregroundStyle(LandColor.mu)
                .multilineTextAlignment(.center)
                .padding(.top, 22)
        }
        .padding(.horizontal, 18)
    }
}

struct LandPrice: View {
    let name: String
    let amount: String
    let unit: String
    let per: String
    let bullets: [String]
    let mid: Bool
    let signup: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(name)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.54)
                .foregroundStyle(LandColor.mu)
            (Text(amount).font(.system(size: 36, weight: .heavy))
             + Text(unit).font(.system(size: 14, weight: .bold)).foregroundColor(LandColor.mu))
                .tracking(-1.08)
                .foregroundStyle(LandColor.tx)
                .padding(.top, 9)
            Text(per)
                .font(.system(size: 12.5))
                .foregroundStyle(LandColor.mu)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
            VStack(spacing: 3) {
                ForEach(bullets, id: \.self) { b in
                    Text(b).font(.system(size: 13)).foregroundStyle(LandColor.mu)
                }
            }
            .padding(.vertical, 16)
            LandButton(title: "Get credits", kind: mid ? .blue : .ghost, fill: true, action: signup)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(mid ? AnyShapeStyle(LinearGradient(colors: [LandColor.blue.opacity(0.09), LandColor.srf],
                                                         startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(LandColor.srf))
        }
        .overlay(RoundedRectangle(cornerRadius: 18)
            .stroke(mid ? LandColor.blue.opacity(0.6) : LandColor.ln, lineWidth: 1))
        .overlay(alignment: .top) {
            if mid {
                Text("MOST POPULAR")
                    .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                    .tracking(1.14)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(landGrad, in: RoundedRectangle(cornerRadius: 9))
                    .offset(y: -10)
            }
        }
        .padding(.top, mid ? 10 : 0)
    }
}

// MARK: faq (#faq)

struct LandFAQ: View {
    private let qs: [(String, String)] = [
        ("Will it mess with my cuts?",
         "No — nothing is ever removed without you. Retakes are always shown side by side for you to pick, every cut is visible on the timeline, and one tap restores anything."),
        ("Does it work on my phone?",
         "Yes — Chop is built phone-first. Film, upload, review and export straight from the TikTok-style editor, then save direct to your camera roll."),
        ("What footage does it work best on?",
         "Talking-head content — product reviews, hauls, storytimes, UGC. If you're speaking to camera, Chop understands it."),
        ("How long does it take?",
         "About 15 seconds of processing per minute of footage. Most creators go from raw file to posted video in under two minutes.")
    ]
    @State private var open: Set<Int> = []

    var body: some View {
        VStack(spacing: 0) {
            LandH2(plain: "Quick ", em: "questions.")
            VStack(spacing: 10) {
                ForEach(qs.indices, id: \.self) { i in
                    let isOpen = open.contains(i)
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if isOpen { open.remove(i) } else { open.insert(i) }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(qs[i].0)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(LandColor.tx)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 6)
                                Text(isOpen ? "−" : "+")
                                    .font(.system(size: 16))
                                    .foregroundStyle(LandColor.mu)
                            }
                        }
                        .buttonStyle(.plain)
                        if isOpen {
                            Text(qs[i].1)
                                .font(.system(size: 14))
                                .foregroundStyle(LandColor.mu)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 11)
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LandColor.srf, in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(LandColor.ln, lineWidth: 1))
                }
            }
            .padding(.top, 36)
        }
        .padding(.horizontal, 18)
    }
}

// MARK: launch offer
//
// The web page reads chop_offer straight from the public REST endpoint and,
// once the cap is hit, rewrites the heading, body and CTA.

struct LandOfferState {
    var claimed = 0
    var cap = 10
    var defaultCredits = 3
    var loaded = false
    var gone: Bool { loaded && claimed >= cap }

    static func load() async -> LandOfferState {
        var s = LandOfferState()
        let url = URL(string: "\(SB_URL)/rest/v1/chop_offer?select=claimed,cap,offer_credits,default_credits&id=eq.1")!
        var r = URLRequest(url: url)
        r.setValue(SB_ANON, forHTTPHeaderField: "apikey")
        guard let (d, resp) = try? await URLSession.shared.data(for: r),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let rows = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]],
              let row = rows.first else { return s }
        s.claimed = row["claimed"] as? Int ?? 0
        s.cap = row["cap"] as? Int ?? 10
        s.defaultCredits = row["default_credits"] as? Int ?? 3
        s.loaded = true
        return s
    }
}

struct LandOffer: View {
    let state: LandOfferState
    let signup: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            LandEyebrow(text: "Launch offer", color: LandColor.bl2)

            if state.gone {
                VStack(spacing: 0) {
                    Text("Every new account gets").foregroundStyle(LandColor.tx)
                    Text("\(state.defaultCredits) free videos.")
                        .font(.custom("Georgia", size: 32).italic())
                        .foregroundStyle(landEmGrad)
                }
                .font(.system(size: 32, weight: .heavy)).tracking(-0.96)
                .multilineTextAlignment(.center).padding(.top, 14)

                Text("The launch credits are gone, but your first \(state.defaultCredits) videos are still on us. No card, no code — just sign up and start chopping.")
                    .font(.system(size: 15.5)).foregroundStyle(LandColor.mu)
                    .multilineTextAlignment(.center).lineSpacing(3)
                    .padding(.top, 14).padding(.bottom, 24)

                LandButton(title: "Start chopping free", kind: .white, big: true, fill: true, action: signup)
            } else {
                VStack(spacing: 0) {
                    Text("First \(state.cap) affiliates get").foregroundStyle(LandColor.tx)
                    Text("\(state.cap) free credits.")
                        .font(.custom("Georgia", size: 32).italic())
                        .foregroundStyle(landEmGrad)
                }
                .font(.system(size: 32, weight: .heavy)).tracking(-0.96)
                .multilineTextAlignment(.center).padding(.top, 14)

                Text("That's \(state.cap) videos chopped, on us. Sign up and the credits land in your account automatically — no code to enter.")
                    .font(.system(size: 15.5)).foregroundStyle(LandColor.mu)
                    .multilineTextAlignment(.center).lineSpacing(3)
                    .padding(.top, 14).padding(.bottom, 24)

                LandButton(title: "Claim my \(state.cap) free credits", kind: .white, big: true, fill: true, action: signup)
            }

            HStack(spacing: 10) {
                Text(state.gone ? "all \(state.cap) claimed" : "\(min(state.claimed, state.cap)) / \(state.cap) claimed")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(LandColor.tx)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.1))
                        Capsule().fill(landGrad)
                            .frame(width: g.size.width * pct)
                    }
                }
                .frame(width: 130, height: 6)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 15).padding(.vertical, 8)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(LandColor.ln2, lineWidth: 1))
            .padding(.top, 18)
        }
        .padding(.horizontal, 20).padding(.vertical, 36)
        .background(
            LinearGradient(colors: [LandColor.blue.opacity(0.13), LandColor.vio.opacity(0.07)],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(LandColor.blue.opacity(0.4), lineWidth: 1))
        .padding(.horizontal, 18)
    }

    private var pct: CGFloat {
        guard state.cap > 0 else { return 0 }
        return min(1, CGFloat(state.claimed) / CGFloat(state.cap))
    }
}

// MARK: footer

struct LandFooter: View {
    let signin: () -> Void
    let jump: (String) -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ChopMarkView(size: 19, flat: LandColor.blue)
                Text("Chop").font(.system(size: 13, weight: .heavy)).foregroundStyle(LandColor.tx)
            }
            Text("© 2026 ATS Collective Ltd")
            HStack(spacing: 14) {
                Button("Sign in", action: signin)
                Button("Pricing") { jump("price") }
                Button("Privacy") { openURL(URL(string: "https://chopedit.com/privacy.html")!) }
                Button("Support") { openURL(URL(string: "mailto:hello@chopedit.com")!) }
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 13))
        .foregroundStyle(LandColor.mu)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18).padding(.vertical, 32)
        .overlay(alignment: .top) { Rectangle().fill(LandColor.ln).frame(height: 1) }
    }
}



// MARK: - Consistency
//
// The web dashboard's activity block: a 6-month heatmap of edit days, current
// and longest streak, and 30-day activity. Derived from statusAt on each job.

struct ChopActivity: View {
    let days: [String: Int]
    let current: Int
    let longest: Int
    let active30: Int

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private var weeks: [[Date]] {
        var out: [[Date]] = []
        let cal = Calendar.current
        var start = cal.date(byAdding: .day, value: -181, to: Date()) ?? Date()
        // wind back to the Sunday so columns line up like the web grid
        while cal.component(.weekday, from: start) != 1 {
            start = cal.date(byAdding: .day, value: -1, to: start) ?? start
        }
        var week: [Date] = []
        var d = start
        while d <= Date() {
            week.append(d)
            if week.count == 7 { out.append(week); week = [] }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        if !week.isEmpty { out.append(week) }
        return out
    }

    private func level(_ d: Date) -> Int { min(4, days[Self.fmt.string(from: d)] ?? 0) }

    private func shade(_ n: Int) -> Color {
        switch n {
        case 0: return ChopColor.soft2
        case 1: return ChopColor.blue.opacity(0.30)
        case 2: return ChopColor.blue.opacity(0.55)
        case 3: return ChopColor.blue.opacity(0.78)
        default: return ChopColor.blue
        }
    }

    var body: some View {
        ChopCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Activity").font(ChopFont.h2(17)).foregroundStyle(ChopColor.ink)

                HStack(spacing: 22) {
                    stat("\(current)", "Current streak")
                    stat("\(longest)", "Longest streak")

                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 3) {
                        ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                            VStack(spacing: 3) {
                                ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(shade(level(day)))
                                        .frame(width: 9, height: 9)
                                }
                            }
                        }
                    }
                }
                .defaultScrollAnchor(.trailing)

                HStack(spacing: 5) {
                    Text("Last 6 months").font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(ChopColor.muted)
                    Spacer()
                    Text("Less").font(.system(size: 10)).foregroundStyle(ChopColor.muted)
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2).fill(shade(i))
                            .frame(width: 9, height: 9)
                    }
                    Text("More").font(.system(size: 10)).foregroundStyle(ChopColor.muted)
                }
            }
        }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.system(size: 19, weight: .bold)).foregroundStyle(ChopColor.ink)
            Text(l).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(ChopColor.muted)
        }
    }
}

// MARK: - Cut Lab preview
//
// The same 20-second demo the web app uses, so the before/after bar reacts to
// the sliders exactly as it does on the web.

struct LabSeg { let s: Double; let e: Double; let k: String; var soft = false }

let LP_SEGS: [LabSeg] = [
    LabSeg(s: 0.0,  e: 0.5,  k: "sil"),  LabSeg(s: 0.5,  e: 3.2,  k: "sp"),
    LabSeg(s: 3.2,  e: 3.7,  k: "fill"), LabSeg(s: 3.7,  e: 6.4,  k: "sp"),
    LabSeg(s: 6.4,  e: 7.9,  k: "sil"),  LabSeg(s: 7.9,  e: 10.6, k: "sp"),
    LabSeg(s: 10.6, e: 11.0, k: "fill", soft: true), LabSeg(s: 11.0, e: 13.8, k: "sp"),
    LabSeg(s: 13.8, e: 14.9, k: "sil"),  LabSeg(s: 14.9, e: 17.6, k: "sp"),
    LabSeg(s: 17.6, e: 18.1, k: "fill"), LabSeg(s: 18.1, e: 19.5, k: "sp"),
    LabSeg(s: 19.5, e: 20.0, k: "sil")
]
let LP_DUR = 20.0

struct ChopLabPreview: View {
    let settings: ChopSettings

    private func isCut(_ g: LabSeg) -> Bool {
        if g.k == "sil"  { return (g.e - g.s) >= settings.minSil }
        if g.k == "fill" { return settings.fillers && (!g.soft || settings.soft) }
        return false
    }
    private var keptDur: Double {
        LP_SEGS.reduce(0) { $0 + (isCut($1) ? 0 : $1.e - $1.s) }
    }
    private var cutCount: Int { LP_SEGS.filter(isCut).count }
    private var pct: Int { Int(((LP_DUR - keptDur) / LP_DUR) * 100) }

    private func clock(_ t: Double) -> String {
        String(format: "%d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
    }

    var body: some View {
        ChopCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("See your style in action")
                    .font(ChopFont.h2(16)).foregroundStyle(ChopColor.ink)
                Text("Our demo clip, chopped live with your settings.")
                    .font(.system(size: 11.5)).foregroundStyle(ChopColor.muted)

                row("Original", LP_DUR, cut: false)
                row("Chopped", keptDur, cut: true)

                HStack(spacing: 10) {
                    ChopBadge(text: "\(cutCount) CUTS")
                    ChopBadge(text: "\(pct)% SHORTER",
                              tint: ChopColor.green, soft: ChopColor.greenSoft)
                    Spacer()
                    Text("saving \(String(format: "%.1f", LP_DUR - keptDur))s of dead air")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(ChopColor.muted)
                }
            }
        }
    }

    private func row(_ label: String, _ dur: Double, cut: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.system(size: 11.5, weight: .heavy))
                    .foregroundStyle(ChopColor.muted)
                Spacer()
                Text(clock(dur)).font(.system(size: 11.5, weight: .heavy).monospacedDigit())
                    .foregroundStyle(cut ? ChopColor.green : ChopColor.ink)
            }
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(Array(LP_SEGS.enumerated()), id: \.offset) { _, g in
                        let w = geo.size.width * (g.e - g.s) / LP_DUR
                        Rectangle()
                            .fill(colour(for: g, cut: cut))
                            .frame(width: max(1, w - 1))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .frame(height: 24)
        }
    }

    private func colour(for g: LabSeg, cut: Bool) -> Color {
        if cut && isCut(g) { return ChopColor.soft2 }
        switch g.k {
        case "sp":   return ChopColor.blue.opacity(cut ? 0.9 : 0.75)
        case "fill": return ChopColor.violet.opacity(0.7)
        default:     return ChopColor.line
        }
    }
}

/// The web dashboard's consistency ring: a 0-99 score with a tier label,
/// 30-day activity and peak day. Same formula as renderHomeStats().
struct ChopRing: View {
    let edits: Int
    let active30: Int
    let streak: Int
    let peakDay: String

    private var pct: Int {
        guard edits > 0 else { return 0 }
        return min(99, 35 + active30 * 2 + min(20, edits) + streak * 2)
    }
    private var tier: String {
        switch pct {
        case 0:      return "Getting started"
        case ..<45:  return "Warming up"
        case ..<65:  return "Building a habit"
        case ..<85:  return "Consistent"
        default:     return "Machine"
        }
    }

    var body: some View {
        ChopCard {
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(ChopColor.soft2, lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: CGFloat(pct) / 100)
                        .stroke(chopGradient,
                                style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(pct)%").font(.system(size: 17, weight: .bold))
                        .foregroundStyle(ChopColor.ink)
                }
                .frame(width: 84, height: 84)

                VStack(alignment: .leading, spacing: 5) {
                    Text(tier).font(.system(size: 15.5, weight: .heavy))
                        .foregroundStyle(ChopColor.ink)
                    Text("Active \(active30) / 30 days · \(streak)-day streak")
                        .font(.system(size: 11.5)).foregroundStyle(ChopColor.muted)
                    Text("Peak day: \(peakDay)")
                        .font(.system(size: 11.5)).foregroundStyle(ChopColor.muted)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
