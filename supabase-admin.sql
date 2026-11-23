-- Apply after supabase-schema.sql and supabase-room-cleanup.sql.
-- Admin credentials and sessions are kept outside the API-exposed public schema.

create extension if not exists pgcrypto with schema extensions;
create schema if not exists netquiz_private;

revoke all on schema netquiz_private from public, anon, authenticated;

create table if not exists netquiz_private.admin_credentials (
  username text primary key check (username = lower(btrim(username)) and length(username) between 1 and 100),
  password_hash text not null,
  created_at timestamptz not null default now()
);

create table if not exists netquiz_private.admin_sessions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  expires_at timestamptz not null
);

alter table netquiz_private.admin_credentials enable row level security;
alter table netquiz_private.admin_sessions enable row level security;
revoke all on netquiz_private.admin_credentials from public, anon, authenticated;
revoke all on netquiz_private.admin_sessions from public, anon, authenticated;

create or replace function public.netquiz_admin_login(p_username text, p_password text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_password_hash text;
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if p_username is null or p_password is null or p_password = ''
     or length(p_username) > 100 or length(p_password) > 1024 then
    delete from netquiz_private.admin_sessions where user_id = v_user_id;
    raise exception 'Login yoki parol noto‘g‘ri';
  end if;

  select c.password_hash
  into v_password_hash
  from netquiz_private.admin_credentials c
  where c.username = lower(btrim(p_username));

  if v_password_hash is null
     or extensions.crypt(p_password, v_password_hash) is distinct from v_password_hash then
    delete from netquiz_private.admin_sessions where user_id = v_user_id;
    raise exception 'Login yoki parol noto‘g‘ri';
  end if;

  insert into netquiz_private.admin_sessions (user_id, expires_at)
  values (v_user_id, now() + interval '30 minutes')
  on conflict (user_id) do update set expires_at = excluded.expires_at;
end;
$$;

create or replace function public.netquiz_admin_logout()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is not null then
    delete from netquiz_private.admin_sessions where user_id = auth.uid();
  end if;
end;
$$;

create or replace function public.netquiz_admin_list_rooms()
returns table (
  user_id uuid,
  user_email text,
  user_created_at timestamptz,
  owner_name text,
  room_code text,
  room_title text,
  room_state text,
  room_created_at bigint,
  active_participants bigint,
  last_activity bigint
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from netquiz_private.admin_sessions s
    where s.user_id = auth.uid()
      and s.expires_at > now()
  ) then
    raise exception 'Admin sessiyasi tugagan. Qayta kiring.';
  end if;

  update netquiz_private.admin_sessions
  set expires_at = now() + interval '30 minutes'
  where user_id = auth.uid();

  return query
  select u.id,
         u.email::text,
         u.created_at,
         coalesce(r.owner_name, latest_participant.name, nullif(u.raw_user_meta_data ->> 'display_name', '')),
         r.code,
         r.title,
         r.state,
         r.created_at,
         coalesce(activity.active_count, 0)::bigint,
         activity.last_seen
  from auth.users u
  left join public.netquiz_rooms r on r.owner_id = u.id
  left join lateral (
    select p.name
    from public.netquiz_participants p
    where p.user_id = u.id
    order by p.updated_at desc
    limit 1
  ) latest_participant on true
  left join lateral (
    select count(*) filter (
             where p.status in ('waiting', 'solving')
               and p.updated_at >= floor(extract(epoch from (now() - interval '5 minutes')) * 1000)::bigint
           ) as active_count,
           max(p.updated_at) as last_seen
    from public.netquiz_participants p
    where p.room_code = r.code
  ) activity on true
  order by u.created_at desc, r.created_at desc;
end;
$$;

create or replace function public.netquiz_admin_delete_room(p_room_code text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted_code text;
begin
  if not exists (
    select 1
    from netquiz_private.admin_sessions s
    where s.user_id = auth.uid()
      and s.expires_at > now()
  ) then
    raise exception 'Admin sessiyasi tugagan. Qayta kiring.';
  end if;

  update netquiz_private.admin_sessions
  set expires_at = now() + interval '30 minutes'
  where user_id = auth.uid();

  select r.code
  into v_deleted_code
  from public.netquiz_rooms r
  where r.code = upper(btrim(p_room_code))
  for update;

  if v_deleted_code is null then
    return false;
  end if;

  perform p.room_code
  from public.netquiz_participants p
  where p.room_code = v_deleted_code
  for update;

  if exists (
    select 1
    from public.netquiz_participants p
    where p.room_code = v_deleted_code
      and p.status in ('waiting', 'solving')
      and p.updated_at >= floor(extract(epoch from (now() - interval '5 minutes')) * 1000)::bigint
  ) then
    return false;
  end if;

  delete from public.netquiz_rooms r where r.code = v_deleted_code;

  return true;
end;
$$;

revoke all on function public.netquiz_admin_login(text, text) from public, anon;
revoke all on function public.netquiz_admin_logout() from public, anon;
revoke all on function public.netquiz_admin_list_rooms() from public, anon;
revoke all on function public.netquiz_admin_delete_room(text) from public, anon;
grant execute on function public.netquiz_admin_login(text, text) to authenticated;
grant execute on function public.netquiz_admin_logout() to authenticated;
grant execute on function public.netquiz_admin_list_rooms() to authenticated;
grant execute on function public.netquiz_admin_delete_room(text) to authenticated;

notify pgrst, 'reload schema';

-- Create a unique login and a strong password in the Supabase SQL Editor.
-- Replace both placeholders and run this statement once; never put the password
-- in supabase-config.js, index.html, or another browser-delivered file.
-- insert into netquiz_private.admin_credentials (username, password_hash)
-- values (
--   lower(btrim('YOUR_ADMIN_LOGIN')),
--   extensions.crypt('CHOOSE_A_LONG_UNIQUE_PASSWORD', extensions.gen_salt('bf', 12))
-- );
