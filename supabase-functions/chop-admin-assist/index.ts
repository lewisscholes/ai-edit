// chop-admin-assist — the admin copilot (bottom-right of chopedit.com/admin).
// Talks over REAL business data via tools: live stats, user lookup, and task
// creation on the shared Lewis+Aaron board. Admin-gated via chop_admins.
// Separate function on purpose — ai-edit (locked retakes) is never redeployed.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SRK = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

async function db(path: string, init: RequestInit = {}) {
  const r = await fetch(`${SB_URL}/rest/v1/${path}`, {
    ...init,
    headers: { apikey: SRK, Authorization: `Bearer ${SRK}`, "Content-Type": "application/json",
      Prefer: "return=representation", ...(init.headers || {}) },
  });
  if (!r.ok) throw new Error(`db ${r.status}: ${await r.text()}`);
  return r.json();
}
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
async function allUsers() {
  const r = await fetch(`${SB_URL}/auth/v1/admin/users?per_page=1000`, { headers: { apikey: SRK, Authorization: `Bearer ${SRK}` } });
  return ((await r.json()).users || []) as any[];
}

/* ---------------- tools ---------------- */
const TOOLS = [
  { name: "get_stats",
    description: "Live Chop business stats for the last N days: signups, videos edited, exports, credits bought, revenue, launch-offer claims, website visitors and App Store clicks, per-day breakdown, all-time totals.",
    input_schema: { type: "object", properties: { days: { type: "number", description: "How many days back (default 7)" } } } },
  { name: "create_task",
    description: "Create a task on the shared Lewis+Aaron board. Use when an admin asks you to add/create a task or assign something.",
    input_schema: { type: "object", properties: {
      title: { type: "string" }, assignee: { type: "string", enum: ["Lewis", "Aaron", "Both"] },
      due: { type: "string", description: "YYYY-MM-DD" }, priority: { type: "string", enum: ["low", "med", "high"] },
      notes: { type: "string" }, status: { type: "string", enum: ["todo", "doing", "review", "done"] },
    }, required: ["title"] } },
  { name: "list_tasks", description: "Read the current shared task board (all columns).",
    input_schema: { type: "object", properties: {} } },
  { name: "find_user",
    description: "Look up Chop users by email or name fragment: credits, videos edited, spend, signup date, last activity.",
    input_schema: { type: "object", properties: { q: { type: "string" } }, required: ["q"] } },
];

async function runTool(name: string, input: any, who: string, actions: any[]) {
  if (name === "get_stats") {
    const days = Math.min(365, Math.max(1, Number(input.days) || 7));
    const since = new Date(Date.now() - days * 86400000);
    const sinceIso = since.toISOString();
    const users = await allUsers();
    const jobs = await db(`chop_jobs?select=created_at,status:data->>status,statusAt:data->statusAt&limit=5000`);
    const purchases = await db(`chop_purchases?select=credits,pence,created_at`);
    const offer = (await db(`chop_offer?select=cap,claimed,offer_credits,default_credits&id=eq.1`))[0] || null;
    let site: any = null;
    try {
      const ev = await db(`chop_site_events?select=type,created_at&created_at=gte.${sinceIso}&limit=20000`);
      site = { visitors: ev.filter((e: any) => e.type === "view").length,
               store_clicks: ev.filter((e: any) => e.type === "store_click").length };
    } catch (_e) { /* table may not exist yet */ }
    const inR = (iso: string | null) => iso ? new Date(iso) >= since : false;
    const perDay: Record<string, { signups: number; edited: number }> = {};
    users.forEach((u2) => { if (inR(u2.created_at)) { const k = u2.created_at.slice(0, 10); (perDay[k] ||= { signups: 0, edited: 0 }).signups++; } });
    jobs.forEach((j: any) => { if (inR(j.created_at)) { const k = j.created_at.slice(0, 10); (perDay[k] ||= { signups: 0, edited: 0 }).edited++; } });
    return {
      range_days: days,
      signups: users.filter((u2) => inR(u2.created_at)).length,
      videos_edited: jobs.filter((j: any) => inR(j.created_at)).length,
      videos_exported: jobs.filter((j: any) => j.status === "exported" && j.statusAt && Number(j.statusAt) >= since.getTime()).length,
      credits_bought: purchases.filter((p: any) => inR(p.created_at)).reduce((a: number, p: any) => a + (p.credits || 0), 0),
      revenue_pence: purchases.filter((p: any) => inR(p.created_at)).reduce((a: number, p: any) => a + (p.pence || 0), 0),
      website: site,
      all_time: { users: users.length, videos: jobs.length,
        revenue_pence: purchases.reduce((a: number, p: any) => a + (p.pence || 0), 0) },
      launch_offer: offer, per_day: perDay,
    };
  }
  if (name === "create_task") {
    const rows = await db(`chop_tasks`, { method: "POST", body: JSON.stringify({
      title: String(input.title || "").slice(0, 200),
      notes: String(input.notes || "").slice(0, 4000) || null,
      status: ["todo", "doing", "review", "done"].includes(input.status) ? input.status : "todo",
      assignee: ["Lewis", "Aaron", "Both"].includes(input.assignee) ? input.assignee : null,
      priority: ["low", "med", "high"].includes(input.priority) ? input.priority : "med",
      due: /^\d{4}-\d{2}-\d{2}$/.test(input.due || "") ? input.due : null,
      who: who + " (via assistant)",
    }) });
    actions.push({ type: "task_created", title: rows[0].title });
    return { created: rows[0] };
  }
  if (name === "list_tasks") {
    return { tasks: await db(`chop_tasks?select=id,title,status,assignee,priority,due,who&order=updated_at.desc&limit=100`) };
  }
  if (name === "find_user") {
    const q = String(input.q || "").trim().toLowerCase();
    const users = (await allUsers()).filter((u2) => (u2.email || "").toLowerCase().includes(q)).slice(0, 10);
    if (!users.length) return { users: [] };
    const ids = users.map((u2) => u2.id);
    const profiles = await db(`chop_profiles?id=in.(${ids.join(",")})&select=id,name,credits`);
    const jobs = await db(`chop_jobs?user_id=in.(${ids.join(",")})&select=user_id,updated_at`);
    const pById: Record<string, any> = {}; profiles.forEach((p: any) => pById[p.id] = p);
    const vids: Record<string, { n: number; last: string }> = {};
    jobs.forEach((j: any) => { const v = (vids[j.user_id] ||= { n: 0, last: "" }); v.n++; if ((j.updated_at || "") > v.last) v.last = j.updated_at; });
    return { users: users.map((u2) => ({ email: u2.email, signed_up: u2.created_at,
      name: pById[u2.id]?.name || null, credits: pById[u2.id]?.credits ?? 0,
      videos: vids[u2.id]?.n || 0, last_active: vids[u2.id]?.last || null })) };
  }
  return { error: "unknown tool" };
}

