with ranked as (
  select
    id,
    row_number() over (
      partition by
        user_id,
        task_date,
        lower(regexp_replace(trim(title), '\s+', ' ', 'g'))
      order by is_complete desc, created_at asc, id asc
    ) as row_number
  from public.task_instances
)
delete from public.task_instances
using ranked
where public.task_instances.id = ranked.id
  and ranked.row_number > 1;

create unique index if not exists task_instances_one_title_per_day
on public.task_instances (
  user_id,
  task_date,
  lower(regexp_replace(trim(title), '\s+', ' ', 'g'))
);
