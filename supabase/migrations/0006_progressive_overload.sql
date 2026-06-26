alter table public.exercise_sets
add column if not exists normalized_exercise text,
add column if not exists exercise_category text,
add column if not exists target_min_reps int,
add column if not exists target_max_reps int,
add column if not exists rir int check (rir between 0 and 10);

update public.exercise_sets
set normalized_exercise = lower(regexp_replace(trim(exercise), '\s+', ' ', 'g'))
where normalized_exercise is null or normalized_exercise = '';

update public.exercise_sets
set exercise_category = case
  when normalized_exercise ~ '(bench press|squat|deadlift|overhead press)' then 'main_compound'
  when normalized_exercise ~ '(row|pulldown|leg press|romanian deadlift|incline|dumbbell press)' then 'secondary_compound'
  when normalized_exercise ~ '(crunch|abs|plank)' then 'abs'
  else 'accessory'
end
where exercise_category is null or exercise_category = '';

update public.exercise_sets
set
  target_min_reps = case
    when exercise_category = 'main_compound' then 6
    when exercise_category = 'secondary_compound' then 8
    when exercise_category = 'abs' then 12
    else 10
  end,
  target_max_reps = case
    when exercise_category = 'main_compound' then 10
    when exercise_category = 'secondary_compound' then 12
    when exercise_category = 'abs' then 20
    else 15
  end
where target_min_reps is null or target_max_reps is null;

create index if not exists exercise_sets_user_normalized_created_idx
on public.exercise_sets (user_id, normalized_exercise, created_at desc);
