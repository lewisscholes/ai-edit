-- Run this FIRST, in Supabase > SQL Editor.
-- Adds idempotency to purchases and an atomic "credit the user" function.

-- 1. remember which Stripe event created each purchase
alter table public.chop_purchases
  add column if not exists stripe_event_id text;

-- 2. the same Stripe event can never be recorded twice
create unique index if not exists chop_purchases_stripe_event_id_key
  on public.chop_purchases (stripe_event_id);

-- 3. one atomic call: log the purchase AND add the credits.
--    Returns false if this event was already processed (Stripe retries a lot).
create or replace function public.chop_apply_purchase(
  p_user    uuid,
  p_credits integer,
  p_pence   integer,
  p_event   text
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  insert into public.chop_purchases (user_id, credits, pence, stripe_event_id)
  values (p_user, p_credits, p_pence, p_event)
  on conflict (stripe_event_id) do nothing;

  get diagnostics n = row_count;
  if n = 0 then
    return false;            -- already processed, do not credit again
  end if;

  update public.chop_profiles
     set credits = coalesce(credits, 0) + p_credits
   where id = p_user;

  return true;
end;
$$;

-- only the service role (the webhook) may call it
revoke all on function public.chop_apply_purchase(uuid,integer,integer,text) from public, anon, authenticated;
