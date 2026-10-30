-- Normal Reviews: "My list" ordering. Paste into Supabase SQL Editor and click Run, once. Safe to run again.
-- Each rating gets a small adjustment (-0.4 to +0.4) from where you dragged that place in your list,
-- and friends' apps receive it so they can show your order.

alter table public.ratings add column if not exists adj real not null default 0;
alter table public.ratings drop constraint if exists ratings_adj_range;
alter table public.ratings add constraint ratings_adj_range check (adj between -0.5 and 0.5);

drop function if exists public.global_ratings(date);
create function public.global_ratings(since date)
returns table (
  id uuid, who uuid, visit_id text,
  place_key text, place_name text, place_label text, place_lat double precision, place_lng double precision,
  visit_day date, tier smallint, reasons text[], comment text, photo_path text,
  rater_n int, rater_grader text, adj real)
language sql stable security definer set search_path = public as $$
  with known as (
    select auth.uid() as uid
    union
    select f.friend_id from public.friends f where f.user_id = auth.uid()
  ),
  stats as (
    select user_id, count(*)::int as n, avg(tier) as a from public.ratings group by user_id
  ),
  overall as (select coalesce(avg(tier), 2) as a from public.ratings)
  select
    r.id,
    case when r.user_id in (select uid from known) then r.user_id end,
    case when r.user_id = auth.uid() then r.visit_id end,
    r.place_key, r.place_name, r.place_label, r.place_lat, r.place_lng,
    r.visit_day, r.tier, r.reasons, r.comment, r.photo_path,
    s.n,
    case when s.a - o.a > 0.25 then 'Easy grader' when s.a - o.a < -0.25 then 'Tough grader' else 'Calibrated' end,
    r.adj
  from public.ratings r
  join stats s on s.user_id = r.user_id
  cross join overall o
  where auth.uid() is not null and r.visit_day >= since;
$$;
revoke all on function public.global_ratings(date) from public, anon;
grant execute on function public.global_ratings(date) to authenticated;
