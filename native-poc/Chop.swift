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

// CREAM EDITORIAL rebrand (from the onboarding mockups): light mode is warm
// paper + ink with TikTok pink/cyan accents — purple is gone. Dark mode keeps
// the midnight palette (and the editor always runs dark).
enum ChopColor {
    static let bg         = dyn(0xf7f3ea, 0x0e1014)   // warm paper
    static let card       = dyn(0xffffff, 0x161922)
    static let ink        = dyn(0x141821, 0xe9edf5)
    static let muted      = dyn(0x6d7484, 0x8a93a5)
    static let line       = dyn(0xe7dfcd, 0x262c38)   // warm hairline
    static let blue       = dyn(0x1a6dff, 0x3b82ff)
    static let blueDk     = dyn(0x0d4fc4, 0xa5c0ff)
    static let blueSoft   = dyn(0xe9f0ff, 0x1b2a4a)
    static let violet     = dyn(0xfe2c55, 0xff5c7d)   // TikTok pink (ex-violet)
    static let violetSoft = dyn(0xffe4ea, 0x3a1d26)
    static let green      = dyn(0x0e9f6e, 0x3ad39c)
    static let greenSoft  = dyn(0xe0f5ec, 0x12291f)
    static let rose       = dyn(0xdc2637, 0xf2596b)
    static let roseSoft   = dyn(0xffe7e4, 0x331a1f)
    static let amber      = dyn(0xb45309, 0xf0b35c)
    static let amberSoft  = dyn(0xfdf0d7, 0x2c2212)
    static let soft2      = dyn(0xefe9db, 0x20242f)   // paper-2
    static let hover      = dyn(0xf2ecdd, 0x20242f)
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

/// The chopped wordmark from the onboarding — two halves of "Chop" offset
/// along a diagonal cut. No icon, pure type.
struct ChopWordmark: View {
    var size: CGFloat = 24
    var color: Color = ChopColor.ink

    var body: some View {
        let base = Text("Chop")
            .font(.system(size: size, weight: .black))
            .kerning(-size * 0.05)
            .foregroundStyle(color)
        return ZStack {
            base
                .clipShape(CutHalf(left: true))
                .offset(x: -size * 0.055, y: -size * 0.04)
            base
                .clipShape(CutHalf(left: false))
                .offset(x: size * 0.055, y: size * 0.04)
        }
        .fixedSize()
        .accessibilityLabel("Chop")
    }

    private struct CutHalf: Shape {
        let left: Bool
        func path(in r: CGRect) -> Path {
            var p = Path()
            if left {
                p.move(to: CGPoint(x: r.minX, y: r.minY))
                p.addLine(to: CGPoint(x: r.minX + r.width * 0.58, y: r.minY))
                p.addLine(to: CGPoint(x: r.minX + r.width * 0.42, y: r.maxY))
                p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            } else {
                p.move(to: CGPoint(x: r.minX + r.width * 0.58, y: r.minY))
                p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
                p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
                p.addLine(to: CGPoint(x: r.minX + r.width * 0.42, y: r.maxY))
            }
            p.closeSubpath()
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
    private var task: Task<Void, Never>?
    func show(_ m: String) {
        message = m
        task?.cancel()
        task = Task { try? await Task.sleep(nanoseconds: 2_600_000_000); message = nil }
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
        }
        .animation(.spring(duration: 0.28), value: toasts.message)
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
        rawDur = max(job.rawSec, segments.last?.end ?? 0)
    }

    func isCut(_ sg: ChopSegment) -> Bool {
        if let m = sg.manual { return m }
        if let take = sg.retake, let p = sg.pair {
            let choice = (p < pairs.count) ? pairs[p].choice : nil
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
        guard !manualCuts.isEmpty else { return padded }
        var all = padded + manualCuts.map { ChopClip(start: max(0, $0.start), end: min(rawDur, $0.end)) }
        all.sort { $0.start < $1.start }
        var out: [ChopClip] = []
        for iv in all {
            if var last = out.last, iv.start <= last.end + 0.001 {
                last.end = max(last.end, iv.end)
                out[out.count - 1] = last
            } else { out.append(iv) }
        }
        return out.filter { $0.end - $0.start > 0.005 }
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
    @Published var profileName = ""
    @Published var profileTiktok = ""
    @Published var profileAvatar = ""

    private(set) var accessToken = ""
    private(set) var userId = ""

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
            accessToken = token
            userId = uid
            signedIn = true
            await loadProfile()
            await loadJobs()
        } catch {
            self.error = "Couldn't reach the sign-in service — refresh to retry."
        }
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
        } catch {
            self.error = error.localizedDescription
        }
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

    func startProcessing(key: String) async -> String? {
        guard let o = await edge(["action": "process", "key": key]) else { return nil }
        return o["jobId"] as? String
    }

