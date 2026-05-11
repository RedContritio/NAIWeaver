# Text Generation — manual test checklist

The Text Gen tool (Tools Hub → **Text Gen**) talks to NovelAI's text API
(`https://text.novelai.net/ai/generate` and `/ai/generate-stream`) using the
same `pst-` token as image generation. Token-id features (`bad_words_ids`,
token-array `stop_sequences`, logit bias) are intentionally **out of scope** in
v1 — only string mode (`use_string: true`) is used.

Run this list once a real `pst-` token is configured (Settings → API key).
Until then, leave it for the user — the automated tests cover the wiring; only
the live round-trips below need a token.

> **Status:** _not yet run end-to-end_ — needs a valid `pst-` token. Automated
> coverage (`flutter test`) passes: param serialization, SSE parsing, client-side
> stop-string truncation, and the panel widget (Generate/Cancel with a fake
> service).

## Checklist

- [ ] **Happy path (streaming).** Input: `The old lighthouse keeper said,`,
      model `glm-4-6`, max length `150`. Click **Generate**. → A plausible
      continuation streams into the Output area visibly token-by-token; the
      button shows **Cancel** while running, then returns to **Generate**; the
      result is added to the History list.

- [ ] **No token set.** Clear the API key in Settings, reopen Text Gen, click
      **Generate**. → A clear error ("NovelAI token not set — add it in
      Settings."), no crash, `isGenerating` returns to false.

- [ ] **Bad token → 401.** Set an obviously invalid token (e.g. `pst-bogus`),
      click **Generate**. → Clear "NovelAI rejected the token (401)…" error, no
      crash.

- [ ] **Long output on a capped tier.** With a free/Tablet token, set max length
      to `400` and **Generate**. → Either the request returns short output (tier
      cap) or a clear 402/403-style "your NovelAI subscription tier may not allow
      …" message. No crash, no infinite spinner.

- [ ] **Cancel mid-stream.** Start a generation, click **Cancel** while tokens
      are still arriving. → Stream stops, the partial output stays in the Output
      area, `isGenerating` is false, and no further tokens append afterwards.

- [ ] **Continue.** After a successful generation, click **Continue** (the
      `↵`-style button in the Output toolbar). → The previous output is appended
      to the Input field, the Output area clears, and a new generation runs from
      the extended prompt.

- [ ] **Stop string.** Open **Parameters**, turn **Generate until sentence end**
      OFF, put `.` in the Stop strings box, then **Generate** from something like
      `She opened the door`. → Output is truncated at the first period (client-
      side), nothing after it appears.

- [ ] **Copy.** With output present, click **Copy** → snackbar "Copied to
      clipboard" and the clipboard holds the output text.

- [ ] **Presets.** Switch the **Preset** dropdown to "Deterministic (low temp)" →
      temperature slider drops to ~0.6. Switch back → 1.0.

- [ ] **Custom model.** Pick **Custom…** in the model dropdown, type a NovelAI
      finetune id (e.g. their "Xialong" GLM-4.6 variant id from the NovelAI docs)
      and **Generate**. → Request uses that model id; works or returns a clear
      error if the id is wrong.

- [ ] **History restore.** Click a History entry → Input/model/params/output are
      restored into the panel.

- [ ] **Non-stream path.** (Code review note, not a UI step.) `NaiTextService.generate()`
      hits `/ai/generate` directly and returns `output`, stripping an echoed
      `input` prefix if the deployment includes one.
