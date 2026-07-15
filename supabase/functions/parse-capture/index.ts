// parse-capture — turns a free-text / dictated note into structured trip items
// (packing, checklist todos, shopping) using Claude. Returns the tool input JSON
// verbatim; the app resolves people, dates, and stores against its own data.
//
// Requires the ANTHROPIC_API_KEY secret:
//   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...   (project ihvljgwfslxorxsorzpi)

const MODEL = "claude-haiku-4-5-20251001";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const TOOL = {
  name: "emit_items",
  description:
    "Emit the structured trip items parsed from the note, split across packing, todos, and shopping.",
  input_schema: {
    type: "object",
    properties: {
      packing: {
        type: "array",
        description: "Physical things to pack, bring, or wear on the trip.",
        items: {
          type: "object",
          properties: {
            item: { type: "string", description: "The thing to pack, singular, no leading verb. e.g. 'sunscreen'." },
            person: {
              type: "string",
              description:
                "Who it's for. Use 'me' if the speaker refers to themselves (myself/I/me/my). Use an exact name from the travelers list if a person is named. Otherwise use 'everyone'.",
            },
          },
          required: ["item", "person"],
        },
      },
      todos: {
        type: "array",
        description:
          "Tasks / reminders to do (NOT things to pack or buy). e.g. 'charge car to 80%'.",
        items: {
          type: "object",
          properties: {
            title: { type: "string", description: "The task, imperative, concise. e.g. 'Charge car to 80%'." },
            due: {
              type: "object",
              description: "When the task should be done, relative to the trip. Use anchor 'none' if no timing is mentioned.",
              properties: {
                anchor: { type: "string", enum: ["departure", "return", "none"] },
                offsetDays: {
                  type: "integer",
                  description:
                    "Days relative to the anchor. 'the night before we leave' = anchor 'departure', offsetDays -1. 'the day we get back' = anchor 'return', offsetDays 0. Departure day itself = 0.",
                },
                date: {
                  type: ["string", "null"],
                  description: "An explicit calendar date in YYYY-MM-DD if one is literally stated; otherwise null.",
                },
              },
              required: ["anchor", "offsetDays", "date"],
            },
          },
          required: ["title", "due"],
        },
      },
      shopping: {
        type: "array",
        description: "Things to buy / purchase for the trip.",
        items: {
          type: "object",
          properties: {
            item: { type: "string", description: "The thing to buy, no leading verb. e.g. 'apples'." },
            store: {
              type: ["string", "null"],
              description:
                "The store or site to buy it at if one is mentioned (e.g. 'at Walmart' -> 'Walmart'); otherwise null.",
            },
            quantity: {
              type: ["string", "null"],
              description: "A quantity if stated (e.g. '2 lbs', 'a dozen'); otherwise null.",
            },
          },
          required: ["item", "store", "quantity"],
        },
      },
    },
    required: ["packing", "todos", "shopping"],
  },
};

function systemPrompt(ctx: Record<string, unknown>): string {
  const travelers = Array.isArray(ctx.travelers) ? (ctx.travelers as string[]) : [];
  const stores = Array.isArray(ctx.stores) ? (ctx.stores as string[]) : [];
  return [
    "You parse a short spoken/typed note about a trip into structured items and call the emit_items tool.",
    "Split every distinct item into exactly one of: packing (things to pack/bring/wear), todos (tasks/reminders to DO), shopping (things to BUY).",
    "Routing hints: 'buy/pick up/get ... at <store>' -> shopping. 'pack/bring/wear/take' -> packing. 'remember to/need to/charge/book/call/confirm' -> todos.",
    "Person rules for packing: 'myself/me/I/my' -> 'me'. A named person that appears in the travelers list -> that exact name. If no person is indicated -> 'everyone'.",
    travelers.length ? `Travelers: ${travelers.join(", ")}.` : "No named travelers provided; use 'me' or 'everyone'.",
    ctx.currentMemberName ? `The speaker (‘me’) is ${ctx.currentMemberName}.` : "",
    stores.length ? `Known stores (match spoken store names to these when possible, case-insensitive): ${stores.join(", ")}.` : "",
    "Keep item text short and clean; strip filler and leading verbs. Do not invent items that weren't mentioned.",
  ].filter(Boolean).join("\n");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) {
    return json({ error: "ANTHROPIC_API_KEY is not set on the function." }, 500);
  }

  let body: { text?: string; context?: Record<string, unknown> };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body." }, 400);
  }
  const text = (body.text ?? "").trim();
  if (!text) return json({ error: "Empty text." }, 400);
  const ctx = body.context ?? {};

  const resp = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 1024,
      system: systemPrompt(ctx),
      tools: [TOOL],
      tool_choice: { type: "tool", name: "emit_items" },
      messages: [{ role: "user", content: text }],
    }),
  });

  if (!resp.ok) {
    const detail = await resp.text();
    return json({ error: `Claude API error (${resp.status})`, detail }, 502);
  }

  const data = await resp.json();
  const toolUse = (data.content ?? []).find((b: { type: string }) => b.type === "tool_use");
  if (!toolUse) return json({ error: "No structured output from model." }, 502);

  // Return the tool input directly — the app resolves people/dates/stores.
  return json(toolUse.input, 200);
});

function json(obj: unknown, status: number): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...CORS, "content-type": "application/json" },
  });
}
