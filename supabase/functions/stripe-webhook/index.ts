import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@17.7.0?target=deno";

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
  const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!stripeKey || !webhookSecret || !url || !serviceKey) return new Response("Webhook is not configured", { status: 503 });

  const signature = req.headers.get("stripe-signature");
  if (!signature) return new Response("Missing Stripe signature", { status: 400 });
  const rawBody = await req.text();
  const stripe = new Stripe(stripeKey, { httpClient: Stripe.createFetchHttpClient() });
  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(rawBody, signature, webhookSecret, undefined, Stripe.createSubtleCryptoProvider());
  } catch (error) {
    console.error("Invalid Stripe signature", error instanceof Error ? error.message : "unknown");
    return new Response("Invalid signature", { status: 400 });
  }

  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  try {
    if (event.type === "checkout.session.completed" || event.type === "checkout.session.async_payment_succeeded") {
      const session = event.data.object as Stripe.Checkout.Session;
      if (session.payment_status !== "paid") return new Response("Payment not completed", { status: 200 });
      const purchaseId = session.metadata?.purchase_id;
      const projectId = session.metadata?.project_id;
      const contractorId = session.metadata?.contractor_id;
      if (!purchaseId || !projectId || !contractorId || !session.id) return new Response("Missing purchase metadata", { status: 400 });
      const { data: purchase, error } = await admin.from("project_purchases")
        .select("id,project_id,contractor_id,amount_pence,currency,payment_status,provider_checkout_id")
        .eq("id", purchaseId).maybeSingle();
      if (error || !purchase) return new Response("Purchase not found", { status: 400 });
      if (purchase.project_id !== projectId || purchase.contractor_id !== contractorId ||
          purchase.provider_checkout_id !== session.id ||
          purchase.amount_pence !== session.amount_total ||
          purchase.currency.toLowerCase() !== session.currency?.toLowerCase()) {
        console.error("Checkout metadata/amount mismatch", purchaseId);
        return new Response("Checkout does not match purchase", { status: 400 });
      }
      // Idempotent: repeated Stripe delivery must not change an already paid record.
      if (purchase.payment_status !== "paid") {
        const { error: updateError } = await admin.from("project_purchases")
          .update({ payment_status: "paid", provider_payment_intent_id: typeof session.payment_intent === "string" ? session.payment_intent : null, paid_at: new Date().toISOString(), payment_provider: "stripe" })
          .eq("id", purchaseId).eq("payment_status", "pending");
        if (updateError) throw updateError;
      }
    } else if (event.type === "checkout.session.async_payment_failed" || event.type === "checkout.session.expired") {
      const session = event.data.object as Stripe.Checkout.Session;
      const purchaseId = session.metadata?.purchase_id;
      if (purchaseId) {
        const { error } = await admin.from("project_purchases")
          .update({ payment_status: "failed" })
          .eq("id", purchaseId).eq("provider_checkout_id", session.id).eq("payment_status", "pending");
        if (error) throw error;
      }
    } else if (event.type === "charge.refunded") {
      const charge = event.data.object as Stripe.Charge;
      const paymentIntentId = typeof charge.payment_intent === "string" ? charge.payment_intent : null;
      if (paymentIntentId) {
        const { error } = await admin.from("project_purchases")
          .update({ payment_status: "refunded", refunded_at: new Date().toISOString() })
          .eq("provider_payment_intent_id", paymentIntentId).eq("payment_status", "paid");
        if (error) throw error;
      }
    }
    return new Response(JSON.stringify({ received: true }), { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (error) {
    console.error("Webhook processing failed", error instanceof Error ? error.message : "unknown");
    return new Response("Webhook processing failed; retry delivery", { status: 500 });
  }
});