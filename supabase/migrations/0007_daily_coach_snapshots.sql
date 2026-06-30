alter table public.daily_metric_snapshots
add column if not exists sleep_minutes int,
add column if not exists sleep_delta_vs_30d int,
add column if not exists hrv_ms numeric,
add column if not exists hrv_delta_vs_30d numeric,
add column if not exists resting_heart_rate numeric,
add column if not exists resting_heart_rate_delta_vs_30d numeric,
add column if not exists respiratory_rate numeric,
add column if not exists respiratory_rate_delta_vs_30d numeric,
add column if not exists exercise_minutes int,
add column if not exists stand_hours int,
add column if not exists move_percent numeric;

create table if not exists public.daily_coach_snapshots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  day_id uuid references public.daily_logs(id) on delete cascade,
  day_date date not null,
  update_window text not null check (update_window in ('morning', 'afternoon', 'evening')),
  energy_snapshot jsonb not null default '{}'::jsonb,
  coach_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, day_date, update_window)
);

alter table public.daily_coach_snapshots enable row level security;

drop policy if exists "daily_coach_snapshots_owner" on public.daily_coach_snapshots;
create policy "daily_coach_snapshots_owner" on public.daily_coach_snapshots
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create index if not exists daily_coach_snapshots_user_day_window_idx
on public.daily_coach_snapshots (user_id, day_date desc, update_window);

create index if not exists daily_coach_snapshots_day_id_idx
on public.daily_coach_snapshots (day_id);