/* ---------------- chat loop ---------------- */
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  try {
    const body = await req.json().catch(() => ({}));
    const u = await callerUser(req);
    if (!u || !u.id) return json({ error: "sign in required" }, 401);
    if (!(await isAdmin(u.id))) return json({ error: "not authorised" }, 403);
    const who = (u.email || "").split("@")[0];

    const key = Deno.env.get("ANTHROPIC_API_KEY");
    if (!key) return json({ error: "ANTHROPIC_API_KEY not set" }, 500);

    const today = new Date().toISOString().slice(0, 10);
    const SYSTEM = `You are the Chop admin assistant, living in the corner of the Chop admin dashboard. You're talking to ${who} (the admins are Lewis and Aaron, founders of Chop — an iOS app that auto-edits talking-head videos for TikTok Shop affiliates).

Today is ${today}. The admins are British: dates they say like "04/10" are DD/MM — resolve to the next future occurrence and pass tools YYYY-MM-DD.

You have LIVE tools: real business stats, user lookup, the shared task board, and task creation. Use them rather than guessing — never invent numbers. When asked about performance, pull the stats, then add one or two sharp, practical observations or suggestions (you know the business: credits are the revenue, signups convert via 3 free edits, the first 10 signups got 10, the site sells the iOS app).

When asked to create a task, just create it with sensible defaults (todo, med priority) and confirm in one line — don't interrogate for missing fields.

Style: brisk, useful, British. Short answers — this is a small chat widget. Plain text only, no markdown headers or bullets unless listing tasks/numbers.`;

    const raw = Array.isArray(body.messages) ? body.messages : [];
    const messages: any[] = raw
      .filter((m: any) => m && (m.role === "user" || m.role === "assistant") && typeof m.content === "string" && m.content.trim())
      .slice(-16)
      .map((m: any) => ({ role: m.role, content: String(m.content).slice(0, 1500) }));
    if (!messages.length || messages[messages.length - 1].role !== "user") {
      return json({ error: "messages must end with a user turn" }, 400);
    }

    const actions: any[] = [];
    let reply = "";
    for (let round = 0; round < 5; round++) {
      const resp = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: { "content-type": "application/json", "x-api-key": key, "anthropic-version": "2023-06-01" },
        body: JSON.stringify({
          model: Deno.env.get("ADMIN_ASSIST_MODEL") || "claude-haiku-4-5",
          max_tokens: 700, system: SYSTEM, tools: TOOLS, messages,
        }),
      });
      if (!resp.ok) return json({ error: "AI error: " + (await resp.text()).slice(0, 200) }, 502);
      const ai = await resp.json();
      const toolUses = (ai.content || []).filter((c: any) => c.type === "tool_use");
      const texts = (ai.content || []).filter((c: any) => c.type === "text").map((c: any) => c.text);
      if (!toolUses.length) { reply = texts.join("\n").trim(); break; }
      messages.push({ role: "assistant", content: ai.content });
      const results: any[] = [];
      for (const t of toolUses) {
        let out;
        try { out = await runTool(t.name, t.input || {}, who, actions); }
        catch (e) { out = { error: String((e as Error)?.message || e) }; }
        results.push({ type: "tool_result", tool_use_id: t.id, content: JSON.stringify(out).slice(0, 12000) });
      }
      messages.push({ role: "user", content: results });
    }
    if (!reply) reply = actions.length ? "Done." : "Sorry — I got stuck on that one. Try rephrasing?";
    return json({ reply, actions });
  } catch (e) {
    return json({ error: String((e as Error)?.message || e) }, 500);
  }
});
