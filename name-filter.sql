-- Normal Reviews: restaurant names everyone sees. Paste into Supabase SQL Editor and click Run, once. Safe to run again.
--  * A name with profanity or slurs is never shared: it's dropped from the rating (the rating itself still counts).
--  * The name everyone sees for a place is the one the most people gave it (one vote per person, newest spelling wins ties).

create or replace function public.nr_bad_name(t text)
returns boolean language plpgsql immutable as $$
declare s text; w text; outp text := ''; run text := ''; words text[];
        re text := '\m(fuck\w*|fvck\w*|fuk|fuks|fukk\w*|fck|fcking|phuck|phucking|phucker\w*|motherfuck\w*|shit|shits|shitty|shithead\w*|shithole\w*|shithouse\w*|shitter\w*|bullshit|bitch|bitches|bitchass|cunt\w*|asshole\w*|dickhead\w*|pussy|pussies|cocksuck\w*|twat\w*|wank\w*|whore\w*|slut\w*|bastard\w*|piss|pissed|nigg\w*|fag|fags|faggot\w*|retard\w*|spic|spics|chink\w*|kike\w*|gook\w*|wetback\w*|tranny|trannies|dyke\w*|porn\w*|rape|rapist\w*|nazi\w*|hitler|kkk|penis\w*|vagina\w*|dildo\w*|jizz\w*|cum|cumshot\w*|blowjob\w*|handjob\w*)\M';
begin
  if t is null then return false; end if;
  s := translate(lower(t), '0134579@$!|', 'oieastgasii');
  s := replace(s, '*', '');
  s := trim(regexp_replace(s, '[^a-z]+', ' ', 'g'));
  -- "s h i t" -> "shit"
  words := string_to_array(s, ' ');
  if words is not null then
    foreach w in array words loop
      if length(w) = 1 then run := run || w;
      else
        if length(run) >= 3 then outp := outp || ' ' || run; elsif run <> '' then outp := outp || ' ' || array_to_string(regexp_split_to_array(run, ''), ' '); end if;
        run := ''; outp := outp || ' ' || w;
      end if;
    end loop;
    if length(run) >= 3 then outp := outp || ' ' || run; elsif run <> '' then outp := outp || ' ' || array_to_string(regexp_split_to_array(run, ''), ' '); end if;
  end if;
  s := trim(outp);
  return s ~ re or regexp_replace(s, '(.)\1{2,}', '\1', 'g') ~ re;
end $$;

-- drop bad names before they're saved
create or replace function public.nr_clean_name()
returns trigger language plpgsql as $$
begin
  if public.nr_bad_name(new.place_name) then new.place_name := null; end if;
  return new;
end $$;
drop trigger if exists nr_clean_name on public.ratings;
create trigger nr_clean_name before insert or update of place_name on public.ratings
  for each row execute function public.nr_clean_name();
update public.ratings set place_name = null where public.nr_bad_name(place_name);

-- the most common name for each place, one vote per person
create or replace function public.place_names(since date)
returns table (place_key text, name text, people int)
language sql stable security definer set search_path = public as $$
  with v as (
    select r.place_key, lower(regexp_replace(trim(r.place_name), '\s+', ' ', 'g')) as k,
           (array_agg(r.place_name order by r.created_at desc))[1] as name,
           count(distinct r.user_id)::int as people, max(r.created_at) as latest
    from public.ratings r
    where auth.uid() is not null and r.visit_day >= since and r.place_name is not null
      and length(trim(r.place_name)) > 0 and not public.nr_bad_name(r.place_name)
    group by r.place_key, 2
  )
  select distinct on (v.place_key) v.place_key, v.name, v.people from v
  order by v.place_key, v.people desc, v.latest desc;
$$;
revoke all on function public.place_names(date) from public, anon;
grant execute on function public.place_names(date) to authenticated;
