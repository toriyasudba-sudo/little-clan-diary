-- Little Clan Diary: Data API permissions
-- Run once in Supabase SQL Editor AFTER RLS policies are in place.
-- RLS remains the real access control layer.

grant usage on schema public to authenticated;

grant select, insert, update, delete on
  public.schools,
  public.profiles,
  public.classes,
  public.subjects,
  public.children,
  public.child_parents,
  public.schedule,
  public.attendance,
  public.observations
  to authenticated;

grant execute on function public.current_school_id() to authenticated;
grant execute on function public.current_role() to authenticated;
grant execute on function public.is_parent_of(uuid) to authenticated;
grant execute on function public.is_teacher_for_schedule(uuid) to authenticated;
grant execute on function public.is_teacher_for_child(uuid) to authenticated;
grant execute on function public.is_teacher_for_child_schedule(uuid, uuid) to authenticated;

grant select, insert, update, delete on
  public.notifications,
  public.push_subscriptions
  to authenticated;
