-- Little Clan Diary — Supabase production-oriented schema v2
-- Run in Supabase SQL Editor after creating the project.
-- IMPORTANT: this file creates the database structure and RLS policies.
-- It does NOT create Auth users. Create the first admin in Authentication -> Users,
-- then insert the admin profile using the bootstrap section at the end.

create extension if not exists pgcrypto;

do $$ begin
  create type public.app_role as enum ('admin','teacher','parent');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.attendance_status as enum ('present','late','absent');
exception when duplicate_object then null; end $$;

create table if not exists public.schools(
  id uuid primary key default gen_random_uuid(),
  name text not null,
  city text,
  created_at timestamptz not null default now()
);

create table if not exists public.profiles(
  id uuid primary key references auth.users(id) on delete cascade,
  school_id uuid not null references public.schools(id) on delete cascade,
  role public.app_role not null,
  full_name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.classes(
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  name text not null,
  school_year text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.subjects(
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  code text not null,
  name text not null,
  icon text,
  active boolean not null default true,
  unique(school_id, code)
);

create table if not exists public.children(
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  class_id uuid references public.classes(id) on delete set null,
  first_name text not null,
  last_name text not null,
  birth_date date,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.child_parents(
  child_id uuid references public.children(id) on delete cascade,
  parent_id uuid references public.profiles(id) on delete cascade,
  relation_label text,
  primary key(child_id,parent_id)
);

create table if not exists public.schedule(
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete restrict,
  teacher_id uuid references public.profiles(id) on delete set null,
  weekday smallint not null check(weekday between 1 and 7),
  starts_at time not null,
  ends_at time not null,
  room text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  check(ends_at > starts_at)
);

create table if not exists public.attendance(
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  child_id uuid not null references public.children(id) on delete cascade,
  schedule_id uuid not null references public.schedule(id) on delete cascade,
  lesson_date date not null,
  status public.attendance_status not null default 'present',
  marked_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  unique(child_id,schedule_id,lesson_date)
);

create table if not exists public.observations(
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  child_id uuid not null references public.children(id) on delete cascade,
  subject_id uuid references public.subjects(id) on delete set null,
  teacher_id uuid not null references public.profiles(id) on delete restrict,
  observed_on date not null default current_date,
  note text not null,
  tags text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Helper functions. SECURITY DEFINER is used only for controlled membership checks.
-- search_path is pinned to reduce search-path hijacking risk.
create or replace function public.current_school_id()
returns uuid
language sql stable security definer
set search_path = ''
as $$
  select p.school_id
  from public.profiles p
  where p.id = auth.uid() and p.active = true
  limit 1
$$;

create or replace function public.current_role()
returns public.app_role
language sql stable security definer
set search_path = ''
as $$
  select p.role
  from public.profiles p
  where p.id = auth.uid() and p.active = true
  limit 1
$$;

create or replace function public.is_parent_of(target_child uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists(
    select 1
    from public.child_parents cp
    where cp.child_id = target_child
      and cp.parent_id = auth.uid()
  )
$$;

create or replace function public.is_teacher_for_schedule(target_schedule uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists(
    select 1
    from public.schedule s
    where s.id = target_schedule
      and s.teacher_id = auth.uid()
      and s.school_id = public.current_school_id()
      and s.active = true
  )
$$;

create or replace function public.is_teacher_for_child(target_child uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists(
    select 1
    from public.children c
    join public.schedule s on s.class_id = c.class_id
    where c.id = target_child
      and c.school_id = public.current_school_id()
      and s.teacher_id = auth.uid()
      and s.active = true
  )
$$;

create or replace function public.is_teacher_for_child_schedule(target_child uuid, target_schedule uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists(
    select 1
    from public.children c
    join public.schedule s on s.class_id = c.class_id
    where c.id = target_child
      and s.id = target_schedule
      and c.school_id = public.current_school_id()
      and s.school_id = public.current_school_id()
      and s.teacher_id = auth.uid()
      and s.active = true
  )
$$;

-- RLS everywhere.
alter table public.schools enable row level security;
alter table public.profiles enable row level security;
alter table public.classes enable row level security;
alter table public.subjects enable row level security;
alter table public.children enable row level security;
alter table public.child_parents enable row level security;
alter table public.schedule enable row level security;
alter table public.attendance enable row level security;
alter table public.observations enable row level security;

-- Cleanly replace policies if this script is re-run.
do $$
declare p record;
begin
  for p in select policyname, tablename from pg_policies where schemaname='public'
    and tablename in ('schools','profiles','classes','subjects','children','child_parents','schedule','attendance','observations')
  loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

-- Schools
create policy "school member reads own school" on public.schools
for select to authenticated
using (id = public.current_school_id());

-- Profiles: users can read themselves; admins can read their school; members can see teacher names only.
create policy "user reads own profile" on public.profiles
for select to authenticated
using (id = auth.uid());

create policy "admin reads school profiles" on public.profiles
for select to authenticated
using (school_id = public.current_school_id() and public.current_role() = 'admin');

create policy "members read teacher profiles" on public.profiles
for select to authenticated
using (school_id = public.current_school_id() and role = 'teacher');

create policy "admin manages profiles" on public.profiles
for all to authenticated
using (school_id = public.current_school_id() and public.current_role() = 'admin')
with check (school_id = public.current_school_id() and public.current_role() = 'admin');

-- Classes
create policy "members read classes" on public.classes
for select to authenticated
using (school_id = public.current_school_id());

create policy "admin manages classes" on public.classes
for all to authenticated
using (school_id = public.current_school_id() and public.current_role() = 'admin')
with check (school_id = public.current_school_id() and public.current_role() = 'admin');

-- Subjects
create policy "members read subjects" on public.subjects
for select to authenticated
using (school_id = public.current_school_id());

create policy "admin manages subjects" on public.subjects
for all to authenticated
using (school_id = public.current_school_id() and public.current_role() = 'admin')
with check (school_id = public.current_school_id() and public.current_role() = 'admin');

-- Children: admins see all; teachers only children in classes where they have an active lesson; parents only linked children.
create policy "admin reads children" on public.children
for select to authenticated
using (school_id = public.current_school_id() and public.current_role() = 'admin');

create policy "teacher reads assigned children" on public.children
for select to authenticated
using (school_id = public.current_school_id() and public.current_role() = 'teacher' and public.is_teacher_for_child(id));

create policy "parent reads linked child" on public.children
for select to authenticated
using (school_id = public.current_school_id() and public.current_role() = 'parent' and public.is_parent_of(id));

create policy "admin manages children" on public.children
for all to authenticated
using (school_id = public.current_school_id() and public.current_role() = 'admin')
with check (school_id = public.current_school_id() and public.current_role() = 'admin');

-- Parent links
create policy "parent reads own links" on public.child_parents
for select to authenticated
using (parent_id = auth.uid());

create policy "admin manages parent links" on public.child_parents
for all to authenticated
using (
  public.current_role() = 'admin'
  and exists(select 1 from public.children c where c.id = child_id and c.school_id = public.current_school_id())
)
with check (
  public.current_role() = 'admin'
  and exists(select 1 from public.children c where c.id = child_id and c.school_id = public.current_school_id())
);

-- Schedule: admins see/manage all; teachers see their own schedule; parents see schedule for their child's class.
create policy "admin reads schedule" on public.schedule
for select to authenticated
using (school_id = public.current_school_id() and public.current_role() = 'admin');

create policy "teacher reads own schedule" on public.schedule
for select to authenticated
using (school_id = public.current_school_id() and public.current_role() = 'teacher' and teacher_id = auth.uid());

create policy "parent reads child schedule" on public.schedule
for select to authenticated
using (
  school_id = public.current_school_id()
  and public.current_role() = 'parent'
  and exists(
    select 1 from public.children c
    where c.class_id = schedule.class_id
      and c.school_id = public.current_school_id()
      and public.is_parent_of(c.id)
  )
);

create policy "admin manages schedule" on public.schedule
for all to authenticated
using (school_id = public.current_school_id() and public.current_role() = 'admin')
with check (school_id = public.current_school_id() and public.current_role() = 'admin');

-- Attendance
create policy "admin reads attendance" on public.attendance
for select to authenticated
using (school_id = public.current_school_id() and public.current_role() = 'admin');

create policy "teacher reads assigned attendance" on public.attendance
for select to authenticated
using (school_id = public.current_school_id() and public.current_role() = 'teacher' and public.is_teacher_for_child_schedule(child_id, schedule_id));

create policy "parent reads child attendance" on public.attendance
for select to authenticated
using (school_id = public.current_school_id() and public.current_role() = 'parent' and public.is_parent_of(child_id));

create policy "teacher inserts attendance" on public.attendance
for insert to authenticated
with check (
  school_id = public.current_school_id()
  and public.current_role() = 'teacher'
  and public.is_teacher_for_child_schedule(child_id, schedule_id)
  and marked_by = auth.uid()
);

create policy "teacher updates attendance" on public.attendance
for update to authenticated
using (school_id = public.current_school_id() and public.current_role() = 'teacher' and public.is_teacher_for_child_schedule(child_id, schedule_id))
with check (school_id = public.current_school_id() and public.current_role() = 'teacher' and public.is_teacher_for_child_schedule(child_id, schedule_id) and marked_by = auth.uid());

create policy "admin manages attendance" on public.attendance
for all to authenticated
using (school_id = public.current_school_id() and public.current_role() = 'admin')
with check (school_id = public.current_school_id() and public.current_role() = 'admin');

-- Observations
create policy "admin reads observations" on public.observations
for select to authenticated
using (school_id = public.current_school_id() and public.current_role() = 'admin');

create policy "teacher reads assigned observations" on public.observations
for select to authenticated
using (school_id = public.current_school_id() and public.current_role() = 'teacher' and public.is_teacher_for_child(child_id));

create policy "parent reads child observations" on public.observations
for select to authenticated
using (school_id = public.current_school_id() and public.current_role() = 'parent' and public.is_parent_of(child_id));

create policy "teacher adds observation" on public.observations
for insert to authenticated
with check (
  school_id = public.current_school_id()
  and public.current_role() = 'teacher'
  and teacher_id = auth.uid()
  and public.is_teacher_for_child(child_id)
);

create policy "teacher edits own observation" on public.observations
for update to authenticated
using (school_id = public.current_school_id() and public.current_role() = 'teacher' and teacher_id = auth.uid() and public.is_teacher_for_child(child_id))
with check (school_id = public.current_school_id() and public.current_role() = 'teacher' and teacher_id = auth.uid() and public.is_teacher_for_child(child_id));

create policy "admin manages observations" on public.observations
for all to authenticated
using (school_id = public.current_school_id() and public.current_role() = 'admin')
with check (school_id = public.current_school_id() and public.current_role() = 'admin');

-- Useful indexes.
create index if not exists idx_profiles_school on public.profiles(school_id);
create index if not exists idx_children_school_class on public.children(school_id, class_id);
create index if not exists idx_child_parents_parent on public.child_parents(parent_id);
create index if not exists idx_schedule_school_teacher on public.schedule(school_id, teacher_id);
create index if not exists idx_schedule_class on public.schedule(class_id);
create index if not exists idx_attendance_child_date on public.attendance(child_id, lesson_date);
create index if not exists idx_observations_child_date on public.observations(child_id, observed_on desc);

-- Seed one school and the standard Little Clan subjects.
insert into public.schools(name, city)
select 'Little Clan', 'Nha Trang'
where not exists (select 1 from public.schools where name='Little Clan');

insert into public.subjects(school_id, code, name, icon)
select s.id, x.code, x.name, x.icon
from public.schools s
cross join (values
  ('rus','Русский язык','📖'),
  ('math','Математика','➗'),
  ('world','Окружающий мир','🌿'),
  ('art','ИЗО','🎨'),
  ('pe','Физическая культура','🏃'),
  ('music','Музыка','🎵'),
  ('eng','Английский язык','🔤'),
  ('after','Продлёнка','🧩')
) as x(code,name,icon)
where s.name='Little Clan'
on conflict (school_id, code) do update set name=excluded.name, icon=excluded.icon;

-- BOOTSTRAP FIRST ADMIN (run ONLY after creating the admin Auth user):
-- 1) Dashboard -> Authentication -> Users -> Add user -> create the first admin email/password.
-- 2) Copy that user's UUID.
-- 3) Replace YOUR_AUTH_USER_UUID below and run the INSERT.
--
-- insert into public.profiles(id, school_id, role, full_name)
-- select 'YOUR_AUTH_USER_UUID'::uuid, s.id, 'admin', 'Администратор Little Clan'
-- from public.schools s where s.name='Little Clan' limit 1;
