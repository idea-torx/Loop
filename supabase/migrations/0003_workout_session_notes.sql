alter table public.workout_sessions
add column if not exists coach_notes text not null default '';
