-- Normal Reviews: restaurant names everyone sees. Paste into Supabase SQL Editor and click Run, once. Safe to run again.
--  * A name with profanity or slurs is never shared: it's dropped from the rating (the rating itself still counts).
--  * The name everyone sees for a place is the one the most people gave it (one vote per person, newest spelling wins ties).

-- (written without backslashes or empty quotes, which the Supabase editor can trip over)
create or replace function public.nr_bad_name(t text)
returns boolean language plpgsql immutable as $$
declare s text; w text; outp text; run text; words text[]; nothing text := repeat('x', 0);
        re text := '(^| )(fuck[a-z]*|fvck[a-z]*|fuk|fuks|fukk[a-z]*|fck|fcking|phuck|phucking|phucker[a-z]*|motherfuck[a-z]*|shit|shits|shitty|shithead[a-z]*|shithole[a-z]*|shithouse[a-z]*|shitter[a-z]*|bullshit|bitch|bitches|bitchass|cunt[a-z]*|asshole[a-z]*|dickhead[a-z]*|pussy|pussies|cocksuck[a-z]*|twat[a-z]*|wank[a-z]*|whore[a-z]*|slut[a-z]*|bastard[a-z]*|piss|pissed|nigg[a-z]*|fag|fags|faggot[a-z]*|retard[a-z]*|spic|spics|chink[a-z]*|kike[a-z]*|gook[a-z]*|wetback[a-z]*|tranny|trannies|dyke[a-z]*|porn[a-z]*|rape|rapist[a-z]*|nazi[a-z]*|hitler|kkk|penis[a-z]*|vagina[a-z]*|dildo[a-z]*|jizz[a-z]*|cum|cumshot[a-z]*|blowjob[a-z]*|handjob[a-z]*)( |$)';
begin
  if t is null then return false; end if;
  s := translate(lower(t), '0134579@$!|', 'oieastgasii');
  s := array_to_string(string_to_array(s, '*'), nothing);                 -- "f*ck" -> "fck"
  s := trim(regexp_replace(s, '[^a-z]+', ' ', 'g'));
  -- spaced-out letters ("s h i t") are joined back into a word
  words := string_to_array(s, ' ');
  if words is not null then
    foreach w in array words loop
      if length(w) = 1 then run := concat(run, w);
      else
        if run is not null then outp := concat(outp, ' ', run); run := null; end if;
        outp := concat(outp, ' ', w);
      end if;
    end loop;
    if run is not null then outp := concat(outp, ' ', run); end if;
  end if;
  s := trim(coalesce(outp, nothing));
  -- also with stretched letters squeezed ("fuuuuck" -> "fuck")
  return s ~ re or regexp_replace(s, '(.)' || chr(92) || '1' || chr(92) || '1+', chr(92) || '1', 'g') ~ re;
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
    select r.place_key, lower(regexp_replace(trim(r.place_name), '[[:space:]]+', ' ', 'g')) as k,
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
