import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { callHaiku } from "../_shared/anthropic.ts";

const system = `Create Nathan's daily adherence plan.
Return JSON only with tasks, workout_focus, nudge_copy, and one adherence priority.
Keep tasks static for the day; completed tasks should stay visible in the client.`;

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
