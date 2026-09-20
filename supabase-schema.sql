-- Little Clan Diary: схема Supabase для общей облачной базы
create extension if not exists pgcrypto;

do $$ begin create type public.app_role as enum ('admin','teacher','parent');
exception when duplicate_object then null; end $$;
do $$ begin create type public.attendance_status as enum ('present','late','absent');
exception when duplicate_object then null; end $$;

create table if not exists public.schools(
 id uuid primary key default gen_random_uuid(), name text not null, city text, created_at timestamptz default now()
);
create table if not exists public.profiles(
 id uuid primary key references auth.users(id) on delete cascade,
 school_id uuid not null references public.schools(id) on delete cascade,
 role public.app_role not null, full_name text not null, active boolean default true
);
create table if not exists public.classes(
 id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id) on delete cascade,
 name text not null, school_year text, active boolean default true
);
create table if not exists public.subjects(
 id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id) on delete cascade,
 code text not null, name text not null, icon text, active boolean default true, unique(school_id,code)
);
create table if not exists public.children(
 id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id) on delete cascade,
 class_id uuid references public.classes(id) on delete set null, first_name text not null, last_name text not null,
 birth_date date, active boolean default true
);
create table if not exists public.child_parents(
 child_id uuid references public.children(id) on delete cascade,
 parent_id uuid references public.profiles(id) on delete cascade,
 relation_label text, primary key(child_id,parent_id)
);
create table if not exists public.schedule(
 id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id) on delete cascade,
 class_id uuid not null references public.classes(id) on delete cascade,
 subject_id uuid not null references public.subjects(id) on delete restrict,
 teacher_id uuid references public.profiles(id) on delete set null,
 weekday smallint not null check(weekday between 1 and 7),
 starts_at time not null, ends_at time not null, room text, active boolean default true
);
create table if not exists public.attendance(
 id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id) on delete cascade,
 child_id uuid not null references public.children(id) on delete cascade,
 schedule_id uuid not null references public.schedule(id) on delete cascade,
 lesson_date date not null, status public.attendance_status not null default 'present',
 marked_by uuid references public.profiles(id) on delete set null, updated_at timestamptz default now(),
 unique(child_id,schedule_id,lesson_date)
);
create table if not exists public.observations(
 id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id) on delete cascade,
 child_id uuid not null references public.children(id) on delete cascade,
 subject_id uuid references public.subjects(id) on delete set null,
 teacher_id uuid not null references public.profiles(id) on delete restrict,
 observed_on date not null default current_date, note text not null, tags text[] not null default '{}',
 created_at timestamptz default now(), updated_at timestamptz default now()
);

create or replace function public.current_school_id() returns uuid
language sql stable security definer set search_path=public as $$
 select school_id from public.profiles where id=auth.uid() and active=true limit 1
$$;
create or replace function public.current_role() returns public.app_role
language sql stable security definer set search_path=public as $$
 select role from public.profiles where id=auth.uid() and active=true limit 1
$$;
create or replace function public.is_parent_of(target_child uuid) returns boolean
language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.child_parents where child_id=target_child and parent_id=auth.uid())
$$;
create or replace function public.is_teacher_for_schedule(target_schedule uuid) returns boolean
language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.schedule where id=target_schedule and teacher_id=auth.uid() and school_id=public.current_school_id())
$$;

alter table public.schools enable row level security;
alter table public.profiles enable row level security;
alter table public.classes enable row level security;
alter table public.subjects enable row level security;
alter table public.children enable row level security;
alter table public.child_parents enable row level security;
alter table public.schedule enable row level security;
alter table public.attendance enable row level security;
alter table public.observations enable row level security;

create policy "members read own school" on public.schools for select to authenticated using(id=public.current_school_id());
create policy "read own profile" on public.profiles for select to authenticated using(id=auth.uid());
create policy "admin reads school profiles" on public.profiles for select to authenticated using(school_id=public.current_school_id() and public.current_role()='admin');
create policy "members read teacher names" on public.profiles for select to authenticated using(school_id=public.current_school_id() and role='teacher');
create policy "admin manages profiles" on public.profiles for all to authenticated
 using(school_id=public.current_school_id() and public.current_role()='admin')
 with check(school_id=public.current_school_id() and public.current_role()='admin');

