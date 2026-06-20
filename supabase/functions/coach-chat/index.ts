import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { callHaiku } from "../_shared/anthropic.ts";

const system = `You are Nathan's personal wellness and training coach.
Be conversational, concise, warm, and direct.
Return JSON only with:
{
  "reply": "human coach message",
  "events": [],
  "app_updates": []
}
Allowed app_updates include meal_timing, gym_days, notification_tone, task_completed, weigh_in, meal_log, workout_substitution.
Mark high-impact changes with "requires_confirmation": true.`;

serve(async (req) => {
  try {
    const body = await req.json();
    const result = await callHaiku(system, [
      {
        role: "user",
        content: JSON.stringify({
          message: body.message,
          recent_context: body.recent_context ?? {},
        }),
      },
    ]);

    return Response.json(result);
  } catch (error) {
    return Response.json({ error: String(error) }, { status: 500 });
  }
});