    /// Poll until Deepgram + retake matching are done. Returns the payload.
    func awaitAnalysis(jobId: String) async -> [String: Any]? {
        for _ in 0..<240 {
            guard let s = await edge(["action": "status", "jobId": jobId]) else { return nil }
            let st = s["status"] as? String
            if st == "done" { return s }
            if st == "error" { return nil }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        return nil
    }

    /// Write the job into chop_jobs so the web app sees it too.
    func saveJob(name: String, payload: [String: Any], rawSec: Double, videoKey: String?) async {
        var data: [String: Any] = [
            "status": "review",
            "payload": payload,
            "rawSec": rawSec,
            "editedSec": 0,
            "statusAt": Int(Date().timeIntervalSince1970 * 1000)
        ]
        if let videoKey = videoKey { data["videoKey"] = videoKey }

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
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let row = rows.first else { return }
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
        guard let url = URL(string: "\(SB_URL)/auth/v1/recover") else { return false }
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

    /// Move a job to "Ready to export", same as the web app's green Done button.
    func setStatus(_ job: ChopJob, to status: String) async {
        var d = job.data
        d["status"] = status
        d["statusAt"] = Int(Date().timeIntervalSince1970 * 1000)
        guard let url = URL(string: "\(SB_URL)/rest/v1/chop_jobs?user_id=eq.\(userId)&name=eq.\(job.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? job.name)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue(SB_ANON, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["data": d, "ts": Int(Date().timeIntervalSince1970 * 1000)])
        _ = try? await URLSession.shared.data(for: req)
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

    func signOut() {
        accessToken = ""; userId = ""; signedIn = false; jobs = []; credits = 0
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let img = thumb {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [Color(red: 0.24, green: 0.27, blue: 0.33),
                                            Color(red: 0.13, green: 0.14, blue: 0.17)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(9.0/13.0, contentMode: .fill)
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
/// Cream editorial backdrop: a warm breathing sun + faint paper rule lines
/// (the onboarding's world). In dark mode the sun cools to a blue glow.
struct AuthBackdrop: View {
    @State private var drift = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            ChopColor.bg.ignoresSafeArea()
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    // the sun
                    Circle()
                        .fill(scheme == .dark ? ChopColor.blue.opacity(0.18)
                                              : Color(red: 1, green: 0.913, blue: 0.768).opacity(0.85))
                        .frame(width: w * 1.45)
                        .blur(radius: 60)
                        .offset(y: drift ? -h * 0.44 : -h * 0.36)
                        .scaleEffect(drift ? 1.1 : 1)
                    // a soft second warmth low on the page
                    Circle()
                        .fill(scheme == .dark ? ChopColor.blue.opacity(0.08)
                                              : Color(red: 1, green: 0.93, blue: 0.82).opacity(0.5))
                        .frame(width: w * 0.9)
                        .blur(radius: 70)
                        .offset(x: drift ? w * 0.2 : -w * 0.1, y: h * 0.42)
                }
                .animation(.easeInOut(duration: 9).repeatForever(autoreverses: true), value: drift)

                // paper rule lines
                if scheme != .dark {
                    VStack(spacing: 25) {
                        ForEach(0..<40, id: \.self) { _ in
                            Rectangle().fill(ChopColor.ink.opacity(0.045)).frame(height: 1)
                        }
                    }
                }
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
    @State private var showImport = false
    @State private var showSettings = false
    @State private var showBilling = false
    @State private var demoJob: ChopJob? = nil   // -screen editor design preview

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
    @State private var theme = ChopTheme.current

    var body: some View {
        Group {
            if api.signedIn {
                app
            } else {
                // straight to Sign in — the marketing landing lives on the web.
                // Anyone opening the app came from there and wants an account.
                NavigationStack { signIn.background(Color.chopBg) }
            }
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
                case "auth":       showAuth = true; authMode = 0
                case "auth-up":    showAuth = true; authMode = 1
                case "auth-reset": showAuth = true; authStage = 1
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
                .sheet(isPresented: $showImport) { ImportSheet(api: api) }
                .sheet(isPresented: $showSettings) { ChopSettingsView(api: api) { theme = $0 } }
                .sheet(isPresented: $showBilling) { ChopBillingView(api: api) }
                .fullScreenCover(item: $demoJob) { j in
                    NavigationStack { ChopPlayerScreen(job: j, api: api) }
                }
                .sheet(isPresented: $showOOC) { OutOfCreditsSheet() }
                .onChange(of: api.credits) { _, c in if c <= 0 && api.signedIn { showOOC = true } }
                .refreshable { await api.loadJobs() }
            }
            if !api.editorOpen {   // web: no Dashboard/Queue/Cut Lab pill inside the editor
                ChopGlassNav(tab: $tab, queueCount: reviewCount)
            }
        }
    }

    private var signIn: some View {
        ZStack {
            AuthBackdrop()   // slow-drifting brand glow — the page breathes
            signInContent
        }
    }

    private var signInContent: some View {
        ScrollView {
            VStack(spacing: 16) {

                // ---- the auth card (web .authform: card bg, 1px line, r20, 26×24) ----
                VStack(spacing: 0) {

                    ChopWordmark(size: 40)
                        .scaleEffect(authGlow ? 1.03 : 1)
                        .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true), value: authGlow)
                        .padding(.bottom, 18)

                    Text(authTitle)
                        .font(ChopFont.serif(24))
                        .foregroundStyle(ChopColor.ink)
                        .padding(.bottom, 4)
                    Text(authSub)
                        .font(.system(size: 13.5))
                        .foregroundStyle(ChopColor.muted)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 22)

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
                            ChopField(label: "Email", placeholder: "you@example.com", text: $api.email)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.emailAddress)
                        }
                        if authStage == 0 {
                            ChopField(label: "Password", placeholder: "••••••••", secure: true, text: $api.password)
                        }
                        if authStage == 2 {
                            ChopField(label: "New password", placeholder: "••••••••", secure: true, text: $newPassword)
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

            HStack(spacing: 5) {
                Image(systemName: "bolt.fill").font(.system(size: 11, weight: .bold))
                Text("\(api.credits) credits").font(.system(size: 14, weight: .heavy))
            }
            .foregroundStyle(ChopColor.blue)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(ChopColor.blueSoft, in: Capsule())

            Button { showSettings = true } label: {
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
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
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

    private func statCard(_ value: String, _ label: String, sub: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(ChopFont.cardBig).foregroundStyle(ChopColor.blue)
            Text(label).font(ChopFont.cardLabel).foregroundStyle(ChopColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let sub { Text(sub).font(.caption2).foregroundStyle(Color.chopMuted) }
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .padding(16)
        .background(Color.chopPanel)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.chopLine, lineWidth: 1))
    }

    // ---- numbers, derived from the jobs themselves ----
    private var savedSeconds: Double {
        api.jobs.reduce(0.0) { $0 + max(0, $1.rawSec - $1.editedSec) }
    }
    private var savedLabel: String {
        let m = Int(savedSeconds / 60)
        return m >= 60 ? String(format: "%.1fh", savedSeconds / 3600) : "\(m)m"
    }
    /// Same basis as the web dashboard: manual editing valued at $30/hour.
    private var moneyLabel: String { "$\(Int(savedSeconds / 3600 * 30))" }

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
                    .font(ChopFont.serif(28))
                    .fixedSize(horizontal: false, vertical: true)
                Text("An overview of how your chopping is going.")
                    .font(.subheadline).foregroundStyle(Color.chopMuted)
                    .padding(.bottom, 4)

                // 2x2, hero first — same arrangement as the web dashboard
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(savedLabel).font(ChopFont.cardBig)
                        Text("Time saved editing").font(ChopFont.cardLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                    .padding(16)
                    .background(  // web: linear-gradient(135deg,#1a6dff,#4e8dff) + blue shadow
                        LinearGradient(colors: [Color(red: 0x1a/255, green: 0x6d/255, blue: 1.0),
                                                Color(red: 0x4e/255, green: 0x8d/255, blue: 1.0)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: Color.chopBlue.opacity(0.35), radius: 12, y: 5)

                    statCard("\(api.jobs.count)", "Videos edited")
                }
                HStack(spacing: 12) {
                    statCard(moneyLabel, "Saved vs. manual editing", sub: "at $30/h")
                    statCard("\(streak)", "Day streak")
                }

                Button { showImport = true } label: {
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

                // .egrid — thumbnail cards, two-up like the web grid on phone
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(api.jobs) { job in
                        NavigationLink { ChopPlayerScreen(job: job, api: api) } label: {
                            EditCard(job: job)
                        }
                        .buttonStyle(.plain)
                    }
                }
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

    private var localURL: URL?
    private var edit: ChopEdit?
    private var composition: AVMutableComposition?
    private var timeObserver: Any?
    private var stripTask: Task<Void, Never>?

    /// Undo stack, same idea as the web app's snap()/applySnap.
    private struct Snapshot {
        var pairs: [ChopPair]
        var segments: [ChopSegment]
        var manualCuts: [ChopClip]
        var minSil: Double
        var fillers: Bool
        var soft: Bool
        var splits: [Double] = []
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
            softFillers = e.settings.soft
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
        softFillers = e.settings.soft
        padStart = e.settings.startPadMs
        padEnd = e.settings.endPadMs
        edit = e
        pairs = e.pairs
        segments = e.segments
        guard !e.segments.isEmpty else { status = "No analysis on this job"; return }

        // prefer the 540p proxy — small, fast, and sharp enough on a phone
        guard let key = (job.data["proxyKey"] as? String) ?? job.videoKey else {
            status = "Video isn't synced to the cloud yet"; return
        }

        status = "Fetching video…"
        guard let signed = await api.presignGet(key) else { status = "Couldn't get the video"; return }

        status = "Downloading…"
        let local: URL
        do {
            let (tmp, _) = try await URLSession.shared.download(from: signed)
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".mp4")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            local = dest
        } catch {
            status = "Download failed: \(error.localizedDescription)"; return
        }

        localURL = local
        rebuild()
    }


    /// Export from the ORIGINAL, never the proxy, and save to the camera roll.
    /// Mirrors CHOP_EXPORT_PROXY_GUARD in the web app: a 540p export would be a
    /// quiet, serious regression.
    func export(job: ChopJob, api: ChopAPI) async {
        guard let e = edit else { return }
        let kept = e.keptClips()
        guard !kept.isEmpty else { exportMsg = "Nothing to export"; return }

        guard let originalKey = job.videoKey else {
            exportMsg = "The full-quality video isn't synced yet — open it on the web once to upload it."
            return
        }

        exporting = true; exportPct = 0
        defer { exporting = false }

        exportMsg = "Fetching the original…"
        guard let signed = await api.presignGet(originalKey) else {
            exportMsg = "Couldn't fetch the original"; return
        }

        exportMsg = "Downloading…"
        let local: URL
        do {
            let (tmp, _) = try await URLSession.shared.download(from: signed)
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "-src.mp4")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            local = dest
        } catch {
            exportMsg = "Download failed: \(error.localizedDescription)"; return
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
        ChopToasts.shared.show(ok ? "Saved to your camera roll ✓" : "Couldn't save to Photos")
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

    func togglePlay() {
        if player.rate > 0 { player.pause() } else {
            if time >= duration - 0.05 { seekExact(to: 0) }
            player.play()
        }
    }

    /// Frames straight off the composition, so the strip shows the EDIT,
    /// not the raw footage — same as the web app's edited view.
    private func buildStrip(_ comp: AVMutableComposition) {
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
                 minSil: minSil, fillers: fillers, soft: softFillers,
                 splits: splits)
    }
    private func apply(_ s: Snapshot) {
        pairs = s.pairs; segments = s.segments
        minSil = s.minSil; fillers = s.fillers; softFillers = s.soft
        splits = s.splits
        if var e = edit { e.manualCuts = s.manualCuts; edit = e }
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
        rebuildKeepingTime()
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
        ed.manualCuts.append(ChopClip(start: clips[i].start, end: clips[i].end))
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
        ed.manualCuts.append(keepAfter ? ChopClip(start: clip.start, end: at)
                                       : ChopClip(start: at, end: clip.end))
        edit = ed
        rebuild()
    }

    // MARK: quick-edit bands — ADDITIVE layer over the locked core.
    // Splits are the web's state.splits: pure band boundaries, NO footage
    // change, NO rebuild — which is why Split never jumps.

    @Published var splits: [Double] = []   // raw times

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
        return bands.firstIndex { abs($0.start - at) < 0.06 }
    }

    /// Web qeDelete: manual cut over the band. The playhead lands EXACTLY on
    /// the join where the two neighbours close together.
    func deleteBand(_ i: Int) {
        let bs = bands; guard i < bs.count, var e = edit else { return }
        pushHistory()
        let b = bs[i]
        e.manualCuts.append(ChopClip(start: b.start, end: b.end))
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

    /// How far a band edge can be pulled OUT (extend), in seconds — only into
    /// footage that a manual trim removed. Auto cuts stay Cut-Lab territory.
    func bandExtendLeft(_ i: Int) -> Double {
        guard let e = edit, i < bands.count else { return 0 }
        let b = bands[i]
        if let c = e.manualCuts.first(where: { abs($0.end - b.start) < 0.05 }) {
            return max(0, c.end - c.start - 0.02)
        }
        return 0
    }
    func bandExtendRight(_ i: Int) -> Double {
        guard let e = edit, i < bands.count else { return 0 }
        let b = bands[i]
        if let c = e.manualCuts.first(where: { abs($0.start - b.end) < 0.05 }) {
            return max(0, c.end - c.start - 0.02)
        }
        return 0
    }

    /// TikTok caps: drag IN = trim (manual cut over the edge), drag OUT =
    /// extend (shrink the adjacent manual cut back). Playhead stays put.
    func resizeBand(_ i: Int, side: Int, deltaSeconds: Double) {
        let bs = bands; guard i < bs.count, var e = edit, abs(deltaSeconds) > 0.02 else { return }
        let b = bs[i]
        pushHistory()
        if side == 0 {
            if deltaSeconds > 0 {          // trim the front
                e.manualCuts.append(ChopClip(start: b.start,
                                             end: min(b.start + deltaSeconds, b.end - 0.05)))
            } else {                       // extend the front into the adjacent trim
                var need = -deltaSeconds
                if let idx = e.manualCuts.firstIndex(where: { abs($0.end - b.start) < 0.05 }) {
                    let c = e.manualCuts[idx]
                    need = min(need, max(0, c.end - c.start - 0.01))
                    let newEnd = c.end - need
                    if newEnd - c.start < 0.02 { e.manualCuts.remove(at: idx) }
                    else { e.manualCuts[idx] = ChopClip(start: c.start, end: newEnd) }
                }
            }
        } else {
            if deltaSeconds > 0 {          // trim the back
                e.manualCuts.append(ChopClip(start: max(b.end - deltaSeconds, b.start + 0.05),
                                             end: b.end))
            } else {                       // extend the back
                var need = -deltaSeconds
                if let idx = e.manualCuts.firstIndex(where: { abs($0.start - b.end) < 0.05 }) {
                    let c = e.manualCuts[idx]
                    need = min(need, max(0, c.end - c.start - 0.01))
                    let newStart = c.start + need
                    if c.end - newStart < 0.02 { e.manualCuts.remove(at: idx) }
                    else { e.manualCuts[idx] = ChopClip(start: newStart, end: c.end) }
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
    func playFrom(segment i: Int) {
        guard let e = edit, i < e.segments.count else { return }
        let raw = e.segments[i].start
        var acc = 0.0
        for clip in e.keptClips() {
            if raw >= clip.start && raw <= clip.end { seekExact(to: acc + (raw - clip.start)); return }
            acc += clip.end - clip.start
        }
        seekExact(to: 0)
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
        player.replaceCurrentItem(with: AVPlayerItem(asset: comp))
        composition = comp
        duration = cursor.seconds
        ready = true
        status = ""
        observeTime()
        buildStrip(comp)
        if wasPlaying { player.play() }
    }
}

struct ChopPlayerScreen: View {
    let job: ChopJob
    @ObservedObject var api: ChopAPI
    @StateObject private var p = ChopPlayer()
    @State private var panel: String? = "retakes"
    @State private var showEdited = true
    @State private var marking = false
    @State private var selected: Int? = nil   // selected timeline section
    @State private var compact = false        // web body.stagecompact: 50dvh ↔ 24dvh
    @Environment(\.dismiss) private var dismiss

    private func clock(_ t: Double) -> String {
        let s = Int(t.rounded()); return String(format: "%d:%02d", s / 60, s % 60)
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {

                // ---- video stage: 50% of the screen, 24% when the panel is up ----
                ZStack(alignment: .top) {
                    PlayerLayerView(player: p.player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)

                    HStack(spacing: 2) {
                        modePill("Raw", on: !showEdited)
                        modePill("Edited", on: showEdited)
                    }
                    .padding(3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                    .padding(.top, 10)

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
                    }
                    .padding(.top, 10).padding(.horizontal, 10)
                }
                .frame(height: p.ready ? geo.size.height * (compact ? 0.24 : 0.50)
                                       : geo.size.height * 0.50)
                .clipped()
                .animation(.easeInOut(duration: 0.35), value: compact)
                .onTapGesture {
                    if compact { compact = false }        // bring the video back first
                    else if p.ready { p.togglePlay() }    // CapCut: tap preview = play/pause
                }

                if p.ready {
                    playBar
                    ChopTimeline(p: p, selected: $selected)
                        .frame(height: 116)   // TikTok strip + doubled thumb pad
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
                            Capsule().fill(Color.chopMuted.opacity(0.5))
                                .frame(width: 40, height: 4.5)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(ChopColor.card)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 12)
                                        .onEnded { g in
                                            if g.translation.height < -24 { compact = true }
                                            if g.translation.height > 24 { compact = false }
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
        .onDisappear { api.editorOpen = false; p.player.pause() }
    }

    // Split / Delete / Restore stretched across the row — deselect via the
    // thumb pad, duration lives on the clip chip (TikTok style)
    private func selBar(_ sel: Int) -> some View {
        let span = p.bandSpansEdit[sel]
        return HStack(spacing: 8) {
            ctxTool("Split", "scissors", Color.chopInk) {
                // web qeSplit: split stays visible, RIGHT band stays selected,
                // nothing rebuilds, nothing jumps
                if span.start + 0.05 < p.time, p.time < span.end - 0.05 {
                    selected = p.splitBand(atEditTime: p.time)
                } else {
                    ChopToasts.shared.show("Drag the playhead inside the selected section, then split")
                }
            }
            ctxTool("Delete", "trash", ChopColor.rose) {
                p.deleteBand(sel); selected = nil
            }
            ctxTool("Restore", "arrow.uturn.backward", ChopColor.green) {
                p.undo(); selected = nil
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(ChopColor.card)
    }

    private func ctxTool(_ label: String, _ icon: String, _ tint: Color,
                         _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                Text(label).font(.system(size: 12, weight: .bold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(ChopColor.soft2)
            .foregroundStyle(tint)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.chopLine, lineWidth: 1))
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

    private func modePill(_ label: String, on: Bool) -> some View {
        Text(label)
            .font(.caption.weight(.bold))
            .foregroundStyle(on ? Color.black : .white)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(on ? Color.white : Color.clear, in: Capsule())
            .onTapGesture { showEdited = (label == "Edited") }
    }

    // TikTok play bar: time left · small centred play · undo/redo right
    private var playBar: some View {
        ZStack {
            HStack(spacing: 8) {
                Text("\(clock(p.time)) / \(clock(p.duration))")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.chopMuted)
                if p.duration > 0, job.rawSec > 0 {
                    Text("\(Int((1 - p.duration / job.rawSec) * 100))% shorter")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.chopGreen)
                }
                Spacer()
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
    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Text/Image/Captions removed for App Store review — Apple
                // rejects visible-but-nonfunctional controls. Re-add at launch.
                tool("retakes", "rectangle.on.rectangle", "Retakes", badge: p.undecided)
                tool("cuts", "scissors", "Cuts")
                tool("script", "text.alignleft", "Script")
                tool("export", "square.and.arrow.down", "Export")
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 6)
        .background(ChopColor.card)
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
    }

    // ---- persistent Done / Queue pills ----
    /// Green tick on the video — web's approve flow. Back arrow = queue.
    private func doneTapped() {
        let pend = p.undecided
        if pend > 0 {
            panel = "retakes"
            ChopToasts.shared.show("\(pend) retake\(pend > 1 ? "s" : "") still need\(pend > 1 ? "" : "s") a decision")
            return
        }
        marking = true
        Task {
            await api.setStatus(job, to: "approved")
            marking = false
            ChopToasts.shared.show("Moved to Ready to export ✓")
            dismiss()
        }
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
                    Toggle(isOn: $p.softFillers) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Also soft fillers").font(.subheadline.weight(.bold))
                            Text("like, you know, I mean — only when isolated")
                                .font(.system(size: 12)).foregroundStyle(Color.chopMuted)
                        }
                    }
                    .tint(Color.chopBlue)
                    .onChange(of: p.softFillers) { _, _ in p.retune() }
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
    @State private var baseDur: Double = 0   // pins px-per-second so edits never rescale the strip

    private let stripH: CGFloat = 44   // TikTok strip height
    private let scrubH: CGFloat = 56   // TikTok-sized thumb-scrub pad (doubled)

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
                    ForEach(Array(spans.enumerated()), id: \.offset) { i, span in
                        // TikTok live trim: the dragged edge moves, neighbours
                        // slide with it, nothing is "previewed" in red
                        let tl = trimLive
                        let s: Double = (tl?.band == i && tl?.side == 0) ? tl!.t : span.start
                        let e: Double = (tl?.band == i && tl?.side == 1) ? tl!.t : span.end
                        let shift: CGFloat = {
                            guard let tl, tl.band != i, tl.band < spans.count else { return 0 }
                            if tl.side == 0, i < tl.band {
                                return CGFloat(tl.t - spans[tl.band].start) * pps
                            }
                            if tl.side == 1, i > tl.band {
                                return CGFloat(tl.t - spans[tl.band].end) * pps
                            }
                            return 0
                        }()
                        let x = CGFloat(s) * pps + shift
                        let bw = max(3, CGFloat(e - s) * pps)

                        bandThumbs(span: (s, e), width: bw, pps: pps, dur: dur)
                            .frame(width: bw, height: stripH)
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

                    // ---- TikTok white selection frame + trim caps ----
                    if let sel = selected?.wrappedValue, sel < spans.count {
                        selectionFrame(sel: sel, spans: spans, pps: pps)
                    }
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
                            // this clip — otherwise pause exactly where it is
                            let span = p.bandSpansEdit[i]
                            if !(p.time >= span.start && p.time <= span.end) {
                                p.seekExact(to: min(span.start + 0.001, p.duration))
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
                            width: CGFloat, pps: CGFloat, dur: Double) -> some View {
        if p.strip.isEmpty {
            LinearGradient(colors: [Color(red: 0.24, green: 0.27, blue: 0.33),
                                    Color(red: 0.15, green: 0.17, blue: 0.21)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            let tileW = stripH * (34.0 / 56.0)      // web thumb aspect
            let count = max(1, Int(ceil(width / tileW)))
            HStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { k in
                    // the frame whose time sits at this tile's centre
                    let t = span.start + (Double(k) + 0.5) * Double(tileW / pps)
                    let idx = min(p.strip.count - 1,
                                  max(0, Int(t / dur * Double(p.strip.count))))
                    Image(uiImage: p.strip[idx]).resizable().scaledToFill()
                        .frame(width: tileW, height: stripH)
                        .clipped()
                }
            }
            .frame(width: width, height: stripH, alignment: .leading)
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
                        // frame-perfect cut — keep pulling to push through
                        let stick = p.time
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
                    }
                    .onEnded { _ in
                        defer { trimLive = nil; trimSnapped = false }
                        guard let tl = trimLive, tl.band == sel else { return }
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
                let t = max(0, min(p.duration, (dragStartTime ?? 0) - Double(g.translation.width / pps)))
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
    private func pinchGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { v in
                if zoomStart == nil { zoomStart = zoom }
                zoom = min(8, max(1, (zoomStart ?? 1.5) * v))
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

    private var statusText: String {
        switch pair.choice {
        case nil: return "Needs decision"
        case "both": return pair.weak ? "Dismissed" : "Keeping both"
        case "a": return "Keeping Take 1"
        default: return "Keeping Take 2"
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

            take("a", label: "Take 1 · first attempt", text: pair.aText, len: pair.aLen)
            take("b", label: "Take 2 · final attempt", text: pair.bText, len: pair.bLen)

            // .rkfoot
            HStack(spacing: 14) {
                if pair.weak && pending {
                    Button("✕ Not a retake") { choose("both") }
                        .font(.system(size: 12.5, weight: .bold)).foregroundStyle(ChopColor.muted)
                }
                Button("Keep both") { choose("both") }
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

    /// Same pipeline the web app uses: audio out, analyse, save the job,
    /// then the full video in the background so export can use the original.
    func run(pickedURL: URL, name: String, api: ChopAPI) async {
        busy = true; failed = ""; done = false
        defer { busy = false }

        let asset = AVURLAsset(url: pickedURL)
        let rawSec = CMTimeGetSeconds(asset.duration)

        // 1. audio only — a fraction of the size, and all Deepgram needs
        stepIndex = 0; step = "Preparing audio…"
        guard let audio = await extractAudio(asset) else {
            failed = "Couldn't read the audio from that clip"; return
        }

        stepIndex = 1; step = "Uploading audio…"
        let audioName = (name as NSString).deletingPathExtension + ".m4a"
        guard let (putURL, key) = await api.presignPut(filename: audioName),
              await api.putFile(audio, to: putURL) else {
            failed = "Upload failed"; return
        }

        stepIndex = 2; step = "Transcribing…"
        guard let jobId = await api.startProcessing(key: key) else {
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
        await api.saveJob(name: name, payload: payload, rawSec: rawSec, videoKey: nil)
        await api.loadJobs()
        ChopToasts.shared.show("Chopped ✓")
        stepIndex = 6
        done = true
        step = ""
        busy = false

        Task.detached { [weak self] in
            guard let (vPut, vKey) = await api.presignPut(filename: "sync-" + name) else { return }
            let ok = await api.putFile(pickedURL, to: vPut)
            guard ok else { return }
            await api.saveJob(name: name, payload: payload, rawSec: rawSec, videoKey: vKey)
            await api.loadJobs()
            await MainActor.run {
                self?.syncMsg = "Full quality video synced — export is ready"
                ChopToasts.shared.show("Full quality video synced")
            }
        }
    }

    private func extractAudio(_ asset: AVAsset) async -> URL? {
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

struct ImportSheet: View {
    @ObservedObject var api: ChopAPI
    @StateObject private var imp = ChopImporter()
    @State private var pickedMany: [PhotosPickerItem] = []
    @Environment(\.dismiss) private var dismiss

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

            if imp.busy {
                // .proc — web parity: card, 20px title, soft step circles, 6px bar
                VStack(alignment: .leading, spacing: 4) {
                    Text("Editing your video…")
                        .font(.system(size: 20, weight: .bold)).foregroundStyle(ChopColor.ink)
                    Text("This usually takes a couple of minutes on real footage.")
                        .font(.system(size: 13)).foregroundStyle(Color.chopMuted)
                        .padding(.bottom, 10)

                    VStack(spacing: 0) {
                        ForEach(Array(ChopImporter.steps.enumerated()), id: \.offset) { i, label in
                            HStack(spacing: 13) {
                                ZStack {
                                    Circle()
                                        .fill(i < imp.stepIndex ? ChopColor.greenSoft
                                              : i == imp.stepIndex ? ChopColor.blueSoft : ChopColor.soft2)
                                        .frame(width: 25, height: 25)
                                    if i < imp.stepIndex {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .heavy))
                                            .foregroundStyle(ChopColor.green)
                                    } else if i == imp.stepIndex {
                                        ProgressView().scaleEffect(0.55).tint(ChopColor.blue)
                                    } else {
                                        Text("\(i + 1)").font(.system(size: 12.5, weight: .heavy))
                                            .foregroundStyle(ChopColor.muted)
                                    }
                                }
                                Text(label)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(ChopColor.ink)
                                Spacer()
                            }
                            .padding(.vertical, 9)
                            .opacity(i > imp.stepIndex ? 0.45 : 1)   // .pstep.pend
                        }
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(ChopColor.soft2)
                            Capsule().fill(ChopColor.blue)
                                .frame(width: geo.size.width *
                                       CGFloat(max(0, min(6, imp.stepIndex))) / 6)
                        }
                    }
                    .frame(height: 6)
                    .padding(.top, 18)
                }
                .padding(.vertical, 32).padding(.horizontal, 34)
                .frame(maxWidth: 520, alignment: .leading)
                .background(ChopColor.card, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.chopLine, lineWidth: 1))
                .padding(.top, 24)
            } else if imp.done {
                Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                Text("Chopped").font(ChopFont.bodyBold)
                Text(imp.syncMsg)
                    .font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
            } else if api.credits <= 0 {
                Image(systemName: "bolt.slash").font(.largeTitle).foregroundStyle(.orange)
                Text("You're out of credits").font(.subheadline.weight(.medium))
                Text("One credit edits one video, any length up to 10 minutes.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Close") { dismiss() }
            } else {
                PhotosPicker(selection: $pickedMany, maxSelectionCount: 5, matching: .videos) {
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
        .onChange(of: pickedMany) { _, items in
            guard !items.isEmpty else { return }
            Task {
                // one at a time — parallel imports exhaust memory on a phone
                for (n, item) in items.enumerated() {
                    guard let movie = try? await item.loadTransferable(type: ChopMovie.self) else {
                        imp.failed = "Couldn't read that video"; continue
                    }
                    let df = DateFormatter(); df.dateFormat = "d MMM, HH.mm"
                    var friendly = "Chop " + df.string(from: Date())
                    if items.count > 1 { friendly += " (\(n + 1))" }
                    await imp.run(pickedURL: movie.url, name: friendly + ".mp4", api: api)
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
    static let ids = [
        "com.chopedit.credits.10",
        "com.chopedit.credits.50",
        "com.chopedit.credits.100",
        "com.chopedit.credits.200",
        "com.chopedit.credits.300",
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
    @State private var n: Double = 50
    @State private var note = ""

    /// line-for-line port of web perCredit(): £1 → 85p (50+) → 75p (100+),
    /// −5p per extra 50, floor 60p
    private func perCredit(_ n: Int) -> Double {
        if n < 50 { return 1.00 }
        if n < 100 { return 0.85 }
        return max(0.60, 0.75 - 0.05 * Double((n - 100) / 50))
    }
    private func gbp(_ v: Double) -> String { String(format: "£%.2f", (v * 100).rounded() / 100) }
    private func perLabel(_ v: Double) -> String { v < 1 ? "\(Int((v * 100).rounded()))p" : gbp(v) }

    var body: some View {
        let count = Int(n)
        let per = perCredit(count)
        let total = Double(count) * per
        let save = Double(count) * 1.0 - total

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // hero
                    Text("Billing").font(ChopFont.serif(30)).foregroundStyle(ChopColor.ink)
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

                    // slide card (web .slidecard)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("How many videos do you want to chop?")
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(ChopColor.ink)
                        Text("One credit chops one video. The more you buy, the less each video costs.")
                            .font(.system(size: 13)).foregroundStyle(ChopColor.muted)

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(count)").font(.system(size: 44, weight: .heavy)).foregroundStyle(ChopColor.ink)
                            Text("credits").font(.system(size: 15)).foregroundStyle(ChopColor.muted)
                        }
                        .padding(.top, 6)

                        Slider(value: $n, in: 1...300, step: 1).tint(ChopColor.blue)

                        HStack {
                            ForEach(["£1.00", "85p", "75p", "70p", "65p", "60p"], id: \.self) { t in
                                Text(t).font(.system(size: 11, weight: .bold)).foregroundStyle(ChopColor.muted)
                                if t != "60p" { Spacer() }
                            }
                        }

                        HStack(spacing: 10) {
                            crStat("Per video", perLabel(per), ChopColor.ink)
                            crStat("Total", gbp(total), ChopColor.ink)
                            crStat("You save", save > 0 ? gbp(save) : "—", ChopColor.green)
                        }
                        .padding(.top, 8)

                        if store.products.isEmpty {
                            // Purchases go live with the App Store release —
                            // honest state until IAP products exist.
                            Button {
                                note = "Purchases aren’t available in this build yet — they arrive with the App Store release."
                            } label: {
                                Text("Buy \(count) credit\(count == 1 ? "" : "s") for \(gbp(total))")
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
                            // live App Store packs — the slider highlights the closest one
                            VStack(spacing: 8) {
                                ForEach(store.products, id: \.id) { product in
                                    let pc = ChopPacks.credits(in: product.id)
                                    let closest = store.products.min {
                                        abs(ChopPacks.credits(in: $0.id) - count) < abs(ChopPacks.credits(in: $1.id) - count)
                                    }?.id == product.id
                                    Button {
                                        Task { await store.buy(product, api: api) }
                                    } label: {
                                        HStack {
                                            Text("\(pc) credits").font(.system(size: 14.5, weight: .heavy))
                                            Spacer()
                                            Text(product.displayPrice).font(.system(size: 14.5, weight: .heavy))
                                        }
                                        .padding(.horizontal, 16).padding(.vertical, 13)
                                        .background(closest ? ChopColor.blue : ChopColor.soft2,
                                                    in: RoundedRectangle(cornerRadius: 14))
                                        .foregroundStyle(closest ? .white : ChopColor.ink)
                                        .overlay(RoundedRectangle(cornerRadius: 14)
                                            .stroke(closest ? Color.clear : Color.chopLine, lineWidth: 1))
                                    }
                                    .disabled(store.buying)
                                }
                            }
                            .padding(.top, 12)
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

                    Text("Credits never expire · VAT included")
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
        }
    }

    private func crStat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 11.5)).foregroundStyle(ChopColor.muted)
            Text(value).font(.system(size: 16, weight: .heavy)).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(ChopColor.soft2, in: RoundedRectangle(cornerRadius: 12))
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

                    group("Profile") {
                        row("Name", value: api.profileName.isEmpty ? "Not set" : api.profileName, chevron: true) { showProfile = true }
                        divider
                        row("TikTok", value: api.profileTiktok.isEmpty ? "Not set" : "@\(api.profileTiktok)", chevron: true) { showProfile = true }
                        divider
                        row("Photo", action: "Change", chevron: true) { showProfile = true }
                    }

                    group("Account") {
                        staticRow("Email", value: api.email.isEmpty ? "—" : api.email)
                        divider
                        row("Credits", value: "\(api.credits)", chevron: true) { showBilling = true }
                        divider
                        row("Billing", action: "Buy credits", chevron: true) { showBilling = true }
                        divider
                        staticRow("Member since", value: "—")
                        divider
                        row("Password", action: pwSent ? "Sent ✓" : "Reset", chevron: false) {
                            Task {
                                let e = api.email
                                guard !e.isEmpty else { return }
                                _ = await api.sendPasswordReset(email: e)
                                pwSent = true
                                ChopToasts.shared.show("Reset link sent — check your inbox")
                            }
                        }
                    }

                    group("Preferences") {
                        HStack {
                            Text("Theme").font(ChopFont.body).foregroundStyle(ChopColor.ink)
                            Spacer()
                            Picker("", selection: $theme) {
                                Text("System").tag(ChopTheme.system)
                                Text("Light").tag(ChopTheme.light)
                                Text("Dark").tag(ChopTheme.dark)
                            }
                            .pickerStyle(.segmented).frame(width: 190)
                            .onChange(of: theme) { _, t in ChopTheme.set(t); onThemeChange?(t) }
                        }
                        .padding(.horizontal, 15).padding(.vertical, 10)
                        divider
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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showProfile) { ChopProfileView(api: api) }
            .sheet(isPresented: $showBilling) { ChopBillingView(api: api) }
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


// MARK: - Queue

struct ChopQueueBody: View {
    @ObservedObject var api: ChopAPI

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
                        .font(ChopFont.serif(24))
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
                            }
                            if list.isEmpty {
                                Text(empties[i])
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(ChopColor.muted)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 18).padding(.horizontal, 6)
                            } else {
                                ForEach(list) { job in
                                    NavigationLink { ChopPlayerScreen(job: job, api: api) } label: {
                                        QueueCard(job: job, current: false)
                                    }
                                    .buttonStyle(.plain)
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
        case "review":     return current ? ("EDITING NOW", ChopColor.blue, ChopColor.blueSoft)
                                          : ("NEEDS REVIEW", ChopColor.amber, ChopColor.amberSoft)
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
    static let relaxed  = ChopSettings(minSil: 0.7,  fillers: true, soft: false, startPadMs: 60, endPadMs: 0)
    static let balanced = ChopSettings(minSil: 0.4,  fillers: true, soft: false, startPadMs: 40, endPadMs: -40)
    static let snappy   = ChopSettings(minSil: 0.05, fillers: true, soft: true,  startPadMs: 0,  endPadMs: -140)

    static var saved: ChopSettings {
        let d = UserDefaults.standard
        guard d.object(forKey: "chopMinSil") != nil else { return balanced }
        return ChopSettings(minSil: d.double(forKey: "chopMinSil"),
                            fillers: d.bool(forKey: "chopFillers"),
                            soft: d.bool(forKey: "chopSoft"),
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

    // web PRESETS copy, verbatim
    private let presetMeta: [(String, String, ChopSettings?)] = [
        ("Relaxed",  "Keeps natural pauses. Silences over 0.7s, hard fillers only.",            ChopPresets.relaxed),
        ("Balanced", "The Chop standard. Silences over 0.4s, fillers removed.",                 ChopPresets.balanced),
        ("Snappy",   "TikTok-tight. Silences over 0.05s, all fillers, tight clip ends.",        ChopPresets.snappy),
        ("Custom",   "Your own recipe, saved from the sliders below.",                          nil)
    ]

    var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {

                    // .hero — web parity
                    Text("Cut Lab")
                        .font(ChopFont.serif(30))
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
                        toggleRow("Also soft fillers", "like, you know, I mean — only when isolated", $s.soft)

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
                                s = ChopPresets.balanced; savedNote = false
                            } label: {
                                Text("Reset to Balanced")
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
        return Button { if let v { s = v; savedNote = false } } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ChopColor.ink)
                Text(desc).font(.system(size: 12)).foregroundStyle(ChopColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            .padding(.horizontal, 20).padding(.vertical, 18)
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

    var body: some View {
        HStack(spacing: 4) {
            item(0, "square.grid.2x2", "Dashboard", 0)
            item(1, "chart.bar.fill", "Queue", queueCount)
            item(2, "slider.horizontal.3", "Cut Lab", 0)
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
        .padding(.bottom, 22)
    }

    private func item(_ i: Int, _ icon: String, _ label: String, _ badge: Int) -> some View {
        let on = tab == i
        return Button { tab = i } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(on ? Color.chopBlue : Color.chopMuted)
                Text(label)
                    .font(.system(size: 13.5, weight: .bold))
                    .fixedSize()
                    .foregroundStyle(on ? Color.chopInk : Color.chopMuted)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Color.chopInk)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(Color.chopBlue, in: Capsule())
                }
            }
            .padding(.horizontal, 15).padding(.vertical, 11)
            .background(on ? Color.white.opacity(0.10) : .clear, in: Capsule())
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
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { big = true }
            }
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
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { dim = true }
        }
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
            .animation(.easeInOut(duration: 1.2), value: collapsed)
            vizLabel("1:42", "0:58", rGreen: false)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { collapsed = true }
        }
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
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { lit = true }
        }
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
            .animation(.easeInOut(duration: 2.2), value: tight)
            vizLabel("pinch · split · trim · snap")
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.25).repeatForever(autoreverses: true)) { tight = true }
        }
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
                LandPrice(name: "CREATOR", amount: "85p", unit: "/video", per: "50+ credits",
                          bullets: ["Everything included", "Bulk upload queue", "Cross-device sync"],
                          mid: true, signup: signup)
                LandPrice(name: "PRO", amount: "75p", unit: "/video", per: "100+ credits · drops to 60p",
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
