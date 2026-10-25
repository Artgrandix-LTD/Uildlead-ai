# BuildLead production activation checklist

This repository contains the website code and SQL migrations. **A GitHub commit does not execute SQL against Supabase and does not make payments live.** Complete these steps in the actual Supabase/Stripe accounts before advertising the service as live.

## 1. Apply database migrations in order

Open the Supabase project configured in `supabase-config.js`, then **SQL Editor**. Review and run these files in order, once each:

1. `supabase/migrations/202610250001_create_customer_leads.sql`
2. `supabase/migrations/202610250002_multi_contractor_marketplace.sql`
3. `supabase/migrations/202610250003_secure_stripe_payments.sql`

If either has already been applied, inspect **Table Editor** and the SQL migration history first; do not blindly rerun a partially applied migration. Verify that `customer_leads`, `contractor_profiles`, `project_purchases`, and `deal_reports` exist and RLS is enabled.

## 2. Configure Supabase Auth

In **Authentication → URL Configuration**, add the live GitHub Pages URL as the site URL and allow the corresponding callback URL. Test email confirmation and password sign-in. Do not disable email confirmation just to make sign-up appear to work.

## 3. Test customer project submissions

Submit a test request using a test email and phone number. Confirm one row appears in `customer_leads` with `status = pending_review`, `contact_verified = false`, and `marketplace_status = not_listed`. Confirm anonymous visitors cannot select customer rows. Delete test data after the test.

## 4. Test contractor profile registration

Create a test contractor account, sign in, save a profile, and verify it appears in `contractor_profiles` with `approved = false`. Approve only a real, vetted contractor through a trusted administrative workflow. Never let browser code approve itself.

## 5. Before opening the marketplace

A privileged operator must verify customer contact details and explicit sharing consent, then set the customer lead to verified/listed using a trusted admin-only path. Do not expose full postcodes, names, phone numbers, email addresses, or exact addresses in the public listing. Audit the `marketplace_open_projects()` output and RLS policies using separate customer, contractor, and anonymous test accounts.

## 6. Stripe integration code is prepared, but payments are NOT live yet

This repository now includes two Supabase Edge Functions:
- `supabase/functions/create-checkout-session/index.ts` — requires an authenticated, approved contractor and creates a Stripe Checkout Session server-side.
- `supabase/functions/stripe-webhook/index.ts` — verifies Stripe signatures and uses an atomic database RPC to confirm payments.
- `supabase/migrations/202610250003_secure_stripe_payments.sql` — adds atomic paid confirmation and a paid-only contact-details RPC.

These files do not deploy themselves. Before checkout can be enabled:

1. Apply migration `202610250003_secure_stripe_payments.sql` after the first two migrations.
2. Install the Supabase CLI, log in, and link the project.
3. Set server secrets (never commit them): `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `SITE_URL=https://artgrandix-ltd.github.io/Uildlead-ai`. Supabase normally provides `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` to Edge Functions; verify those defaults exist in the deployed project.
4. Deploy both functions:
   ```sh
   supabase functions deploy create-checkout-session
   supabase functions deploy stripe-webhook --no-verify-jwt
   supabase secrets set STRIPE_SECRET_KEY=... STRIPE_WEBHOOK_SECRET=... SITE_URL=https://artgrandix-ltd.github.io/Uildlead-ai
   ```
   Run the secrets command interactively and substitute actual Stripe test secrets. Do not paste secrets into chat or commit them.
5. In Stripe **test mode**, create a webhook endpoint pointing to `https://lwbvnqelvgqcxcupzuvv.supabase.co/functions/v1/stripe-webhook`. Subscribe to `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `checkout.session.async_payment_failed`, `checkout.session.expired`, and `charge.refunded`. Copy the endpoint signing secret into Supabase secrets as `STRIPE_WEBHOOK_SECRET`.
6. Run a full test purchase and verify the Stripe event delivery, the purchase row's `payment_status`, and that only the purchasing approved contractor can call `paid_project_contact(p_purchase_id)` after payment. Test refunds, duplicate webhook delivery, cancelled checkout, and the contractor cap.
7. Only after these pass, wire the purchase/contact UI and then separately switch to live Stripe credentials.

**Important:** a checkout can be paid at Stripe while failing the project cap allocation if several checkouts race. The webhook logs this case and must be monitored; refund that payment manually in Stripe. Do not consider payments production-ready until this case has an operational refund process.

Never put Stripe secret keys or Supabase service-role keys in HTML/JavaScript or GitHub. Do not advertise payment as live until deployed and tested.

## 7. Production sign-off

- [ ] All three migrations applied successfully in the correct Supabase project
- [ ] Auth redirect/email confirmation tested
- [ ] Customer insert and private-read protections tested
- [ ] Contractor profile insert/update and approval controls tested
- [ ] Listing RPC checked for postcode and personal-data minimisation
- [ ] Purchase cap tested with concurrent requests
- [ ] Edge Functions deployed and Stripe test checkout plus signed webhook tested
- [ ] Refund and failure handling tested
- [ ] Privacy notice, retention, and data deletion process reviewed
- [ ] Live payment keys configured only as server-side secrets
- [ ] Final smoke test performed on the deployed website

**Current status:** code and migrations are in GitHub; live database activation, production access-control tests, and payment activation require the actual Supabase/Stripe dashboards and must not be assumed complete.
