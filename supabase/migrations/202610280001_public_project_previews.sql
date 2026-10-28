-- Safe public project previews for the BuildLead homepage.
-- Exposes no names, contact details, full postcodes, or private project notes.
create or replace function public.public_project_previews()
returns table (
  id uuid,
  created_at timestamptz,
  project_type text,
  postcode_area text,
  start_timing text,
  budget_range text,
  map_area text
)
language sql
security definer
set search_path = public
as $$
  select l.id,
         l.created_at,
         l.project_type,
         left(regexp_replace(upper(l.postcode), '[0-9].*$', ''), 4),
         l.start_timing,
         l.budget_range,
         upper(substring(l.postcode from '^[A-Z]{1,2}'))
  from public.customer_leads l
  where l.status = 'verified'
    and l.contact_verified = true
    and l.sharing_consent = true
    and l.marketplace_status = 'open'
    and (
      select count(*) from public.project_purchases p
      where p.project_id = l.id and p.payment_status = 'paid'
    ) < l.max_contractors
  order by l.created_at desc
  limit 100
$$;

revoke all on function public.public_project_previews() from public;
grant execute on function public.public_project_previews() to anon, authenticated;
