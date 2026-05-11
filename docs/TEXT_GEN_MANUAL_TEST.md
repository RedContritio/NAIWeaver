# Text Generation — manual test checklist

The Text Gen tool (Tools Hub → **Text Gen**) talks to NovelAI's text API,
reusing the same `pst-` token as image generation.

NovelAI has **two text APIs** and the panel picks one based on the selected
model:

| Models | Transport | Request body | Non-stream response |
|---|---|---|---|
| `glm-4-6` (and GLM/"Xialong" finetunes) | `POST {host}/ai/generate` (and `/ai/generate-stream`) | chat-style: `{ model, messages:[{role,content}], temperature, max_tokens, top_p, top_k?, frequency_penalty?, presence_penalty?, min_p?, stop? }` | `{ "choices": [ { "text": "…" } ] }` |
| `kayra-v1`, `clio-v1`, `llama-3-erato-v1` (legacy) | same paths | `{ input, model, parameters:{ use_string:true, temperature, max_length, min_length, top_k/top_p/top_a/typical_p, tail_free_sampling, repetition_penalty*, phrase_rep_pen, generate_until_sentence, order, force_emotion:false } }` | `{ "output": "…" }` |

Host routing: `kayra-v1`/`llama-3-erato-v1` → `text.novelai.net`; everything
else (Clio, GLM) → `api.novelai.net` (the documented legacy alias). Streaming
events: legacy emits `{"token":"…","ptr":N,"final":bool}`; chat emits
OpenAI-style `{"choices":[{"delta":{"content":"…"}}]}` chunks (exact shape not
publicly documented — the SSE parser handles both, and `generateStream` falls
back to the non-stream `/ai/generate` call if it can't parse a stream).

> ⚠️ The GLM chat wire format here is **reverse-engineered from NovelAI's
> scripting-API docs** (`api.v1.generate` → `messages` + OpenAI-ish params →
> `choices[0].text`). The exact raw HTTP route/streaming chunk shape isn't
> officially published. The non-streaming `/ai/generate` path is the primary
> one; iterate against the debug log (`NaiTextService: /ai/generate failed
> <code>: <body> (sent: …)`) if a request is rejected.
>
> **Status:** _not yet verified end-to-end against a live account._ Automated
> tests cover the request/response shaping, SSE parsing (legacy + chat chunks),
> client-side stop-string truncation, and the panel widget with a fake service.

## Checklist (needs a valid `pst-` token in Settings)

- [ ] **GLM happy path.** Input `The old lighthouse keeper said,`, model
      `glm-4-6`, max length `150` → a plausible continuation appears in the
      Output area (streamed if the server streams, otherwise as one chunk),
      and it lands in the History list.

- [ ] **No token set.** Clear the API key, click **Generate** → clear "NovelAI
      token not set" error, no crash, spinner clears.

- [ ] **Bad token → 401.** Set `pst-bogus`, **Generate** → clear "NovelAI
      rejected the token (401)…" message.

- [ ] **Server-message surfacing.** If anything 4xx's, the snackbar/inline error
      shows the server's `message` field, and the debug console prints
      `NaiTextService: …failed <code>: <body> (sent: …)`. Paste that back if it
      fails — it tells us exactly which field/route the server didn't like.

- [ ] **Long output on a capped tier.** With a free/Tablet token, max length
      `400`, **Generate** → either short output (tier cap) or a clear 402/403
      message; no crash, no hang.

- [ ] **Cancel mid-stream.** Start a generation, **Cancel** while tokens arrive
      → stream stops, partial output retained, `isGenerating` false, nothing
      appends afterwards.

- [ ] **Continue.** After a generation, click **Continue** → previous output is
      appended to Input, Output clears, a new generation runs from the extended
      prompt.

- [ ] **Stop string.** Parameters → turn **Generate until sentence end** off
      (legacy models) / leave default (GLM passes `stop`), put `.` in Stop
      strings, **Generate** from `She opened the door` → output truncated at the
      first period (client-side, regardless of model).

- [ ] **Legacy model.** Switch model to `kayra-v1` or `clio-v1` and **Generate**
      → uses the `{input, parameters}` body; works on tiers that still allow it,
      or returns a clear error (NovelAI is deprecating Kayra for subscribers).

- [ ] **Custom model.** Model dropdown → **Custom…**, type a GLM finetune id
      (e.g. NovelAI's "Xialong" variant from their docs) → name pattern routes
      it through the chat path.

- [ ] **Copy.** With output present, **Copy** → "Copied to clipboard" snackbar +
      clipboard holds the text.

- [ ] **Presets / history.** Preset → "Deterministic (low temp)" drops
      temperature to 0.6; clicking a History entry restores
      input/model/params/output.
