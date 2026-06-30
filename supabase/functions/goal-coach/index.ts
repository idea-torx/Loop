import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { callHaiku } from "../_shared/anthropic.ts";

const system = `You are the long-term cut planning coach inside Loop.

You receive structured goal, weight trend, food logging, activity, and adherence data. Use only the supplied context. Do not invent missing meals, calories, active calories, weigh-ins, RMR, or progress.

Your job:
- Explain whether Leo's cut is on pace.
- Use weight trend first when available.
- Use logged food and active calories as supporting evidence.
- Call out low confidence when food logs or weigh-ins are sparse.
- Give practical next moves for the next 24-72 hours.
- Do not make medical claims.

Return JSON only:
{
  "summary": "2-3 sentence goal read",
  "suggestions": ["three practical suggestions"]
}`;

serve(async (req) => {
  try {
    const body = await req.json();
    const result = await callHaiku(
      system,
      [{
        role: "user",
        content: `Loop goal context:\n${JSON.stringify(body.context ?? {}, null, 2)}`,
      }],
      { max_tokens: 650, temperature: 0.2 },
    );

    const text = result.content
      ?.filter((part: { type?: string }) => part.type === "text")
      ?.map((part: { text?: string }) => part.text ?? "")
      ?.join("\n")
      ?.trim();

    if (!text) throw new Error("Goal coach returned no text");
    return Response.json(parseJsonObject(text));
  } catch (error) {
    return Response.json({ error: String(error) }, { status: 500 });
  }
});

function parseJsonObject(text: string) {
  try {
    return JSON.parse(text);
  } catch {
    const start = text.indexOf("{");
    const end = text.lastIndexOf("}");
    if (start >= 0 && end > start) return JSON.parse(text.slice(start, end + 1));
    throw new Error(`Goal coach did not return JSON: ${text.slice(0, 240)}`);
  }
}
