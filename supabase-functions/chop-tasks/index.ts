// chop-tasks — the admin task board (Lewis + Aaron), SEPARATE function on
// purpose: the ai-edit function carries the locked retakes ladder and must
// not be redeployed for admin features. Same chop_admins allowlist gate.
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
    headers: {
      apikey: SRK, Authorization: `Bearer ${SRK}`, "Content-Type": "application/json",
      Prefer: "return=representation", ...(init.headers || {}),
    },
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

const STATUSES = ["todo", "doing", "review", "done"];
const clean = (v: unknown, max: number) => String(v ?? "").slice(0, max) || null;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  try {
    const body = await req.json().catch(() => ({}));
    const u = await callerUser(req);
    if (!u || !u.id) return json({ error: "sign in required" }, 401);
    if (!(await isAdmin(u.id))) return json({ error: "not authorised" }, 403);
    const op = body.op;

    if (op === "t_list") {
      return json({ items: await db(`chop_tasks?select=*&order=updated_at.desc`) });
    }
    if (op === "t_add") {
      const rows = await db(`chop_tasks`, { method: "POST", body: JSON.stringify({
        title: String(body.title || "").slice(0, 200),
        notes: clean(body.notes, 4000),
        status: STATUSES.includes(body.status) ? body.status : "todo",
        assignee: clean(body.assignee, 40),
        priority: ["low", "med", "high"].includes(body.priority) ? body.priority : "med",
        due: body.due || null,
        who: (u.email || "").split("@")[0],
      }) });
      return json({ item: rows[0] });
    }
    if (op === "t_upd") {
      const patch: Record<string, unknown> = { updated_at: new Date().toISOString() };
      if ("title" in body) patch.title = String(body.title || "").slice(0, 200);
      if ("notes" in body) patch.notes = clean(body.notes, 4000);
      if ("status" in body && STATUSES.includes(body.status)) patch.status = body.status;
      if ("assignee" in body) patch.assignee = clean(body.assignee, 40);
      if ("priority" in body && ["low", "med", "high"].includes(body.priority)) patch.priority = body.priority;
      if ("due" in body) patch.due = body.due || null;
      const rows = await db(`chop_tasks?id=eq.${Number(body.id)}`, { method: "PATCH", body: JSON.stringify(patch) });
      return json({ item: rows[0] });
    }
    if (op === "t_del") {
      await db(`chop_tasks?id=eq.${Number(body.id)}`, { method: "DELETE" });
      return json({ ok: true });
    }
    /* roadmap, board-style (chop_roadmap) — same gate, richer ops than the
       legacy rm_* handlers in ai-edit (which stay untouched) */
    if (op === "r_list") {
      return json({ items: await db(`chop_roadmap?select=*&order=created_at.desc`) });
    }
    if (op === "r_add") {
      const rows = await db(`chop_roadmap`, { method: "POST", body: JSON.stringify({
        title: String(body.title || "").slice(0, 200),
        tag: ["feat", "bug", "biz"].includes(body.tag) ? body.tag : "feat",
        status: ["backlog", "doing", "staged", "done"].includes(body.status) ? body.status : "backlog",
        notes: clean(body.notes, 1000),
        who: (u.email || "").split("@")[0],
      }) });
      return json({ item: rows[0] });
    }
    if (op === "r_upd") {
      const patch: Record<string, unknown> = {};
      if ("title" in body) patch.title = String(body.title || "").slice(0, 200);
      if ("tag" in body && ["feat", "bug", "biz"].includes(body.tag)) patch.tag = body.tag;
      if ("status" in body && ["backlog", "doing", "staged", "done"].includes(body.status)) patch.status = body.status;
      if ("notes" in body) patch.notes = clean(body.notes, 1000);
      const rows = await db(`chop_roadmap?id=eq.${Number(body.id)}`, { method: "PATCH", body: JSON.stringify(patch) });
      return json({ item: rows[0] });
    }
    if (op === "r_del") {
      await db(`chop_roadmap?id=eq.${Number(body.id)}`, { method: "DELETE" });
      return json({ ok: true });
    }
    /* admin accounts: profiles + team management (owner adds/removes) */
    if (op === "a_list") {
      const admins = await db(`chop_admins?select=user_id,role,name,avatar,created_at`);
      const ur = await fetch(`${SB_URL}/auth/v1/admin/users?per_page=1000`, { headers: { apikey: SRK, Authorization: `Bearer ${SRK}` } });
      const users = ((await ur.json()).users || []) as any[];
      const emailById: Record<string, string> = {}; users.forEach((x) => emailById[x.id] = x.email);
      const rows = admins.map((a: any) => ({ ...a, email: emailById[a.user_id] || null }));
      const me = rows.find((a: any) => a.user_id === u.id) || null;
      return json({ admins: rows, me });
    }
    if (op === "a_profile") {
      const patch: Record<string, unknown> = {};
      if ("name" in body) patch.name = clean(body.name, 60);
      if ("avatar" in body) patch.avatar = clean(body.avatar, 20);
      const rows = await db(`chop_admins?user_id=eq.${u.id}`, { method: "PATCH", body: JSON.stringify(patch) });
      return json({ me: rows[0] });
    }
    if (op === "a_add" || op === "a_del") {
      const meRow = (await db(`chop_admins?user_id=eq.${u.id}&select=role`))[0];
      if (!meRow || meRow.role !== "owner") return json({ error: "only the owner can manage admins" }, 403);
      if (op === "a_add") {
        const email = String(body.email || "").trim().toLowerCase();
        const ur = await fetch(`${SB_URL}/auth/v1/admin/users?per_page=1000`, { headers: { apikey: SRK, Authorization: `Bearer ${SRK}` } });
        const users = ((await ur.json()).users || []) as any[];
        const t = users.find((x) => (x.email || "").toLowerCase() === email);
        if (!t) return json({ error: "no Chop account with that email — they need to sign up in the app first" }, 404);
        await db(`chop_admins?on_conflict=user_id`, { method: "POST",
          headers: { Prefer: "resolution=merge-duplicates,return=representation" },
          body: JSON.stringify({ user_id: t.id, role: "admin", added_by: u.id }) });
        return json({ ok: true, email });
      }
      const target = String(body.user_id || "");
      const tRow = (await db(`chop_admins?user_id=eq.${target}&select=role`))[0];
      if (!tRow) return json({ error: "not an admin" }, 404);
      if (tRow.role === "owner") return json({ error: "the owner can't be removed" }, 400);
      await db(`chop_admins?user_id=eq.${target}`, { method: "DELETE" });
      return json({ ok: true });
    }
    if (op === "site_stats") {
      const now = Date.now();
      const d7 = new Date(now - 7 * 86400000).toISOString();
      const d30 = new Date(now - 30 * 86400000).toISOString();
      const ev = await db(`chop_site_events?select=type,created_at&created_at=gte.${d30}&limit=50000`);
      const cnt = (t: string, since: string) => ev.filter((e: any) => e.type === t && e.created_at >= since).length;
      const all = await db(`chop_site_events?select=type&limit=100000`);
      const perDay: Record<string, { v: number; c: number }> = {};
      ev.forEach((e: any) => { const k = e.created_at.slice(0, 10);
        const d = (perDay[k] ||= { v: 0, c: 0 }); if (e.type === "view") d.v++; else d.c++; });
      return json({
        views7: cnt("view", d7), clicks7: cnt("store_click", d7),
        views30: cnt("view", d30), clicks30: cnt("store_click", d30),
        viewsAll: all.filter((e: any) => e.type === "view").length,
        clicksAll: all.filter((e: any) => e.type === "store_click").length,
        perDay,
      });
    }
    return json({ error: "unknown op" }, 400);
  } catch (e) {
    return json({ error: String((e as Error)?.message || e) }, 500);
  }
});
