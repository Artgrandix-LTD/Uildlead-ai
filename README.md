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
