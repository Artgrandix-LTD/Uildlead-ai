-- BuildLead AI: private customer requests
-- Run in Supabase SQL Editor. Public visitors may submit requests, but cannot read them.
create extension if not exists pgcrypto;

create table if not exists public.customer_leads (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  project_type text not null check (project_type in (
    'house_extension','loft_conversion','renovation','kitchen_bathroom',
    'roofing','painting_decorating','plumbing_heating','flooring',
    'garden_outdoor','carpentry_joinery','other'
  )),
  postcode text not null check (char_length(postcode) between 3 and 10),
  start_timing text not null check (start_timing in (
    'asap','1_3_months','3_6_months','researching'
  )),
  budget_range text not null check (budget_range in (
    'under_5k','5k_10k','10k_30k','30k_plus','unsure'
  )),
  project_details text not null default '' check (char_length(project_details) <= 2000),
  full_name text not null check (char_length(full_name) between 2 and 100),
  email text not null check (char_length(email) between 5 and 254),
  phone text not null check (char_length(phone) between 7 and 30),
  contact_consent boolean not null default false check (contact_consent = true),
  sharing_consent boolean not null default false check (sharing_consent = true),
  status text not null default 'pending_review' check (status in (
    'pending_review','verified','matched','closed','rejected'
  )),
  contact_verified boolean not null default false,
  privacy_notice_version text not null default '2026-10-25'
);

alter table public.customer_leads enable row level security;
revoke all on table public.customer_leads from anon, authenticated;
grant insert (project_type, postcode, start_timing, budget_range, project_details, full_name, email, phone, contact_consent, sharing_consent) on table public.customer_leads to anon;
grant select, insert, update, delete on table public.customer_leads to service_role;

drop policy if exists "Public can submit customer requests" on public.customer_leads;
create policy "Public can submit customer requests"
  on public.customer_leads
  for insert
  to anon
  with check (
    contact_consent is true
    and sharing_consent is true
    and status = 'pending_review'
    and contact_verified is false
  );

-- No SELECT, UPDATE, or DELETE grants/policies for public visitors.
-- Keep admin access in Supabase dashboard or a protected server-side function.
