-- Admin metrics: funnel, repeat purchase, revenue in £, outstanding credit liability.
-- Run in Supabase > SQL Editor. Called only by the admin edge function (service role).
--
-- NOTE: deliberately never selects chop_jobs.data wholesale — payloads are huge.
-- Only data->>'status' is read.

create or replace function public.chop_admin_metrics(p_from date, p_to date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare res jsonb;
begin
  select jsonb_build_object(

    -- 1. FUNNEL — of people who signed up in range, how far did they get?
    'funnel', (
      select jsonb_build_object(
        'signed_up',    count(*),
        'profile_done', count(*) filter (where p.name is not null and p.name <> ''),
        'uploaded',     count(*) filter (where coalesce(j.n,0) > 0),
        'reviewed',     count(*) filter (where coalesce(j.reviewed,0) > 0),
        'exported',     count(*) filter (where coalesce(j.exported,0) > 0)
      )
      from auth.users u
      left join chop_profiles p on p.id = u.id
      left join (
        select user_id,
               count(*)                                                          as n,
               count(*) filter (where data->>'status' in ('review','approved','exported')) as reviewed,
               count(*) filter (where data->>'status' = 'exported')               as exported
        from chop_jobs
        group by user_id
      ) j on j.user_id = u.id
      where u.created_at::date between p_from and p_to
    ),

    -- 2. REPEAT PURCHASE — all time, this is the retention signal
    'repeat', (
      select jsonb_build_object(
        'buyers',        coalesce(count(*),0),
        'repeat_buyers', coalesce(count(*) filter (where c > 1),0),
        'repeat_pct',    case when count(*) = 0 then 0
                              else round(100.0 * count(*) filter (where c > 1) / count(*), 1) end,
        'avg_orders',    coalesce(round(avg(c),2),0)
      )
      from (select user_id, count(*) c from chop_purchases group by user_id) t
    ),

    -- 3. REVENUE in pence, per day in range + totals
    'revenue_total',    (select coalesce(sum(pence),0) from chop_purchases
                          where created_at::date between p_from and p_to),
    'revenue_all_time', (select coalesce(sum(pence),0) from chop_purchases),
    'revenue_days', (
      select coalesce(jsonb_agg(jsonb_build_object('d', d, 'pence', pence) order by d), '[]'::jsonb)
      from (select created_at::date as d, sum(pence)::bigint as pence
              from chop_purchases
             where created_at::date between p_from and p_to
             group by 1) r
    ),

    -- 4. OUTSTANDING CREDIT LIABILITY — paid-for credits not yet spent.
    --    Balances mix free and paid credits, so we count at most what each
    --    user actually bought. Valued at what they paid per credit.
    'liability', (
      select jsonb_build_object(
        'credits',   coalesce(sum(least(coalesce(p.credits,0), coalesce(b.bought,0))),0),
        'pence_est', coalesce(sum(least(coalesce(p.credits,0), coalesce(b.bought,0)) * coalesce(b.avg_pence,0))::bigint,0)
      )
      from chop_profiles p
      left join (
        select user_id,
               sum(credits) as bought,
               case when sum(credits) = 0 then 0 else sum(pence)::numeric / sum(credits) end as avg_pence
        from chop_purchases group by user_id
      ) b on b.user_id = p.id
    )

  ) into res;
  return res;
end $$;

revoke all on function public.chop_admin_metrics(date,date) from public, anon, authenticated;
