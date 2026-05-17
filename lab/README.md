# Character / Wardrobe Prompt Lab

A backend-only harness for iterating on the character-generation + wardrobe-generation prompts without booting the Flutter app. Hits a real NovelAI text endpoint, runs scenarios, dumps everything (form + prompt + raw + parsed JSON) to `lab/runs/`, and runs an audit that flags forbidden-material tokens, chest-coverage misses, missing colours, smuggled body/pose/weather tokens, and tag-count violations.

## Current iteration target — v2 spec (lean character-gen)

The headline character-gen pipeline is being scoped down. See **`docs/CHARACTER_V2_STATUS.md`** for the working status (what's done, what's next), and `docs/CHARACTER_FEATURES_PLAN.md` §4 for the spec. tl;dr: the lab iterates on a smaller "appearance tags only" prompt — `{name, gender, tags:{base, face, hair, body, nsfw_top, nsfw_bottom, nsfw_always, nsfw}}`. No `soul_md`, `reaction_patterns`, `theme`, `meet_cute`, `personality_summary`, `character_description`, `preview_scene`, `aliases`, or `outfit_tags`.

Current winning lean prompt: `lab/prompts/character.lean.v2.txt` — vocabulary block + canonical-tag validation against `Tags/high-frequency-tags-list.json` + auto-correction pass when invented tags slip through.

### Lean prompt env vars

```powershell
$env:LAB_MAIN_PROMPT = "lab/prompts/character.lean.v2.txt"
$env:LAB_SHAPE = "lean"        # enables lean-shape audit + canonical check + correction pass
$env:LAB_USER_DESCRIPTION = "" # optional free-text steering
```

Audit findings to track on lean runs: **`unknownTag`** (a tag not in the canonical Danbooru list) and **`tags.<bucket>` clothing-smuggle** (clothing leaked into appearance tags). The `nsfw_slot_warning` is informational (importer fills omitted keys with ""), not blocking.

### Wardrobe iteration is up next

