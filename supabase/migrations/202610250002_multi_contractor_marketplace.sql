-- BuildLead multi-contractor lead marketplace
-- Apply after 202610250001_create_customer_leads.sql.
-- Payment confirmation is server-only: never mark a purchase paid from browser code.

create extension if not exists pgcrypto;

alter table public.customer_leads
  add column if not exists owner_user_id uuid references auth.users(id) on delete set null,
  add column if not exists max_contractors smallint not null default 3
    check (max_contractors in (2,3)),
  add column if not exists marketplace_status text not null default 'not_listed'
    check (marketplace_status in ('not_listed','open','deal_pending','closed','withdrawn')),
  add column if not exists deal_reported_by uuid references auth.users(id),
  add column if not exists deal_reported_at timestamptz,
  add column if not exists deal_confirmed_at timestamptz,
  add column if not exists deal_confirmation_note text;

create table if not exists public.contractor_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  business_name text not null check (char_length(business_name) between 2 and 160),
  trades text[] not null default '{}',
  service_postcodes text[] not null default '{}',
  contact_email text,
  contact_phone text,
  approved boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.project_purchases (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.customer_leads(id) on delete restrict,
  contractor_id uuid not null references auth.users(id) on delete restrict,
  payment_status text not null default 'pending'
    check (payment_status in ('pending','paid','failed','refunded')),
  amount_pence integer not null check (amount_pence > 0),
  currency text not null default 'GBP' check (currency = 'GBP'),
  payment_provider text not null default 'stripe_test',
  provider_checkout_id text unique,
  provider_payment_intent_id text unique,
  paid_at timestamptz,
  refunded_at timestamptz,
  created_at timestamptz not null default now(),
  unique(project_id, contractor_id)
);

create table if not exists public.deal_reports (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.customer_leads(id) on delete restrict,
  purchase_id uuid not null references public.project_purchases(id) on delete restrict,
  contractor_id uuid not null references auth.users(id) on delete restrict,
  status text not null default 'awaiting_landlord'
    check (status in ('awaiting_landlord','confirmed','rejected','cancelled')),
  contractor_note text check (char_length(coalesce(contractor_note,'')) <= 1000),
  landlord_note text check (char_length(coalesce(landlord_note,'')) <= 1000),
  reported_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id)
);

create index if not exists customer_leads_marketplace_idx
  on public.customer_leads (marketplace_status, created_at desc);
create index if not exists project_purchases_project_idx
  on public.project_purchases (project_id, payment_status);
create index if not exists deal_reports_project_idx
  on public.deal_reports (project_id, status);

alter table public.contractor_profiles enable row level security;
alter table public.project_purchases enable row level security;
alter table public.deal_reports enable row level security;
alter table public.customer_leads enable row level security;

-- Remove broad grants, then grant only columns/actions intended for authenticated users.
revoke all on public.contractor_profiles, public.project_purchases, public.deal_reports from anon, authenticated;
grant select, insert, update on public.contractor_profiles to authenticated;
grant select on public.project_purchases to authenticated;
grant select, insert on public.deal_reports to authenticated;
grant select on public.customer_leads to authenticated;

drop policy if exists "Contractors manage own profile" on public.contractor_profiles;
create policy "Contractors manage own profile"
on public.contractor_profiles for all to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid() and approved = false);

drop policy if exists "Users see own purchases" on public.project_purchases;
create policy "Users see own purchases"
on public.project_purchases for select to authenticated
using (
  contractor_id = auth.uid()
  or exists (
    select 1 from public.customer_leads l
    where l.id = project_purchases.project_id and l.owner_user_id = auth.uid()
  )
);

drop policy if exists "Participants see deal reports" on public.deal_reports;
create policy "Participants see deal reports"
on public.deal_reports for select to authenticated
using (
  contractor_id = auth.uid()
  or exists (
    select 1 from public.customer_leads l
    where l.id = deal_reports.project_id and l.owner_user_id = auth.uid()
  )
);

drop policy if exists "Paid contractor can report deal" on public.deal_reports;
create policy "Paid contractor can report deal"
on public.deal_reports for insert to authenticated
with check (
  contractor_id = auth.uid()
  and status = 'awaiting_landlord'
  and resolved_by is null
  and exists (
    select 1 from public.project_purchases p
    join public.contractor_profiles cp on cp.user_id = p.contractor_id and cp.approved
    where p.id = deal_reports.purchase_id
      and p.project_id = deal_reports.project_id
      and p.contractor_id = auth.uid()
      and p.payment_status = 'paid'
  )
  and exists (
    select 1 from public.customer_leads l
    where l.id = deal_reports.project_id
      and l.marketplace_status = 'open'
      and l.owner_user_id is not null
  )
);

