import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { callHaiku } from "../_shared/anthropic.ts";

const system = `Analyze a meal from text or image.
Return JSON only with title, foods, calories, protein_grams, carbs_grams, fat_grams, confidence, and correction_question.
Do not claim precision. Ask for one correction if the estimate is uncertain.`;

serve(async (req) => {
  try {
    const body = await req.json();
    const content = body.image_base64
      ? [
          { type: "text", text: body.prompt ?? "Estimate this meal." },
          {
            type: "image",
            source: {
              type: "base64",
              media_type: body.media_type ?? "image/jpeg",
              data: body.image_base64,
            },
          },
        ]
      : body.prompt ?? body.text ?? "Estimate this meal.";

    const result = await callHaiku(system, [{ role: "user", content }]);
    return Response.json(result);
  } catch (error) {
    return Response.json({ error: String(error) }, { status: 500 });
  }
});
