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
