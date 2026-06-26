create table if not exists public.daily_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  day_date date not null,
  timezone text not null default 'America/Vancouver',
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, day_date)
);

alter table public.daily_logs enable row level security;

drop policy if exists "daily_logs_owner" on public.daily_logs;
create policy "daily_logs_owner" on public.daily_logs
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

alter table public.task_instances
add column if not exists day_id uuid references public.daily_logs(id) on delete cascade;

alter table public.weigh_ins
add column if not exists day_id uuid references public.daily_logs(id) on delete cascade;

alter table public.meals
add column if not exists day_id uuid references public.daily_logs(id) on delete cascade;

alter table public.workout_sessions
add column if not exists day_id uuid references public.daily_logs(id) on delete cascade;

alter table public.daily_metric_snapshots
add column if not exists day_id uuid references public.daily_logs(id) on delete cascade;

insert into public.daily_logs (user_id, day_date, timezone)
select user_id, task_date, 'America/Vancouver'
from public.task_instances
on conflict (user_id, day_date) do nothing;

insert into public.daily_logs (user_id, day_date, timezone)
select user_id, (measured_at at time zone 'America/Vancouver')::date, 'America/Vancouver'
from public.weigh_ins
on conflict (user_id, day_date) do nothing;

insert into public.daily_logs (user_id, day_date, timezone)
select user_id, (eaten_at at time zone 'America/Vancouver')::date, 'America/Vancouver'
from public.meals
on conflict (user_id, day_date) do nothing;

insert into public.daily_logs (user_id, day_date, timezone)
select user_id, (started_at at time zone 'America/Vancouver')::date, 'America/Vancouver'
from public.workout_sessions
on conflict (user_id, day_date) do nothing;

insert into public.daily_logs (user_id, day_date, timezone)
select user_id, metric_date, 'America/Vancouver'
from public.daily_metric_snapshots
on conflict (user_id, day_date) do nothing;

update public.task_instances item
set day_id = day.id
from public.daily_logs day
where item.day_id is null
  and day.user_id = item.user_id
  and day.day_date = item.task_date;

update public.weigh_ins item
set day_id = day.id
from public.daily_logs day
where item.day_id is null
  and day.user_id = item.user_id
  and day.day_date = (item.measured_at at time zone 'America/Vancouver')::date;

update public.meals item
set day_id = day.id
from public.daily_logs day
where item.day_id is null
  and day.user_id = item.user_id
  and day.day_date = (item.eaten_at at time zone 'America/Vancouver')::date;

update public.workout_sessions item
set day_id = day.id
from public.daily_logs day
where item.day_id is null
  and day.user_id = item.user_id
  and day.day_date = (item.started_at at time zone 'America/Vancouver')::date;

update public.daily_metric_snapshots item
set day_id = day.id
from public.daily_logs day
where item.day_id is null
  and day.user_id = item.user_id
  and day.day_date = item.metric_date;

create index if not exists daily_logs_user_day_date_idx
on public.daily_logs (user_id, day_date desc);

create index if not exists task_instances_day_id_idx
on public.task_instances (day_id);

create index if not exists weigh_ins_day_id_idx
on public.weigh_ins (day_id);

create index if not exists meals_day_id_idx
on public.meals (day_id);

create index if not exists workout_sessions_day_id_idx
on public.workout_sessions (day_id);

create index if not exists daily_metric_snapshots_day_id_idx
on public.daily_metric_snapshots (day_id);
