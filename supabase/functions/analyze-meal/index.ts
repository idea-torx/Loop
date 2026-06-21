import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { callHaiku } from "../_shared/anthropic.ts";

const system = `You estimate the nutrition of a meal from a short description and/or a photo.
Give a reasonable, non-precise estimate of total calories and total protein in grams.
Write a short, clean title for the meal (e.g. "Chicken bowl with rice").
Always call the record_meal tool with your estimate. Do not over-claim precision.`;

const tool = {
  name: "record_meal",
  description: "Record the estimated macro-nutrients for a meal.",
  input_schema: {
    type: "object",
    properties: {
      title: { type: "string", description: "Short clean meal title" },
      calories: { type: "integer", description: "Estimated total calories" },
      protein: { type: "integer", description: "Estimated total protein in grams" },
    },
    required: ["title", "calories", "protein"],
  },
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const prompt = body.prompt ?? body.text ?? "Estimate this meal.";
    const content = body.image_base64
      ? [
          { type: "text", text: prompt },
          {
            type: "image",
            source: {
              type: "base64",
              media_type: body.media_type ?? "image/jpeg",
              data: body.image_base64,
            },
          },
        ]
      : prompt;

    const result = await callHaiku(system, [{ role: "user", content }], {
      tools: [tool],
      tool_choice: { type: "tool", name: "record_meal" },
      max_tokens: 512,
    });

    const block = (result.content ?? []).find(
      (b: Record<string, unknown>) => b.type === "tool_use",
    );
    const macros = (block?.input ?? {}) as {
      title?: string;
      calories?: number;
      protein?: number;
    };

    return Response.json(
      {
        title: macros.title ?? "Meal",
        calories: Math.max(0, Math.round(macros.calories ?? 0)),
        protein: Math.max(0, Math.round(macros.protein ?? 0)),
      },
      { headers: corsHeaders },
    );
  } catch (error) {
    return Response.json({ error: String(error) }, { status: 500, headers: corsHeaders });
  }
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
