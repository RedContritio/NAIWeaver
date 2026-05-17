# Character / wardrobe / text-gen feature track — plan & status

This is the working plan for NAIWeaver's character-system features, ported from
the **`bri.` "Companion CD-ROM"** project (`D:\bri`, a Python app). It tracks
three pieces of work, in dependency order:

1. **LLM (NovelAI text) scaffolding** — ✅ **DONE** (commits `a0f06dc → 1c83508`)
2. **Characters module + Wardrobe + Outfit-state mode** — ✅ **DONE** (Phase A + B, commit `6ad941f`)
3. **AI character generation (encounter pipeline / `soul_md`)** — ⚠️ **SHIPPED but SCOPED DOWN** — see §4. The encounter-style pipeline in `lib/features/characters/gen/` is being replaced for the headline UX by a leaner appearance-only flow. The existing code still works and is staying in the repo for reference / soul-doc users, but it is NOT the path new UI work is targeting.
4. **Lean character-gen + per-outfit prompt + modeling mode** — 🚧 **IN PROGRESS** — the v2 spec; what the app is actually shipping next.

Source of truth for the original implementations is `D:\bri` — that path is
readable from a Claude Code session in this repo, so when porting a prompt or a
data table, **Read the original file directly** rather than working from a
paraphrase. The `bri.` prompt strings are heavily tuned and should be copied
verbatim.

---

## 1. LLM (NovelAI text) scaffolding — DONE

What shipped:

- `lib/core/services/text_gen_service.dart` — `abstract class TextGenService`
  (`generateStream`, `generate`, `providerId`), `TextGenRequest`, `TextGenParams`
  (with named presets), `kDefaultTextModel`, `TextGenException`.
- `lib/core/services/nai_text_service.dart` — `class NaiTextService implements
  TextGenService`. Reuses the same `pst-` token as image gen. **Two transports,
  picked from the model id:**
  | Models | Endpoint | Body | Non-stream resp | Stream |
  |---|---|---|---|---|
  | GLM / Xialong / chat-style (`glm-4-6`, `glm-4-5`, `xialong-v1`, …) | `POST text.novelai.net/oa/v1/completions` (or `/oa/v1/chat/completions` when thinking is on) | `{ prompt, model, max_tokens, temperature, top_p, [top_k, min_p, frequency_penalty, presence_penalty, stop], stream }` | `{ "choices": [ { "text": "…" } ] }` | SSE: `data: {"choices":[{"text":"…"}]}` lines, ending `data: [DONE]` |
  | Legacy (`kayra-v1`, `clio-v1`, `llama-3-erato-v1`) | `POST text.novelai.net/ai/generate` (`-stream` for SSE) | `{ input, model, parameters: { use_string:true, temperature, max_length, min_length, top_k/top_p/top_a/typical_p, tail_free_sampling, repetition_penalty*, phrase_rep_pen, generate_until_sentence, order, force_emotion:false } }` | `{ "output": "…" }` | SSE: `data: {"token":"…","ptr":N,"final":bool}` |
  Headers on every request: `Authorization: Bearer <pst- token>`, `Content-Type:
  application/json`, plus `x-correlation-id` / `x-initiated-at` (matching NAI's
  own client). NAI text models *continue* text — the input is sent as one text
  block, not a chat conversation.
- `lib/features/text_gen/providers/text_gen_notifier.dart` — `TextGenNotifier
  extends ChangeNotifier`. Holds input/model/params/output/reasoning/history.
  Service is injected via `updateService(...)` (pushed by `GenerationNotifier`
  when the API key loads). Exposes `.service` so callers (e.g. the wardrobe
  generator) can drive `TextGenService` directly. `enable_thinking` switch +
  collapsible REASONING section.
- `lib/features/text_gen/widgets/text_gen_panel.dart` — the Text Gen panel
  (Tools Hub → **Text Gen**): multiline input, model dropdown, params expander,
  Generate/Cancel, live streaming output, Continue, Copy, history list.
- Manual test checklist: `docs/TEXT_GEN_MANUAL_TEST.md`.

Notes for future work that uses this:

- **Output-token cap is real.** GLM-4.6 on free/Tablet tiers caps output around
  ~150 tokens; Scroll/Opus allow much more. Anything that needs long output
  (a `soul_md` doc, a 7-outfit JSON) must batch or chunked-continue. The
  wardrobe generator already does this (`WardrobeGeneratorService._batchSizeFor`).
- **GLM-4.6 / Xialong are instruct-capable** (unlike old NAI models). For
  structured-JSON generation you can prompt them like a normal instruct model.
  For prose continuation use NAI-style prompting (one text block).
- To call it from new code: take a `TextGenService` (or `TextGenNotifier.service`),
  build a `TextGenRequest`, `await service.generate(req)` or stream it.

---

