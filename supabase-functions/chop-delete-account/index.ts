// chop-delete-account — permanently deletes the signed-in user's account.
// Apple require in-app account deletion (App Store Review Guideline 5.1.1(v)).
//
// Secrets: SUPABASE_SERVICE_ROLE_KEY is injected by Supabase automatically.
// Deploy with Verify JWT ON — only a signed-in user can delete themselves.
//
// Purchases are kept but anonymised: we null the user_id rather than deleting
// the row, so takings still reconcile. Nothing in chop_purchases identifies a
// person once user_id is gone.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY     = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });

const svc = (path: string, init: RequestInit = {}) =>
  fetch(`${SUPABASE_URL}${path}`, {
    ...init,
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      "Content-Type": "application/json",
      ...(init.headers ?? {}),
    },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  try {
    const auth = req.headers.get("Authorization") ?? "";
    if (!auth.startsWith("Bearer ")) return json({ error: "Not signed in" }, 401);

    const ures = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: { Authorization: auth, apikey: ANON_KEY },
    });
    if (!ures.ok) return json({ error: "Not signed in" }, 401);
    const user = await ures.json();
    const id = user?.id;
    if (!id) return json({ error: "Not signed in" }, 401);

    // 1. the user's saved jobs (metadata + any cloud video keys)
    await svc(`/rest/v1/chop_jobs?user_id=eq.${id}`, { method: "DELETE" });

    // 2. anonymise purchase history, keep the financial record
    await svc(`/rest/v1/chop_purchases?user_id=eq.${id}`, {
      method: "PATCH",
      body: JSON.stringify({ user_id: null }),
    });

    // 3. profile (name, avatar, tiktok handle, credits)
    await svc(`/rest/v1/chop_profiles?id=eq.${id}`, { method: "DELETE" });

    // 4. the auth user itself — this is the irreversible bit
    const del = await svc(`/auth/v1/admin/users/${id}`, { method: "DELETE" });
    if (!del.ok) {
      const t = await del.text();
      console.error("chop-delete-account: auth delete failed", del.status, t);
      return json({ error: "Couldn't delete the account. Nothing was removed." }, 500);
    }

    console.info("chop-delete-account: deleted", id);
    return json({ ok: true });
  } catch (e) {
    console.error("chop-delete-account", e);
    return json({ error: "Something went wrong." }, 500);
  }
});
