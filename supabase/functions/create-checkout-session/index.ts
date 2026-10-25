import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@17.7.0?target=deno";

const cors = {
  "Access-Control-Allow-Origin": Deno.env.get("SITE_URL") ?? "https://artgrandix-ltd.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};
const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return reply({ error: "Sign in required" }, 401);
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
  const siteUrl = Deno.env.get("SITE_URL");
  if (!url || !anonKey || !serviceKey || !stripeKey || !siteUrl) {
    return reply({ error: "Checkout is not configured on the server" }, 503);
  }

  try {
    const userClient = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: { user }, error: userError } = await userClient.auth.getUser();
    if (userError || !user) return reply({ error: "Invalid session" }, 401);

    const body = await req.json();
    const projectId = typeof body.project_id === "string" ? body.project_id : "";
    if (!/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(projectId)) return reply({ error: "Invalid project_id" }, 400);

    // The database RPC verifies approved contractor status and enforces the buyer cap.
    const { data: purchaseId, error: purchaseError } = await userClient.rpc("create_project_purchase", { p_project_id: projectId });
    if (purchaseError || !purchaseId) return reply({ error: purchaseError?.message ?? "Could not reserve purchase" }, 400);

    const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: purchase, error: readError } = await admin.from("project_purchases")
      .select("id,project_id,contractor_id,amount_pence,currency,payment_status")
      .eq("id", purchaseId).eq("contractor_id", user.id).maybeSingle();
    if (readError || !purchase || purchase.payment_status !== "pending") {
      return reply({ error: "Purchase is not awaiting payment" }, 409);
    }

    const stripe = new Stripe(stripeKey, { httpClient: Stripe.createFetchHttpClient() });
    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      payment_method_types: ["card"],
      client_reference_id: purchase.id,
      line_items: [{
        quantity: 1,
        price_data: {
          currency: purchase.currency.toLowerCase(),
          unit_amount: purchase.amount_pence,
          product_data: { name: "BuildLead verified project lead", description: "One contractor licence for a verified project. Contact details are released only after confirmed payment." },
        },
      }],
      metadata: { purchase_id: purchase.id, project_id: purchase.project_id, contractor_id: user.id },
      payment_intent_data: { metadata: { purchase_id: purchase.id, project_id: purchase.project_id, contractor_id: user.id } },
      success_url: `${siteUrl.replace(/\/$/, "")}/marketplace.html?payment=success`,
      cancel_url: `${siteUrl.replace(/\/$/, "")}/marketplace.html?payment=cancelled`,
    });
    const { error: updateError } = await admin.from("project_purchases")
      .update({ provider_checkout_id: session.id, payment_provider: "stripe" })
      .eq("id", purchase.id).eq("contractor_id", user.id).eq("payment_status", "pending");
    if (updateError) {
      await stripe.checkout.sessions.expire(session.id).catch(() => undefined);
      return reply({ error: "Could not save checkout session" }, 500);
    }
    return reply({ url: session.url });
  } catch (error) {
    console.error("checkout error", error instanceof Error ? error.message : "unknown");
    return reply({ error: "Could not start secure checkout" }, 500);
  }
});