## 2. Characters module + Wardrobe + Outfit-state mode — DONE

What shipped (`lib/features/characters/`, commit `6ad941f`):

- **Models**
  - `models/saved_character.dart` — `SavedCharacter`: `id, name, gender,
    tags:{base,face,hair,body,nsfwTop,nsfwBottom,nsfwAlways}` (Danbooru strings,
    no clothing), `characterDescription, artistTag, stylePrefix, theme
    {accent,accentSecondary,bg}, primaryOutfitId, notes`. Derived `bodyTags` =
    `[base,face,hair,body].where(non-empty).join(", ")`. Persisted one JSON file
    per character: `<appSupport>/characters/{id}.json`.
  - `models/closet_outfit.dart` — `ClosetOutfit`: `id, name, tags` (Danbooru
    clothing), `seasons[], weather[], activities[], temperatureRange:[minC,maxC],
    slots[]` (morning/daytime/evening/sleep, [] = any), `hairStyleId` (reserved),
    `items` (parsed per-slot state, lazily populated). Persisted as a JSON array:
    `<appSupport>/characters/{id}/closet.json`.
- **Outfit slot model** (`outfit/` — ported from `bri.`'s `outfit_slots.py` +
  `outfit_slots_data.py`)
  - `outfit/outfit_slots.dart` — the 10 SLOTS (`outerwear, armor, top, dress,
    bottom, bra, panties, legwear, footwear, headwear, accessory`), the STATES
    (`intact, unbuttoned, open, lifted, pulled_down, aside, around_ankles,
    removed`), per-slot VALID state sets, the `dress` two-half model
    (`topState`/`bottomState`), the per-piece `accessory` model.
  - `outfit/outfit_slots_data.dart` — the tag→slot table + slot keyword priority.
  - `outfit/outfit_classifier.dart` — `classifyOutfitTags(rawTags) -> items`:
    exact-table → ambiguity guards → whole-word priority substring match
    (`(?<!\w)bra(?!\w)` so "bracers" ≠ "bra") → unknown → `accessory` + log.
  - `outfit/outfit_renderer.dart` — `renderItemsToTags(items) -> (tags,
    isDishevelled)`: fixed render order, per-(slot,state) verb tags, `removed` →
    canonical nudity tags, nudity consolidation (`topless+bottomless → nude →
    completely nude`), CONCEALMENT (underwear hidden under intact closed-front
    outerwear / dress-top / armor; long closed pieces conceal pelvis too; armor
    hides base top; coverage suppression). Also `applyConcealment(rawTags)` for
    flat strings, `renderItemsForPov(items, {feetInFrame})`. `isDishevelled` =
    any of `{top,bottom,dress,bra,panties,legwear}` non-intact & visible
    (armor excluded) → caller appends `nsfw`.
  - `outfit/outfit_delta.dart` — `applyOutfitDelta(items, delta, turnNo)` with
    validation, decay tick, layer-aware reroute (`top:removed` + intact
    outerwear → `outerwear:removed`), `filterFreshDelta` (scrub first
    post-swap delta of removal-type transitions), `resetItemsToIntact`.
  - `outfit/widgets/outfit_state_panel.dart` — the manual per-slot UI: pick the
    active outfit, cycle each slot's state via a dropdown (valid states only),
    `dress` shows two dropdowns, concealed underwear shown read-only/greyed,
    `accessory` expands to per-piece rows, [Reset to intact], [Re-parse from
    tags], live "→ Rendered tags:" readout, [Apply to prompt].
- **Services / state**
  - `services/character_library_service.dart` — CRUD for SavedCharacter JSON
    files (mirrors PresetService/StyleService, atomic writes).
  - `services/closet_service.dart` — CRUD for a character's closet array.
  - `services/wardrobe_generator_service.dart` — **Phase B**: `WardrobeGeneratorService`
    ports `bri.`'s `_WARDROBE_GENERATE_PROMPT` (no-meet-cute path) verbatim —
    TAG SCOPE / COLOR RULE / PATTERN-COMPOUND RULE / CHEST COVERAGE RULE /
    era-base-layer rule. Requests outfits in small batches sized to the output
    cap (`_batchSizeFor`); salvages complete `{...}` objects from a truncated
    array. Returns `List<GeneratedOutfit>` (outfit + isPrimary flag).
  - `providers/character_library_notifier.dart` — `ChangeNotifier` driving the
    Characters UI **and** tag autocomplete.
