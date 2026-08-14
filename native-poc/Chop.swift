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

let SB_URL  = "https://vcrforlyuhapvkewsogq.supabase.co"
let SB_ANON = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZjcmZvcmx5dWhhcHZrZXdzb2dxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAzODk4NzAsImV4cCI6MjA5NTk2NTg3MH0.lcFC5aJFUGYrj4iw8oJ8R1bci4y_-aYKyQg8v9zrMqQ"


// MARK: - Brand

extension Color {
    static let chopBg     = Color(red: 0.055, green: 0.063, blue: 0.078)   // #0e1014
    static let chopPanel  = Color(red: 0.082, green: 0.094, blue: 0.125)   // #151820
    static let chopLine   = Color(red: 0.149, green: 0.165, blue: 0.200)   // #262a33
    static let chopBlue   = Color(red: 0.102, green: 0.427, blue: 1.0)     // #1a6dff
    static let chopViolet = Color(red: 0.486, green: 0.227, blue: 0.929)   // #7c3aed
    static let chopMuted  = Color(red: 0.541, green: 0.576, blue: 0.647)   // #8a93a5
    static let chopGreen  = Color(red: 0.184, green: 0.749, blue: 0.561)   // #2fbf8f
}

let chopGradient = LinearGradient(colors: [.chopBlue, .chopViolet],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)

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
    @Published var signedIn = false
    @Published var jobs: [ChopJob] = []
    @Published var credits: Int = 0
    @Published var profileName = ""
    @Published var profileTiktok = ""
    @Published var profileAvatar = ""

    private(set) var accessToken = ""
    private(set) var userId = ""

    func signIn() async {
        error = ""; busy = true
        defer { busy = false }

        guard var comps = URLComponents(string: "\(SB_URL)/auth/v1/token") else { return }
        comps.queryItems = [URLQueryItem(name: "grant_type", value: "password")]
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
            if let msg = obj["error_description"] as? String { error = msg; return }
            if let msg = obj["msg"] as? String, obj["access_token"] == nil { error = msg; return }
            guard let token = obj["access_token"] as? String,
                  let user = obj["user"] as? [String: Any],
                  let uid = user["id"] as? String else {
                error = "Couldn't sign in"; return
            }
            accessToken = token
            userId = uid
            signedIn = true
            await loadProfile()
            await loadJobs()
        } catch {
            self.error = error.localizedDescription
        }
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

// MARK: - UI

struct ChopRootView: View {
    @StateObject private var api = ChopAPI()
    @State private var showImport = false
    @State private var showSettings = false
    @State private var showOOC = false
    @State private var tab = 0

