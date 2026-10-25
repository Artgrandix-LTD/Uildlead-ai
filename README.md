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
