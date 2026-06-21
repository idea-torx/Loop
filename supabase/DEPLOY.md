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
supabase link --project-ref <YOUR_REF> # from step 1
```

## 4. Apply the database schema

```sh
supabase db push
```

This runs `supabase/migrations/0001_initial_schema.sql` (tables + row-level security).

## 5. Set the function secrets

```sh
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...   # your Anthropic key — stays server-side
supabase secrets set ANTHROPIC_MODEL=claude-haiku-4-5
```

## 6. Deploy the Edge Functions

```sh
supabase functions deploy analyze-meal
supabase functions deploy coach-chat
supabase functions deploy weekly-review
supabase functions deploy daily-plan
```

(They verify the user's JWT by default; the app sends the anonymous user's token.)

## 7. Point the app at Supabase

In Xcode: **Product → Scheme → Edit Scheme… → Run → Arguments → Environment Variables**,
add:

| Name | Value |
|------|-------|
| `SUPABASE_URL` | `https://<YOUR_REF>.supabase.co` |
| `SUPABASE_ANON_KEY` | the anon/public key from step 1 |

Run the app. Settings → "Cloud & AI" should read **Cloud sync ready · Supabase + Haiku**.

> The anon key is a publishable client key (safe in the app). The secret
> `ANTHROPIC_API_KEY` only ever lives in Supabase function secrets — never in the repo.

## Verify

- Log a meal (Trends → Log a meal, or tell the coach "lunch was …") → it should persist
  and survive an app relaunch.
- Check the dashboard → **Table editor** → `meals` / `weigh_ins` / `coach_messages` for rows.