    var body: some View {
        Group {
            if api.signedIn { app } else { signIn.background(Color.chopBg) }
        }
        .preferredColorScheme(.dark)
        .tint(Color.chopBlue)
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
                .sheet(isPresented: $showSettings) { ChopSettingsView(api: api) }
                .sheet(isPresented: $showOOC) { OutOfCreditsSheet() }
                .onChange(of: api.credits) { _, c in if c <= 0 && api.signedIn { showOOC = true } }
                .refreshable { await api.loadJobs() }
            }
            ChopGlassNav(tab: $tab, queueCount: reviewCount)
        }
    }

    private var signIn: some View {
        VStack(spacing: 16) {
            Spacer()
            Group {
                if UIImage(named: "ChopMark") != nil {
                    Image("ChopMark").resizable().scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 22).fill(chopGradient)
                        .overlay(Text("C").font(.system(size: 46, weight: .bold))
                        .foregroundStyle(.white))
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(.bottom, 4)
            Text("Chop").font(.largeTitle.weight(.bold))
            Text("Don't edit, just film.")
                .font(.subheadline).foregroundStyle(Color.chopMuted)
                .padding(.bottom, 8)

            TextField("Email", text: $api.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            SecureField("Password", text: $api.password)
                .textFieldStyle(.roundedBorder)

            Button {
                Task { await api.signIn() }
            } label: {
                if api.busy { ProgressView() } else { Text("Sign in").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(api.busy || api.email.isEmpty || api.password.isEmpty)

            if !api.error.isEmpty {
                Text(api.error).font(.footnote).foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Spacer(); Spacer()
        }
        .padding(28)
    }



    private var chopHeader: some View {
        HStack(spacing: 10) {
            Group {
                if UIImage(named: "ChopMark") != nil {
                    Image("ChopMark").resizable().scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 9).fill(chopGradient)
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 9))

            Text("Chop").font(.title3.weight(.bold))

            Spacer()

            HStack(spacing: 5) {
                Image(systemName: "bolt.fill").font(.system(size: 11, weight: .bold))
                Text("\(api.credits) credits").font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(Color.chopBlue)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(Color.chopBlue.opacity(0.14), in: Capsule())

            Button { showSettings = true } label: {
                Text(avatarEmoji)
                    .font(.system(size: 17))
                    .frame(width: 36, height: 36)
                    .background(LinearGradient(colors: avatarColours,
                                startPoint: .topLeading, endPoint: .bottomTrailing))
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
            Text(value).font(.system(size: 30, weight: .bold)).foregroundStyle(Color.chopBlue)
            Text(label).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
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
    /// Same basis as the web dashboard: manual editing valued at £30/hour.
    private var moneyLabel: String { "£\(Int(savedSeconds / 3600 * 30))" }

    private var editDays: [String] {
        api.jobs.compactMap { j in
            guard let ms = j.data["statusAt"] as? Double else { return nil }
            let d = Date(timeIntervalSince1970: ms / 1000)
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            return f.string(from: d)
        }
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

                Text("Hey \(api.profileName.isEmpty ? "there" : api.profileName), let's chop 👋")
                    .font(.system(size: 30, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("An overview of how your chopping is going.")
                    .font(.subheadline).foregroundStyle(Color.chopMuted)
                    .padding(.bottom, 4)

                // 2x2, hero first — same arrangement as the web dashboard
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(savedLabel).font(.system(size: 30, weight: .bold))
                        Text("Time saved editing")
                            .font(.system(size: 14, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                    .padding(16)
                    .background(Color.chopBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                    statCard("\(api.jobs.count)", "Videos edited")
                }
                HStack(spacing: 12) {
                    statCard(moneyLabel, "Saved vs. manual editing", sub: "at £30/h")
                    statCard("\(streak)", "Day streak")
                }

                Button { showImport = true } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "icloud.and.arrow.up")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color.chopBlue)
                            .frame(width: 58, height: 58)
                            .background(Color.chopBlue.opacity(0.14), in: Circle())
                        Text("Drop your videos here to edit")
                            .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                        Text("or click to browse")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Color.chopBlue)
                        Text("MP4 or MOV · straight from your camera roll")
                            .font(.caption2).foregroundStyle(Color.chopMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 26)
                    .overlay(RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                        .foregroundStyle(Color.chopLine))
                }
                .padding(.top, 4)

                HStack {
                    Text("Your edits").font(.title3.weight(.bold))
                    Spacer()
                    Text("\(api.jobs.count)").font(.subheadline).foregroundStyle(Color.chopMuted)
                }
                .padding(.top, 10)

                if api.jobs.isEmpty && !api.busy {
                    Text("Videos you edit will show up here.")
                        .font(.footnote).foregroundStyle(Color.chopMuted)
                        .padding(.vertical, 20)
                }

                ForEach(api.jobs) { job in
                    NavigationLink { ChopPlayerScreen(job: job, api: api) } label: {
                        QueueCard(job: job)
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

    /// Downloads the source once, then plays the edit as a single composition.
    func open(job: ChopJob, api: ChopAPI) async {
        var e = ChopEdit(job: job)
        // a job with no saved settings inherits the creator's Cut Lab default
        if (job.data["settings"] as? [String: Any]) == nil { e.settings = ChopPresets.saved }
        minSil = e.settings.minSil
        fillers = e.settings.fillers
        softFillers = e.settings.soft
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
        strip = []
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

    /// Pick a take for one pair, then rebuild. nil = undecided (keeps both).
    func choose(pair idx: Int, take: String?) {
        guard idx < pairs.count else { return }
        pairs[idx].choice = take
        rebuild()
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
        let wasCut = cut(i)
        segments[i].manual = !wasCut
        rebuild()
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
    @State private var showQueue = false
    @State private var marking = false
    @Environment(\.dismiss) private var dismiss

    private func clock(_ t: Double) -> String {
        let s = Int(t.rounded()); return String(format: "%d:%02d", s / 60, s % 60)
    }

    var body: some View {
        VStack(spacing: 0) {

            // ---- video, with the liquid-glass Raw|Edited pill on top ----
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
            }
            .frame(maxHeight: .infinity)

            if p.ready {
                playBar
                ChopTimeline(p: p)
                    .frame(height: 58)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                clipTools
                toolbar
                actions
                if let panel { panelBody(panel) }
            } else {
                Spacer()
                ProgressView().tint(Color.chopBlue)
                Text(p.status).font(.footnote).foregroundStyle(Color.chopMuted)
                    .multilineTextAlignment(.center).padding(.top, 8).padding(.horizontal, 24)
                Spacer()
            }
        }
        .background(Color.chopBg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(job.name).font(.footnote.weight(.medium))
                    .foregroundStyle(Color.chopMuted).lineLimit(1)
            }
        }
        .task { await p.open(job: job, api: api) }
        .onDisappear { p.player.pause() }
    }

    private func modePill(_ label: String, on: Bool) -> some View {
        Text(label)
            .font(.caption.weight(.bold))
            .foregroundStyle(on ? Color.black : .white)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(on ? Color.white : Color.clear, in: Capsule())
            .onTapGesture { showEdited = (label == "Edited") }
    }

    private var playBar: some View {
        HStack(spacing: 16) {
            Button { p.togglePlay() } label: {
                Image(systemName: p.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 38, height: 38)
                    .background(Color.white, in: Circle())
            }
            Text("\(clock(p.time)) / \(clock(p.duration))")
                .font(.caption.monospacedDigit()).foregroundStyle(Color.chopMuted)
            Spacer()
            if p.duration > 0, job.rawSec > 0 {
                Text("\(Int((1 - p.duration / job.rawSec) * 100))% shorter")
                    .font(.caption.weight(.semibold)).foregroundStyle(Color.chopGreen)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    /// Split, trim and delete at the playhead — the web app's quick-edit tools.
    private var clipTools: some View {
        HStack(spacing: 8) {
            clipTool("Trim start", "arrow.right.to.line") { p.trimAtPlayhead(keepAfter: false) }
            clipTool("Trim end", "arrow.left.to.line") { p.trimAtPlayhead(keepAfter: true) }
            clipTool("Delete", "trash") { p.deleteClipAtPlayhead() }
            if p.manualCutCount > 0 {
                clipTool("Undo", "arrow.uturn.backward") { p.undoManualCuts() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func clipTool(_ label: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(label).font(.system(size: 11, weight: .semibold))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 9)
            .background(Color.chopPanel)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.chopLine, lineWidth: 1))
        }
    }

    // ---- the icon-square toolbar, same shape as the web editor ----
    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                tool("retakes", "rectangle.on.rectangle", "Retakes", badge: p.undecided)
                tool("cuts", "scissors", "Cuts")
                tool("script", "text.alignleft", "Script")
                tool("export", "square.and.arrow.down", "Export")
            }
            .padding(.horizontal, 14)
        }
        .padding(.bottom, 10)
    }

    private func tool(_ key: String, _ icon: String, _ label: String, badge: Int = 0) -> some View {
        let on = panel == key
        return Button {
            panel = on ? nil : key
        } label: {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(on ? Color.chopBlue : Color.chopPanel)
                        .frame(width: 54, height: 54)
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .stroke(on ? Color.clear : Color.chopLine, lineWidth: 1))
                        .overlay(Image(systemName: icon)
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(on ? .white : Color.chopMuted))
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(.black)
                            .padding(4).background(Color.orange, in: Circle())
                            .offset(x: 5, y: -5)
                    }
                }
                Text(label).font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(on ? .white : Color.chopMuted)
            }
        }
    }

    // ---- persistent Done / Queue pills ----
    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                marking = true
                Task {
                    await api.setStatus(job, to: "approved")
                    marking = false
                    showQueue = true
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark").font(.footnote.weight(.bold))
                    Text(marking ? "Saving…" : "Done")
                }
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(p.undecided > 0 ? Color.chopPanel : Color.white)
                .foregroundStyle(p.undecided > 0 ? Color.chopMuted : .black)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(marking || p.undecided > 0)

            Button { showQueue = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2").font(.footnote.weight(.bold))
                    Text("Queue")
                }
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(Color.chopPanel)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.chopLine, lineWidth: 1))
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .sheet(isPresented: $showQueue) { NavigationStack { ChopQueueBody(api: api).background(Color.chopBg).navigationTitle("Review queue").navigationBarTitleDisplayMode(.inline) }.preferredColorScheme(.dark) }
    }

    @ViewBuilder
    private func panelBody(_ key: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch key {
                case "retakes":
                    if p.pairs.filter({ $0.complete }).isEmpty {
                        Text("No retakes in this one.")
                            .font(.footnote).foregroundStyle(Color.chopMuted)
                    } else {
                        ForEach(p.pairs) { pair in
                            if pair.complete { RetakeCard(pair: pair, player: p) }
                        }
                    }
                case "cuts":
                    HStack {
                        Text("Remove silences over").font(.subheadline)
                        Spacer()
                        Text("\(String(format: "%.2f", p.minSil))s")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(Color.chopMuted)
                    }
                    Slider(value: $p.minSil, in: 0.05...1.0, step: 0.05)
                        .tint(Color.chopBlue)
                        .onChange(of: p.minSil) { _, _ in p.rebuild() }
                    Toggle("Remove filler words", isOn: $p.fillers)
                        .font(.subheadline).tint(Color.chopBlue)
                        .onChange(of: p.fillers) { _, _ in p.rebuild() }
                    Toggle("Also soft fillers", isOn: $p.softFillers)
                        .font(.subheadline).tint(Color.chopBlue)
                        .onChange(of: p.softFillers) { _, _ in p.rebuild() }
                case "script":
                    Text("Tap a line to cut it or bring it back.")
                        .font(.caption).foregroundStyle(Color.chopMuted)
                    ForEach(Array(p.segments.enumerated()), id: \.offset) { i, seg in
                        if seg.kind == "speech" && !seg.text.isEmpty {
                            let isCut = p.cut(i)
                            HStack(alignment: .top, spacing: 10) {
                                Button { p.playFrom(segment: i) } label: {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.chopMuted)
                                        .frame(width: 26, height: 26)
                                        .background(Color.chopBg, in: Circle())
                                }
                                Text(seg.text)
                                    .font(.footnote)
                                    .strikethrough(isCut)
                                    .foregroundStyle(isCut ? Color.chopMuted : .white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button { p.toggleSegment(i) } label: {
                                    Image(systemName: isCut ? "arrow.uturn.backward" : "scissors")
                                        .font(.system(size: 11))
                                        .foregroundStyle(isCut ? Color.chopGreen : Color.chopMuted)
                                        .frame(width: 26, height: 26)
                                        .background(Color.chopBg, in: Circle())
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                default:
                    if !p.exportMsg.isEmpty {
                        Text(p.exportMsg).font(.footnote).foregroundStyle(Color.chopMuted)
                    }
                    Text("Exports at 1080p from the original, not the preview copy.")
                        .font(.caption).foregroundStyle(Color.chopMuted)
                }
            }
            .padding(16)
        }
        .frame(maxHeight: 230)
        .background(Color.chopPanel.opacity(0.5))
    }
}

/// Filmstrip of the EDIT with a centre-locked playhead. Drag to scrub —
/// the stick follows your finger and the picture catches up, which is the
/// behaviour mobile Safari could never manage.
struct ChopTimeline: View {
    @ObservedObject var p: ChopPlayer

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let frac = p.duration > 0 ? p.time / p.duration : 0

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8).fill(Color.chopPanel)

                HStack(spacing: 0) {
                    if p.strip.isEmpty {
                        Rectangle().fill(Color.chopPanel)
                    } else {
                        ForEach(Array(p.strip.enumerated()), id: \.offset) { _, img in
                            Image(uiImage: img).resizable().scaledToFill()
                                .frame(width: w / CGFloat(p.strip.count))
                                .clipped()
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .opacity(0.85)

                // progress veil
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.35))
                    .frame(width: max(0, w * (1 - frac)))
                    .offset(x: w * frac)
                    .allowsHitTesting(false)

                // playhead
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: 3)
                    .shadow(radius: 2)
                    .offset(x: max(0, min(w - 3, w * frac)))
                    .allowsHitTesting(false)
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.chopLine, lineWidth: 1))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        p.scrubbing = true
                        let f = max(0, min(1, g.location.x / w))
                        p.time = f * p.duration
                        p.seek(to: p.time)
                    }
                    .onEnded { g in
                        let f = max(0, min(1, g.location.x / w))
                        p.scrubbing = false
                        p.seekExact(to: f * p.duration)
                    }
            )
        }
    }
}

