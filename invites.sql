-- Normal Reviews: invite-only sign-up with a beta size limit.
-- Paste into Supabase SQL Editor and click Run, once. Safe to run again.
--   * Any signed-in tester can invite an email address; the link works once, for that email, for 14 days.
--   * New accounts are only created with a valid invite, and only while the beta has room.
--   * Whoever invited you becomes your friend automatically.
-- Change the beta size later with:  update public.app_settings set max_users = 25;

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.app_settings (
  id        integer primary key default 1 check (id = 1),
  max_users integer not null default 15 check (max_users > 0)
);
insert into public.app_settings (id, max_users) values (1, 15) on conflict (id) do nothing;
alter table public.app_settings enable row level security;
drop policy if exists "settings are readable" on public.app_settings;
create policy "settings are readable" on public.app_settings for select to anon, authenticated using (true);

create table if not exists public.invites (
  token      text primary key default encode(extensions.gen_random_bytes(12), 'hex'),
  email      text not null check (char_length(email) between 3 and 254),
  invited_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '14 days',
  used_at    timestamptz,
  used_by    uuid
);
create index if not exists invites_email on public.invites (lower(email));
alter table public.invites enable row level security;
drop policy if exists "invites: see the ones I sent" on public.invites;
create policy "invites: see the ones I sent" on public.invites for select to authenticated using (invited_by = auth.uid());
grant select on public.invites to authenticated;

-- how full the beta is
create or replace function public.beta_status()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object('users', (select count(*) from auth.users),
                           'max',   (select max_users from public.app_settings where id = 1));
$$;

-- a signed-in tester invites an email address; returns the invite token for the link
create or replace function public.create_invite(p_email text)
returns text language plpgsql security definer set search_path = public as $$
declare e text := lower(trim(p_email)); t text; mx integer; n integer;
begin
  if auth.uid() is null then raise exception 'sign in first'; end if;
  if e !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'invalid_email'; end if;
  if exists (select 1 from auth.users where lower(email) = e) then raise exception 'already_member'; end if;
  select max_users into mx from public.app_settings where id = 1;
  select count(*) into n from auth.users;
  if n >= mx then raise exception 'beta_full'; end if;
  select token into t from public.invites
   where lower(email) = e and used_at is null and expires_at > now()
   order by created_at desc limit 1;
  if t is not null then return t; end if;
  if (select count(*) from public.invites where invited_by = auth.uid() and used_at is null and expires_at > now()) >= 10
    then raise exception 'too_many_open'; end if;
  insert into public.invites (email, invited_by) values (e, auth.uid()) returning token into t;
  return t;
end $$;

-- what an invite link shows before sign-up (works signed out)
create or replace function public.invite_info(p_token text)
returns json language plpgsql stable security definer set search_path = public as $$
declare i public.invites; who text; mx integer; n integer;
begin
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

-- every new account needs a valid invite for its email, and room in the beta
create or replace function public.check_invite()
returns trigger language plpgsql security definer set search_path = public as $$
declare t text := new.raw_user_meta_data->>'invite'; mx integer; n integer;
begin
  select max_users into mx from public.app_settings where id = 1;
  select count(*) into n from auth.users;
  if n >= mx then raise exception 'Normal Reviews beta is full'; end if;
  if t is null or not exists (
       select 1 from public.invites
        where token = t and lower(email) = lower(new.email) and used_at is null and expires_at > now())
    then raise exception 'Normal Reviews needs a valid invite to join'; end if;
  update public.invites set used_at = now(), used_by = new.id where token = t;
  return new;
end $$;
drop trigger if exists nr_check_invite on auth.users;
create trigger nr_check_invite before insert on auth.users for each row execute function public.check_invite();

-- after joining: keep the name they chose, and make them friends with whoever invited them
create or replace function public.after_join()
returns trigger language plpgsql security definer set search_path = public as $$
declare who uuid; nm text := left(nullif(trim(new.raw_user_meta_data->>'display_name'), ''), 40);
begin
  if nm is not null then update public.profiles set display_name = nm where id = new.id; end if;
  select invited_by into who from public.invites where used_by = new.id limit 1;
  if who is not null and who <> new.id then
    insert into public.friends (user_id, friend_id) values (new.id, who), (who, new.id) on conflict do nothing;
  end if;
  return new;
end $$;
drop trigger if exists on_auth_user_joined on auth.users;
create trigger on_auth_user_joined after insert on auth.users for each row execute function public.after_join();

revoke all on function public.create_invite(text) from public, anon;
grant execute on function public.create_invite(text) to authenticated;
grant execute on function public.invite_info(text) to anon, authenticated;
grant execute on function public.beta_status() to anon, authenticated;
