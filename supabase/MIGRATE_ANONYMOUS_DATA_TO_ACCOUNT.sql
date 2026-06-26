-- Run this once in the Supabase SQL editor after signing into Loop with your
-- permanent email/password account.
--
-- 1. In Loop Settings > Cloud & AI, copy the new "Current Supabase user".
-- 2. Replace NEW_ACCOUNT_USER_ID below with that value.
-- 3. Keep OLD_ANONYMOUS_USER_ID as the previous anonymous user that owns the
--    existing rows, or replace it if Supabase shows another old owner.

begin;

do $$
declare
  old_user uuid := '91410c2f-cf5d-47b0-bf74-72c9b19f934d';
  new_user uuid := 'NEW_ACCOUNT_USER_ID';
begin
  delete from public.daily_metric_snapshots where user_id = new_user;
  delete from public.weekly_reviews where user_id = new_user;
  delete from public.healthkit_sync_state where user_id = new_user;

  update public.app_constraints set user_id = new_user where user_id = old_user;
  update public.coach_messages set user_id = new_user where user_id = old_user;
  update public.task_templates set user_id = new_user where user_id = old_user;
  update public.task_instances set user_id = new_user where user_id = old_user;
  update public.weigh_ins set user_id = new_user where user_id = old_user;
  update public.meals set user_id = new_user where user_id = old_user;
  update public.workout_sessions set user_id = new_user where user_id = old_user;
  update public.exercise_sets set user_id = new_user where user_id = old_user;
  update public.daily_metric_snapshots set user_id = new_user where user_id = old_user;
  update public.weekly_reviews set user_id = new_user where user_id = old_user;
  update public.reminder_rules set user_id = new_user where user_id = old_user;
  update public.healthkit_sync_state set user_id = new_user where user_id = old_user;

  insert into public.profiles (id, display_name, goal, training_level, preferred_tone, timezone)
  select new_user, display_name, goal, training_level, preferred_tone, timezone
  from public.profiles
  where id = old_user
  on conflict (id) do update set
    display_name = excluded.display_name,
    goal = excluded.goal,
    training_level = excluded.training_level,
    preferred_tone = excluded.preferred_tone,
    timezone = excluded.timezone;

  delete from public.profiles where id = old_user;
end $$;

commit;
