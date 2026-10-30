alter table public.invites alter column email drop not null;

create or replace function public.create_invite_code()
returns text language plpgsql security definer set search_path = public as $$
declare c text; abc text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; k integer;
begin
  if auth.uid() is null then raise exception 'sign in first'; end if;
  if (select count(*) from auth.users) >= (select max_users from public.app_settings where id = 1) then raise exception 'beta_full'; end if;
  if (select count(*) from public.invites where invited_by = auth.uid() and used_at is null and expires_at > now()) >= 10
    then raise exception 'too_many_open'; end if;
  loop
    c := repeat('x', 0);
    for k in 1..8 loop c := c || substr(abc, 1 + floor(random() * length(abc))::int, 1); end loop;
    exit when not exists (select 1 from public.invites where token = c);
  end loop;
  insert into public.invites (token, email, invited_by) values (c, null, auth.uid());
  return c;
end $$;
revoke all on function public.create_invite_code() from public, anon;
grant execute on function public.create_invite_code() to authenticated;

create or replace function public.invite_check(p_email text, p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare e text := lower(trim(p_email)); c text := upper(coalesce(trim(p_code), 'none')); v public.invites;
begin
  delete from public.invite_tries where at < now() - interval '1 day';
  if (select count(*) from public.invite_tries where email = e and at > now() - interval '1 hour') >= 10
    then return json_build_object('ok', false, 'reason', 'locked'); end if;
  if exists (select 1 from auth.users where lower(email) = e) then return json_build_object('ok', false, 'reason', 'member'); end if;
  v := (select x from public.invites x where x.token = c and (x.email is null or lower(x.email) = e) limit 1);
  if v.token is null then
    insert into public.invite_tries (email) values (e);
    return json_build_object('ok', false, 'reason', 'nomatch');
  end if;
  if v.used_at is not null then return json_build_object('ok', false, 'reason', 'used'); end if;
  if v.expires_at <= now() then return json_build_object('ok', false, 'reason', 'expired'); end if;
  if (select count(*) from auth.users) >= (select max_users from public.app_settings where id = 1) then return json_build_object('ok', false, 'reason', 'full'); end if;
  return json_build_object('ok', true, 'inviter', coalesce((select display_name from public.profiles where id = v.invited_by), 'A tester'));
end $$;
revoke all on function public.invite_check(text, text) from public;
grant execute on function public.invite_check(text, text) to anon, authenticated;

create or replace function public.check_invite()
returns trigger language plpgsql security definer set search_path = public as $$
declare t text := upper(new.raw_user_meta_data->>'invite');
begin
  if (select count(*) from auth.users) >= (select max_users from public.app_settings where id = 1) then raise exception 'Normal Reviews beta is full'; end if;
  if t is null or not exists (
       select 1 from public.invites
        where upper(token) = t and (email is null or lower(email) = lower(new.email)) and used_at is null and expires_at > now())
    then raise exception 'Normal Reviews needs a valid invite to join'; end if;
  update public.invites set used_at = now(), used_by = new.id, email = coalesce(email, lower(new.email)) where upper(token) = t;
  return new;
end $$;

create or replace function public.cancel_invite(p_token text)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'sign in first'; end if;
  delete from public.invites where token = p_token and invited_by = auth.uid() and used_at is null;
  return found;
end $$;
revoke all on function public.cancel_invite(text) from public, anon;
grant execute on function public.cancel_invite(text) to authenticated;

notify pgrst, 'reload schema';
