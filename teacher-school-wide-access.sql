-- Teacher school-wide access: all active/inactive children and schedules in their school.
-- Teachers can read all children/schedule for substitutions, while writes remain tied to their own auth identity.

-- CHILDREN: replace assigned-only teacher read with school-wide teacher read.
drop policy if exists "teacher reads assigned children" on public.children;
create policy "teacher reads all school children" on public.children
for select to authenticated
using (
  school_id = public.current_school_id()
  and public.current_role() = 'teacher'
);

-- SCHEDULE: teachers can see the whole school's schedule so they can cover substitutions.
drop policy if exists "teacher reads own schedule" on public.schedule;
create policy "teacher reads school schedule" on public.schedule
for select to authenticated
using (
  school_id = public.current_school_id()
  and public.current_role() = 'teacher'
);

-- ATTENDANCE: teachers can mark attendance for any child/schedule in their school.
drop policy if exists "teacher reads assigned attendance" on public.attendance;
drop policy if exists "teacher inserts attendance" on public.attendance;
drop policy if exists "teacher updates attendance" on public.attendance;

create policy "teacher reads school attendance" on public.attendance
for select to authenticated
using (
  school_id = public.current_school_id()
  and public.current_role() = 'teacher'
);

create policy "teacher inserts school attendance" on public.attendance
for insert to authenticated
with check (
  school_id = public.current_school_id()
  and public.current_role() = 'teacher'
  and marked_by = auth.uid()
);

create policy "teacher updates school attendance" on public.attendance
for update to authenticated
using (
  school_id = public.current_school_id()
  and public.current_role() = 'teacher'
)
with check (
  school_id = public.current_school_id()
  and public.current_role() = 'teacher'
  and marked_by = auth.uid()
);

-- OBSERVATIONS: teachers can read all school observations and write their own.
drop policy if exists "teacher reads assigned observations" on public.observations;
drop policy if exists "teacher adds observation" on public.observations;
drop policy if exists "teacher edits own observation" on public.observations;

create policy "teacher reads school observations" on public.observations
for select to authenticated
using (
  school_id = public.current_school_id()
  and public.current_role() = 'teacher'
);

create policy "teacher adds school observation" on public.observations
for insert to authenticated
with check (
  school_id = public.current_school_id()
  and public.current_role() = 'teacher'
  and teacher_id = auth.uid()
);

create policy "teacher edits own school observation" on public.observations
for update to authenticated
using (
  school_id = public.current_school_id()
  and public.current_role() = 'teacher'
  and teacher_id = auth.uid()
)
with check (
  school_id = public.current_school_id()
  and public.current_role() = 'teacher'
  and teacher_id = auth.uid()
);

-- LESSON RECORDS: a teacher can enter the topic/note for any school's scheduled lesson.
drop policy if exists "teacher reads own lesson records" on public.lesson_records;
drop policy if exists "teacher manages own lesson records" on public.lesson_records;

create policy "teacher reads school lesson records" on public.lesson_records
for select to authenticated
using (
  school_id = public.current_school_id()
  and public.current_role() = 'teacher'
);

create policy "teacher manages school lesson records" on public.lesson_records
for all to authenticated
using (
  school_id = public.current_school_id()
  and public.current_role() = 'teacher'
)
with check (
  school_id = public.current_school_id()
  and public.current_role() = 'teacher'
  and teacher_id = auth.uid()
);

-- FEEDBACK REPORTS: any teacher may prepare a report for any child in their school.
drop policy if exists "teacher reads own feedback" on public.feedback_reports;
drop policy if exists "teacher manages own feedback" on public.feedback_reports;

create policy "teacher reads school feedback" on public.feedback_reports
for select to authenticated
using (
  school_id = public.current_school_id()
  and public.current_role() = 'teacher'
);

create policy "teacher manages school feedback" on public.feedback_reports
for all to authenticated
using (
  school_id = public.current_school_id()
  and public.current_role() = 'teacher'
)
with check (
  school_id = public.current_school_id()
  and public.current_role() = 'teacher'
  and teacher_id = auth.uid()
);

-- FEEDBACK SECTIONS: follow school-wide teacher access through the report.
drop policy if exists "teacher reads own feedback sections" on public.feedback_sections;
drop policy if exists "teacher manages own feedback sections" on public.feedback_sections;

create policy "teacher reads school feedback sections" on public.feedback_sections
for select to authenticated
using (
  school_id = public.current_school_id()
  and public.current_role() = 'teacher'
);

create policy "teacher manages school feedback sections" on public.feedback_sections
for all to authenticated
using (
  school_id = public.current_school_id()
  and public.current_role() = 'teacher'
)
with check (
  school_id = public.current_school_id()
  and public.current_role() = 'teacher'
);
