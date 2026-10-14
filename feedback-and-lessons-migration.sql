-- Little Clan Diary: lesson topics + periodic feedback
create table if not exists public.lesson_records (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  schedule_id uuid not null references public.schedule(id) on delete cascade,
  lesson_date date not null,
  teacher_id uuid not null references auth.users(id) on delete restrict,
  topic text not null default '',
  note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(schedule_id, lesson_date)
);

create table if not exists public.feedback_reports (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  child_id uuid not null references public.children(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  teacher_id uuid not null references auth.users(id) on delete restrict,
  overall_comment text not null default '',
  status text not null default 'draft' check (status in ('draft','published')),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(child_id, period_start, period_end)
);

create table if not exists public.feedback_sections (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  feedback_id uuid not null references public.feedback_reports(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete cascade,
  studied text not null default '',
  strengths text not null default '',
  attention text not null default '',
  next_step text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(feedback_id, subject_id)
);

create index if not exists idx_lesson_records_school_date on public.lesson_records(school_id, lesson_date);
create index if not exists idx_lesson_records_schedule on public.lesson_records(schedule_id, lesson_date);
create index if not exists idx_feedback_reports_child_period on public.feedback_reports(child_id, period_start, period_end);
create index if not exists idx_feedback_reports_school on public.feedback_reports(school_id, status);
create index if not exists idx_feedback_sections_feedback on public.feedback_sections(feedback_id);

alter table public.lesson_records enable row level security;
alter table public.feedback_reports enable row level security;
alter table public.feedback_sections enable row level security;

drop policy if exists "admin manages lesson records" on public.lesson_records;
drop policy if exists "teacher reads own lesson records" on public.lesson_records;
drop policy if exists "teacher manages own lesson records" on public.lesson_records;
drop policy if exists "parent reads published feedback" on public.feedback_reports;
drop policy if exists "admin reads feedback" on public.feedback_reports;
drop policy if exists "teacher reads own feedback" on public.feedback_reports;
drop policy if exists "teacher manages own feedback" on public.feedback_reports;
drop policy if exists "admin manages feedback sections" on public.feedback_sections;
drop policy if exists "teacher reads own feedback sections" on public.feedback_sections;
drop policy if exists "teacher manages own feedback sections" on public.feedback_sections;
drop policy if exists "parent reads published feedback sections" on public.feedback_sections;

create policy "admin manages lesson records" on public.lesson_records
for all to authenticated
using (school_id = public.current_school_id() and public.current_role() = 'admin')
with check (school_id = public.current_school_id() and public.current_role() = 'admin');

create policy "teacher reads own lesson records" on public.lesson_records
for select to authenticated
using (school_id = public.current_school_id() and public.current_role() = 'teacher' and teacher_id = auth.uid());

create policy "teacher manages own lesson records" on public.lesson_records
for all to authenticated
using (school_id = public.current_school_id() and public.current_role() = 'teacher' and teacher_id = auth.uid() and public.is_teacher_for_schedule(schedule_id))
with check (school_id = public.current_school_id() and public.current_role() = 'teacher' and teacher_id = auth.uid() and public.is_teacher_for_schedule(schedule_id));

create policy "admin manages feedback" on public.feedback_reports
for all to authenticated
using (school_id = public.current_school_id() and public.current_role() = 'admin')
with check (school_id = public.current_school_id() and public.current_role() = 'admin');

create policy "teacher reads own feedback" on public.feedback_reports
for select to authenticated
using (school_id = public.current_school_id() and public.current_role() = 'teacher' and teacher_id = auth.uid());

create policy "teacher manages own feedback" on public.feedback_reports
for all to authenticated
using (
  school_id = public.current_school_id()
  and public.current_role() = 'teacher'
  and teacher_id = auth.uid()
  and public.is_teacher_for_child(child_id)
)
with check (
  school_id = public.current_school_id()
  and public.current_role() = 'teacher'
  and teacher_id = auth.uid()
  and public.is_teacher_for_child(child_id)
);

create policy "parent reads published feedback" on public.feedback_reports
for select to authenticated
using (
  school_id = public.current_school_id()
  and public.current_role() = 'parent'
  and status = 'published'
  and public.is_parent_of(child_id)
);

create policy "admin manages feedback sections" on public.feedback_sections
for all to authenticated
using (school_id = public.current_school_id() and public.current_role() = 'admin')
with check (school_id = public.current_school_id() and public.current_role() = 'admin');

create policy "teacher reads own feedback sections" on public.feedback_sections
for select to authenticated
using (
  school_id = public.current_school_id()
  and public.current_role() = 'teacher'
  and exists(select 1 from public.feedback_reports f where f.id = feedback_id and f.teacher_id = auth.uid())
);

create policy "teacher manages own feedback sections" on public.feedback_sections
for all to authenticated
using (
  school_id = public.current_school_id()
  and public.current_role() = 'teacher'
  and exists(select 1 from public.feedback_reports f where f.id = feedback_id and f.teacher_id = auth.uid())
)
with check (
  school_id = public.current_school_id()
  and public.current_role() = 'teacher'
  and exists(select 1 from public.feedback_reports f where f.id = feedback_id and f.teacher_id = auth.uid())
);

create policy "parent reads published feedback sections" on public.feedback_sections
for select to authenticated
using (
  school_id = public.current_school_id()
  and public.current_role() = 'parent'
  and exists(
    select 1 from public.feedback_reports f
    where f.id = feedback_id
      and f.status = 'published'
      and public.is_parent_of(f.child_id)
  )
);

grant select, insert, update, delete on public.lesson_records, public.feedback_reports, public.feedback_sections to authenticated;
