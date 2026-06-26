# Supabase setup — Nathan Coach

One-time backend setup. Run from the repo root (`Nathan-App/`). You only need to do
the project-creation + secret steps; everything else is copy-paste.

## 1. Create the project (dashboard)

1. Go to https://supabase.com/dashboard → **New project**.
2. Note the **Project ref** (the `xxxx` in `https://xxxx.supabase.co`).
3. Project Settings → **API** → copy the **Project URL** and the **anon / public** key.

## 2. Enable anonymous sign-ins (dashboard)

Authentication → **Sign In / Providers** → enable **Anonymous sign-ins** → Save.
(The app creates a silent anonymous user; without this, RLS returns no rows.)

## 3. Install + log in to the CLI

```sh
brew install supabase/tap/supabase
supabase login                         # opens a browser
```

## 4. Initialize/link this repo

Run these from the repo root, not from `supabase/` or `supabase/migrations/`:

```sh
cd /Users/leofelix/Documents/Nathan-App
supabase init                          # creates supabase/config.toml if missing
supabase link --project-ref <YOUR_REF> # from step 1
```

Confirm the CLI can see the linked project:

```sh
supabase projects list
```

If you run `supabase db push` from inside `supabase/migrations/`, the CLI may not use this
repo's migration folder or linked project. The dashboard will then show no new tables.

## 5. Apply the database schema

```sh
cd /Users/leofelix/Documents/Nathan-App
supabase db push
```

This runs all files in `supabase/migrations/`:

- `0001_initial_schema.sql` creates the core tables and row-level security policies.
- `0002_task_instance_reminder_fields.sql` adds task ordering and reminder time fields used by the iOS app.

## 6. Set the function secrets

```sh
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...   # your Anthropic key — stays server-side
supabase secrets set ANTHROPIC_MODEL=claude-haiku-4-5
```

## 7. Deploy the Edge Functions

```sh
supabase functions deploy analyze-meal
supabase functions deploy coach-chat
supabase functions deploy weekly-review
supabase functions deploy daily-plan
```

(They verify the user's JWT by default; the app sends the anonymous user's token.)

## 8. Point the app at Supabase

For an installed dev app that works away from your Mac, the Supabase values must be
embedded in the app's generated Info.plist, not only supplied as Xcode run environment
variables. Scheme environment variables exist only when Xcode launches the app.

In `NathanCoach.xcodeproj/project.pbxproj`, the generated Info.plist build settings should include:

| Name | Value |
|------|-------|
| `INFOPLIST_KEY_SUPABASE_URL` | `https://<YOUR_REF>.supabase.co` |
| `INFOPLIST_KEY_SUPABASE_ANON_KEY` | the anon/public key from step 1 |

You can still keep the same values in Xcode's Run scheme for local debugging, but the
Info.plist values are what make the app functional when launched from the phone home
screen.

The iOS app also includes a defensive fallback inside `SupabaseGateway`: it checks the
Xcode environment, generated Info.plist, an on-device config cache, and finally the
hosted Supabase defaults baked into the app. This keeps the dev-installed phone app
cloud-capable even after it is launched away from the Mac.

Run the app. Settings → "Cloud & AI" should read **Cloud sync ready · Supabase + Haiku**.

> The anon key is a publishable client key (safe in the app). The secret
> `ANTHROPIC_API_KEY` only ever lives in Supabase function secrets — never in the repo.

## Verify

- Log a meal, send a coach message, complete a task, add a weigh-in, and log a workout set.
- Relaunch the app → cloud-backed data should reload instead of returning to only seed data.
- Check the dashboard → **Table editor** → `meals`, `weigh_ins`, `coach_messages`,
  `task_instances`, `workout_sessions`, `exercise_sets`, and `weekly_reviews` for rows.