- **UI**
  - `widgets/characters_page.dart` — Tools Hub → **Characters**: list pane
    (＋ new, search, accent swatch, primary-outfit name) + editor pane (name,
    gender, notes; the four identity tag buckets with autocomplete + a "no
    clothing here" hint; collapsible NSFW sub-buckets; collapsible style
    identity & description; theme color swatches; live combined-tags preview;
    Wardrobe sub-section — outfit grid with name/tags/chips/primary-star/
    Edit/Delete/Wear, ＋ new outfit, ✨ Generate outfits; Outfit-state panel).
  - `widgets/outfit_editor_sheet.dart` — create/edit one outfit (name, tags w/
    autocomplete, season/weather/activity multi-selects, temperature range
    slider, time-slot multi-select, set-as-primary toggle).
  - `widgets/wardrobe_generate_dialog.dart` — Phase B: count stepper, optional
    era/setting hint, optional vibe hint → runs `WardrobeGeneratorService` with
    a progress indicator → appends results to the closet for review.
  - `widgets/tag_text_field.dart` — the autocomplete-enabled tag field reused by
    the editors.
- **Autocomplete integration** — SavedCharacters surface in every prompt box's
  suggestion list: ranked **favorited wildcards > matching SavedCharacters >
  non-favorited tags/wildcards**. Entry labels are `[Character Name]` (→ primary
  outfit) and `[Character Name] ([Outfit Name])` per closet outfit. Picking one
  **inserts the expanded tag string immediately** at the cursor: `bodyTags` +
  the chosen outfit's tags via `applyConcealment` (or `renderItemsToTags` if an
  outfit-state is active), comma-joined, `+ nsfw` if dishevelled.
- Manual test checklist: `docs/CHARACTERS_MANUAL_TEST.md`.

---

## 3. AI character generation (encounter pipeline) — DONE

Shipped in `lib/features/characters/gen/`:

- **`character_gen_data.dart`** — the 10 builtin vibes (ported from bri.'s
  `vibes.py`, with the `traditional` / `touched` / `addicted` / `custom`
  guidance blobs verbatim), the era catalogue loaded from
  `assets/character_eras.json` (a stripped port of bri.'s `time_periods.json` —
  26 eras, moments verbatim, pins/images dropped) with a small built-in
  fallback, the `eraBlockFor` / `soulAddendumFor` / `eraMomentBlock`
  prompt-block builders (knowledge-boundary clause for historical eras), and the
  `CharacterImageStyle` / gender enums.
- **`character_gen_prompts.dart`** — `CharacterGenPrompts.buildGeneration`
  (verbatim port of bri.'s `_ENCOUNTER_GENERATION_DEFAULT`, trimmed: the
  `music` / voiced-`prompts` / OS / homepage fields are dropped; `meet_cute`
  kept as an optional flavour blurb; the remaining fields — `name`, `gender`,
  `aliases`, `soul_md`, `reaction_patterns`, `character_description`, `tags`,
  `outfit_tags`, `preview_scene`, `personality_summary`, `theme` — are
  requested with the COLOR / PATTERN-COMPOUND / CLOTHING-ONLY / CHEST-COVERAGE
  rules intact), `buildCompletion` (port of `_ENCOUNTER_COMPLETION_DEFAULT`),
  and `buildSoulContinuation` for the chunked-continuation loop.
- **`character_gen_service.dart`** — `CharacterGenService`, the orchestrator:
  Step 1 main call → parse with truncation repair (ported `_repair_truncated_json`
  / `_repair_completion_json` / `_soul_md_truncated`); Step 2 completion pass —
  loops `buildSoulContinuation` calls (cap ~1500 appended tokens / 8 loops) to
  finish a cut-off `soul_md`, then a single fill-the-missing-fields call; Step 3
  starter wardrobe via the existing `WardrobeGeneratorService` (its own batching
  handles low-tier output caps), with the LLM's `outfit_tags` becoming the first
  (primary) closet entry; Step 4 assemble a `SavedCharacter` (+ closet) — the
  `aliases` / `reaction_patterns` / `preview_scene` / `meet_cute` extras are
  stashed in `notes`; the model persists `soul_md`, the tag buckets, the
  description, the summary and the theme as first-class fields. A
  `CharacterGenCancelToken` aborts between steps/continuation calls; nothing is
  written to disk until the final assemble step.
- **`providers/character_gen_notifier.dart`** — `CharacterGenNotifier`
  (`ChangeNotifier`): form state, `progress` (a `CharacterGenProgress`),
  `isGenerating`, `lastError`, `lastGeneratedId`, `cancel()`. On success it
  persists via `CharacterLibraryNotifier.importGeneratedCharacter` (new method)
  so the character shows up in the list + tag autocomplete immediately. Wired
  into `MultiProvider` via a `ChangeNotifierProxyProvider2<CharacterLibraryNotifier,
  TextGenNotifier, _>`.
- **`widgets/character_gen_dialog.dart`** — the form (vibe dropdown w/ hint,
  gender, era dropdown, location text, NSFW toggle, image-style chips, wardrobe
  count slider, conditional custom-vibe / addiction-subject fields); returns a
  `CharacterGenForm`.
