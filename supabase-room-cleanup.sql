-- Apply once in the Supabase SQL Editor. This migration leaves the base schema intact.

alter table public.netquiz_rooms
  drop constraint if exists netquiz_rooms_state_check;

alter table public.netquiz_rooms
  add constraint netquiz_rooms_state_check
  check (state in ('lobby', 'active', 'closed'));

do $$
declare
  v_room_code_att smallint;
  v_fk record;
  v_has_cascade boolean := false;
begin
  select a.attnum
  into v_room_code_att
  from pg_catalog.pg_attribute a
  where a.attrelid = 'public.netquiz_participants'::regclass
    and a.attname = 'room_code'
    and not a.attisdropped;

  for v_fk in
    select c.conname, c.confdeltype
    from pg_catalog.pg_constraint c
    where c.conrelid = 'public.netquiz_participants'::regclass
      and c.confrelid = 'public.netquiz_rooms'::regclass
      and c.contype = 'f'
      and c.conkey = array[v_room_code_att]::smallint[]
  loop
    if v_fk.confdeltype = 'c' then
      v_has_cascade := true;
    else
      execute format(
        'alter table public.netquiz_participants drop constraint %I',
        v_fk.conname
      );
    end if;
  end loop;

  if not v_has_cascade then
    alter table public.netquiz_participants
      add constraint netquiz_participants_room_code_fkey
      foreign key (room_code) references public.netquiz_rooms(code) on delete cascade;
  end if;
end;
$$;

create or replace function public.leave_netquiz_room(p_room_code text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_room_code text := upper(trim(p_room_code));
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1
    from public.netquiz_rooms r
    where r.code = v_room_code
  ) then
    raise exception 'Room not found';
  end if;

  update public.netquiz_rooms
  set state = 'closed'
  where code = v_room_code
    and owner_id = auth.uid()
    and state <> 'closed';

  delete from public.netquiz_participants
  where room_code = v_room_code
    and user_id = auth.uid();
end;
$$;

revoke all on function public.leave_netquiz_room(text) from public, anon;
grant execute on function public.leave_netquiz_room(text) to authenticated;

create or replace function public.join_netquiz_room(p_room_code text, p_name text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_room_code text := upper(trim(p_room_code));
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not exists (
    select 1
    from public.netquiz_rooms r
    where r.code = v_room_code
      and r.state <> 'closed'
  ) then
    raise exception 'Room not found or closed';
  end if;

  insert into public.netquiz_participants
    (room_code, user_id, name, status, progress, score, elapsed, updated_at)
  values
    (v_room_code, auth.uid(), left(trim(p_name), 30), 'waiting', 0, 0, 0,
     (extract(epoch from now()) * 1000)::bigint)
  on conflict (room_code, user_id) do update
    set name = excluded.name,
        status = 'waiting',
        progress = 0,
        score = 0,
        elapsed = 0,
        updated_at = excluded.updated_at;
end;
$$;

revoke all on function public.join_netquiz_room(text, text) from public, anon;
grant execute on function public.join_netquiz_room(text, text) to authenticated;

create or replace function public.cleanup_netquiz_inactive_rooms()
returns table (inactive_participants_deleted bigint, inactive_rooms_deleted bigint)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cutoff bigint := (extract(epoch from (now() - interval '5 minutes')) * 1000)::bigint;
begin
  delete from public.netquiz_participants p
  where p.updated_at < v_cutoff;
  get diagnostics inactive_participants_deleted = row_count;

  delete from public.netquiz_rooms r
  where r.created_at < v_cutoff
    and not exists (
      select 1
      from public.netquiz_participants p
      where p.room_code = r.code
        and p.updated_at >= v_cutoff
    );
  get diagnostics inactive_rooms_deleted = row_count;

  return next;
end;
$$;

revoke all on function public.cleanup_netquiz_inactive_rooms() from public, anon, authenticated, service_role;

create extension if not exists pg_cron with schema pg_catalog;

do $$
declare
  v_job_id bigint;
begin
  for v_job_id in
    select j.jobid
    from cron.job j
    where j.jobname = 'netquiz-inactive-room-cleanup'
  loop
    perform cron.unschedule(v_job_id);
  end loop;

  perform cron.schedule(
    'netquiz-inactive-room-cleanup',
    '*/10 * * * *',
    'select * from public.cleanup_netquiz_inactive_rooms();'
  );
end;
$$;
