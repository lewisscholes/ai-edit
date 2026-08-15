-- Credit ledger + admin grant.
-- Run in Supabase > SQL Editor. Purely additive: nothing existing changes
-- behaviour, so the web app and the native app carry on untouched.
--
-- This gives you two things:
--   1. A record of every credit movement — who, how many, why, when.
--   2. A safe way for an admin to add or remove credits on any account.
--
-- The column lockdown (stopping the CLIENT writing credits directly) is
-- deliberately NOT here. That one breaks both apps until they're updated, so it
-- needs coordinating with Lewis. See CREDIT_ADMIN_PLAN.md.

-- ---------------------------------------------------------------- ledger

create table if not exists public.chop_credit_ledger (
  id            bigserial primary key,
  user_id       uuid not null references auth.users(id) on delete cascade,
  delta         integer not null,          -- +10 granted, -1 spent
  balance_after integer not null,
  reason        text not null,             -- purchase | spend | admin_grant | signup_bonus | refund
  note          text,                      -- free text: 'App Review account', 'goodwill — failed export'
  actor         uuid,                      -- admin who did it; null for system/automatic
  created_at    timestamptz not null default now()
);

create index if not exists chop_credit_ledger_user_idx
  on public.chop_credit_ledger (user_id, created_at desc);

alter table public.chop_credit_ledger enable row level security;

-- Nobody reads this from the client. Admin reads go through the edge function
-- on the service role key, which bypasses RLS. No policies = no client access.

-- ---------------------------------------------------------------- grant fn

create or replace function public.chop_admin_grant(
  p_user  uuid,
  p_delta integer,
  p_note  text default null,
  p_actor uuid default null
)
returns integer                            -- new balance
language plpgsql
security definer
set search_path = public
as $$
declare new_bal integer;
begin
  if p_delta = 0 then
    raise exception 'delta must not be zero';
  end if;

  update public.chop_profiles
     set credits = greatest(0, coalesce(credits, 0) + p_delta)
   where id = p_user
  returning credits into new_bal;

  if new_bal is null then
    raise exception 'no profile for user %', p_user;
  end if;

  insert into public.chop_credit_ledger (user_id, delta, balance_after, reason, note, actor)
  values (p_user, p_delta, new_bal, 'admin_grant', p_note, p_actor);

  return new_bal;
end;
$$;

-- Service role only — same posture as chop_apply_purchase.
revoke all on function public.chop_admin_grant(uuid, integer, text, uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------- backfill

-- Record where everyone stands today, so the ledger has a starting point and
-- future movements can be reconciled against it.
insert into public.chop_credit_ledger (user_id, delta, balance_after, reason, note)
select id, coalesce(credits, 0), coalesce(credits, 0), 'signup_bonus', 'opening balance at ledger creation'
from public.chop_profiles
where not exists (
  select 1 from public.chop_credit_ledger l where l.user_id = chop_profiles.id
);