- **`widgets/character_gen_progress_dialog.dart`** — modal progress view
  (mirrors the cascade feature's pattern): kicks the run off in `initState`,
  shows the live step text + a linear bar + a Cancel button, pops itself with
  the new character's id when done.

Entry point: a **✨** button next to **+** in the Characters list pane
(`characters_page.dart`), disabled until a `pst-` token is present. The editor
gained a "Personality / soul" expander showing the summary + the editable
`soul_md`. `SavedCharacter` gained `soulMd` + `personalitySummary` (additive,
back-compat `fromJson`). Step 5 of the original spec (auto-generating a preview
portrait via the image-gen path) is **not implemented** — left as a TODO.

Tests: `test/characters/character_gen_test.dart` (JSON repair, `soulMdTruncated`,
continuation stitching, vibe/era prompt-block injection, full-pipeline runs with
a scripted fake `TextGenService` incl. the chunked-continuation path and
cancellation, notifier persistence to a temp dir) and
`test/characters/character_gen_dialog_test.dart` (form renders, custom-vibe
gating, default form). Manual checklist: `docs/CHARACTER_GEN_MANUAL_TEST.md`.

<details>
<summary>Original prompt (for reference)</summary>

### Prompt — "Add AI character generation"

```
We're adding **AI character generation** to NAIWeaver: generate a complete
SavedCharacter (name, Danbooru appearance tags, a personality "soul" doc, theme
colors, and a starter wardrobe) from a few inputs (vibe, gender, era/setting,
NSFW toggle, optional location). Modeled on the "bri." project's
`generate_encounter` pipeline (`D:\bri\app\encounters.py`), adapted for an image
client.

## What already exists (reuse, do NOT reimplement)
- Text-gen backend: `lib/core/services/text_gen_service.dart` (`TextGenService`
  interface, `TextGenRequest`, `TextGenParams`, `kDefaultTextModel`,
  `TextGenException`) + `lib/core/services/nai_text_service.dart` (the concrete
  NAI impl, two transports — GLM models use `text.novelai.net/oa/v1/completions`
  with `{prompt, model, max_tokens, temperature, ...}` → `{choices:[{text}]}`).
  `TextGenNotifier` exposes `.service`. **Output cap warning:** GLM-4.6 on
  free/Tablet caps output around ~150 tokens; Scroll/Opus allow much more — so
  long output MUST be chunked/batched (see Step 2).
- Characters module: `lib/features/characters/` — `SavedCharacter`
  (`tags:{base,face,hair,body,nsfwTop,nsfwBottom,nsfwAlways}`, `bodyTags`
  derived, `characterDescription, artistTag, stylePrefix, theme, primaryOutfitId,
  notes`), `ClosetOutfit`, `CharacterLibraryService` + `CharacterLibraryNotifier`,
  `ClosetService`, the outfit-slot model (`outfit/...`), and
  `WardrobeGeneratorService` (already ports bri.'s `_WARDROBE_GENERATE_PROMPT`
  and handles output-cap batching). The Characters UI is `characters_page.dart`
  (Tools Hub → Characters).
- For multi-step Tools-feature UX patterns (progress steps + cancel), look at
  `lib/features/tools/cascade/` — mirror its notifier/progress structure.
- Read `ARCHITECTURE.md` for house conventions.

## Read these from the bri. source (the path D:\bri is readable from here — Read them directly, copy verbatim, don't paraphrase)
- `D:\bri\app\prompts.py` — `_ENCOUNTER_GENERATION_DEFAULT` (the main gen prompt),
  `_ENCOUNTER_COMPLETION_DEFAULT` (the truncation-repair pass), the encounter
  sub-blocks (`encounter_period_modern`, `encounter_period_historical`,
  `encounter_soul_addendum`, `encounter_type_*`).
- `D:\bri\app\vibes.py` — the 10 vibes and their guidance text. `traditional`,
  `touched`, `addicted`, `custom` have substantial guidance blobs; copy them
  exactly. `addicted` has an optional addiction-subject sub-field; `custom`
  takes free text.
- `D:\bri\config\time_periods.json` — the 26 curated eras (each has a `moment`
  prose blob). Either port the list or start with a short subset (modern,
  ancient Rome, medieval, Renaissance, Victorian, 1920s, 1980s, …).
- `D:\bri\app\encounters.py` — `generate_encounter` (the orchestration),
  `_run_completion_pass`, `_repair_truncated_json`, `_generate_starter_closet`,
  `_CRITICAL_FIELDS`, `_soul_md_truncated`.

## The pipeline

### Inputs (a small form)
- `gender`: any | female | male | nonbinary
- `vibe`: surprise_me | friendly | mysterious | chaotic | romantic | intimidating
  | traditional | touched | addicted | custom  (+ conditional "addiction subject"
  text for `addicted`, "custom vibe" text for `custom`)
- `era`: "modern day" or a historical era label; if historical → inject the
  knowledge-boundary block
- `location`: optional free text ("a coastal town in Portugal", "Winterfell");
  optional `loreContext` blob for a fantasy world
- `nsfw`: bool — when true, also request the split nsfwTop/nsfwBottom/nsfwAlways
  buckets
- `imageStyle`: anime (default; NAI image gen is tag-based) | realistic (also
  fill `characterDescription` natural-language prose)
- `wardrobeCount`: default 5
- optional "also generate a preview image" checkbox

### Step 1 — main generation LLM call
Build the prompt from `_ENCOUNTER_GENERATION_DEFAULT` (verbatim, with the
`{vibe_guidance}` / era / knowledge-boundary / location-lore slots filled).
Essentials to preserve: the "must feel REAL — not a template, not a trope" frame;
the LOCATION/GENDER/AGE/VIBE/PERIOD/SEASON/WEATHER header; the critical guidelines
(root in the location; specific occupation; language flavor / code-switching; a
backstory TURNING POINT; speech patterns describe STYLE/RHYTHM not catchphrases —
NEVER embed repeated phrases/pet names/verbal tics); the JSON output fields:
`name, gender, aliases, soul_md` (600–1000-word 2nd-person "You are…" doc with
mandated sections WHO / BODY / PERSONALITY (traits with contradictions) / SPEECH
(pattern not phrases) / BACKSTORY (turning point) / RELATIONSHIPS / BEHAVIORAL
RULES / WHAT THEY ARE NOT), `reaction_patterns` (7 keys: nervous, angry,
attracted, sad, scared, embarrassed, happy — each 2–3 sentences of THIS
character's specific tells, not stock body language), `character_description`
(40–80-word permanent physical description — only what's ALWAYS true; no
clothing/expressions/poses/lighting/camera terms), `tags` ({base [1girl/1boy/
1other, ethnicity, age range, always-visible marks — don't default to scars],
face, hair, body} strict Danbooru no-clothing; + nsfw_top/nsfw_bottom/nsfw_always
when nsfw=true), `outfit_tags` (the "meet outfit" — Danbooru clothing, same
COLOR RULE / PATTERN-COMPOUND RULE / CLOTHING-ONLY rules `WardrobeGeneratorService`
uses), `preview_scene` (Danbooru pose/expression/background), `personality_summary`
(one vivid memorable sentence), `theme` ({accent, accent_secondary, bg} hex —
accent from personality/culture/appearance; bg HSL lightness < 15%). Skip bri.'s
`music` / `prompts` fields (irrelevant to an image client); keep `meet_cute` only
as an optional flavor blurb if cheap.

Knowledge-boundary block for historical eras (port verbatim from
`encounter_period_historical` + `encounter_soul_addendum`): native of the era, not
a modern person in costume; knows ONLY what someone living in {era} in {location}
would know; never heard of anything invented/discovered/established after their
era; include 5–8 specific post-era concepts they've never heard of.

### Step 2 — completion/repair pass + chunked continuation (REQUIRED)
Port `_run_completion_pass` + `_ENCOUNTER_COMPLETION_DEFAULT`: after Step 1,
detect missing/mid-sentence-truncated fields (critical: `tags, outfit_tags,
personality_summary, character_description, preview_scene, reaction_patterns`;
`soul_md` truncated if its last non-whitespace char ∉ `.!?"')…`). If anything's
missing/truncated, second call asking only for those (+ a `soul_md_completion`
continuation to APPEND if soul_md was cut). Keep a deterministic JSON-repair
fallback: strip fences, extract `{`..`}`, `jsonDecode`; on failure walk backwards
trimming and try appending closing brackets until it parses (require `name` +
`soul_md` to accept).

**Output-cap handling — do this from day one:** a 600–1000-word `soul_md` is
~800–1300 tokens; on free/Tablet (`max_tokens` ≈ 150) it WILL NOT come back in
one call. Either (A) request `soul_md` in its own call, then loop continuation
calls ("continue the document exactly where it left off, no preamble") until it
ends on sentence-final punctuation or you hit ~1500 tokens, then request the
structured fields in a separate call; or (B) detect truncation after each call
and auto-continue the JSON. Pick one, make it robust, show per-step progress.
On Scroll/Opus it'll often complete in 1–2 calls — don't force the loop if the
first response is already complete.

### Step 3 — starter wardrobe
Reuse `WardrobeGeneratorService` (it already handles batching/output-caps):
generate `wardrobeCount` outfits passing the generated `bodyTags` as background +
the era hint + the meet-outfit as context. Add them to the character's closet.
Turn the Step-1 `outfit_tags` into a closet outfit too and set it as
`primaryOutfitId`.

### Step 4 — assemble & save
Build a `SavedCharacter`: `id` = uuid hex, populate `name, gender, tags{...},
bodyTags` (derived), `characterDescription, personalitySummary`, the soul doc
(add a `soulMd` field to `SavedCharacter` if it doesn't have one — just a long
string), `theme`, and stash `aliases` / `reaction_patterns` / `preview_scene` in
`notes` or add fields (your call). Save via `CharacterLibraryService`; save the
closet via `ClosetService`. The new character then immediately shows up in the
Characters list AND in tag autocomplete (the notifiers already drive both).
**Write only at the end** (or write to a temp file and rename) so a cancel
leaves no half-written character.

### Step 5 (optional) — preview image
If "also generate a preview" is checked: after save, run a NovelAI image gen for
a portrait using `artistTag (if any) + bodyTags + outfit_tags + preview_scene`,
save it as the character's avatar — via the EXISTING image path
(`NovelAIService` / `GenerationNotifier`). Mind NAI's anti-throttle if batching.

## UI
- "✨ Generate Character" entry point in the Characters module (next to "＋ New"
  in `characters_page.dart`'s list pane, and/or a Tools Hub tile — match
  existing patterns).
- Form dialog: vibe dropdown (guidance as tooltip/subtitle), gender dropdown,
  era dropdown, optional location field, NSFW toggle, image-style toggle,
  wardrobe-count stepper, "generate preview" checkbox, conditional addiction-
  subject / custom-vibe fields.
- Progress view (mirror cascade's): "Generating character… → Completing fields…
  → Generating wardrobe (3/5)… → Saving…", with a Cancel that aborts cleanly.
- On completion: open the new character in the editor for review. Snackbar.
  On error: clear message, no partial save.
- `CharacterGenNotifier extends ChangeNotifier` holding form state / progress
  step / isGenerating / lastError; wired into MultiProvider.

## Testing
- Unit tests: JSON-repair / completion-detection (feed truncated JSON cut
  mid-string / mid-array / after a key → repairs or correctly flags what's
  missing); `soul_md` truncation detection (ends on "," vs "."); the chunked-
  continuation loop terminates and stitches correctly given a fake `TextGenService`
  returning canned partial chunks; vibe/era prompt-block injection produces the
  expected substrings; assembled `SavedCharacter` from a canned good response has
  all fields and serializes round-trip.
- Widget test: the generate form renders & validates; submitting with a mocked
  `TextGenService` runs the steps and produces a saved character; Cancel aborts
  with no file written.
- Manual checklist → `docs/CHARACTER_GEN_MANUAL_TEST.md`: with a real pst- token,
  generate "mysterious / female / modern / Lisbon" → soul_md reads like a real
  person not a wiki, tags are sane Danbooru, 5 outfits generated & sensible,
  theme colors applied, character in autocomplete; generate "traditional / male /
  medieval / a monastery" → knowledge-boundary clause produced era-appropriate
  content, wardrobe avoided modern underwear tags; on a free-tier token verify
  chunked continuation actually fires and yields a complete soul_md (not a
  150-token stub).
- `flutter analyze` clean, `flutter test` green, existing tests unaffected.

## Constraints
- No new pub dependencies. Discuss before adding anything.
- Reuse, don't reimplement: text-gen service, `SavedCharacter`/`ClosetOutfit`,
  the closet services, the outfit-slot model, `WardrobeGeneratorService`, the
  image-gen path. This feature is an ORCHESTRATOR.
- Match existing conventions (Provider/ChangeNotifier, multi-step Tools UI,
  JSON-file services, theming tokens, snackbar/error, l10n).
- Don't break image gen or the existing Characters module.
- Copy the `bri.` prompt strings verbatim (Read them from `D:\bri\...`); they're
  heavily tuned.
- Commit at the end (no `Co-Authored-By` trailer per CLAUDE.md). Don't push
  unless asked.

Start by exploring the prerequisite modules + the cascade feature, then propose
a plan (orchestration steps, chunked-continuation strategy, form fields, entry
point) before writing code.
```

</details>

---

---

## 4. Lean character-gen + per-outfit prompt + modeling mode — IN PROGRESS

The v2 spec. The encounter-style soul_md flow shipped in §3 produces a 9k-char JSON blob that GLM-4.6 routinely truncates at 2000 max_tokens, and most of those fields (soul_md, reaction_patterns, theme, meet_cute, preview_scene, aliases, personality_summary, character_description) aren't actually useful for the headline UX. Replace the headline path with three small generators.

### 4.1 Lean character-gen (appearance only)

**Input UI**
- Free-text description (one textarea — "freckled redhead barista with a nose ring, late 20s, slim build")
- Structured fields, kept from the existing dialog: gender, age range, era, location, NSFW toggle, image style. These anchor the model; the free text steers it.

**Output** — strict Danbooru tags, nothing else. JSON shape:
```json
{
  "name": "...",
  "gender": "female|male|nonbinary",
  "tags": {
    "base": "1girl, 20yo, ...",
    "face": "...",
    "hair": "...",
    "body": "...",
    "nsfw_top": "...",
    "nsfw_bottom": "...",
    "nsfw_always": "...",
    "nsfw": ""
  }
}
```
- `nsfw_top` / `nsfw_bottom` / `nsfw_always` / `nsfw` follow bri's split (`nsfw` is the legacy fallback, leave empty). All four are empty strings when the NSFW toggle is off.
- No `soul_md`, `reaction_patterns`, `character_description`, `personality_summary`, `theme`, `meet_cute`, `preview_scene`, `aliases`, `outfit_tags`. None of them.

**Implementation**
- New prompt builder (in `character_gen_prompts.dart` or a new file) — `buildLeanGeneration(inputs)` — returning a prompt that asks for ONLY the JSON above plus respects the free-text input.
- New service path on `CharacterGenService` — `generateAppearanceOnly(form)` — that calls the LLM once, parses, and returns a partial `SavedCharacter` (no soul_md / theme / etc.). Existing `generateFull(form)` for soul_md flow stays callable for users who want it.
- `SavedCharacter`'s `soulMd`, `personalitySummary`, `theme`, `characterDescription` are already nullable / optional — confirm that, leave them blank on the lean path.
- Persist via the same `CharacterLibraryNotifier.importGeneratedCharacter` (the import is already field-agnostic).

**Why it works on GLM at 2000 tokens**
- The whole JSON above is maybe 400–600 tokens. No truncation risk at any tier. No chunked-continuation loop needed.
- All 7 NSFW slots ship per call; no second completion pass.

### 4.2 Per-outfit prompt area

A textarea on the character page that takes free text ("cozy winter coffee shop fit") and produces ONE outfit JSON. No seasons / weather / activities / temperature_range / slots / primary fields — just:
```json
{
  "name": "...",
  "tags": "..."
}
```

**Implementation**
- New prompt builder in `wardrobe_generator_service.dart` (or a sibling file): `buildSingleOutfitPrompt({characterTags, userPrompt, eraHint})`. Same TAG SCOPE / COLOR / PATTERN-COMPOUND / CHEST-COVERAGE rules as the wardrobe prompt — those are still right; they just apply to one outfit.
- New service method `WardrobeGeneratorService.generateOne(...)` returning `GeneratedOutfit?`. JSON shape change: parser must accept `{name, tags}` directly (top-level object, not wrapped in `{"outfits":[...]}`).
- The new outfit gets appended to the character's closet via the existing `ClosetService`.
- UI: a small free-text input in the Wardrobe sub-section of the character editor, "Add outfit from prompt" button, progress indicator while the call runs, snackbar on success.

### 4.3 Modeling mode (per-garment state → image prompt)

A new generation mode that takes outfit tags + per-garment state flags and produces an image prompt that reflects those states. NOT an LLM call — this is pure mechanical assembly using the **existing** outfit-slot model (`lib/features/characters/outfit/`).

**What's already there (reuse — do NOT reimplement)**
- The 10 slots and 8 states are already defined in `outfit/outfit_slots.dart`.
- `outfit/outfit_classifier.dart` already parses raw tags → per-slot items.
- `outfit/outfit_renderer.dart` already renders `items + states → (tags, isDishevelled)` with per-state verb tags, removal canonicalisation, and concealment.
- `widgets/outfit_state_panel.dart` already exposes per-slot state dropdowns with valid-state-only filtering, dress two-half model, concealed-underwear greying, accessory expansion, "Apply to prompt" button.

**What's new in modeling mode**
- A first-class "modeling mode" entry point on the character page (today the outfit-state panel is a sub-section of the editor). Modeling mode = a dedicated screen where the user picks a character + outfit, then sees the outfit-state panel front-and-centre alongside a live render and a "Generate image" button.
- The image prompt sent to the NAI image path = `artistTag (if any) + bodyTags + renderItemsToTags(items) + (isDishevelled ? "nsfw" : "")`. That's already what `renderItemsToTags` returns; modeling mode just wires it through.
- Saving / loading "scene presets" — a named (character, outfit, statesPerSlot) tuple — is the natural follow-up if users want to revisit a partially-removed look. Defer until requested.

**State flags (already in `OutfitSlotState`)**
- `intact` — fully worn
- `unbuttoned` — open at the closure (shirts, blouses, jackets)
- `open` — pulled open further than unbuttoned (coats, cardigans)
- `lifted` — pushed up (skirts, dresses)
- `pulled_down` — pulled below the waist / pulled down off shoulders depending on slot
- `aside` — moved to one side without removal (panties aside)
- `around_ankles` — bottoms / panties around the ankles
- `removed` — gone (becomes a nudity tag)

The valid-state set per slot is defined in `outfit/outfit_slots.dart`; the UI already enforces it.

### 4.4 What happens to §3 (the soul_md pipeline)

- Stays in the repo (`lib/features/characters/gen/`) as-is. No file deletions.
- The ✨ button on the Characters page currently invokes the full soul_md flow. **Plan**: change it to invoke the lean flow by default, with a "Generate with personality (soul_md)" option behind a More-actions menu for users who want the full pipeline.
- `SavedCharacter.soulMd` / `personalitySummary` / `theme` / `characterDescription` remain in the model so existing characters round-trip cleanly.

### 4.5 Order of work

1. Lean character-gen prompt + service path + audit fixture (this is what the lab is iterating on now).
2. Swap the ✨ button to lean-by-default; keep soul_md behind a menu.
3. Per-outfit prompt input + parser + UI.
4. Modeling mode screen (mostly UI work — the rendering pipeline is done).

### 4.6 Lab harness target

The prompt lab at `lab/` is the iteration surface for §4.1 (lean character-gen) and §4.2 (per-outfit prompt). The existing scenarios and audit are still relevant — the audit already catches the things we care about for tags (color, chest coverage, smuggle, tag count, parse failures). The audit's character-level checks for `soul_md` / `reaction_patterns` / `theme` should be relaxed or made opt-in once the lean prompt lands so audit findings don't fire on dropped fields.

---

## Held-off items (deliberately not doing yet)

From the original assessment of `bri.`, these were explicitly **deferred** — listed
here so they're not forgotten:

- **`correct_tags` two-tier tag normalization** + the 41K-tag frequency list — the
  app already has the same tag list, so this is lower value; revisit if tag
  autocomplete / a "clean up my prompt" button is wanted.
- **Curated interaction / pose tag palettes** (`bri.`'s `interaction_tag_palette`
  / `solo_pose_palette` in `D:\bri\app\prompts.py`) — a categorized
  canonical-tag picker for multi-character scenes. Held.
- **SillyTavern card import** (`D:\bri\app\card_import.py`) — V2/V3 PNG / `.charx`
  / `.risum` → `SavedCharacter`. Standalone value (raw mode needs no LLM). Held.
- **Hairstyle library subsystem** (`D:\bri\app\hairstyle.py` + `hairstyle_pools.py`)
  — per-character length-gated booru-tag styles; outfits can pin a `hairStyleId`.
  The `hairStyleId` field already exists on `ClosetOutfit` as a placeholder. Held.
- **Body-state subsystem** (`D:\bri\app\body_state.py`) — graded sweat/blush/wet/
  arousal tags, clothing-exposure-gated anatomy tag swaps. Held (NSFW machinery,
  orthogonal to core use).
- **Fictional-IP lookup** (`D:\bri\app\character_lookup.py` + `lookup_sources.py`)
  — web-search a named character across Wikidata/AniList/VNDB/Fandom/Wikipedia →
  synthesize a profile, with a canonical-Danbooru-anchor injection. A bigger
  separate feature; pairs naturally with character generation once that lands.
- **NOT porting at all:** the cron scheduler, Telegram/Discord bots, briOS virtual
  desktop, autonomous behaviors (musings/echoes/curiosity), letters, music gen —
  habitat features orthogonal to an image client.

## Reference: where the originals live

- `D:\bri\app\outfit_slots.py`, `outfit_slots_data.py` — outfit slot model (ported)
- `D:\bri\app\realtime_outfit.py` — the LLM delta-extraction prompt (not ported; no RP in NAIWeaver)
- `D:\bri\app\wardrobe.py`, `D:\bri\app\dashboard\routes\wardrobe_routes.py` — `_WARDROBE_GENERATE_PROMPT` (ported)
- `D:\bri\app\encounters.py`, `D:\bri\app\prompts.py` — character generation (to port — item 3)
- `D:\bri\app\vibes.py`, `D:\bri\config\worlds.json`, `D:\bri\config\time_periods.json` — vibes / worlds / eras
- `D:\bri\app\character_lookup.py`, `D:\bri\app\lookup_sources.py` — IP lookup (held)
- `D:\bri\app\card_import.py` — SillyTavern import (held)
- `D:\bri\app\hairstyle.py`, `D:\bri\app\hairstyle_pools.py` — hairstyle library (held)
- `D:\bri\app\body_state.py`, `D:\bri\app\body_state_tuning.py` — body state (held)
- `D:\bri\tools\selfie.py` — `bri.`'s NovelAI **image** call + 3-layer prompt assembly + Director-tools usage
- `D:\bri\app\backends\` — `bri.`'s LLM adapter registry (reference for a future provider abstraction)
