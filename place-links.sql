-- Normal Reviews: shared link table (Google place ID -> open map restaurant).
-- Paste into Supabase SQL Editor and click Run, once. Safe to run again.
-- Stores only Google place IDs (allowed to keep permanently) and our own open-map listing.
-- No user is recorded with a link, and only restaurants are ever linked.

create table if not exists public.place_links (
  google_id  text primary key check (char_length(google_id) between 5 and 300),
  tile       text not null check (char_length(tile) <= 20),
  map_key    text not null check (char_length(map_key) <= 60),
  map_name   text check (char_length(map_name) <= 120),
  map_lat    double precision,
  map_lng    double precision,
  votes      integer not null default 1,
  updated_at timestamptz not null default now()
);
create index if not exists place_links_tile on public.place_links (tile);

alter table public.place_links enable row level security;
drop policy if exists "links are readable" on public.place_links;
create policy "links are readable" on public.place_links for select to anon, authenticated using (true);
-- no insert/update/delete policies: writes only go through link_place() below

create or replace function public.link_place(
  p_google_id text, p_tile text, p_map_key text, p_map_name text,
  p_lat double precision, p_lng double precision, p_fix boolean default false)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'sign in first'; end if;
  insert into place_links (google_id, tile, map_key, map_name, map_lat, map_lng)
  values (p_google_id, p_tile, p_map_key, left(p_map_name, 120), p_lat, p_lng)
  on conflict (google_id) do update set
    votes      = case when place_links.map_key = excluded.map_key then place_links.votes + 1
                      when p_fix then 1 else place_links.votes end,
    map_key    = case when p_fix then excluded.map_key  else place_links.map_key  end,
    map_name   = case when p_fix then excluded.map_name else place_links.map_name end,
    map_lat    = case when p_fix then excluded.map_lat  else place_links.map_lat  end,
    map_lng    = case when p_fix then excluded.map_lng  else place_links.map_lng  end,
    tile       = case when p_fix then excluded.tile     else place_links.tile     end,
    updated_at = now();
end $$;

revoke all on function public.link_place(text,text,text,text,double precision,double precision,boolean) from public, anon;
grant execute on function public.link_place(text,text,text,text,double precision,double precision,boolean) to authenticated;
