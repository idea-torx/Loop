import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { callHaiku } from "../_shared/anthropic.ts";

const system = `Write Nathan's weekly review.
Use weight trend, task adherence, meals, workouts, steps, active energy, and missed patterns.
Return JSON only with summary, trend_notes, suggestions, and next_week_focus.
Suggestions must be practical, non-medical, and specific.`;

serve(async (req) => {
  try {
    const body = await req.json();
    const result = await callHaiku(system, [
      { role: "user", content: JSON.stringify(body) },
    ]);

    return Response.json(result);
  } catch (error) {
    return Response.json({ error: String(error) }, { status: 500 });
  }
});