create policy "members read classes" on public.classes for select to authenticated using(school_id=public.current_school_id());
create policy "admin manages classes" on public.classes for all to authenticated
 using(school_id=public.current_school_id() and public.current_role()='admin')
 with check(school_id=public.current_school_id() and public.current_role()='admin');

create policy "members read subjects" on public.subjects for select to authenticated using(school_id=public.current_school_id());
create policy "admin manages subjects" on public.subjects for all to authenticated
 using(school_id=public.current_school_id() and public.current_role()='admin')
 with check(school_id=public.current_school_id() and public.current_role()='admin');

create policy "staff reads children" on public.children for select to authenticated
 using(school_id=public.current_school_id() and public.current_role() in ('admin','teacher'));
create policy "parent reads linked child" on public.children for select to authenticated
 using(school_id=public.current_school_id() and public.is_parent_of(id));
create policy "admin manages children" on public.children for all to authenticated
 using(school_id=public.current_school_id() and public.current_role()='admin')
 with check(school_id=public.current_school_id() and public.current_role()='admin');

create policy "parent reads own links" on public.child_parents for select to authenticated using(parent_id=auth.uid());
create policy "admin manages parent links" on public.child_parents for all to authenticated
 using(public.current_role()='admin' and exists(select 1 from public.children c where c.id=child_id and c.school_id=public.current_school_id()))
 with check(public.current_role()='admin' and exists(select 1 from public.children c where c.id=child_id and c.school_id=public.current_school_id()));

create policy "members read schedule" on public.schedule for select to authenticated using(school_id=public.current_school_id());
create policy "admin manages schedule" on public.schedule for all to authenticated
 using(school_id=public.current_school_id() and public.current_role()='admin')
 with check(school_id=public.current_school_id() and public.current_role()='admin');

create policy "admin reads attendance" on public.attendance for select to authenticated
 using(school_id=public.current_school_id() and public.current_role()='admin');
create policy "teacher reads own lesson attendance" on public.attendance for select to authenticated
 using(school_id=public.current_school_id() and public.current_role()='teacher' and public.is_teacher_for_schedule(schedule_id));
create policy "parent reads child attendance" on public.attendance for select to authenticated
 using(school_id=public.current_school_id() and public.current_role()='parent' and public.is_parent_of(child_id));
create policy "teacher inserts attendance" on public.attendance for insert to authenticated
 with check(school_id=public.current_school_id() and public.current_role()='teacher' and public.is_teacher_for_schedule(schedule_id) and marked_by=auth.uid());
create policy "teacher updates attendance" on public.attendance for update to authenticated
 using(school_id=public.current_school_id() and public.current_role()='teacher' and public.is_teacher_for_schedule(schedule_id))
 with check(school_id=public.current_school_id() and public.current_role()='teacher' and public.is_teacher_for_schedule(schedule_id));
create policy "admin manages attendance" on public.attendance for all to authenticated
 using(school_id=public.current_school_id() and public.current_role()='admin')
 with check(school_id=public.current_school_id() and public.current_role()='admin');

create policy "staff reads observations" on public.observations for select to authenticated
 using(school_id=public.current_school_id() and public.current_role() in ('admin','teacher'));
create policy "parent reads child observations" on public.observations for select to authenticated
 using(school_id=public.current_school_id() and public.current_role()='parent' and public.is_parent_of(child_id));
create policy "teacher adds observation" on public.observations for insert to authenticated
 with check(school_id=public.current_school_id() and public.current_role()='teacher' and teacher_id=auth.uid());
create policy "teacher edits own observation" on public.observations for update to authenticated
 using(school_id=public.current_school_id() and public.current_role()='teacher' and teacher_id=auth.uid())
 with check(school_id=public.current_school_id() and public.current_role()='teacher' and teacher_id=auth.uid());
create policy "admin manages observations" on public.observations for all to authenticated
 using(school_id=public.current_school_id() and public.current_role()='admin')
 with check(school_id=public.current_school_id() and public.current_role()='admin');

-- Для Realtime в Supabase включите таблицы attendance и observations в публикации.
-- Предметы после создания школы:
-- Русский язык, Математика, Окружающий мир, ИЗО, Физическая культура,
-- Музыка, Английский язык, Продлёнка.