Wardrobe-gen has not yet been moved to the v2 vocabulary + canonical-validation pattern. It still emits invented compounds like `iron muscle cuirass (lorica musculata)` and `leather sole sandals`. Plan: `lab/prompts/wardrobe.v3.txt` with era-aware vocabulary blocks (port bri's `_PERIOD_CLOTHING_HINTS`) + canonical-tag tokenization audit + correction pass. The harness also needs to capture the raw response on wardrobe runs (today it only saves parsed outfits, which is useless when parsing fails — as it did on modern_tokyo_mysterious_f).

## What's here

```
lab/
  prompts/
    wardrobe.v1.txt     -- snapshot of the current in-code prompt (the baseline)
    wardrobe.v2.txt     -- candidate next prompt (forbidden-materials made explicit + GOOD/BAD examples)
  scenarios.dart        -- hand-picked test cases (modern Tokyo / Victorian / Roman / etc.)
  audit.dart            -- pure logic: outfit + character quality audit
  runs/                 -- per-run JSON dumps (gitignored; created on first run)
test/
  lab/
    character_lab_test.dart  -- the CLI (driven by env vars; skipped if no NAI_TOKEN)
    audit_test.dart          -- unit tests for the audit
```

## Run it

```powershell
# minimum: token + run
$env:NAI_TOKEN = "pst-..."
flutter test test/lab/character_lab_test.dart --reporter=expanded
```

This runs every scenario in main-gen mode AND wardrobe mode against the live API, with the in-code (v1) prompts. Each run writes a JSON to `lab/runs/`. The console prints prompt size, request duration, and the audit summary for every run.

### Iterate on the wardrobe prompt

```powershell
# baseline
$env:NAI_TOKEN  = "pst-..."
$env:LAB_MODE   = "wardrobe"
$env:LAB_SCENARIOS = "modern_tokyo_mysterious_f,victorian_zenith_f,pax_romana_intimidating_m"
$env:LAB_PROMPT = "lab/prompts/wardrobe.v1.txt"
flutter test test/lab/character_lab_test.dart --reporter=expanded

# candidate
$env:LAB_PROMPT = "lab/prompts/wardrobe.v2.txt"
flutter test test/lab/character_lab_test.dart --reporter=expanded
```

The runs are tagged with the prompt version (`*_wardrobe_v1_*.json` vs `*_wardrobe_v2_*.json`) so you can diff the audit results side by side.

### Drive the free/Tablet-tier failure mode

```powershell
$env:LAB_MAX_TOKENS = "200"   # simulate ~150-token cap by limiting per-call max_length
flutter test test/lab/character_lab_test.dart --reporter=expanded
```

This exercises the batching + truncation-repair code paths that the prod app's wardrobe service uses on low-tier tokens.

## Environment variables

| var              | default              | meaning |
|------------------|----------------------|---------|
| `NAI_TOKEN`      | (required)           | `pst-...` NovelAI token. Absent ⇒ harness skips. |
| `LAB_MODE`       | `both`               | `wardrobe` / `main` / `both` |
| `LAB_SCENARIOS`  | (all)                | comma-separated scenario ids — see `lab/scenarios.dart` |
| `LAB_PROMPT`     | (use in-code)        | path to a wardrobe prompt override file |
| `LAB_MODEL`      | `glm-4-6`            | text model id |
| `LAB_MAX_TOKENS` | `2000`               | per-call `max_length`. Set to ~200 to simulate Tablet-tier. |

## Prompt-override placeholders

Both wardrobe prompt files accept these substitutions (see `substituteWardrobePrompt` in `lib/features/characters/services/wardrobe_generator_service.dart`):

- `{count}` — number of outfits to produce
- `{character_tags}` — body tags (`1girl, 20yo, ...`)
- `{era_hint}` — raw era string (`Pax Romana`), empty for modern
- `{vibe_hint}` — vibe display name (`Mysterious`), empty if surprise-me
- `{era_context}` — pre-formatted era preamble line (empty for modern)
- `{vibe_context}` — pre-formatted vibe preamble line

To extend (per-era underwear hints, GOOD/BAD examples, personality block) — add the placeholder to your prompt file and the substitution in `substituteWardrobePrompt`. Right now `wardrobe.v2.txt` uses the same set v1 does; the per-era underwear hint is the obvious next placeholder to wire in.

## What the audit catches

- **forbiddenMaterial** — any tag containing `linen`, `silk`, `corduroy`, `chiffon`, `velvet`, or `tweed`. (Note: bri's own reference output occasionally violates this — those are real findings, not false positives. `satin` is allowed.)
- **chestCoverage** — outer torso layer (jacket, cardigan, blazer, coat, cloak, surcoat, breastplate, etc.) without a base top garment. Exempts loungewear + `slot=sleep`.
- **tagCountLow / tagCountHigh** — <4 or >7 garment tags.
- **missingColor** — a tag with no recognised colour token. Conservative; some base layers fairly omit colour, so review the flag rather than treat it as a hard fail.
- **smuggle** — body / pose / weather / environment tokens that leaked into `tags`.

Run `flutter test test/lab/audit_test.dart` to see the audit's exact behaviour exercised against fixture cases.

## Iteration loop

1. Pick a scenario or three from `lab/scenarios.dart`. Add new ones freely.
2. Run baseline (`v1`).
3. Skim `lab/runs/*.json` and the console audit summaries.
4. Copy `wardrobe.v1.txt` → `wardrobe.v3.txt`, edit, run with `LAB_PROMPT=lab/prompts/wardrobe.v3.txt`.
5. Compare audit tallies + diff the actual outfit JSON.
6. When a prompt wins, port it back into `buildWardrobePrompt` in `lib/features/characters/services/wardrobe_generator_service.dart` (or `CharacterGenPrompts.buildGeneration` for the main-gen prompt).

The main-gen prompt is not yet templated to a file — it's pure Dart in `lib/features/characters/gen/character_gen_prompts.dart`. Once we know what we want there, we can extract it the same way.

## Known drift vs. bri

The current Flutter port is missing several things bri's wardrobe path has:

- **Era-specific clothing VOCABULARY** (toga / chiton / surcoat / cloche-hat lists per era)
- **Era-specific underwear hints** (chemise / corset / sarashi / bloomers per era)
- **GOOD / BAD example pairs per era**
- **Personality block** when re-generating wardrobe for an existing character (description + summary as context)
- **Male underwear rule** (port hardcodes female base layers; bri has a male variant)

`wardrobe.v2.txt` adds explicit forbidden-material substitutions and a generic GOOD/BAD example. The next iterations should wire `{underwear_rule}` to scenarios that carry an era + gender, and add `{era_vocabulary}` for historical scenarios.
