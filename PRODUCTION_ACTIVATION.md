# BuildLead production activation checklist

This repository contains the website code and SQL migrations. **A GitHub commit does not execute SQL against Supabase and does not make payments live.** Complete these steps in the actual Supabase/Stripe accounts before advertising the service as live.

## 1. Apply database migrations in order

Open the Supabase project configured in `supabase-config.js`, then **SQL Editor**. Review and run these files in order, once each:

1. `supabase/migrations/202610250001_create_customer_leads.sql`
2. `supabase/migrations/202610250002_multi_contractor_marketplace.sql`

If either has already been applied, inspect **Table Editor** and the SQL migration history first; do not blindly rerun a partially applied migration. Verify that `customer_leads`, `contractor_profiles`, `project_purchases`, and `deal_reports` exist and RLS is enabled.

## 2. Configure Supabase Auth

In **Authentication → URL Configuration**, add the live GitHub Pages URL as the site URL and allow the corresponding callback URL. Test email confirmation and password sign-in. Do not disable email confirmation just to make sign-up appear to work.

## 3. Test customer project submissions

Submit a test request using a test email and phone number. Confirm one row appears in `customer_leads` with `status = pending_review`, `contact_verified = false`, and `marketplace_status = not_listed`. Confirm anonymous visitors cannot select customer rows. Delete test data after the test.

## 4. Test contractor profile registration

Create a test contractor account, sign in, save a profile, and verify it appears in `contractor_profiles` with `approved = false`. Approve only a real, vetted contractor through a trusted administrative workflow. Never let browser code approve itself.

## 5. Before opening the marketplace

A privileged operator must verify customer contact details and explicit sharing consent, then set the customer lead to verified/listed using a trusted admin-only path. Do not expose full postcodes, names, phone numbers, email addresses, or exact addresses in the public listing. Audit the `marketplace_open_projects()` output and RLS policies using separate customer, contractor, and anonymous test accounts.

## 6. Payments are NOT live

The current site intentionally disables purchase buttons. To activate payments, configure Stripe in test mode, implement a server-side checkout endpoint and a signed Stripe webhook (for example, Supabase Edge Functions with secrets stored in Supabase project secrets), and only mark purchases paid after validating the webhook signature and payment amount/currency. Add idempotency, refunds, failed-payment handling, contractor purchase limits, and tests. Never put Stripe secret keys or Supabase service-role keys in HTML/JavaScript or GitHub.

Test successful, failed, duplicate, cancelled, and refunded checkout events before considering live mode. Keep purchases disabled until all tests pass.

## 7. Production sign-off

- [ ] Both migrations applied successfully in the correct Supabase project
- [ ] Auth redirect/email confirmation tested
- [ ] Customer insert and private-read protections tested
- [ ] Contractor profile insert/update and approval controls tested
- [ ] Listing RPC checked for postcode and personal-data minimisation
- [ ] Purchase cap tested with concurrent requests
- [ ] Stripe test checkout and signed webhook tested
- [ ] Refund and failure handling tested
- [ ] Privacy notice, retention, and data deletion process reviewed
- [ ] Live payment keys configured only as server-side secrets
- [ ] Final smoke test performed on the deployed website

**Current status:** code and migrations are in GitHub; live database activation, production access-control tests, and payment activation require the actual Supabase/Stripe dashboards and must not be assumed complete.
