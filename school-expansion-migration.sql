-- Little Clan Diary — полный пакет расширения схемы
-- Запускать один раз в Supabase → SQL Editor под владельцем проекта.
-- Существующие дети, расписание и история не удаляются.

-- 1. Дополнительные поля карточки ребёнка и предметов
alter table public.children add column if not exists parent_telegram text;
alter table public.children add column if not exists aftercare_active boolean not null default true;
alter table public.subjects add column if not exists category text not null default 'lesson';
update public.subjects set category='meal' where code in ('breakfast','lunch','snack');
update public.subjects set category='routine' where code in ('circle','break','extended');

-- 2. Учебные группы: английский по уровню, ИКТ, физкультура, технология, элективы
create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  name text not null,
  group_type text not null default 'learning' check (group_type in ('learning','english','elective')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (school_id, name)
);
create table if not exists public.child_groups (
  child_id uuid not null references public.children(id) on delete cascade,
  group_id uuid not null references public.groups(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (child_id, group_id)
);
create index if not exists child_groups_group_idx on public.child_groups(group_id);

-- 3. Расписание может быть для класса, группы, всей школы или продлёнки
alter table public.schedule alter column class_id drop not null;
alter table public.schedule add column if not exists group_id uuid references public.groups(id) on delete set null;
alter table public.schedule add column if not exists audience_type text not null default 'class';
-- Существующие записи остаются расписанием класса.
update public.schedule set audience_type='class' where audience_type is null;

-- 4. Примеры работ: метаданные + приватное хранилище изображений
create table if not exists public.child_work_samples (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  child_id uuid not null references public.children(id) on delete cascade,
  subject_id uuid references public.subjects(id) on delete set null,
  schedule_id uuid references public.schedule(id) on delete set null,
  uploaded_by uuid references public.profiles(id) on delete set null,
  title text,
  note text,
  storage_path text not null,
  created_at timestamptz not null default now()
);
create index if not exists child_work_samples_child_created_idx on public.child_work_samples(child_id, created_at desc);

-- 5. Доступ к таблицам. RLS остаётся обязательным; эти политики ограничивают школу и роль.
grant select, insert, update, delete on public.groups, public.child_groups, public.child_work_samples to authenticated;
alter table public.groups enable row level security;
alter table public.child_groups enable row level security;
alter table public.child_work_samples enable row level security;

drop policy if exists "school members read groups" on public.groups;
create policy "school members read groups" on public.groups for select to authenticated
using (school_id = public.current_school_id());
drop policy if exists "admins manage groups" on public.groups;
create policy "admins manage groups" on public.groups for all to authenticated
using (school_id = public.current_school_id() and public.current_role() = 'admin')
with check (school_id = public.current_school_id() and public.current_role() = 'admin');

drop policy if exists "school members read child groups" on public.child_groups;
create policy "school members read child groups" on public.child_groups for select to authenticated
using (exists (select 1 from public.children c where c.id=child_id and c.school_id=public.current_school_id()) and (public.current_role() in ('admin','teacher') or (public.current_role()='parent' and public.is_parent_of(child_id))));
drop policy if exists "admins manage child groups" on public.child_groups;
create policy "admins manage child groups" on public.child_groups for all to authenticated
using (public.current_role()='admin' and exists (select 1 from public.children c where c.id=child_id and c.school_id=public.current_school_id()) and exists (select 1 from public.groups g where g.id=group_id and g.school_id=public.current_school_id()))
with check (public.current_role()='admin' and exists (select 1 from public.children c where c.id=child_id and c.school_id=public.current_school_id()) and exists (select 1 from public.groups g where g.id=group_id and g.school_id=public.current_school_id()));

drop policy if exists "admin manages child work samples" on public.child_work_samples;
create policy "admin manages child work samples" on public.child_work_samples for all to authenticated
using (school_id=public.current_school_id() and public.current_role()='admin')
with check (school_id=public.current_school_id() and public.current_role()='admin');
drop policy if exists "teachers manage child work samples" on public.child_work_samples;
create policy "teachers manage child work samples" on public.child_work_samples for all to authenticated
using (school_id=public.current_school_id() and public.current_role()='teacher')
with check (school_id=public.current_school_id() and public.current_role()='teacher');
drop policy if exists "parents read linked child work samples" on public.child_work_samples;
create policy "parents read linked child work samples" on public.child_work_samples for select to authenticated
using (school_id=public.current_school_id() and public.current_role()='parent' and public.is_parent_of(child_id));

-- Schedule visibility for parents includes group lessons and school-wide meals/activities.
drop policy if exists "parents read relevant schedule entries" on public.schedule;
create policy "parents read relevant schedule entries" on public.schedule for select to authenticated
using (
 school_id=public.current_school_id() and public.current_role()='parent' and (
  (audience_type='class' and exists (select 1 from public.child_parents cp join public.children c on c.id=cp.child_id where cp.parent_id=auth.uid() and c.class_id=schedule.class_id))
  or (audience_type='group' and exists (select 1 from public.child_parents cp join public.child_groups cg on cg.child_id=cp.child_id where cp.parent_id=auth.uid() and cg.group_id=schedule.group_id))
  or audience_type='school'
  or (audience_type='aftercare' and exists (select 1 from public.child_parents cp join public.children c on c.id=cp.child_id where cp.parent_id=auth.uid() and c.aftercare_active=true))
 )
);

-- 6. Private Storage bucket for children's work. Existing bucket configuration is updated safely.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('child-work-samples','child-work-samples',false,8388608,array['image/jpeg','image/png','image/webp','image/heic'])
on conflict (id) do update set public=false,file_size_limit=8388608,allowed_mime_types=array['image/jpeg','image/png','image/webp','image/heic'];

drop policy if exists "school staff upload work samples" on storage.objects;
create policy "school staff upload work samples" on storage.objects for insert to authenticated
with check (bucket_id='child-work-samples' and split_part(name,'/',1)=public.current_school_id()::text and public.current_role() in ('admin','teacher'));
drop policy if exists "school staff read work samples" on storage.objects;
create policy "school staff read work samples" on storage.objects for select to authenticated
using (bucket_id='child-work-samples' and split_part(name,'/',1)=public.current_school_id()::text and public.current_role() in ('admin','teacher'));
drop policy if exists "parents read linked work sample files" on storage.objects;
create policy "parents read linked work sample files" on storage.objects for select to authenticated
using (bucket_id='child-work-samples' and split_part(name,'/',1)=public.current_school_id()::text and public.current_role()='parent' and exists (
 select 1 from public.child_work_samples w where w.storage_path=name and public.is_parent_of(w.child_id)
));
drop policy if exists "staff delete work samples" on storage.objects;
create policy "staff delete work samples" on storage.objects for delete to authenticated
using (bucket_id='child-work-samples' and split_part(name,'/',1)=public.current_school_id()::text and public.current_role() in ('admin','teacher'));

-- NOTE: all rows are scoped to the existing school. No service-role key is exposed in the browser.