struct RetakeCard: View {
    let pair: ChopPair
    @ObservedObject var player: ChopPlayer

    private func label(_ key: String) -> String {
        key == "a" ? "Take 1 · first attempt" : "Take 2 · final attempt"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(pair.weak ? "Possible retake" : "Retake \(pair.id + 1)")
                    .font(.subheadline.weight(.semibold))
                Text("\(Int(pair.sim * 100))% match")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(statusText).font(.caption)
                    .foregroundStyle(pair.choice == nil ? .orange : .secondary)
            }

            take("a", text: pair.aText, len: pair.aLen)
            take("b", text: pair.bText, len: pair.bLen)

            HStack {
                Button("Keep both") { player.choose(pair: pair.id, take: "both") }
                    .font(.caption)
                if pair.choice != nil {
                    Button("Undo") { player.choose(pair: pair.id, take: nil) }
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var statusText: String {
        switch pair.choice {
        case nil: return "Needs decision"
        case "both": return pair.weak ? "Dismissed" : "Keeping both"
        case "a": return "Keeping Take 1"
        default: return "Keeping Take 2"
        }
    }

    @ViewBuilder
    private func take(_ key: String, text: String, len: Double) -> some View {
        let chosen = pair.choice == key
        let dropped = pair.choice != nil && pair.choice != "both" && pair.choice != key
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label(key)).font(.caption.weight(.medium))
                Text(String(format: "%.1fs", len)).font(.caption2).foregroundStyle(.secondary)
                if key == "b" {
                    Text("AI pick").font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .clipShape(Capsule())
                }
                Spacer()
            }
            Text("\u{201C}\(text)\u{201D}")
                .font(.footnote)
                .foregroundStyle(dropped ? .secondary : .primary)
                .strikethrough(dropped)
            Button(chosen ? "Keeping this" : "Keep this take") {
                player.choose(pair: pair.id, take: key)
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
        }
        .padding(10)
        .background(chosen ? Color.blue.opacity(0.15) : Color.clear)
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(chosen ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
            await MainActor.run { self?.syncMsg = "Full quality video synced — export is ready" }
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
    @State private var picked: PhotosPickerItem?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            if !imp.busy { Text("Add a video").font(.title2.weight(.semibold)) }

            if imp.busy {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Editing your video…").font(.title3.weight(.bold))
                    Text("This usually takes a couple of minutes on real footage.")
                        .font(.footnote).foregroundStyle(Color.chopMuted)

                    VStack(spacing: 0) {
                        ForEach(Array(ChopImporter.steps.enumerated()), id: \.offset) { i, label in
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(i < imp.stepIndex ? Color.chopGreen
                                              : i == imp.stepIndex ? Color.chopBlue : Color.chopPanel)
                                        .frame(width: 26, height: 26)
                                    if i < imp.stepIndex {
                                        Image(systemName: "checkmark")
                                            .font(.caption2.weight(.bold)).foregroundStyle(.black)
                                    } else if i == imp.stepIndex {
                                        ProgressView().scaleEffect(0.6).tint(.white)
                                    } else {
                                        Text("\(i + 1)").font(.caption2.weight(.bold))
                                            .foregroundStyle(Color.chopMuted)
                                    }
                                }
                                Text(label)
                                    .font(.subheadline)
                                    .foregroundStyle(i <= imp.stepIndex ? .white : Color.chopMuted)
                                Spacer()
                            }
                            .padding(.vertical, 7)
                        }
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.chopPanel)
                            Capsule().fill(chopGradient)
                                .frame(width: geo.size.width *
                                       CGFloat(max(0, min(6, imp.stepIndex))) / 6)
                        }
                    }
                    .frame(height: 6)

                    Text("Keep the app open — iOS pauses uploads in the background.")
                        .font(.caption2).foregroundStyle(Color.chopMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if imp.done {
                Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                Text("Chopped and saved").font(.subheadline)
                Text(imp.syncMsg.isEmpty ? "Uploading the full video in the background — you can review now."
                                         : imp.syncMsg)
                    .font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
            } else if api.credits <= 0 {
                Image(systemName: "bolt.slash").font(.largeTitle).foregroundStyle(.orange)
                Text("You're out of credits").font(.subheadline.weight(.medium))
                Text("One credit chops one video. Credits are managed on your Chop account.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Close") { dismiss() }
            } else {
                PhotosPicker(selection: $picked, matching: .videos) {
                    Label("Choose a video", systemImage: "video.badge.plus")
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
        .onChange(of: picked) { _, item in
            guard let item = item else { return }
            Task {
                guard let movie = try? await item.loadTransferable(type: ChopMovie.self) else {
                    imp.failed = "Couldn't read that video"; return
                }
                let df = DateFormatter()
                df.dateFormat = "d MMM, HH.mm"
                let friendly = "Chop " + df.string(from: Date()) + ".mp4"
                await imp.run(pickedURL: movie.url, name: friendly, api: api)
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


// MARK: - Settings

struct ChopSettingsView: View {
    @ObservedObject var api: ChopAPI
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false
    @State private var showProfile = false
    @State private var deleting = false
    @State private var failed = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    Button { showProfile = true } label: {
                        HStack { Text("Edit profile").foregroundStyle(.white); Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                                .foregroundStyle(Color.chopMuted) }
                    }
                    HStack { Text("Name"); Spacer()
                        Text(api.profileName.isEmpty ? "—" : api.profileName)
                            .foregroundStyle(.secondary) }
                    HStack { Text("Credits"); Spacer()
                        Text("\(api.credits)").foregroundStyle(.secondary) }
                }

                Section {
                    Link("Privacy policy", destination: URL(string: "https://chopedit.com/privacy.html")!)

                }

                Section {
                    Button("Sign out") { api.signOut(); dismiss() }
                }

                Section("Danger zone") {
                    Button(role: .destructive) {
                        confirming = true
                    } label: {
                        if deleting { ProgressView() } else { Text("Delete my account") }
                    }
                    .disabled(deleting)
                    Text("Permanently removes your profile, saved edits and any remaining credits. This cannot be undone.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !failed.isEmpty {
                        Text(failed).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .sheet(isPresented: $showProfile) { ChopProfileView(api: api) }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
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

    private let titles = ["Processing", "Ready to review", "Ready to export", "Downloaded"]
    private let empties = [
        "Nothing processing",
        "Nothing waiting for review",
        "Press Done in the editor to move a video here",
        "Exported videos land here so you never download twice"
    ]

    var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(0..<4, id: \.self) { i in
                        let list = api.jobs.filter { bucket($0) == i }
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(titles[i]).font(.subheadline.weight(.bold))
                                Text("\(list.count)")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Color.chopPanel, in: Capsule())
                                    .foregroundStyle(Color.chopMuted)
                                Spacer()
                            }
                            if list.isEmpty {
                                Text(empties[i]).font(.caption)
                                    .foregroundStyle(Color.chopMuted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .background(Color.chopPanel.opacity(0.5))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            } else {
                                ForEach(list) { job in
                                    NavigationLink { ChopPlayerScreen(job: job, api: api) } label: {
                                        QueueCard(job: job)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 90)
            }
    }
}

struct QueueCard: View {
    let job: ChopJob

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.black)
                if let img = job.thumbnail {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Image(systemName: "film").foregroundStyle(Color.chopMuted)
                }
            }
            .frame(width: 46, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(job.name).font(.subheadline.weight(.medium))
                    .lineLimit(1).foregroundStyle(.white)
                HStack(spacing: 6) {
                    if job.savedPct > 0 {
                        Text("\(job.savedPct)% shorter")
                            .font(.caption2.weight(.semibold)).foregroundStyle(Color.chopGreen)
                    }
                    if job.videoKey == nil {
                        Text("syncing…").font(.caption2).foregroundStyle(.orange)
                    }
                    if !job.hasAnalysis {
                        Text("no analysis").font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.chopMuted)
        }
        .padding(10)
        .background(Color.chopPanel)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.chopLine, lineWidth: 1))
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

    var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {

                    Text("Dial in your cutting style once — every video you drop gets chopped with these settings.")
                        .font(.footnote).foregroundStyle(Color.chopMuted)

                    HStack(spacing: 10) {
                        preset("Relaxed", "Keeps natural pauses", ChopPresets.relaxed)
                        preset("Balanced", "The Chop standard", ChopPresets.balanced)
                        preset("Snappy", "TikTok-tight", ChopPresets.snappy)
                    }

                    group("Fine-tune") {
                        slider("Remove silences over", value: $s.minSil,
                               range: 0.05...1.0, step: 0.05, fmt: { String(format: "%.2fs", $0) },
                               note: "Any pause longer than this is cut automatically.")

                        Toggle("Remove filler words", isOn: $s.fillers)
                            .font(.subheadline).tint(Color.chopBlue)
                        Text("um, uh, hmm…").font(.caption2).foregroundStyle(Color.chopMuted)

                        Toggle("Also soft fillers", isOn: $s.soft)
                            .font(.subheadline).tint(Color.chopBlue)
                        Text("like, you know, I mean — only when isolated")
                            .font(.caption2).foregroundStyle(Color.chopMuted)

                        slider("Clip start", value: $s.startPadMs,
                               range: -200...200, step: 10, fmt: { "\(Int($0))ms" },
                               note: "Positive keeps a little more before each clip.")

                        slider("Clip end", value: $s.endPadMs,
                               range: -200...200, step: 10, fmt: { "\(Int($0))ms" },
                               note: "Negative trims tighter after each clip.")
                    }

                    Button {
                        ChopPresets.save(s)
                        savedNote = true
                    } label: {
                        Text("Save as my default").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Color.chopBlue)

                    Button("Reset to Balanced") { s = ChopPresets.balanced }
                        .font(.footnote).foregroundStyle(Color.chopMuted)
                        .frame(maxWidth: .infinity)

                    if savedNote {
                        Text("Saved — every new video will use these settings")
                            .font(.caption).foregroundStyle(Color.chopGreen)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(16)
                .padding(.bottom, 90)
            }
    }

    private func preset(_ title: String, _ desc: String, _ v: ChopSettings) -> some View {
        let on = s.matches(v)
        return Button { s = v; savedNote = false } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption.weight(.bold)).foregroundStyle(on ? .white : Color.chopMuted)
                Text(desc).font(.system(size: 9)).foregroundStyle(Color.chopMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(on ? Color.chopBlue.opacity(0.22) : Color.chopPanel)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(on ? Color.chopBlue : Color.chopLine, lineWidth: 1))
        }
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

struct ChopProfileView: View {
    @ObservedObject var api: ChopAPI
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var tiktok = ""
    @State private var avatar = "e:💸:0"
    @State private var saving = false
    @State private var failed = ""

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
                                    .onTapGesture { avatar = key }
                            }
                        }
                    }

                    Button {
                        saving = true
                        Task {
                            let ok = await api.saveProfile(name: name, tiktok: tiktok, avatar: avatar)
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
                            .foregroundStyle(.white)
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
                    .foregroundStyle(on ? .white : Color.chopMuted)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.white)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(Color.chopBlue, in: Capsule())
                }
            }
            .padding(.horizontal, 15).padding(.vertical, 11)
            .background(on ? Color.white.opacity(0.10) : .clear, in: Capsule())
        }
    }
}
