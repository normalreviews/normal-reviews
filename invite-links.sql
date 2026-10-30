-- Normal Reviews: invites without an email. Paste into Supabase SQL Editor and click Run, once. Safe to run again.
-- An invite is an 8-character code (like KX7P-M2QD) that works once, for 14 days, for whoever has it.
-- Older invites tied to an email keep working.

alter table public.invites alter column email drop not null;

-- a signed-in tester makes a code; returns it (8 letters and numbers, no look-alikes like 0/O or 1/I)
create or replace function public.create_invite_code()
returns text language plpgsql security definer set search_path = public as $$
declare c text; mx integer; n integer; abc text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; i integer;
begin
  if auth.uid() is null then raise exception 'sign in first'; end if;
  select max_users into mx from public.app_settings where id = 1;
  select count(*) into n from auth.users;
  if n >= mx then raise exception 'beta_full'; end if;
  if (select count(*) from public.invites where invited_by = auth.uid() and used_at is null and expires_at > now()) >= 10
    then raise exception 'too_many_open'; end if;
  loop
    c := repeat('x', 0);
    for i in 1..8 loop c := c || substr(abc, 1 + floor(random() * length(abc))::int, 1); end loop;
    exit when not exists (select 1 from public.invites where token = c);
  end loop;
  insert into public.invites (token, email, invited_by) values (c, null, auth.uid());
  return c;
end $$;
revoke all on function public.create_invite_code() from public, anon;
grant execute on function public.create_invite_code() to authenticated;

-- checking a code before joining: a code without an email works for any email
create or replace function public.invite_check(p_email text, p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare e text := lower(trim(p_email)); c text := upper(coalesce(trim(p_code), 'none'));
        i public.invites; who text; mx integer; n integer;
begin
  delete from public.invite_tries where at < now() - interval '1 day';
  if (select count(*) from public.invite_tries where email = e and at > now() - interval '1 hour') >= 10
    then return json_build_object('ok', false, 'reason', 'locked'); end if;
  if exists (select 1 from auth.users where lower(email) = e) then return json_build_object('ok', false, 'reason', 'member'); end if;
  select * into i from public.invites where token = c and (email is null or lower(email) = e);
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
revoke all on function public.invite_check(text, text) from public;
grant execute on function public.invite_check(text, text) to anon, authenticated;

-- every new account needs a valid invite (and room in the beta); the code's email, if it has one, must match
create or replace function public.check_invite()
returns trigger language plpgsql security definer set search_path = public as $$
declare t text := upper(new.raw_user_meta_data->>'invite'); mx integer; n integer;
begin
  select max_users into mx from public.app_settings where id = 1;
  select count(*) into n from auth.users;
  if n >= mx then raise exception 'Normal Reviews beta is full'; end if;
  if t is null or not exists (
       select 1 from public.invites
        where upper(token) = t and (email is null or lower(email) = lower(new.email)) and used_at is null and expires_at > now())
    then raise exception 'Normal Reviews needs a valid invite to join'; end if;
  update public.invites set used_at = now(), used_by = new.id, email = coalesce(email, lower(new.email)) where upper(token) = t;
  return new;
end $$;
