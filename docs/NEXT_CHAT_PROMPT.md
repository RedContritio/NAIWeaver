# Next-chat handoff prompt — Character v2 (wardrobe iteration)

> Copy the block below into the new chat verbatim. The chat will land with full context, planning docs, and the lab harness ready to go.

---

I'm continuing the NAIWeaver character-system v2 pivot. Previous session got the lean character-gen prompt working (`lab/prompts/character.lean.v2.txt` — 100% canonical Danbooru tags, 5-9s per scenario on glm-4-6). Now I want to iterate on the wardrobe path with the same vocabulary + canonical-validation pattern, plus fix audit false-positives.

**Start by reading these in order:**

1. `docs/CHARACTER_V2_STATUS.md` — the working status doc. What's done, what's next, design decisions locked in (especially: negative-tag context-aware routing, structured per-bucket character + outfit fields, NAI character prefix, photoshoot mode as a toggle).
2. `docs/CHARACTER_FEATURES_PLAN.md` §4 — the spec.
3. `lab/README.md` — how the lab harness works + current iteration target.
4. `lab/prompts/character.lean.v2.txt` — the winning lean prompt for reference (the wardrobe one should follow the same shape).
5. `lab/audit.dart` — what the audit currently flags. Note known issues called out below.
6. `lib/features/characters/services/wardrobe_generator_service.dart` — the wardrobe path. `_batchSizeFor`, `extractWardrobeOutfits`, `_repairTruncatedWardrobe`. Don't edit yet — read for context.
7. The most recent wardrobe diagnostic runs at `lab/runs/*_wardrobe_in-code_*.json` — open them and read the `diagnostic_raw` field. The diagnostic_raw is the single-shot capture (separate from prod batching). Compare the diagnostic_raw output against the parsed outfits to see batching's effect.

## Concrete tasks for this session

### Task A — fix audit false-positives (do this first, the noise is hurting signal)

In `lab/audit.dart`:

1. **`missingColor` is over-strict**: today it flags ANY tag without a color word. But Danbooru has plenty of legitimate **attribute-only tags** that don't need colors: `long sleeves`, `short sleeves`, `high collar`, `scoop neck`, `lace trim`, `ribbon trim`, `hooded`, `floor-length`, `ankle-high`, `flat`. Fix: only flag tags that contain a recognized **garment word** AND lack a color. Build a `_garmentTokens` set (shirt, blouse, t-shirt, sweater, cardigan, hoodie, jacket, blazer, coat, dress, skirt, pants, jeans, shorts, leggings, tights, pantyhose, boots, shoes, loafers, sneakers, heels, sandals, sweatshirt, gown, robe, kimono, hat, beanie, cap, bonnet, scarf, gloves, etc.). Skip the check on tags that don't match the garment list.

2. **Drop `tan` and `chestnut` from `_colors`**: they cause hair/skin drift in NAI. Specifically, "tan" can mean skin tone, garment color, or leather color; NAI gets confused. Same with "chestnut" for hair vs. brown leather. Replace usage with explicit alternatives (`brown`, `beige`, `khaki`).

3. **`forbiddenMaterial` → soft warning, not blocking**: NAI 4.5's Flux text decoder handles non-Danbooru material words (linen, silk, velvet, corduroy, chiffon, tweed) reasonably well. Move these from `findings` to a new `warnings` section in `OutfitReport`, or keep in findings but with a `materialWarning` category that's clearly informational. Update the formatted output to distinguish blocking findings from warnings.

4. **NEW canonical-tag check for outfits, tokenized**: load `Tags/high-frequency-tags-list.json` via the existing `loadCanonicalTags()` helper. For each outfit tag string (which is a compound like `cream knit sweater`):
   - Split into tokens
   - Skip tokens that are in the `_colors` set
   - Walk the remaining tokens and check if each is in the canonical list OR if any **trailing N-gram** (e.g., `knit sweater`, `ankle boots`, `pleated skirt`) is in the canonical list
   - If a token doesn't resolve canonically, emit an `unknownTagToken` finding (info-level)
   - Parenthetical content like `iron muscle cuirass (lorica musculata)` should fail the parenthetical and flag

Write unit tests in `test/lab/audit_test.dart` covering each of these changes.

### Task B — wardrobe.v3.txt with vocabulary blocks

Mirror `lab/prompts/character.lean.v2.txt`'s structure:

- **VOCABULARY BLOCKS by garment category** — top (shirt, blouse, sweater, etc.), bottom (skirt, pants, jeans, etc.), outerwear (jacket, coat, cardigan, cloak, etc.), footwear (boots, sneakers, sandals, etc.), accessories (scarf, hat, gloves, jewelry, etc.). Pull from canonical Danbooru high-frequency. ~30-50 per category.

- **COLOR VOCABULARY** — a curated allow-list of safe Danbooru colors. EXCLUDE `tan`, `chestnut`. Include: white, black, grey, ivory, cream, beige, khaki, brown, burgundy, red, crimson, pink, rose, peach, salmon, coral, orange, mustard, yellow, gold, olive, sage, mint, green, forest, teal, turquoise, aqua, blue, navy, cobalt, indigo, purple, violet, plum, lavender, charcoal, slate, silver. Verify each exists in the canonical list before including.

- **ERA-AWARE BLOCK** — port bri's `_PERIOD_CLOTHING_HINTS` (at `D:\bri\app\dashboard\routes\wardrobe_routes.py:686-697`) as a `{era_vocabulary}` placeholder. Modern → modern garments. Victorian → chemise/corset/bustle/walking skirt/walking suit/etc. Pax Romana → tunic/stola/palla/loincloth/etc. NAI 4.5 handles material words so don't fight `linen tunic` — let it through.

