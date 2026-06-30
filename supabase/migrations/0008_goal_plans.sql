create table if not exists public.goal_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  goal_type text not null default 'cut',
  start_date date not null,
  end_date date not null,
  start_weight numeric(6,2) not null,
  target_loss_percent numeric(5,4) not null default 0.10,
  target_weight numeric(6,2) not null,
  active_calorie_min int not null default 800,
  active_calorie_max int not null default 1000,
  calorie_target int not null default 2200,
  protein_target int not null default 170,
  status text not null default 'active',
  body_profile jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.goal_plans enable row level security;

drop policy if exists "goal_plans_owner" on public.goal_plans;
create policy "goal_plans_owner" on public.goal_plans
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create unique index if not exists goal_plans_one_active_per_user_idx
on public.goal_plans (user_id, status)
where status = 'active';

create index if not exists goal_plans_user_created_idx
on public.goal_plans (user_id, created_at desc);

create table if not exists public.goal_insights (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  goal_plan_id uuid references public.goal_plans(id) on delete cascade,
  insight_date date not null,
  summary text not null,
  suggestions jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  unique (user_id, goal_plan_id, insight_date)
);

alter table public.goal_insights enable row level security;

drop policy if exists "goal_insights_owner" on public.goal_insights;
create policy "goal_insights_owner" on public.goal_insights
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
