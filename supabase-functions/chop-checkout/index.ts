// chop-checkout — creates a Stripe Checkout Session for a credit purchase.
// Price is ALWAYS recomputed here from the credit count. The browser never
// tells us an amount, so it can't be tampered with in dev tools.
//
// Secrets required (Supabase > Edge Functions > Secrets):
//   STRIPE_SECRET_KEY
// Deploy with JWT verification ON (default) — callers must be signed in.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY     = Deno.env.get("SUPABASE_ANON_KEY")!;
const STRIPE_KEY   = Deno.env.get("STRIPE_SECRET_KEY")!;

const APP = "https://chopedit.com/app/";
const MIN_CREDITS = 1;
const MAX_CREDITS = 300;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

/** Must stay identical to perCredit() in the app. */
function perCredit(n: number): number {
  if (n < 50) return 1.00;
  if (n < 100) return 0.85;
  return Math.max(0.60, 0.75 - 0.05 * Math.floor((n - 100) / 50));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  try {
    // --- who is asking? -----------------------------------------------
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) return json({ error: "Not signed in" }, 401);

    const ures = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: { Authorization: authHeader, apikey: ANON_KEY },
    });
    if (!ures.ok) return json({ error: "Not signed in" }, 401);
    const user = await ures.json();
    if (!user?.id) return json({ error: "Not signed in" }, 401);

    // --- how many credits? --------------------------------------------
    const payload = await req.json().catch(() => ({}));
    const n = Math.floor(Number(payload?.credits));
    if (!Number.isFinite(n) || n < MIN_CREDITS || n > MAX_CREDITS) {
      return json({ error: `Choose between ${MIN_CREDITS} and ${MAX_CREDITS} credits.` }, 400);
    }

    // --- price, computed here, never trusted from the client ----------
    const unitAmount = Math.round(n * perCredit(n) * 100); // pence

    const form = new URLSearchParams();
    form.set("mode", "payment");
    form.set("success_url", `${APP}?paid=1&session_id={CHECKOUT_SESSION_ID}`);
    form.set("cancel_url", `${APP}?checkout=cancelled`);
    form.set("client_reference_id", user.id);
    if (user.email) form.set("customer_email", user.email);
    form.set("metadata[user_id]", user.id);
    form.set("metadata[credits]", String(n));
    form.set("payment_intent_data[metadata][user_id]", user.id);
    form.set("payment_intent_data[metadata][credits]", String(n));
    form.set("line_items[0][quantity]", "1");
    form.set("line_items[0][price_data][currency]", "gbp");
    form.set("line_items[0][price_data][unit_amount]", String(unitAmount));
    form.set("line_items[0][price_data][product_data][name]",
             `${n} Chop credit${n === 1 ? "" : "s"}`);
    form.set("line_items[0][price_data][product_data][description]",
             `One credit chops one video, up to 10 minutes.`);

    const sres = await fetch("https://api.stripe.com/v1/checkout/sessions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${STRIPE_KEY}`,
        "Content-Type": "application/x-www-form-urlencoded",
        // guards against a double-click creating two sessions
        "Idempotency-Key": `${user.id}-${n}-${Math.floor(Date.now() / 10000)}`,
      },
      body: form,
    });

    const session = await sres.json();
    if (!sres.ok) {
      console.error("stripe error", session);
      return json({ error: session?.error?.message ?? "Stripe rejected that." }, 502);
    }

    return json({ url: session.url, id: session.id, amount: unitAmount, credits: n });
  } catch (e) {
    console.error("chop-checkout", e);
    return json({ error: "Something went wrong creating checkout." }, 500);
  }
});
