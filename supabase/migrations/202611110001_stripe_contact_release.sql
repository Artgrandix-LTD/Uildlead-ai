-- BuildLead AI: secure Stripe lead-purchase contact release
-- Apply after 202610250002_multi_contractor_marketplace.sql.
-- Stripe webhook remains the only writer of paid/refunded purchase states.

create or replace function public.get_paid_project_contact(p_purchase_id uuid)
returns table (
  project_id uuid,
  project_type text,
  postcode text,
  project_details text,
  full_name text,
  email text,
  phone text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in required';
  end if;

  return query
  select l.id, l.project_type, l.postcode, l.project_details,
         l.full_name, l.email, l.phone
  from public.project_purchases p
  join public.customer_leads l on l.id = p.project_id
  join public.contractor_profiles cp on cp.user_id = p.contractor_id
  where p.id = p_purchase_id
    and p.contractor_id = auth.uid()
    and p.payment_status = 'paid'
    and cp.approved = true
    and l.contact_verified = true
    and l.sharing_consent = true;
end;
$$;

revoke all on function public.get_paid_project_contact(uuid) from public, anon;
grant execute on function public.get_paid_project_contact(uuid) to authenticated;

-- Do not grant ordinary users direct access to customer contact columns.
-- The function above releases them only to the approved contractor with a paid purchase.


-- Atomically confirm a Stripe payment and enforce the per-project contractor cap.
-- This RPC is callable only by the server-side webhook service role.
create or replace function public.confirm_project_purchase_payment(
  p_purchase_id uuid,
  p_checkout_id text,
  p_payment_intent_id text,
  p_amount_pence integer,
  p_currency text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_purchase public.project_purchases%rowtype;
  v_limit smallint;
  v_paid_count integer;
begin
  select p.* into v_purchase
  from public.project_purchases p
  where p.id = p_purchase_id
  for update;

  if not found then return false; end if;
  if v_purchase.payment_status = 'paid' then
    return v_purchase.provider_checkout_id = p_checkout_id
       and v_purchase.amount_pence = p_amount_pence
       and lower(v_purchase.currency) = lower(p_currency);
  end if;

  if v_purchase.payment_status <> 'pending'
     or v_purchase.provider_checkout_id is distinct from p_checkout_id
     or v_purchase.amount_pence <> p_amount_pence
     or lower(v_purchase.currency) <> lower(p_currency)
     or lower(p_currency) <> 'gbp' then
    return false;
  end if;

  select l.max_contractors into v_limit
  from public.customer_leads l
  where l.id = v_purchase.project_id
    and l.marketplace_status = 'open'
    and l.contact_verified = true
    and l.sharing_consent = true
  for update;

  if not found then return false; end if;

  select count(*)::integer into v_paid_count
  from public.project_purchases p
  where p.project_id = v_purchase.project_id
    and p.payment_status = 'paid';

  if v_paid_count >= v_limit then
    return false;
  end if;

  update public.project_purchases
  set payment_status = 'paid',
      payment_provider = 'stripe',
      provider_payment_intent_id = p_payment_intent_id,
      paid_at = now()
  where id = p_purchase_id
    and payment_status = 'pending';

  return found;
end;
$$;

revoke all on function public.confirm_project_purchase_payment(uuid,text,text,integer,text) from public, anon, authenticated;
grant execute on function public.confirm_project_purchase_payment(uuid,text,text,integer,text) to service_role;
