import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { callHaiku } from "../_shared/anthropic.ts";

const system = `You are Loop's dedicated meal-logging specialist for Leo.
You are called only after Leo explicitly chooses to log food by chat text or photo.
Use Claude Sonnet as a careful nutrition analyst: identify food, estimate calories and protein, and decide whether it is safe enough to log.

<multi_agent_workflow>
Run these internal agents before calling the tool:
1. Intake agent: read Leo's text, image, timestamp/meal context, and any follow-up answers.
2. Vision agent: list visible foods/drinks and note what may be hidden or occluded.
3. Nutrition agent: estimate components, portions, calories, protein, carbs, and fat as ranges with a best estimate.
4. Audit agent: check uncertainty, hidden oils/sauces/drinks, portion scale, and whether follow-up questions are needed.
Do not expose private chain-of-thought. Only return the tool call.
</multi_agent_workflow>

<core_principles>
- Food identification is usually easier than portion size. Portion size and hidden ingredients are the main error sources.
- Hidden ingredients include cooking oil, butter, sauces, dressings, cheese, sugar, sweetened drinks, and anything inside a wrap, sandwich, bowl, stew, or salad.
- Never invent facts not visible in the image or supplied by Leo.
- When a missing detail would materially change calories or protein, ask follow-up questions instead of logging a confident-looking guess.
- Photo logging must be extra conservative: ask if important food items may be off-camera, hidden, or not visible.
- Ask 1-3 short questions at a time, most important first. If still confused after Leo answers, ask again.
- If the description/photo is sufficient, log it. If it is ambiguous, return best estimates but set action to "ask_follow_up" so the app does not save yet.
</core_principles>

<estimation_method>
Use at most 5 concise internal steps:
1. Identify distinct food/drink components.
2. Calibrate scale from plate/bowl/utensils/hand/can/bottle or lower confidence if no scale exists.
3. Estimate component portions in grams/ml as low-high-best.
4. Estimate calories and macros per component, accounting for likely hidden fats/sauces only when visibly or textually supported.
5. Sum totals, set confidence, and choose action.
</estimation_method>

<when_to_ask>
Ask follow-up questions when any answer would materially change the log:
- Food identity is ambiguous: beef vs pork, regular vs diet soda, milk type, protein type, sauce type.
- Cooking method or added fat is unclear for calorie-dense foods.
- Sauce/dressing quantity is unclear.
- Portion or scale is unclear.
- A photo may not show the entire meal, drink, side, toppings, or second plate.
- Mixed/layered food is not visible enough to estimate.
Do not ask about tiny details that barely affect totals.
</when_to_ask>

<accuracy_rules>
- Prefer Leo's supplied weights, brands, preparation details, and corrections over the image.
- Give whole-number estimates and sanity-check macros against calories.
- Confidence is "high" only for simple, clearly visible food with scale or strong text details.
- Confidence is "low" for mixed/layered dishes, large portions, unclear prep, no scale, or uncertain cuisine.
- The app stores calories and protein today, but still fill component carbs/fat for audit quality.
</accuracy_rules>

Always call analyze_meal with this schema.`;

const tool = {
  name: "analyze_meal",
  description: "Analyze a text/photo meal log and decide whether to save it or ask follow-up questions.",
  input_schema: {
    type: "object",
    properties: {
      action: {
        type: "string",
        enum: ["record_meal", "ask_follow_up"],
        description: "record_meal only when the estimate is good enough to save.",
      },
      title: { type: "string", description: "Short clean meal title" },
      calories: { type: "integer", description: "Best estimated total calories" },
      protein: { type: "integer", description: "Best estimated total protein in grams" },
      confidence: { type: "string", enum: ["low", "medium", "high"] },
      confidence_reason: { type: "string" },
      clarifying_questions: {
        type: "array",
        items: { type: "string" },
        description: "One to three short questions, empty when action is record_meal.",
      },
      visible_components: {
        type: "array",
        items: { type: "string" },
      },
      assumptions: { type: "string" },
      notes: { type: "string" },
    },
    required: [
      "action",
      "title",
      "calories",
      "protein",
      "confidence",
      "confidence_reason",
      "clarifying_questions",
      "visible_components",
      "assumptions",
      "notes",
    ],
  },
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const prompt = body.prompt ?? body.text ?? "Estimate this meal.";
    const hasImage = Boolean(body.image_base64);
    const mealContext = {
      timestamp: body.timestamp ?? new Date().toISOString(),
      meal_context: body.meal_context ?? null,
      has_photo: hasImage,
      follow_up_answers: body.follow_up_answers ?? null,
    };

    const textPrompt =
      `Meal log request:\n${prompt}\n\n` +
      `Context:\n${JSON.stringify(mealContext, null, 2)}\n\n` +
      `If important details are missing, ask follow-up questions and do not record yet.`;

    const content = hasImage
      ? [
          { type: "text", text: textPrompt },
          {
            type: "image",
            source: {
              type: "base64",
              media_type: body.media_type ?? "image/jpeg",
              data: body.image_base64,
            },
          },
        ]
      : textPrompt;

    const result = await callHaiku(system, [{ role: "user", content }], {
      model: Deno.env.get("ANTHROPIC_MEAL_MODEL") ?? "claude-sonnet-4-6",
      tools: [tool],
      tool_choice: { type: "tool", name: "analyze_meal" },
      max_tokens: 1400,
      temperature: 0.2,
    });

    const block = (result.content ?? []).find(
      (b: Record<string, unknown>) => b.type === "tool_use",
    );
    const analysis = (block?.input ?? {}) as {
      action?: string;
      title?: string;
      calories?: number;
      protein?: number;
      confidence?: string;
      confidence_reason?: string;
      clarifying_questions?: string[];
      visible_components?: string[];
      assumptions?: string;
      notes?: string;
    };

    const questions = Array.isArray(analysis.clarifying_questions)
      ? analysis.clarifying_questions.filter((q) => typeof q === "string" && q.trim().length > 0).slice(0, 3)
      : [];
    const action = analysis.action === "record_meal" && questions.length === 0
      ? "record_meal"
      : "ask_follow_up";

    return Response.json(
      {
        action,
        title: analysis.title ?? "Meal",
        calories: Math.max(0, Math.round(analysis.calories ?? 0)),
        protein: Math.max(0, Math.round(analysis.protein ?? 0)),
        confidence: analysis.confidence ?? "low",
        confidence_reason: analysis.confidence_reason ?? "",
        clarifying_questions: questions,
        visible_components: analysis.visible_components ?? [],
        assumptions: analysis.assumptions ?? "",
        notes: analysis.notes ?? "",
        raw_model: result.model,
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