- **NEGATIVE EXAMPLES** — list of things NOT to emit (carried from character v2): "long sleeves" by itself with no color is fine (attribute-only), but `cuirass (lorica musculata)` style parentheticals are out, prose descriptors are out, etc.

- **`<<END>>` stop marker** — same as character v2.

- Wire the new placeholder `{era_vocabulary}` into `substituteWardrobePrompt` in `lib/features/characters/services/wardrobe_generator_service.dart`.

### Task C — run + iterate

```powershell
$env:NAI_TOKEN = "<paste-token>"
$env:LAB_MODE = "wardrobe"
$env:LAB_SCENARIOS = "modern_tokyo_mysterious_f,victorian_zenith_f,pax_romana_intimidating_m"
$env:LAB_MODEL = "glm-4-6"
$env:LAB_MAX_TOKENS = "2000"
$env:LAB_PROMPT = "lab/prompts/wardrobe.v3.txt"
flutter test test/lab/character_lab_test.dart --reporter=expanded
```

Compare against the baseline runs in `lab/runs/*_wardrobe_in-code_*.json` (most recent: `*2026-05-17T15-55-*`). Goal: drop unknownTagToken findings to near-zero, keep the period-coherent garment vocabulary.

### Task D — batching investigation (separate, smaller)

Run wardrobe-only against the 3 scenarios with `_batchSizeFor` artificially forced to the full count (5 in one call). Compare audit tallies vs the batched run. If single-shot is meaningfully better at high token tiers, propose updating `_batchSizeFor` to return `min(count, ceil(maxTokens / 400))` or similar — the current `7` cap at `maxTokens > 1500` is conservative.

The lab harness already does a single-shot diagnostic capture (`diagnostic_raw` in the wardrobe run dumps). Use that as the single-shot baseline.

## Decisions already made (don't relitigate)

- **Lean character-gen output shape**: `{name, gender, tags:{base, face, hair, body, nsfw_top, nsfw_bottom, nsfw_always, nsfw}}` — NO soul_md, NO theme, NO reaction_patterns, NO outfit_tags.
- **Per-outfit prompt area output shape**: `{name, tags}` only — NO seasons/weather/activities/temperature_range/slots/primary.
- **Negative-tag injection**: `DanbooruTag` gets a `negativeExpansion` sibling. Routing is **context-aware**: if the saved-character tag is inserted INSIDE a character's per-character prompt field, negatives go to that character's per-character negative field. Inserted into the GLOBAL prompt, negatives go to the GLOBAL negative.
- **NAI character scaffolding**: structured per-bucket fields on `SavedCharacter` (base/face/hair/body/nsfwTop/nsfwBottom — already exists) and ALSO per-bucket on `ClosetOutfit` (NEW: top/bottom/outer/footwear/accessories/nsfwTop/nsfwBottom — migration needed). Optional `naiCharacterPrefix` on `SavedCharacter`. Rendered to a single comma-joined string at expansion time.
- **Outfit-state respect**: a TOGGLE in regular generation (default off), AND the primary mode in the dedicated photoshoot screen. Same underlying renderer (`outfit_renderer.dart`).
- **Text Gen sidebar tile**: keep `TextGenService` / `NaiTextService` / `TextGenNotifier` (character pipeline depends on them), drop the Tools Hub tile + page for "Text Gen" — character-gen + wardrobe + per-outfit prompt all live in the Characters tab now.

## Constraints

- No frontend work this session. Backend / lab / prompt iteration only.
- No new pub deps.
- Match existing conventions (Provider/ChangeNotifier, KvStore JSON-file services, `context.t` theme tokens, no `Co-Authored-By` trailer on commits per CLAUDE.md).
- Don't break the existing wardrobe-gen prod path.
- The model running everything: glm-4-6 via `text.novelai.net/oa/v1/completions`. Max tokens 2000 unless testing low-tier cap.

## How to run / debug

The lab is `test/lab/character_lab_test.dart`. Driven by env vars. Each run dumps a JSON to `lab/runs/` with the prompt, raw response, parsed output, audit findings. The console prints the audit summary live.

For diagnostic deep-dives: read the `diagnostic_raw` field of a wardrobe run JSON to see GLM's actual single-shot output (separate from the prod batching path).

## What "done" looks like for this session

- Audit at `lab/audit.dart` no longer flags attribute-only tags as `missingColor`. `tan`/`chestnut` dropped. `forbiddenMaterial` demoted to a warning. New `unknownTagToken` finding for non-canonical garment words. All existing audit unit tests still pass.
- `lab/prompts/wardrobe.v3.txt` exists, runs through the harness, and produces outputs with significantly fewer audit findings than the in-code v1 baseline across all 3 scenarios. Real `forbiddenMaterial` cases (linen tunic, silk chemise) are warnings, not blockers. Real invented tags (parentheticals, prose) are flagged as `unknownTagToken`.
- A short report posted back to the user: tally diff v1 → v3, surprising findings, what to iterate on next.

DO NOT promote wardrobe.v3.txt to the in-code prompt yet — same rule as character. Promote only after it wins on multiple scenarios.

DO NOT start the in-code integration of lean character (extracting v2.txt to a Dart string + wiring `generateAppearanceOnly` to the ✨ button) — that's the next session after wardrobe lands.
