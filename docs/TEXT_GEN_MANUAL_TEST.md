# Text Generation — manual test checklist

The Text Gen tool (Tools Hub → **Text Gen**) talks to NovelAI's text API,
reusing the same `pst-` token as image generation. There are **two transports**,
picked from the selected model:

| Models | Endpoint | Request body | Non-stream response | Stream |
|---|---|---|---|---|
| `glm-4-6`, `glm-4-5`, `xialong-v1` (and other GLM/Xialong/chat ids) | `POST text.novelai.net/oa/v1/completions` | `{ prompt, model, max_tokens, temperature, top_p, [top_k, min_p, frequency_penalty, presence_penalty, stop], stream }` | `{ "choices": [ { "text": "…" } ] }` | SSE: `data: {"choices":[{"text":"…"}]}` lines, ending `data: [DONE]` |
| `kayra-v1`, `clio-v1`, `llama-3-erato-v1` (legacy) | `POST text.novelai.net/ai/generate` (`-stream` for SSE) | `{ input, model, parameters: { use_string:true, temperature, max_length, min_length, top_k/top_p/top_a/typical_p, tail_free_sampling, repetition_penalty*, phrase_rep_pen, generate_until_sentence, order, force_emotion:false } }` | `{ "output": "…" }` | SSE: `data: {"token":"…","ptr":N,"final":bool}` |

Headers on every request: `Authorization: Bearer <pst- token>`, `Content-Type:
application/json`, plus `x-correlation-id` / `x-initiated-at` (matching NovelAI's
own client). NAI text models *continue* text — the panel sends the input as the
`prompt` (a single text block), not a chat conversation.

> Sources for the GLM/`/oa/` route + body shape: NovelAI's published
> `script-types.d.ts` (`GenerationParams` / `GenerationChoice` / `model:
> "glm-4-6" | "xialong-v1"`), the `GALIAIS/NovelAI2api` Go bridge
> (`POST {textBase}/oa/v1/completions` with `{prompt, model, max_tokens,
> temperature, top_p, stop, stream}` → `{choices:[{text}]}`, SSE `data:` lines +
> `[DONE]`), and the NovelAI Swagger spec for the legacy `/ai/generate` body.
> SillyTavern / `Aedial/novelai-api` / `LlmKira/novelai-python` don't implement
> the GLM route yet.
>
> **Status:** _route + body verified against docs/clients; not yet run
> end-to-end against a live account._ Automated tests cover request/response
> shaping (both transports), SSE parsing (legacy `{token}` + OpenAI `{choices}`
> chunks), client-side stop-string truncation, and the panel widget with a fake
> service.

## Checklist (needs a valid `pst-` token in Settings)

- [ ] **GLM happy path.** Input `The old lighthouse keeper said,`, model
      `glm-4-6`, max length `150` → a plausible continuation appears in the
      Output area (streamed if the server streams, otherwise as one chunk) and
      lands in the History list.

- [ ] **No token set.** Clear the API key, **Generate** → clear "NovelAI token
      not set" error, no crash, spinner clears.

- [ ] **Bad token → 401.** Set `pst-bogus`, **Generate** → clear "NovelAI
      rejected the token (401)…" message.

- [ ] **Server-message surfacing.** On any 4xx, the inline error / snackbar
      shows the server's `message`, and the debug console prints
      `NaiTextService: POST <url> failed <code>: <body>  (sent: <body>)`. Paste
      that back if a request fails.

- [ ] **Long output on a capped tier.** Free/Tablet token, max length `400`,
      **Generate** → either short output (tier cap) or a clear 402/403 message;
      no crash, no hang.

- [ ] **Cancel mid-stream.** Start a generation, **Cancel** while tokens arrive
      → stream stops, partial output retained, `isGenerating` false, nothing
      appends afterwards.

- [ ] **Continue.** After a generation, **Continue** → previous output appended
      to Input, Output cleared, new generation runs from the extended prompt.

- [ ] **Stop string.** Parameters → put `.` in Stop strings (GLM also passes it
      as `stop`; legacy relies on client-side truncation) → output truncated at
      the first period.

- [ ] **Legacy model.** Switch to `kayra-v1` or `clio-v1`, **Generate** → uses
      the `{input, parameters}` body on `/ai/generate`; works on tiers that
      still allow it (NovelAI is deprecating Kayra for subscribers) or returns a
      clear error.

- [ ] **Custom model.** Model dropdown → **Custom…**, type `xialong-v1` (or
      another GLM finetune id) → name pattern routes it through `/oa/v1/completions`.

- [ ] **Copy / presets / history.** **Copy** → "Copied to clipboard"; preset
      "Deterministic (low temp)" drops temperature to 0.6; clicking a History
      entry restores input/model/params/output.
