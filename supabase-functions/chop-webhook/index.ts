// chop-webhook — receives Stripe events and grants credits.
//
// Secrets required (Supabase > Edge Functions > Secrets):
//   STRIPE_WEBHOOK_SECRET      whsec_... from the Stripe webhook endpoint
//   SUPABASE_SERVICE_ROLE_KEY  service role key (Project Settings > API)
//
// IMPORTANT: deploy this function with **Verify JWT OFF**.
// Stripe does not send a Supabase JWT; leave it on and every event 401s.

const WEBHOOK_SECRET = Deno.env.get("STRIPE_WEBHOOK_SECRET")!;
const SUPABASE_URL   = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY    = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const TOLERANCE_SECONDS = 300;

/** Constant-time string compare — avoids leaking the signature by timing. */
function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function toHex(buf: ArrayBuffer): string {
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Verifies Stripe's `Stripe-Signature` header against the raw body. */
async function verifyStripe(raw: string, header: string | null): Promise<boolean> {
  if (!header) return false;
  const parts = Object.fromEntries(
    header.split(",").map((kv) => kv.split("=", 2) as [string, string]),
  );
  const t = parts["t"];
  const v1 = parts["v1"];
  if (!t || !v1) return false;

  // reject replays of very old events
  const age = Math.abs(Math.floor(Date.now() / 1000) - Number(t));
  if (!Number.isFinite(age) || age > TOLERANCE_SECONDS) return false;

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(WEBHOOK_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${t}.${raw}`));
  return safeEqual(toHex(mac), v1);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("POST only", { status: 405 });

  // must read the RAW body — re-serialising JSON breaks the signature
  const raw = await req.text();

  if (!await verifyStripe(raw, req.headers.get("Stripe-Signature"))) {
    console.warn("chop-webhook: bad signature");
    return new Response("bad signature", { status: 400 });
  }

  let event: any;
  try { event = JSON.parse(raw); } catch { return new Response("bad json", { status: 400 }); }

  // we only care about completed, paid checkouts
  if (event.type !== "checkout.session.completed") {
    return new Response(JSON.stringify({ ignored: event.type }), { status: 200 });
  }

  const session = event.data?.object ?? {};
  if (session.payment_status !== "paid") {
    return new Response(JSON.stringify({ ignored: "unpaid" }), { status: 200 });
  }

  const userId  = session.metadata?.user_id ?? session.client_reference_id;
  const credits = parseInt(session.metadata?.credits ?? "", 10);
  const pence   = Number(session.amount_total ?? 0);

  if (!userId || !Number.isFinite(credits) || credits < 1) {
    console.error("chop-webhook: missing metadata", session.id);
    return new Response("missing metadata", { status: 200 }); // 200 so Stripe stops retrying
  }

  // atomic: logs the purchase and adds the credits, or no-ops on a retry
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/chop_apply_purchase`, {
    method: "POST",
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      p_user: userId,
      p_credits: credits,
      p_pence: pence,
      p_event: event.id,
    }),
  });

  if (!res.ok) {
    const body = await res.text();
    console.error("chop-webhook: rpc failed", res.status, body);
    // 500 => Stripe retries, which is what we want if the DB was briefly down
    return new Response("rpc failed", { status: 500 });
  }

  const applied = await res.json();
  console.info("chop-webhook", event.id, "applied:", applied, "user:", userId, "credits:", credits);
  return new Response(JSON.stringify({ ok: true, applied }), { status: 200 });
});
