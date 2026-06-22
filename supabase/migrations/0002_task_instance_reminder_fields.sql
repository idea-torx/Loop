alter table public.task_instances
  add column if not exists sort_order int not null default 0,
  add column if not exists local_hour int check (local_hour between 0 and 23),
  add column if not exists local_minute int check (local_minute between 0 and 59);
