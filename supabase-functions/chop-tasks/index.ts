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
    return json({ error: "unknown op" }, 400);
  } catch (e) {
    return json({ error: String((e as Error)?.message || e) }, 500);
  }
});
