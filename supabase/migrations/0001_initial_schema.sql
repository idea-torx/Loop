create extension if not exists "pgcrypto";

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Nathan',
  goal text not null default '',
  training_level text not null default '',
  preferred_tone text not null default 'Warm, direct, human',
  timezone text not null default 'America/Vancouver',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.app_constraints (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  key text not null,
  value jsonb not null,
  source text not null default 'coach',
  requires_confirmation boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, key)
);

create table public.coach_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('user', 'assistant', 'system')),
  content text not null,
  extracted_events jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

create table public.task_templates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  detail text not null default '',
  system_image text not null default 'circle',
  recurrence text not null default 'daily',
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.task_instances (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  template_id uuid references public.task_templates(id) on delete set null,
  task_date date not null,
  title text not null,
  detail text not null default '',
  system_image text not null default 'circle',
  is_complete boolean not null default false,
  completed_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.weigh_ins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  measured_at timestamptz not null default now(),
  pounds numeric(6,2) not null,
  source text not null default 'app'
);

create table public.meals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  eaten_at timestamptz not null default now(),
  title text not null,
  notes text not null default '',
  calories int,
  protein_grams int,
  carbs_grams int,
  fat_grams int,
  confidence numeric(4,3),
  source text not null default 'conversation',
  stored_photo_path text
);

create table public.workout_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  started_at timestamptz not null default now(),
  title text not null,
  focus text not null default '',
  is_complete boolean not null default false,
  healthkit_uuid text
);

create table public.exercise_sets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  workout_session_id uuid not null references public.workout_sessions(id) on delete cascade,
  exercise text not null,
  reps int not null,
  weight int not null default 0,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create table public.daily_metric_snapshots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  metric_date date not null,
  steps int,
  active_energy_calories int,
  workouts_count int,
  task_completion_rate numeric(5,4),
  created_at timestamptz not null default now(),
  unique (user_id, metric_date)
);

create table public.weekly_reviews (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  week_starts_on date not null,
  summary text not null,
  suggestions jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  unique (user_id, week_starts_on)
);

create table public.reminder_rules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  body_template text not null,
  local_hour int not null check (local_hour between 0 and 23),
  local_minute int not null check (local_minute between 0 and 59),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.healthkit_sync_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  last_weight_sync_at timestamptz,
  last_activity_sync_at timestamptz,
  last_workout_sync_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.app_constraints enable row level security;
alter table public.coach_messages enable row level security;
alter table public.task_templates enable row level security;
alter table public.task_instances enable row level security;
alter table public.weigh_ins enable row level security;
alter table public.meals enable row level security;
alter table public.workout_sessions enable row level security;
alter table public.exercise_sets enable row level security;
alter table public.daily_metric_snapshots enable row level security;
alter table public.weekly_reviews enable row level security;
alter table public.reminder_rules enable row level security;
alter table public.healthkit_sync_state enable row level security;

create policy "profiles_owner" on public.profiles for all using (auth.uid() = id) with check (auth.uid() = id);
create policy "constraints_owner" on public.app_constraints for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "messages_owner" on public.coach_messages for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "task_templates_owner" on public.task_templates for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "task_instances_owner" on public.task_instances for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "weigh_ins_owner" on public.weigh_ins for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "meals_owner" on public.meals for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "workout_sessions_owner" on public.workout_sessions for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "exercise_sets_owner" on public.exercise_sets for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "metric_snapshots_owner" on public.daily_metric_snapshots for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "weekly_reviews_owner" on public.weekly_reviews for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "reminder_rules_owner" on public.reminder_rules for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "healthkit_sync_owner" on public.healthkit_sync_state for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
