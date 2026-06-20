# Nathan Coach

Native iOS personal coach prototype for daily adherence, conversational logging, workouts, meal check-ins, trend graphs, HealthKit permissions, and weekly suggestions.

## What is built

- Xcode project: `NathanCoach.xcodeproj`
- Native SwiftUI iOS 26 app with `Today`, `Coach`, `Workout`, `Trends`, and `Settings`
- Static daily checklist where completed tasks stay visible and crossed out
- Conversational coach shell that can update local tasks, weigh-ins, meal logs, and preferences
- Swift Charts trend dashboard for weight, adherence, activity, and training volume
- HealthKit and local notification permission flows
- Supabase schema and Edge Function starter files for cloud persistence and Claude Haiku

## Run

Open `NathanCoach.xcodeproj` in Xcode, choose the `NathanCoach` scheme, select your iPhone, set your Apple development team in Signing, then run.

The app currently runs in local prototype mode. Add Supabase credentials and deploy the Edge Functions to enable real cloud sync and Haiku responses.

## Backend Next Steps

1. Create a Supabase project.
2. Apply `supabase/migrations/0001_initial_schema.sql`.
3. Add function secrets:
   - `ANTHROPIC_API_KEY`
   - `ANTHROPIC_MODEL`, default `claude-3-5-haiku-latest`
   - Supabase function environment values.
4. Deploy the functions in `supabase/functions`.
5. Wire `SupabaseGateway` to call those functions from the app.
