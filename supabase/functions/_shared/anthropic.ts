export type AnthropicMessage = {
  role: "user" | "assistant";
  content: string | Array<Record<string, unknown>>;
};

type CallOptions = {
  tools?: Array<Record<string, unknown>>;
  tool_choice?: Record<string, unknown>;
  max_tokens?: number;
};

export async function callHaiku(
  system: string,
  messages: AnthropicMessage[],
  options: CallOptions = {},
) {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) {
    throw new Error("Missing ANTHROPIC_API_KEY");
  }

  const model = Deno.env.get("ANTHROPIC_MODEL") ?? "claude-haiku-4-5";
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model,
      max_tokens: options.max_tokens ?? 1024,
      system,
      messages,
      ...(options.tools ? { tools: options.tools } : {}),
      ...(options.tool_choice ? { tool_choice: options.tool_choice } : {}),
    }),
  });

  if (!response.ok) {
    throw new Error(`Anthropic request failed: ${response.status} ${await response.text()}`);
  }

  return response.json();
}
