# Admin credit injection — design (not built yet)

You asked for a way to bump credits on any account from the admin dashboard.
Before writing it, I looked at how credits are currently written. There is a
problem that has to be fixed in the same change, because it is the same surface.

---

## The problem

`app/index.html:4543`:

```js
function creditsSet(n, skipCloud){
  ...
  sb.from('chop_profiles').update({credits:n}).eq('id', authUser.id)
}
```

The **client** writes its own credit balance. For that line to work at all, the
row-level security policy on `chop_profiles` must allow an authenticated user to
update their own row — including the `credits` column.

If that is the case, then any signed-in user can open the browser console and
run:

```js
sb.from('chop_profiles').update({credits: 99999}).eq('id', <their own id>)
```

and grant themselves unlimited credits. No exploit needed — it is the app's own
supported call path.

The Stripe webhook does this correctly: `chop_apply_purchase` is `security
definer`, writes a purchase row, and is explicitly revoked from `anon` and
`authenticated`. Only the service role can call it. The client path bypasses all
of that.

### Verify before assuming

I cannot query your database from here. Check it yourself in 30 seconds:

- Supabase → Authentication → Policies → `chop_profiles`
- Look at the UPDATE policy for `authenticated`

If it is `auth.uid() = id` with no column restriction, the hole is real.

Faster empirical check: sign in as a throwaway account on chopedit.com, open the
console, and run the update above against your own id. If your balance changes,
it is exploitable.

**This matters now because you are about to start charging for credits.** Right
now the only people who know are you, me and Lewis. That changes at launch.

---

## The fix and the feature, together

Both come down to: nothing except the server may write `credits`.

### 1. Ledger table

Every credit movement gets a row. Needed for the admin feature, for accounting,
and for working out what happened when a customer disputes a balance.

```sql
create table public.chop_credit_ledger (
  id          bigserial primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  delta       integer not null,           -- +10 grant, -1 spend
  balance_after integer not null,
  reason      text not null,              -- 'purchase' | 'spend' | 'admin_grant' | 'signup_bonus' | 'refund'
  note        text,                       -- free text, e.g. 'App Review account'
  actor       uuid,                       -- admin who did it, null for system
  created_at  timestamptz not null default now()
);
create index on public.chop_credit_ledger (user_id, created_at desc);
```

### 2. Lock the column

Revoke direct update on `credits` from `authenticated`. Either a
column-restricted policy, or simplest: keep the row policy but drop `credits`
from the updatable column grant:

```sql
revoke update (credits) on public.chop_profiles from authenticated, anon;
```

### 3. Replace the client write with an RPC

Spending a credit becomes a server call that checks the balance is actually
there, decrements atomically, and writes a ledger row:

```sql
create or replace function public.chop_spend_credit(p_note text default null)
returns integer            -- new balance
language plpgsql security definer set search_path = public
```

Callable by `authenticated`, but it can only ever *decrement*, and only for
`auth.uid()`. No parameter lets the caller choose an amount or a user.

### 4. Admin grant function

```sql
create or replace function public.chop_admin_grant(
  p_user uuid, p_delta integer, p_note text, p_actor uuid)
returns integer
language plpgsql security definer set search_path = public
```

Revoked from `public`, `anon`, `authenticated` — service role only, exactly like
`chop_apply_purchase`.

### 5. Edge function `chop-admin-credits`

Same shape as whatever `admin.html` already calls. Verify JWT on, check the
caller's email is on the admin allowlist (the gate already exists — `admin.html`
returns "This account isn't on the admin list"), then call the RPC with the
service role key.

### 6. Admin UI

Add to `admin.html`, reusing its existing auth gate:

- Search a user by email → show current balance and recent ledger rows
- Field for amount, field for reason, Grant button
- Negative amounts allowed, for corrections
- Show who granted what and when

---

## Order of work

1. Check the RLS policy — confirm whether the hole is real
2. Ledger table + `chop_spend_credit` + lock the column
3. Update `app/index.html` to call the RPC instead of writing directly
4. Update the native app the same way — Lewis needs to know, it has its own spend path
5. `chop_admin_grant` + edge function
6. `admin.html` UI

Steps 1–4 are the security fix and should go first. Steps 5–6 are the feature you
asked for. Doing 5–6 without 1–4 would mean building a careful audited grant path
while the front door is still open.

---

## Also worth checking — StoreKit

Lewis's commit says "load/purchase/verify/finish". Worth confirming the receipt
is verified **server-side** before credits are granted, not just locally on
device. If the native app grants credits after a purely client-side StoreKit
check, a modified device can mint credits the same way. Same class of problem,
different door.

Ask him directly: does the IAP grant path go through an edge function that
validates the transaction with Apple?

---

## Nothing here is pushed

No code written, no migrations run. Say the word and I'll start at step 1.
