# BuildLead AI

Live website: https://artgrandix-ltd.github.io/Uildlead-ai/

BuildLead currently combines public London planning signals with an in-progress customer enquiry flow. Planning records are not confirmed customer requests.

## Customer enquiry MVP setup

The customer request page is `/lead-request.html`. It requires a Supabase project before it can accept submissions.

### 1. Create the database table

1. Create a Supabase project at https://supabase.com/dashboard.
2. Open **SQL Editor** in the project dashboard.
3. Copy and run `supabase/migrations/202610250001_create_customer_leads.sql`.
4. Confirm the `customer_leads` table exists and Row Level Security is enabled.

The migration is designed to let unauthenticated visitors submit only a narrow set of fields. Public visitors have no read/update/delete access. The operator should review records in the Supabase dashboard or a protected server-side admin tool. Do not add a public SELECT policy.

### 2. Configure the public client values

1. In the Supabase dashboard, find the project URL and the **publishable** key (older projects may label this the anon key).
2. Copy `supabase/config.example.js` to `supabase-config.js` in the repository root.
3. Replace the placeholders in `supabase-config.js` with the real project URL and publishable key.
4. Never put a Supabase service-role or secret key in browser JavaScript or GitHub Pages.

The publishable key is not a secret, but it must only be used with the restrictive RLS rules from the migration. Do not commit any database password or service key.

### 3. Important pre-launch checks

- Replace the placeholder business identity and contact details in `privacy.html`.
- Set an approved retention period and document the lawful basis and data processors.
- Test a request using a dedicated test email and phone number; confirm it appears in Supabase and cannot be read from a logged-out browser.
- Confirm the live GitHub Pages site loads `supabase-config.js` and the form returns a clear success/error state.
- Add server-side rate limiting, CAPTCHA or equivalent abuse controls, and a real contact-verification process before promoting the form.
- Do not sell/share a request until it has been reviewed and the customer's explicit sharing consent is recorded.
- A form submission is not yet email/phone verification. Current MVP requests remain `pending_review`; there is no automatic contractor matching or payment workflow yet.

## Current capabilities and limits

- Public planning data scanner: potential planning signals only.
- Customer request page: front end is prepared; it needs Supabase configuration to receive data.
- Private lead storage: migration supplied; it must be run in the user's Supabase project.
- Admin dashboard, verified contact workflow, contractor accounts, billing and automated lead distribution are not yet implemented.


## Multi-contractor marketplace (new migration)

The marketplace page is `/marketplace.html`. It introduces account sign-in, verified project discovery, purchase-history display, and the contractor deal-report flow. It is deliberately **not taking payments yet**.

Before enabling it:
1. In Supabase SQL Editor, run `supabase/migrations/202610250002_multi_contractor_marketplace.sql` after the first migration.
2. Review the SQL and test it in a non-production Supabase project first.
3. Create a trusted server-side payment checkout endpoint and signed Stripe webhook. Only the verified webhook/service role may set `project_purchases.payment_status = 'paid'`; never mark paid from browser code.
4. Add account approval tooling and link reviewed landlord requests to the correct authenticated account by setting `customer_leads.owner_user_id`. Anonymous form submissions do not automatically become owned landlord projects.
5. Confirm each listed lead has verified contact details, explicit sharing consent, and a capacity of 2 or 3 contractors. The RPC locks the project row while creating a purchase intent and counts paid purchases against the cap.
6. Test RLS and all role boundaries with separate landlord, approved contractor, unapproved contractor, and logged-out test accounts. Confirm no contact fields are available through public or ordinary contractor queries before payment.
7. Set a real lead price in trusted configuration before checkout. The current SQL uses a clearly marked placeholder of £25.00 and the UI keeps checkout disabled.

### Marketplace workflow and safety notes

- A lead can be purchased by up to 2 or 3 distinct approved contractors.
- Payment is pending until a trusted server/webhook confirms it; this repository does not yet contain that webhook.
- After a paid contractor reports a deal, the lead enters `deal_pending` and is removed from open listings. The landlord must confirm to close it; if the landlord rejects the report, the project returns to `open`.
- Customer contact data must only be returned by a separate authenticated server-side/RPC function after a confirmed paid purchase. Do not grant broad SELECT access to `customer_leads`.
- Do not advertise the marketplace as fully live until migrations, payment webhook, approval workflow, contact-release logic, privacy review, and end-to-end tests are complete.


## Stripe payments for ARTGRANDIX LTD (initial one-off lead checkout)

The marketplace checkout is designed for ARTGRANDIX LTD as the legal operator and settlement business. The first payment model is a one-time GBP payment per verified project lead. Recurring contractor subscriptions and Stripe Connect contractor payouts are separate follow-on work and are not enabled by this integration.

### Required setup

1. Apply `supabase/migrations/202611110001_stripe_contact_release.sql` after both marketplace migrations. This adds the paid-only contact-release RPC and the server-only payment confirmation RPC.
2. Deploy the existing Edge Functions:
   ```sh
   supabase functions deploy create-checkout-session
   supabase functions deploy stripe-webhook
   ```
3. In Supabase Dashboard → Edge Functions → Secrets, configure:
   - `STRIPE_SECRET_KEY`: Stripe **test-mode** secret key (`sk_test_...`) only for initial testing.
   - `STRIPE_WEBHOOK_SECRET`: signing secret for the webhook endpoint created in Stripe.
   - `PAYMENTS_MODE`: `test`.
   - `PAYMENTS_ENABLED`: leave `false` until test setup and verification are complete; set `true` only when ready to test checkout.
   - `SITE_URL`: `https://artgrandix-ltd.github.io/Uildlead-ai`.
   Supabase supplies its project URL and standard server-side keys to Edge Functions. Never copy a service-role key into GitHub or browser code.
4. In Stripe Dashboard test mode, add a webhook endpoint:
   `https://lwbvnqelvgqcxcupzuvv.supabase.co/functions/v1/stripe-webhook`
   Subscribe to `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `checkout.session.async_payment_failed`, `checkout.session.expired`, and `charge.refunded`. Copy the endpoint signing secret into the Supabase secret `STRIPE_WEBHOOK_SECRET`.
5. Run end-to-end tests using Stripe test cards and separate approved contractor accounts. Verify successful payment, failed/expired checkout, duplicate webhook delivery, refund, contractor cap, purchase history, and paid-only contact release.
6. The current SQL uses a **test placeholder price of £25.00** per lead. Confirm the commercial price before enabling any live payments. Do not switch to live keys until ARTGRANDIX LTD's Stripe verification, website disclosures, refund policy, tax/accounting treatment, privacy notice, and test results have been reviewed.

### Payment safety

- Checkout is created server-side from the authenticated user's session and database purchase record.
- The signed Stripe webhook verifies payment before changing purchase status.
- The database confirmation RPC is service-role-only and locks the project row before enforcing the contractor purchase cap.
- If a payment succeeds after the project can no longer be allocated, the webhook attempts an idempotent automatic refund.
- Customer contact details are released only through `get_paid_project_contact` to the approved contractor who owns the paid purchase.
- The marketplace browser never receives Stripe secret keys or marks a purchase as paid.
- GitHub Pages only hosts the public UI; Supabase Edge Functions and the Supabase database perform payment and access-control operations.
