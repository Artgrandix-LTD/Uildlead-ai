-- Secure payment confirmation and paid-only contact release.
-- Apply after 202610250002_multi_contractor_marketplace.sql.
create or replace function public.confirm_project_purchase_payment(
  p_purchase_id uuid,
  p_checkout_id text,
  p_payment_intent_id text,
  p_amount_pence integer,
  p_currency text
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_purchase public.project_purchases%rowtype;
  v_limit smallint;
  v_paid_count integer;
begin
  select * into v_purchase from public.project_purchases
    where id = p_purchase_id for update;
  if not found then raise exception 'Purchase not found'; end if;

  if v_purchase.payment_status = 'paid' then
    return v_purchase.provider_checkout_id = p_checkout_id
      and v_purchase.amount_pence = p_amount_pence
      and lower(v_purchase.currency) = lower(p_currency);
  end if;

  if v_purchase.payment_status <> 'pending'
    or v_purchase.provider_checkout_id is distinct from p_checkout_id
    or v_purchase.amount_pence <> p_amount_pence
    or lower(v_purchase.currency) <> lower(p_currency)
    or lower(p_currency) <> 'gbp'
    or p_payment_intent_id is null then
    raise exception 'Payment does not match pending purchase';
  end if;

  -- Serialize confirmations per project so simultaneous paid sessions cannot exceed the cap.
  select max_contractors into v_limit from public.customer_leads
    where id = v_purchase.project_id for update;
  if not found then raise exception 'Project not found'; end if;
  select count(*) into v_paid_count from public.project_purchases
    where project_id = v_purchase.project_id and payment_status = 'paid';
  if v_paid_count >= v_limit then
    update public.project_purchases set payment_status = 'failed'
      where id = p_purchase_id and payment_status = 'pending';
    return false;
  end if;

  update public.project_purchases set
    payment_status = 'paid',
    provider_payment_intent_id = p_payment_intent_id,
    payment_provider = 'stripe',
    paid_at = now()
  where id = p_purchase_id and payment_status = 'pending';
  return found;
end;
$$;

revoke all on function public.confirm_project_purchase_payment(uuid,text,text,integer,text) from public, anon, authenticated;
grant execute on function public.confirm_project_purchase_payment(uuid,text,text,integer,text) to service_role;

create or replace function public.paid_project_contact(p_purchase_id uuid)
returns table (
  project_id uuid,
  full_name text,
  email text,
  phone text,
  postcode text,
  project_details text
)
language sql
security definer
set search_path = public
as $$
  select l.id, l.full_name, l.email, l.phone, l.postcode, l.project_details
  from public.project_purchases p
  join public.customer_leads l on l.id = p.project_id
  where p.id = p_purchase_id
    and p.contractor_id = auth.uid()
    and p.payment_status = 'paid'
    and l.contact_verified = true
    and l.sharing_consent = true
    and l.status = 'verified'
    and l.marketplace_status in ('open','deal_pending','closed')
    and exists (select 1 from public.contractor_profiles cp
      where cp.user_id = auth.uid() and cp.approved)
$$;

revoke all on function public.paid_project_contact(uuid) from public, anon;
grant execute on function public.paid_project_contact(uuid) to authenticated;
