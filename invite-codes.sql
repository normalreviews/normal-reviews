-- Normal Reviews: 6-digit invite codes. Paste into Supabase SQL Editor and click Run, once. Safe to run again.
-- An invite is now a 6-digit code for one email: it works once, for 14 days. The invited person types
-- their email and the code in the app. Links you already sent keep working.

-- wrong-code tries, so nobody can guess codes (10 wrong tries per email per hour, then a pause)
create table if not exists public.invite_tries (
  email text not null,
  at    timestamptz not null default now()
);
create index if not exists invite_tries_email on public.invite_tries (email, at);
alter table public.invite_tries enable row level security;
revoke all on public.invite_tries from anon, authenticated;

create or replace function public.create_invite(p_email text)
returns text language plpgsql security definer set search_path = public as $$
declare e text := lower(trim(p_email)); t text; c text; mx integer; n integer;
begin
  if auth.uid() is null then raise exception 'sign in first'; end if;
  if e !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'invalid_email'; end if;
  if exists (select 1 from auth.users where lower(email) = e) then raise exception 'already_member'; end if;
  select max_users into mx from public.app_settings where id = 1;
  select count(*) into n from auth.users;
  if n >= mx then raise exception 'beta_full'; end if;
  loop   -- a fresh 6-digit code no other invite has ever used
    c := lpad((floor(random() * 1000000))::int::text, 6, '0');
    exit when not exists (select 1 from public.invites where token = c);
  end loop;
  select token into t from public.invites
   where lower(email) = e and used_at is null and expires_at > now()
   order by created_at desc limit 1;
  if t is not null then
    if length(t) = 6 then return t; end if;
    update public.invites set token = c where token = t;   -- an older link-style invite gets a code
    return c;
  end if;
  if (select count(*) from public.invites where invited_by = auth.uid() and used_at is null and expires_at > now()) >= 10
    then raise exception 'too_many_open'; end if;
  insert into public.invites (token, email, invited_by) values (c, e, auth.uid());
  return c;
end $$;

-- old-style invite links only; a 6-digit code always needs its email too
create or replace function public.invite_info(p_token text)
returns json language plpgsql stable security definer set search_path = public as $$
declare i public.invites; who text; mx integer; n integer;
begin
  if length(coalesce(p_token, '')) < 16 then return json_build_object('ok', false, 'reason', 'notfound'); end if;
  select * into i from public.invites where token = p_token;
  if not found then return json_build_object('ok', false, 'reason', 'notfound'); end if;
  if i.used_at is not null then return json_build_object('ok', false, 'reason', 'used', 'email', i.email); end if;
  if i.expires_at <= now() then return json_build_object('ok', false, 'reason', 'expired'); end if;
  select max_users into mx from public.app_settings where id = 1;
  select count(*) into n from auth.users;
  if n >= mx then return json_build_object('ok', false, 'reason', 'full'); end if;
  select display_name into who from public.profiles where id = i.invited_by;
  return json_build_object('ok', true, 'email', i.email, 'inviter', coalesce(who, 'A tester'));
end $$;

-- the app checks an email + code before showing "Join"
create or replace function public.invite_check(p_email text, p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare e text := lower(trim(p_email)); c text := regexp_replace(coalesce(p_code, ''), '\D', '', 'g');
        i public.invites; who text; mx integer; n integer;
begin
  delete from public.invite_tries where at < now() - interval '1 day';
  if (select count(*) from public.invite_tries where email = e and at > now() - interval '1 hour') >= 10
    then return json_build_object('ok', false, 'reason', 'locked'); end if;
  if exists (select 1 from auth.users where lower(email) = e) then return json_build_object('ok', false, 'reason', 'member'); end if;
  select * into i from public.invites where token = c and lower(email) = e;
  if not found then
    insert into public.invite_tries (email) values (e);
    return json_build_object('ok', false, 'reason', 'nomatch');
  end if;
  if i.used_at is not null then return json_build_object('ok', false, 'reason', 'used'); end if;
  if i.expires_at <= now() then return json_build_object('ok', false, 'reason', 'expired'); end if;
  select max_users into mx from public.app_settings where id = 1;
  select count(*) into n from auth.users;
  if n >= mx then return json_build_object('ok', false, 'reason', 'full'); end if;
  select display_name into who from public.profiles where id = i.invited_by;
  return json_build_object('ok', true, 'inviter', coalesce(who, 'A tester'));
end $$;

revoke all on function public.create_invite(text) from public, anon;
grant execute on function public.create_invite(text) to authenticated;
grant execute on function public.invite_info(text) to anon, authenticated;
revoke all on function public.invite_check(text, text) from public;
grant execute on function public.invite_check(text, text) to anon, authenticated;
