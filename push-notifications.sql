-- Little Clan Diary — push notifications + in-app notification center
-- Run AFTER the main schema and data-api-grants.sql.

create table if not exists public.notifications(
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  school_id uuid not null references public.schools(id) on delete cascade,
  type text not null default 'observation',
  title text not null,
  body text not null,
  data jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.push_subscriptions(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  endpoint text not null unique,
  subscription jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.notifications enable row level security;
alter table public.push_subscriptions enable row level security;

drop policy if exists "users read own notifications" on public.notifications;
create policy "users read own notifications" on public.notifications
for select to authenticated
using (recipient_id = auth.uid() and school_id = public.current_school_id());

drop policy if exists "users update own notifications" on public.notifications;
create policy "users update own notifications" on public.notifications
for update to authenticated
using (recipient_id = auth.uid() and school_id = public.current_school_id())
with check (recipient_id = auth.uid() and school_id = public.current_school_id());

drop policy if exists "users manage own push subscriptions" on public.push_subscriptions;
create policy "users manage own push subscriptions" on public.push_subscriptions
for all to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create index if not exists idx_notifications_recipient_created
  on public.notifications(recipient_id, created_at desc);
create index if not exists idx_notifications_unread
  on public.notifications(recipient_id, read_at);
create index if not exists idx_push_subscriptions_user
  on public.push_subscriptions(user_id);

-- Create an in-app notification for every parent linked to the child.
create or replace function public.notify_parents_about_observation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.notifications(recipient_id, school_id, type, title, body, data)
  select cp.parent_id,
         new.school_id,
         'observation',
         'Новое наблюдение в Little Clan',
         coalesce(
           (select p.full_name from public.profiles p where p.id = new.teacher_id limit 1),
           'Педагог'
         ) || ': ' || left(new.note, 180),
         jsonb_build_object('child_id', new.child_id, 'observation_id', new.id)
  from public.child_parents cp
  where cp.child_id = new.child_id;
  return new;
end;
$$;

drop trigger if exists trg_observation_parent_notification on public.observations;
create trigger trg_observation_parent_notification
after insert or update of note, tags, observed_on on public.observations
for each row execute function public.notify_parents_about_observation();

-- Notify parents only for late/absent attendance to avoid notification noise.
create or replace function public.notify_parents_about_attendance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status in ('late','absent') then
    insert into public.notifications(recipient_id, school_id, type, title, body, data)
    select cp.parent_id,
           new.school_id,
           'attendance',
           case when new.status='absent' then 'Отсутствие' else 'Опоздание' end,
           'Отметка посещаемости на ' || to_char(new.lesson_date, 'DD.MM.YYYY'),
           jsonb_build_object('child_id', new.child_id, 'attendance_id', new.id, 'status', new.status);
    from public.child_parents cp
    where cp.child_id = new.child_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_attendance_parent_notification on public.attendance;
create trigger trg_attendance_parent_notification
after insert or update of status, lesson_date on public.attendance
for each row execute function public.notify_parents_about_attendance();

-- Realtime is useful for the in-app notification counter while the app is open.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
exception when undefined_object then
  null;
end $$;
