-- =====================================================================
-- Normal Reviews: beta database setup
-- Paste this whole file into Supabase → SQL Editor → New query → Run.
-- Safe to run once on a new, empty project.
--
-- Privacy design:
--   * No Timelines, stops, routes or times are ever stored here.
--   * A rating stores: which restaurant, the DAY of the visit, the tier,
--     optional comment / problem reasons / photo.
--   * People can only read and change their OWN rows directly.
--   * Everyone else's ratings come through global_ratings(), which only
--     reveals who rated something if that person is you or your friend.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- tables ----------------------------------------------------

create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text check (char_length(display_name) <= 40),
  friend_code  text unique not null default upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 6)),
  created_at   timestamptz not null default now()
);

create table if not exists public.friends (
  user_id    uuid not null references auth.users(id) on delete cascade,
  friend_id  uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id),
  check (user_id <> friend_id)
);

create table if not exists public.ratings (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  visit_id    text not null check (char_length(visit_id) <= 300),
  place_key   text not null check (char_length(place_key) <= 200),
  place_name  text check (char_length(place_name) <= 120),
  place_label text check (char_length(place_label) <= 80),
  place_lat   double precision,      -- the restaurant's location, rounded to ~10 m
  place_lng   double precision,
  visit_day   date not null,         -- day only, never the time
  tier        smallint not null check (tier between 0 and 4),
  reasons     text[],
  comment     text check (char_length(comment) <= 140),
  photo_path  text check (char_length(photo_path) <= 200),
  created_at  timestamptz not null default now(),
  unique (user_id, visit_id)
);
create index if not exists ratings_visit_day_idx on public.ratings (visit_day);
create index if not exists ratings_place_key_idx on public.ratings (place_key);

-- ---------- row level security -----------------------------------------

alter table public.profiles enable row level security;
alter table public.friends  enable row level security;
alter table public.ratings  enable row level security;

-- profiles: see yourself and your friends; you may only change your own name
drop policy if exists "profiles: read self or friends" on public.profiles;
create policy "profiles: read self or friends" on public.profiles
  for select to authenticated
  using (id = auth.uid() or exists (
    select 1 from public.friends f where f.user_id = auth.uid() and f.friend_id = profiles.id));

drop policy if exists "profiles: update own" on public.profiles;
create policy "profiles: update own" on public.profiles
  for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

revoke insert, update, delete on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (display_name) on public.profiles to authenticated;

-- friends: you see and remove only your own friendships (adding goes through add_friend)
drop policy if exists "friends: read own" on public.friends;
create policy "friends: read own" on public.friends
  for select to authenticated using (user_id = auth.uid());

revoke insert, update, delete on public.friends from anon, authenticated;
grant select on public.friends to authenticated;

-- ratings: direct access only to your own rows
drop policy if exists "ratings: read own"   on public.ratings;
drop policy if exists "ratings: insert own" on public.ratings;
drop policy if exists "ratings: update own" on public.ratings;
drop policy if exists "ratings: delete own" on public.ratings;
create policy "ratings: read own"   on public.ratings for select to authenticated using (user_id = auth.uid());
create policy "ratings: insert own" on public.ratings for insert to authenticated with check (user_id = auth.uid());
create policy "ratings: update own" on public.ratings for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "ratings: delete own" on public.ratings for delete to authenticated using (user_id = auth.uid());

revoke all on public.ratings from anon;
grant select, insert, update, delete on public.ratings to authenticated;

-- ---------- a profile for every new sign-up ---------------------------

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id) values (new.id) on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users for each row execute function public.handle_new_user();

-- ---------- friends by code -------------------------------------------

create or replace function public.add_friend(code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare other uuid;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  select id into other from public.profiles where friend_code = upper(trim(code));
  if other is null then raise exception 'No one has that friend code'; end if;
  if other = auth.uid() then raise exception 'That is your own code'; end if;
  insert into public.friends (user_id, friend_id)
    values (auth.uid(), other), (other, auth.uid())
    on conflict do nothing;
  return other;
end $$;

create or replace function public.remove_friend(other uuid)
returns void language sql security definer set search_path = public as $$
  delete from public.friends
  where auth.uid() is not null
    and ((user_id = auth.uid() and friend_id = other) or (user_id = other and friend_id = auth.uid()));
$$;

-- ---------- everyone's ratings, with strangers kept anonymous ---------
-- "who" is filled in only for you and your friends; for everyone else it is null.
-- Rater badges are coarse (a rating count and a grader type), not an identity.

create or replace function public.global_ratings(since date)
returns table (
  id uuid, who uuid, visit_id text,
  place_key text, place_name text, place_label text, place_lat double precision, place_lng double precision,
  visit_day date, tier smallint, reasons text[], comment text, photo_path text,
  rater_n int, rater_grader text)
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
    case when s.a - o.a > 0.25 then 'Easy grader' when s.a - o.a < -0.25 then 'Tough grader' else 'Calibrated' end
  from public.ratings r
  join stats s on s.user_id = r.user_id
  cross join overall o
  where auth.uid() is not null and r.visit_day >= since;
$$;

-- ---------- delete everything you've shared ---------------------------

create or replace function public.delete_my_data()
returns void language sql security definer set search_path = public as $$
  delete from public.ratings where user_id = auth.uid();
  delete from public.friends where user_id = auth.uid() or friend_id = auth.uid();
  update public.profiles set display_name = null where id = auth.uid();
$$;

revoke execute on function public.add_friend(text)       from public, anon;
revoke execute on function public.remove_friend(uuid)    from public, anon;
revoke execute on function public.global_ratings(date)   from public, anon;
revoke execute on function public.delete_my_data()       from public, anon;
grant  execute on function public.add_friend(text)       to authenticated;
grant  execute on function public.remove_friend(uuid)    to authenticated;
grant  execute on function public.global_ratings(date)   to authenticated;
grant  execute on function public.delete_my_data()       to authenticated;

-- ---------- photos -----------------------------------------------------
-- Private bucket; file names are random, so a photo never reveals who took it.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', false, 2097152, array['image/jpeg'])
on conflict (id) do nothing;

drop policy if exists "photos: upload" on storage.objects;
drop policy if exists "photos: read"   on storage.objects;
drop policy if exists "photos: delete own" on storage.objects;
create policy "photos: upload" on storage.objects
  for insert to authenticated with check (bucket_id = 'photos');
create policy "photos: read" on storage.objects
  for select to authenticated using (bucket_id = 'photos');
create policy "photos: delete own" on storage.objects
  for delete to authenticated using (bucket_id = 'photos' and owner_id = auth.uid()::text);

-- Done. You should see "Success. No rows returned".
