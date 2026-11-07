-- ============ JADVALLAR ============
create table if not exists public.netquiz_rooms (
  code text primary key check (code ~ '^[A-Z0-9]{6}$'),
  title text not null,
  owner_id uuid not null references auth.users(id) on delete cascade,
  owner_name text not null,
  state text not null default 'lobby' check (state in ('lobby', 'active')),
  question_ids integer[] not null,
  created_at bigint not null
);

create table if not exists public.netquiz_participants (
  room_code text not null references public.netquiz_rooms(code) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  status text not null default 'waiting' check (status in ('waiting', 'solving', 'done')),
  progress integer not null default 0,
  score integer not null default 0,
  elapsed integer not null default 0,
  updated_at bigint not null default 0,
  primary key (room_code, user_id)
);

-- ============ TRIGGER: room_code va user_id o'zgarmasin ============
create or replace function public.prevent_netquiz_participant_identity_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.room_code is distinct from old.room_code
     or new.user_id is distinct from old.user_id then
    raise exception 'Participant room and user identity cannot be changed';
  end if;
  return new;
end;
$$;

drop trigger if exists netquiz_participant_identity_immutable on public.netquiz_participants;
create trigger netquiz_participant_identity_immutable
  before update on public.netquiz_participants
  for each row execute function public.prevent_netquiz_participant_identity_change();

-- ============ RLS ============
alter table public.netquiz_rooms enable row level security;
alter table public.netquiz_participants enable row level security;

create or replace function public.is_netquiz_room_member(p_room_code text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.netquiz_participants p
    where p.room_code = p_room_code
      and p.user_id = auth.uid()
  );
$$;

revoke all on function public.is_netquiz_room_member(text) from public;
grant execute on function public.is_netquiz_room_member(text) to authenticated;

-- Xonalar
drop policy if exists "Room members can read rooms" on public.netquiz_rooms;
create policy "Room members can read rooms"
  on public.netquiz_rooms for select to authenticated
  using (owner_id = auth.uid() or public.is_netquiz_room_member(code));

drop policy if exists "Users create rooms as owner" on public.netquiz_rooms;
create policy "Users create rooms as owner"
  on public.netquiz_rooms for insert to authenticated
  with check (owner_id = auth.uid());

drop policy if exists "Owners update rooms" on public.netquiz_rooms;
create policy "Owners update rooms"
  on public.netquiz_rooms for update to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

drop policy if exists "Owners delete rooms" on public.netquiz_rooms;
create policy "Owners delete rooms"
  on public.netquiz_rooms for delete to authenticated
  using (owner_id = auth.uid());

-- Ishtirokchilar
drop policy if exists "Room members can read participants" on public.netquiz_participants;
create policy "Room members can read participants"
  on public.netquiz_participants for select to authenticated
  using (public.is_netquiz_room_member(room_code));

drop policy if exists "Users update own participant row" on public.netquiz_participants;
create policy "Users update own participant row"
  on public.netquiz_participants for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "Users leave own room" on public.netquiz_participants;
create policy "Users leave own room"
  on public.netquiz_participants for delete to authenticated
  using (user_id = auth.uid());

-- ============ XONAGA QO'SHILISH FUNKSIYASI ============
create or replace function public.join_netquiz_room(p_room_code text, p_name text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not exists (
    select 1 from public.netquiz_rooms r where r.code = upper(p_room_code)
  ) then
    raise exception 'Room not found';
  end if;
  insert into public.netquiz_participants
    (room_code, user_id, name, status, progress, score, elapsed, updated_at)
  values
    (upper(p_room_code), auth.uid(), left(trim(p_name), 30), 'waiting', 0, 0, 0, (extract(epoch from now()) * 1000)::bigint)
  on conflict (room_code, user_id) do update
    set name = excluded.name,
        status = 'waiting',
        progress = 0,
        score = 0,
        elapsed = 0,
        updated_at = excluded.updated_at;
end;
$$;

revoke all on function public.join_netquiz_room(text, text) from public;
grant execute on function public.join_netquiz_room(text, text) to authenticated;

-- ============ RUXSATLAR ============
grant select, insert, update, delete on public.netquiz_rooms to authenticated;
grant select, update, delete on public.netquiz_participants to authenticated;

-- ============ REALTIME (xato bermaydi, qayta ishga tushirsa ham) ============
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'netquiz_rooms'
  ) then
    alter publication supabase_realtime add table public.netquiz_rooms;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'netquiz_participants'
  ) then
    alter publication supabase_realtime add table public.netquiz_participants;
  end if;
end $$;

-- ============ SCHEMA CACHE YANGILASH ============
notify pgrst, 'reload schema';