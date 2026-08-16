import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { AwsClient } from "npm:aws4fetch@1.0.20";

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SRK = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const DG_KEY = Deno.env.get("DEEPGRAM_API_KEY")!;
const R2_ID = Deno.env.get("R2_ACCOUNT_ID")!;
const R2_AK = Deno.env.get("R2_ACCESS_KEY_ID")!;
const R2_SK = Deno.env.get("R2_SECRET_ACCESS_KEY")!;
const BUCKET = "ai-edit";
const RETAKE_THRESHOLD = 0.7;
const WEAK_THRESHOLD = 0.5;
const SHORT_THRESHOLD = 0.85;
const MIN_GAP = 0.03;

function r2Client() {
  return new AwsClient({ accessKeyId: R2_AK, secretAccessKey: R2_SK, service: "s3", region: "auto" });
}
async function presign(method: string, key: string, expires = 3600): Promise<string> {
  const url = new URL(`https://${R2_ID}.r2.cloudflarestorage.com/${BUCKET}/${key}`);
  url.searchParams.set("X-Amz-Expires", String(expires));
  const signed = await r2Client().sign(new Request(url.toString(), { method }), { aws: { signQuery: true } });
  return signed.url;
}

async function db(path: string, init: RequestInit = {}) {
  const r = await fetch(`${SB_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: SRK, Authorization: `Bearer ${SRK}`, "Content-Type": "application/json",
      Prefer: "return=representation", ...(init.headers || {}),
    },
  });
  if (!r.ok) throw new Error(`db ${r.status}: ${await r.text()}`);
  return r.json();
}

const HARD_FILLERS = new Set(["um","uh","er","ah","hmm","mhmm","mm","uhh","umm","erm","mhm","huh"]);
const SOFT_FILLERS = new Set(["like","so","actually","basically","literally","right"]);
const LEAD_IN = new Set(["and","but","so","okay","ok","now","also","then","well","yeah"]);

type Word = { word: string; punctuated_word?: string; start: number; end: number };
type Seg = { id: number; start: number; end: number; kind: string; text: string; soft: boolean; retake: string | null; pair: number | null; manual: null };

function cleanWord(w: string) { return w.toLowerCase().replace(/[^a-z0-9']/g, ""); }

function buildSegments(words: Word[], duration: number) {
  type Item = { start: number; end: number; kind: "speech" | "filler"; soft: boolean; texts: string[] };
  const items: Item[] = [];
  for (let i = 0; i < words.length; i++) {
    const w = words[i];
    const cw = cleanWord(w.word);
    const gapBefore = i === 0 ? w.start : w.start - words[i - 1].end;
    const gapAfter = i === words.length - 1 ? duration - w.end : words[i + 1].start - w.end;
    let kind: "speech" | "filler" = "speech"; let soft = false;
    if (HARD_FILLERS.has(cw)) kind = "filler";
    else if (SOFT_FILLERS.has(cw) && gapBefore >= 0.15 && gapAfter >= 0.15) { kind = "filler"; soft = true; }
    if (cw === "you" && i + 1 < words.length && cleanWord(words[i + 1].word) === "know") {
      const gA = i + 2 < words.length ? words[i + 2].start - words[i + 1].end : duration - words[i + 1].end;
      if (gapBefore >= 0.15 && gA >= 0.15) {
        items.push({ start: w.start, end: words[i + 1].end, kind: "filler", soft: true, texts: ["you know"] });
        i++; continue;
      }
    }
    const txt = (w.punctuated_word || w.word);
    const last = items[items.length - 1];
    if (last && last.kind === kind && last.soft === soft && kind === "speech" && w.start - last.end < MIN_GAP) {
      last.end = w.end; last.texts.push(txt);
    } else {
      items.push({ start: w.start, end: w.end, kind, soft, texts: [txt] });
    }
  }
  const segs: Seg[] = [];
  let cursor = 0;
  const pushSil = (s: number, e: number) => { if (e - s > 0.01) segs.push({ id: 0, start: s, end: e, kind: "silence", text: "", soft: false, retake: null, pair: null, manual: null }); };
  for (let i = 0; i < items.length; i++) {
    const it = items[i];
    let start = it.start;
    const gap = start - cursor;
    if (gap >= MIN_GAP) pushSil(cursor, start);
    else if (gap > 0) {
      if (it.kind === "filler") start = cursor;
      else if (segs.length && segs[segs.length - 1].kind === "filler") segs[segs.length - 1].end = start;
      else if (segs.length) segs[segs.length - 1].end = start;
      else start = cursor;
    }
    segs.push({ id: 0, start, end: it.end, kind: it.kind, text: it.texts.join(" "), soft: it.soft, retake: null, pair: null, manual: null });
    cursor = it.end;
  }
  if (duration - cursor >= MIN_GAP) pushSil(cursor, duration);
  else if (segs.length) segs[segs.length - 1].end = Math.max(cursor, duration);
  segs.forEach((s, i) => (s.id = i));
  return segs;
}

function normTokens(s: string) {
  return s.toLowerCase().replace(/[^a-z0-9' ]+/g, " ").split(/\s+/).filter((w) => w && !HARD_FILLERS.has(w));
}
function compTokens(s: string) {
  const t = normTokens(s);
  while (t.length > 2 && LEAD_IN.has(t[0])) t.shift();
  return t;
}
function levSim(a: string[], b: string[]) {
  const m = a.length, n = b.length; if (!m || !n) return 0;
  const dp: number[][] = Array.from({ length: m + 1 }, (_, i) => { const r = new Array(n + 1).fill(0); r[0] = i; return r; });
  for (let j = 0; j <= n; j++) dp[0][j] = j;
  for (let i = 1; i <= m; i++) for (let j = 1; j <= n; j++)
    dp[i][j] = Math.min(dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
  return 1 - dp[m][n] / Math.max(m, n);
}
function prefixOverlap(a: string[], b: string[]) {
  const n = Math.min(a.length, b.length); if (!n) return 0;
  let k = 0; while (k < n && a[k] === b[k]) k++;
  return k / n;
}
function leadRun(a: string[], b: string[]) {   // identical opening words, absolute count
  const n = Math.min(a.length, b.length);
  let k = 0; while (k < n && a[k] === b[k]) k++;
  return k;
}

type Utt = { start: number; end: number; transcript: string };
function detectRetakes(utts: Utt[]) {
  const toks = utts.map((u) => compTokens(u.transcript));
  const parent = utts.map((_, i) => i);
  const find = (x: number): number => (parent[x] === x ? x : (parent[x] = find(parent[x])));
  const scores: Record<string, number> = {};
  const weakCand: { i: number; j: number; score: number }[] = [];
  for (let i = 0; i < utts.length; i++) {
    if (toks[i].length < 2) continue;
    for (let j = i + 1; j <= Math.min(i + 3, utts.length - 1); j++) {
      if (toks[j].length < 2) continue;
      const short = Math.min(toks[i].length, toks[j].length) < 3;
      const score = Math.max(levSim(toks[i], toks[j]), prefixOverlap(toks[i], toks[j]));
      const lead = leadRun(toks[i], toks[j]);
      const strongTh = short ? SHORT_THRESHOLD : RETAKE_THRESHOLD;
      if (score >= strongTh) { const a = find(i), b = find(j); if (a !== b) parent[b] = a; scores[`${i}-${j}`] = score; }
      /* the 'potential retake' net: a weak overall score still gets flagged
         for review when it clears 0.5, OR when both takes OPEN with the same
         3+ words — restarts share their opening even when the rest diverges */
      else if (!short && (score >= WEAK_THRESHOLD || lead >= 3)) {
        weakCand.push({ i, j, score: Math.max(score, 0.5) });
      }
    }
  }
  const groups: Record<number, number[]> = {};
  for (let i = 0; i < utts.length; i++) { const r = find(i); (groups[r] ||= []).push(i); }
  const out: { members: number[]; sim: number; weak?: boolean }[] = [];
  const inStrong = new Set<number>();
  for (const g of Object.values(groups)) {
    if (g.length < 2) continue;
    g.forEach((m) => inStrong.add(m));
    g.sort((a, b) => utts[a].start - utts[b].start);
    let best = 0;
    for (const k of Object.keys(scores)) { const [a, b] = k.split("-").map(Number); if (g.includes(a) && g.includes(b)) best = Math.max(best, scores[k]); }
    out.push({ members: g, sim: Math.round(best * 100) / 100 });
  }
  weakCand.sort((a, b) => b.score - a.score);
  const usedWeak = new Set<number>();
  for (const c of weakCand) {
    if (inStrong.has(c.i) || inStrong.has(c.j) || usedWeak.has(c.i) || usedWeak.has(c.j)) continue;
    usedWeak.add(c.i); usedWeak.add(c.j);
    out.push({ members: [c.i, c.j], sim: Math.round(c.score * 100) / 100, weak: true });
  }
  out.sort((a, b) => utts[a.members[0]].start - utts[b.members[0]].start);
  return out;
}

function applyRetakes(segs: Seg[], utts: Utt[], groups: { members: number[]; sim: number; weak?: boolean }[]) {
  const kept: { sim: number; weak: boolean }[] = [];
  groups.forEach((g) => {
    const gi = kept.length;
    const lastIdx = g.members[g.members.length - 1];
    let hasA = false, hasB = false;
    const marked: Seg[] = [];
    for (const m of g.members) {
      const u = utts[m];
      for (const s of segs) {
        if (s.kind !== "speech") continue;
        const ov = Math.min(s.end, u.end) - Math.max(s.start, u.start);
        if (ov > 0.5 * (s.end - s.start)) {
          s.retake = m === lastIdx ? "b" : "a"; s.pair = gi; marked.push(s);
          if (m === lastIdx) hasB = true; else hasA = true;
        }
      }
    }
    if (hasA && hasB) kept.push({ sim: g.sim, weak: !!g.weak });
    else marked.forEach((s) => { s.retake = null; s.pair = null; });
  });
  return kept;
}

/* Deepgram's 0.4s utterance split merges a quick false start ("this bundle
   is—") straight into the retake that follows it, so the pair never forms and
   an obvious retake gets missed. Rebuild utterances from word timings with a
   tighter 0.28s gap, unioned with Deepgram's own boundaries. This feeds
   RETAKE DETECTION ONLY — the cut logic never sees these. */
function buildUtterances(words: Word[], dgUtts: Utt[]): Utt[] {
  if (!words.length) return dgUtts;
  const bounds = new Set(dgUtts.map((u) => Math.round(u.start * 1000)));
  const out: Utt[] = [];
  let cur: Word[] = [];
  const flush = () => {
    if (!cur.length) return;
    out.push({ start: cur[0].start, end: cur[cur.length - 1].end,
               transcript: cur.map((w) => w.punctuated_word || w.word).join(" ") });
    cur = [];
  };
  for (const w of words) {
    if (cur.length) {
      const gap = w.start - cur[cur.length - 1].end;
      if (gap >= 0.28 || bounds.has(Math.round(w.start * 1000))) flush();
    }
    cur.push(w);
  }
  flush();
  return out;
}

async function processJob(jobId: string, key: string) {
  try {
    const getUrl = await presign("GET", key, 7200);
    const dgParams = "model=nova-3&filler_words=true&utterances=true&utt_split=0.4&punctuate=true";
    const dg = await fetch(`https://api.deepgram.com/v1/listen?${dgParams}`, {
      method: "POST",
      headers: { Authorization: `Token ${DG_KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify({ url: getUrl }),
    });
    if (!dg.ok) throw new Error(`Deepgram ${dg.status}: ${await dg.text()}`);
    const res = await dg.json();
    const duration: number = res.metadata?.duration ?? 0;
    const words: Word[] = res.results?.channels?.[0]?.alternatives?.[0]?.words ?? [];
    const dgUtts: Utt[] = (res.results?.utterances ?? []).map((u: any) => ({ start: u.start, end: u.end, transcript: u.transcript }));
    const utts = buildUtterances(words, dgUtts);
    if (!words.length) throw new Error("No speech detected in this video");
    const segs = buildSegments(words, duration);
    const groups = detectRetakes(utts);
    const pairs = applyRetakes(segs, utts, groups);
    await db(`ai_edit_jobs?id=eq.${jobId}`, { method: "PATCH", body: JSON.stringify({ status: "done", duration, segments: segs, pairs }) });
  } catch (e) {
    await db(`ai_edit_jobs?id=eq.${jobId}`, { method: "PATCH", body: JSON.stringify({ status: "error", error: String(e).slice(0, 500) }) }).catch(() => {});
  }
}

/* ---------- ADMIN (additive): allowlisted via chop_admins ---------- */
async function callerUser(req: Request) {
  const auth = req.headers.get("Authorization") || "";
  const r = await fetch(`${SB_URL}/auth/v1/user`, { headers: { Authorization: auth, apikey: SRK } });
  if (!r.ok) return null;
  return await r.json();
}
async function isAdmin(uid: string) {
  const rows = await db(`chop_admins?user_id=eq.${uid}&select=user_id`);
  return rows.length > 0;
}
function dayKey(d: Date) { return d.toISOString().slice(0, 10); }

async function adminHandler(body: any, req: Request) {
  const u = await callerUser(req);
  if (!u || !u.id) return json({ error: "sign in required" }, 401);
  if (!(await isAdmin(u.id))) return json({ error: "not authorised" }, 403);
  const op = body.op;

  if (op === "ping") return json({ ok: true, email: u.email });

  if (op === "stats") {
    const from = new Date(body.from), to = new Date(body.to);
    const fromIso = from.toISOString(), toIso = to.toISOString();
    const ur = await fetch(`${SB_URL}/auth/v1/admin/users?per_page=1000`, { headers: { apikey: SRK, Authorization: `Bearer ${SRK}` } });
    const users = ((await ur.json()).users || []) as any[];
    const jobs = await db(`chop_jobs?select=user_id,name,created_at,updated_at,status:data->>status,statusAt:data->statusAt&limit=5000`);
    const profiles = await db(`chop_profiles?select=id,name,avatar,credits`);
    const purchases = await db(`chop_purchases?select=credits,pence,created_at&created_at=gte.${fromIso}&created_at=lte.${toIso}`);
    const logs = await db(`chop_client_logs?select=msg,ctx,ua,created_at&order=created_at.desc&limit=10`);

    const inR = (iso: string | null) => { if (!iso) return false; const t = new Date(iso).getTime(); return t >= from.getTime() && t <= to.getTime(); };
    const signups = users.filter((x) => inR(x.created_at)).length;
    const edited = jobs.filter((j: any) => inR(j.created_at)).length;
    const published = jobs.filter((j: any) => j.status === "exported" && j.statusAt && Number(j.statusAt) >= from.getTime() && Number(j.statusAt) <= to.getTime()).length;
    const credBought = purchases.reduce((a: number, p: any) => a + (p.credits || 0), 0);
    const penceBought = purchases.reduce((a: number, p: any) => a + (p.pence || 0), 0);

    const series: Record<string, { s: number; e: number }> = {};
    for (let d = new Date(from); d <= to; d = new Date(d.getTime() + 86400000)) series[dayKey(d)] = { s: 0, e: 0 };
    users.forEach((x) => { const k = (x.created_at || "").slice(0, 10); if (series[k] && inR(x.created_at)) series[k].s++; });
    jobs.forEach((j: any) => { const k = (j.created_at || "").slice(0, 10); if (series[k] && inR(j.created_at)) series[k].e++; });

    const byUser: Record<string, { n: number; last: string }> = {};
    jobs.forEach((j: any) => { const b = (byUser[j.user_id] ||= { n: 0, last: "" }); b.n++; if ((j.updated_at || "") > b.last) b.last = j.updated_at || ""; });
    const emailById: Record<string, string> = {}; users.forEach((x) => emailById[x.id] = x.email);
    const creators = profiles.map((p: any) => ({
      id: p.id, name: p.name || emailById[p.id] || "creator", avatar: p.avatar || null,
      credits: p.credits, videos: (byUser[p.id] || {}).n || 0, last: (byUser[p.id] || {}).last || null,
    })).sort((a: any, b: any) => b.videos - a.videos);

    return json({ signups, edited, published, credBought, penceBought,
      totalUsers: users.length, totalJobs: jobs.length,
      series: Object.entries(series).map(([k, v]) => ({ d: k, ...v })), creators, logs });
  }

  /* ---- customers & credits ---- */

  if (op === "user_find") {
    const q = String(body.q || "").trim().toLowerCase();
    const ur = await fetch(`${SB_URL}/auth/v1/admin/users?per_page=1000`, { headers: { apikey: SRK, Authorization: `Bearer ${SRK}` } });
    const all = ((await ur.json()).users || []) as any[];
    const hits = (q ? all.filter((x) => (x.email || "").toLowerCase().includes(q)) : all).slice(0, 25);
    if (!hits.length) return json({ users: [] });
    const ids = hits.map((h) => h.id);
    const inList = `(${ids.join(",")})`;
    const profiles = await db(`chop_profiles?id=in.${inList}&select=id,name,credits,avatar`);
    const jobs = await db(`chop_jobs?user_id=in.${inList}&select=user_id,updated_at,status:data->>status&limit=5000`);
    const pur = await db(`chop_purchases?user_id=in.${inList}&select=user_id,credits,pence`);
    const pById: Record<string, any> = {}; profiles.forEach((p: any) => pById[p.id] = p);
    const agg: Record<string, { videos: number; exported: number; last: string }> = {};
    jobs.forEach((j: any) => {
      const a = (agg[j.user_id] ||= { videos: 0, exported: 0, last: "" });
      a.videos++; if (j.status === "exported") a.exported++;
      if ((j.updated_at || "") > a.last) a.last = j.updated_at || "";
    });
    const spend: Record<string, { credits: number; pence: number }> = {};
    pur.forEach((x: any) => { const s2 = (spend[x.user_id] ||= { credits: 0, pence: 0 }); s2.credits += x.credits || 0; s2.pence += x.pence || 0; });
    return json({ users: hits.map((h) => ({
      id: h.id, email: h.email, created_at: h.created_at, last_sign_in: h.last_sign_in_at,
      name: pById[h.id]?.name || null, avatar: pById[h.id]?.avatar || null,
      credits: pById[h.id]?.credits ?? 0,
      videos: agg[h.id]?.videos || 0, exported: agg[h.id]?.exported || 0, last_active: agg[h.id]?.last || null,
      bought_credits: spend[h.id]?.credits || 0, spent_pence: spend[h.id]?.pence || 0,
    })) });
  }

  if (op === "credit_grant") {
    const target = String(body.user_id || "");
    const delta = Math.trunc(Number(body.delta));
    if (!target) return json({ error: "user_id required" }, 400);
    if (!Number.isFinite(delta) || delta === 0) return json({ error: "delta must be a non-zero whole number" }, 400);
    if (Math.abs(delta) > 1000) return json({ error: "delta capped at 1000 — do it in smaller steps if you really mean it" }, 400);
    const rows = await db(`rpc/chop_admin_grant`, {
      method: "POST",
      body: JSON.stringify({ p_user: target, p_delta: delta, p_note: String(body.note || "").slice(0, 200) || null, p_actor: u.id }),
    });
    return json({ balance: rows });
  }

  if (op === "credit_history") {
    const target = String(body.user_id || "");
    if (!target) return json({ error: "user_id required" }, 400);
    const rows = await db(`chop_credit_ledger?user_id=eq.${target}&select=delta,balance_after,reason,note,actor,created_at&order=created_at.desc&limit=50`);
    return json({ entries: rows });
  }

  if (op === "rm_list") return json({ items: await db(`chop_roadmap?select=*&order=created_at.desc`) });
  if (op === "rm_add") {
    const rows = await db(`chop_roadmap`, { method: "POST", body: JSON.stringify({ title: String(body.title || "").slice(0, 200), tag: body.tag || "feat", status: "backlog", who: (u.email || "").split("@")[0], notes: String(body.notes || "").slice(0, 1000) || null }) });
    return json({ item: rows[0] });
  }
  if (op === "rm_note") {
    await db(`chop_roadmap?id=eq.${Number(body.id)}`, { method: "PATCH", body: JSON.stringify({ notes: String(body.notes || "").slice(0, 1000) || null }) });
    return json({ ok: true });
  }
  if (op === "rm_move") {
    await db(`chop_roadmap?id=eq.${Number(body.id)}`, { method: "PATCH", body: JSON.stringify({ status: String(body.status) }) });
    return json({ ok: true });
  }
  if (op === "rm_del") {
    await db(`chop_roadmap?id=eq.${Number(body.id)}`, { method: "DELETE" });
    return json({ ok: true });
  }
  if (op === "add_admin") {
    const ur2 = await fetch(`${SB_URL}/auth/v1/admin/users?per_page=1000`, { headers: { apikey: SRK, Authorization: `Bearer ${SRK}` } });
    const all = ((await ur2.json()).users || []) as any[];
    const t = all.find((x) => (x.email || "").toLowerCase() === String(body.email || "").toLowerCase());
    if (!t) return json({ error: "no account with that email" }, 404);
    await db(`chop_admins`, { method: "POST", headers: { Prefer: "resolution=ignore-duplicates" }, body: JSON.stringify({ user_id: t.id }) });
    return json({ ok: true });
  }
  return json({ error: "unknown op" }, 400);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  let body: any;
  try { body = await req.json(); } catch { return json({ error: "bad json" }, 400); }

  try {
    if (body.action === "presign") {
      const safe = String(body.filename || "video.mp4").replace(/[^a-zA-Z0-9._-]/g, "_").slice(-80);
      const key = `uploads/${Date.now()}-${crypto.randomUUID().slice(0, 8)}-${safe}`;
      const uploadUrl = await presign("PUT", key, 3600);
      return json({ uploadUrl, key });
    }
    if (body.action === "presign_get") {
      if (!body.key || !String(body.key).startsWith("uploads/")) return json({ error: "bad key" }, 400);
      const url = await presign("GET", String(body.key), 7200);
      return json({ url });
    }
    if (body.action === "presign_delete") {
      // additive: lets the apps clean old Downloaded videos out of R2
      if (!body.key || !String(body.key).startsWith("uploads/")) return json({ error: "bad key" }, 400);
      const url = await presign("DELETE", String(body.key), 600);
      return json({ url });
    }
    if (body.action === "process") {
      if (!body.key || !String(body.key).startsWith("uploads/")) return json({ error: "bad key" }, 400);
      const rows = await db("ai_edit_jobs", { method: "POST", body: JSON.stringify({ key: body.key, status: "processing" }) });
      const jobId = rows[0].id;
      EdgeRuntime.waitUntil(processJob(jobId, body.key));
      return json({ jobId });
    }
    if (body.action === "status") {
      const rows = await db(`ai_edit_jobs?id=eq.${encodeURIComponent(body.jobId)}&select=status,duration,segments,pairs,error`);
      if (!rows.length) return json({ error: "not found" }, 404);
      return json(rows[0]);
    }
    if (body.action === "admin") return await adminHandler(body, req);
    return json({ error: "unknown action" }, 400);
  } catch (e) {
    return json({ error: String(e).slice(0, 500) }, 500);
  }
});