-- Customer contact fields are not selectable directly by ordinary users.
-- Public/contractor UI must use the RPCs below; purchases never expose contacts until paid.
create or replace function public.marketplace_open_projects()
returns table (
  id uuid,
  created_at timestamptz,
  project_type text,
  postcode_area text,
  start_timing text,
  budget_range text,
  project_details text,
  max_contractors smallint,
  buyers_count bigint,
  price_pence integer
)
language sql
security definer
set search_path = public
as $$
  select l.id, l.created_at, l.project_type,
         left(regexp_replace(upper(l.postcode), '[0-9].*$', ''), 4),
         l.start_timing, l.budget_range, l.project_details,
         l.max_contractors,
         count(p.id) filter (where p.payment_status = 'paid'),
         2500
  from public.customer_leads l
  left join public.project_purchases p on p.project_id = l.id
  where l.status = 'verified'
    and l.contact_verified = true
    and l.sharing_consent = true
    and l.marketplace_status = 'open'
    and auth.uid() is not null
    and exists (select 1 from public.contractor_profiles cp
                where cp.user_id = auth.uid() and cp.approved)
  group by l.id
  having count(p.id) filter (where p.payment_status = 'paid') < l.max_contractors
$$;

create or replace function public.create_project_purchase(p_project_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_purchase_id uuid;
  v_limit smallint;
  v_status text;
  v_paid_count integer;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if not exists (select 1 from public.contractor_profiles
                 where user_id = auth.uid() and approved) then
    raise exception 'Approved contractor account required';
  end if;

  -- Lock project row so two buyers cannot exceed the configured cap concurrently.
  select marketplace_status, max_contractors into v_status, v_limit
  from public.customer_leads where id = p_project_id for update;
  if not found or v_status <> 'open' then raise exception 'Project is not available'; end if;

  select count(*) into v_paid_count from public.project_purchases
   where project_id = p_project_id and payment_status = 'paid';
  if v_paid_count >= v_limit then raise exception 'Project has reached its contractor limit'; end if;

  insert into public.project_purchases(project_id, contractor_id, amount_pence)
  values (p_project_id, auth.uid(), 2500)
  on conflict (project_id, contractor_id) do update
    set payment_status = case when public.project_purchases.payment_status = 'failed'
                              then 'pending' else public.project_purchases.payment_status end
  returning id into v_purchase_id;

  if (select payment_status from public.project_purchases where id = v_purchase_id) <> 'pending' then
    raise exception 'Existing purchase is not awaiting payment';
  end if;
  return v_purchase_id;
end;
$$;

create or replace function public.report_project_deal(p_purchase_id uuid, p_note text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_report_id uuid; v_project_id uuid;
begin
  select project_id into v_project_id from public.project_purchases
   where id = p_purchase_id and contractor_id = auth.uid() and payment_status = 'paid';
  if v_project_id is null then raise exception 'Paid project purchase not found'; end if;
  if not exists (select 1 from public.customer_leads
                 where id = v_project_id and marketplace_status = 'open') then
    raise exception 'Project is not open';
  end if;
  insert into public.deal_reports(project_id,purchase_id,contractor_id,contractor_note)
  values (v_project_id,p_purchase_id,auth.uid(),left(coalesce(p_note,''),1000))
  returning id into v_report_id;
  update public.customer_leads set marketplace_status='deal_pending',
    deal_reported_by=auth.uid(), deal_reported_at=now()
  where id=v_project_id and marketplace_status='open';
  if not found then raise exception 'Project status changed; refresh and retry'; end if;
  return v_report_id;
end;
$$;

create or replace function public.resolve_project_deal(p_report_id uuid, p_confirm boolean, p_note text default null)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare v_project_id uuid; v_status text;
begin
  select project_id,status into v_project_id,v_status
  from public.deal_reports where id=p_report_id for update;
  if v_project_id is null then raise exception 'Deal report not found'; end if;
  if not exists (select 1 from public.customer_leads
                 where id=v_project_id and owner_user_id=auth.uid()) then
    raise exception 'Only the project landlord can resolve this report';
  end if;
  if v_status <> 'awaiting_landlord' then raise exception 'Report already resolved'; end if;

  update public.deal_reports set
    status=case when p_confirm then 'confirmed' else 'rejected' end,
    landlord_note=left(coalesce(p_note,''),1000),
    resolved_at=now(), resolved_by=auth.uid()
  where id=p_report_id;

  if p_confirm then
    update public.customer_leads set marketplace_status='closed',
      deal_confirmed_at=now(), deal_confirmation_note=left(coalesce(p_note,''),1000)
    where id=v_project_id and marketplace_status='deal_pending';
  else
    update public.customer_leads set marketplace_status='open',
      deal_reported_by=null, deal_reported_at=null
    where id=v_project_id and marketplace_status='deal_pending';
  end if;
  return true;
end;
$$;

revoke all on function public.marketplace_open_projects() from public, anon;
revoke all on function public.create_project_purchase(uuid) from public, anon;
revoke all on function public.report_project_deal(uuid,text) from public, anon;
revoke all on function public.resolve_project_deal(uuid,boolean,text) from public, anon;
grant execute on function public.marketplace_open_projects() to authenticated;
grant execute on function public.create_project_purchase(uuid) to authenticated;
grant execute on function public.report_project_deal(uuid,text) to authenticated;
grant execute on function public.resolve_project_deal(uuid,boolean,text) to authenticated;

-- Important: payment status/provider IDs must be changed only by a trusted server/webhook.
revoke insert, update, delete on public.project_purchases from authenticated;
revoke insert, update, delete on public.customer_leads from authenticated;
