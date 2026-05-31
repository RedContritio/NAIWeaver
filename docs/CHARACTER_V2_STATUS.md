# Character v2 — Status & Roadmap

Tracking the **v2 character-system pivot** (May 2026). See `CHARACTER_FEATURES_PLAN.md` §4 for the spec; this doc is the working status / what's done / what's next.

## TL;DR

Replacing the heavyweight encounter-style character generation (9k-char soul_md JSON that GLM-4.6 routinely truncates) with three small generators wired through the **tag library**:

- **Lean character-gen** — appearance tags only.
- **Wardrobe-gen** — same as today but with canonical-tag validation.
- **Per-outfit prompt** — free-text → `{name, tags}` for one outfit.

The end state: a user types in the Characters tab, generates a character + wardrobe, optionally adds per-character negative tags + NAI character scaffolding, and the result becomes an autocomplete entry (`[OCNAME]` / `[OCNAME (OUTFITNAME)]`) that expands into the right tag string anywhere they prompt.

## Status snapshot

| Piece | Status | Notes |
|---|---|---|
| Text-gen scaffolding (NAI `/oa/v1/completions`) | ✅ shipped | `lib/core/services/text_gen_service.dart`, `nai_text_service.dart` |
| Characters module (storage, models, library) | ✅ shipped | `lib/features/characters/`, file-per-character JSON |
| Encounter-style soul_md pipeline | ⚠️ shipped, **being demoted** | `lib/features/characters/gen/` — code stays, will be moved off the default ✨ button |
| Wardrobe-gen (no-meet-cute) | ✅ shipped | `WardrobeGeneratorService` — works but emits non-canonical tags |
| **Outfit-state model + renderer** (modeling mode foundation) | ✅ shipped | `lib/features/characters/outfit/` — 10 slots, 8 states, classifier + renderer + delta |
| **Tag library autocomplete: `[OCNAME]` + `[OCNAME (OUTFITNAME)]`** | ✅ shipped | `CharacterLibraryNotifier.suggestionTags` — DanbooruTag with `typeName='saved_character'` and pre-expanded `expansion` |
| Prompt lab harness | ✅ shipped + iterating | `lab/`, `test/lab/`, `Tags/high-frequency-tags-list.json` for canonical validation |
| **Lean character prompt v2** (vocabulary + canonical validation + auto-correction) | ✅ working in lab | `lab/prompts/character.lean.v2.txt` — 0 findings on all 3 baseline scenarios |
| Lean character-gen wired into in-code service + ✨ button | 🚧 TODO | extract v2 prompt → Dart, add `generateAppearanceOnly()` |
| **Wardrobe canonical validation + correction pass** | 🚧 NEXT | apply the same pattern that worked for character |
| Per-outfit prompt area | 🚧 TODO | `{name, tags}` only — no seasons/weather/etc per user spec |
| Negative-tag support per character / per outfit | 🚧 TODO | adds `negativeTags` to SavedCharacter + per-outfit; flows through `expansion` |
| NovelAI character scaffolding block | 🚧 TODO | optional `naiCharacterPrefix` field on SavedCharacter |
| Sunset Text Gen sidebar tile | 🚧 TODO | Tools Hub registration change — keep the service, drop the page |
| Modeling mode UI (front-and-center outfit-state screen) | 🚧 deferred until other items land | rendering pipeline is already done |
| Soul_md pipeline (encounter style) | ⚠️ keep callable via menu | not the default flow |

## What we did this session — turn 4 (2026-05-17, wardrobe v3.1 + audit hardening)

### Audit hardening (zero LLM cost)

`lab/audit.dart`:
- **`_baseTops` expanded** with `dress, gown, tunic, tunica, stola, chiton, peplos` so historical/draped single-garment looks (long dress + cardigan, stola + palla, tunica + cloak, chiton + cape) no longer false-flag `chestCoverage`.
- **`_attributeTokens` allow-list added** (`hooded, floor-length, ankle-high, knee-length, high-waisted, off-shoulder, cropped, fitted, plunging, flat, heeled, open, sleeveless, scoop, v-neck`). When a tag's non-colour tokens are ALL in this set, `unknownTagToken` passes it. Stops the `high-waisted` / `hooded` / `floor-length` warnings v3 was throwing.
- **`_eraToleratedTags` allow-list added** for period vocab NAI handles but high-frequency-tags-list.json doesn't index (`stola, palla, tunica, subligaculum, pallium, calcei, fibula, torque, peplos, himation, hauberk, gambeson, doublet, shendyt`). Pax Romana warnings collapsed from 8 → ~0 on the v3 dumps under the new audit.
- **`_canonicalSupplement`** (`tights, stockings, pajama set, rain boots`) — verified each against `high-frequency-tags-list.json` first. Treated as canonical for the trailing-N-gram check. `silver bracelet` was dropped (`pearl bracelet` IS canonical but `silver bracelet` isn't, and isn't widely-rendered enough to allow-list).
- Unit tests in `test/lab/audit_test.dart` cover every new branch + non-regression cases.
- New one-shot `test/lab/reaudit_v3_runs_test.dart` re-scores the v3 baseline dumps under the post-hardening audit (anchor for v3.1).

Baseline shifts under updated audit:
| run set | pre-Task-B audit | post-Task-B audit |
|---|---|---|
| v1 (3 scenarios, in-code prompt) | 12 blocking / 27 warnings | 10 blocking / 17 warnings |
| v3 (3 scenarios, wardrobe.v3.txt) | 6 blocking / 12 warnings | 5 blocking / 1 warning |

The v3 warning drop is the audit being right rather than the prompt being better — v3 was already producing tidy period-correct output; the previous audit was conflating "didn't match canonical token-by-token" with "actually bad."

### wardrobe.v3.1 — single-sentence color tightening

`lab/prompts/wardrobe.v3.1.txt`: identical to v3 except one added sentence in the `tags` description:

> "This applies to footwear and accessories too — 'leather boots' alone is NOT enough; write 'brown leather boots'. Same for slippers, sandals, sneakers, straw hat, etc."

Motivation: every remaining v3 missingColor blocking finding (`flat sandals`, `slippers`, `leather boots`, `straw hat`) was footwear or accessories. The base COLOR RULE was phrased in terms of sweater/skirt examples and GLM was dropping colour on footwear specifically.

### v3.1 live run (4 scenarios, glm-4-6, max_tokens=2000)

| scenario | v3 (post-Task-B audit) | v3.1 | delta |
|---|---|---|---|
| modern_tokyo_mysterious_f | 2 blocking, 1 warn | **0 blocking, 0 warn** | -2 / -1 |
| victorian_zenith_f | 1 blocking, 0 warn | **0 blocking, 0 warn** | -1 / 0 |
| pax_romana_intimidating_m | 2 blocking, 0 warn | **4 blocking, 1 warn** | +2 / +1 |
| roaring_twenties_f (new) | n/a | **1 blocking, 1 warn** | new |
| **TOTAL (3 overlapping)** | **5 blocking, 1 warn** | **4 blocking, 1 warn** | -1 / 0 |
| **TOTAL (4 scenarios)** | n/a | **5 blocking, 2 warn** | n/a |

Modern Tokyo and Victorian became fully clean. Roaring Twenties (transitional era vocab — bandeau / cloche hat / mary janes / oxfords) parsed cleanly with one residual `straw hat` slip. Pax Romana regressed: GLM rolled "wool tunica", "leather belt", "leather sandals", "hooded cloak" — all missing colour. Comparing prod vs `diagnostic_raw` for pax_romana: the diagnostic single-shot was much cleaner (`burgundy tunica`, `brown cloak`, `brown sandals`, only `leather boots` uncoloured), and prod just rolled badly. GLM-4.6 non-determinism at temp 0.8 striking again.

### Promotion decision: NOT promoted

Criteria check (4 scenarios):
- ≤4 blocking findings — **5, fails by 1**
- No parse failures — **pass** (22/22 outfits returned)
- No new categories — **pass** (only missingColor + unknownTagToken)

The single-sentence prompt change moved the needle clearly on three of four scenarios but didn't survive a non-deterministic re-roll on pax_romana. Not robust enough to lock in.

### v3.2 proposal

Two options, both targeted at the pax_romana failure mode (the model dropping colour on era-specific garments and on footwear when material is in the slot):

1. **Move COLOR RULE earlier and bold it**, with explicit Roman example:
   - Reorder so "Every GARMENT tag MUST include a colour" appears BEFORE the vocabulary blocks (right after the BACKGROUND ONLY line). Currently it's buried at the bottom of the FOR EACH OUTFIT block.
   - Add a Roman-specific GOOD example next to the modern one:
     `"crimson tunica, gold sandals, ivory palla, brown leather belt, gold head wreath"`
   - Add a Roman-specific BAD example:
     `"wool tunica, leather belt, leather sandals, hooded cloak"` — followed by "every one of these needs a colour."

2. **Add a "MATERIAL IS NOT A COLOUR" line** to the COLOR VOCABULARY section:
   - "Words like `wool`, `leather`, `linen`, `silk` are MATERIALS, not COLOURS. `wool tunica` is missing a colour. Write `cream wool tunica` or `cream tunica`."
   - This catches the model substituting material for colour, which is the actual failure mode in the pax_romana run.

I'd do both as a single v3.2 since they're tiny and complementary. The MATERIAL line is the one most likely to fix the specific regression. After v3.2 ships, re-run all 4 scenarios; if blocking ≤4 and no regressions on the 3 that were clean, promote.

### Task D — batching investigation (closed)

At `LAB_MAX_TOKENS=2000` and outfit counts ≤7, `_batchSizeFor(2000) = 7`, so prod and diagnostic_raw are both single-shot calls — they only differ because of GLM non-determinism at temp 0.8. Batching question is moot at maxTokens=2000. Re-open only if the Tablet-tier (maxTokens=200, batch=2) path needs validation, which can wait until someone runs that tier.

### Files changed (this turn)

- `lab/audit.dart` — `_baseTops` expansion + `_attributeTokens` + `_eraToleratedTags` + `_canonicalSupplement` + updated unknownTagToken branch
- `lab/prompts/wardrobe.v3.1.txt` — new (footwear-color sentence)
- `test/lab/audit_test.dart` — 14 new tests covering every Task B branch
- `test/lab/reaudit_v3_runs_test.dart` — new (re-audit v3 dumps under post-Task-B audit)
- `lab/runs/*_wardrobe_wardrobe.v3.1_2026-05-17T19-*.json` — 4 v3.1 run dumps
- `docs/CHARACTER_V2_STATUS.md` — this section

## What we did this session — turn 1 (2026-05-17, lean character-gen + audit canonical check)

### Lean character-gen (the headline pivot)

- Established `lab/prompts/character.lean.v1.txt` — the lean prompt template. Output JSON shape: `{name, gender, tags:{base, face, hair, body, nsfw_top, nsfw_bottom, nsfw_always, nsfw}}`. No `soul_md` / `reaction_patterns` / `theme` / `meet_cute` / `preview_scene` / `aliases` / `personality_summary` / `character_description` / `outfit_tags`.
- Added `substituteLeanCharacterPrompt(...)` helper in `lib/features/characters/gen/character_gen_prompts.dart`.
- Lab harness wired with new env vars: `LAB_MAIN_PROMPT` (path to main prompt override), `LAB_SHAPE` (`lean`|`full`), `LAB_USER_DESCRIPTION` (free-text). Existing `LAB_PROMPT` still controls wardrobe.
- `auditCharacter()` learned a `shape` param. `CharacterShape.lean` skips soul_md/theme/etc checks, adds a clothing-smuggle check on each tag bucket, and (after canonical-tag check landed) flags unknown tags.

### Iteration loop (4 runs against 3 baseline scenarios: modern Tokyo, Victorian London, Pax Romana Ostia)

| Run | Prompt | Outcome |
|---|---|---|
| 1 | in-code encounter v1 | 3/3 truncated — soul_md too big at 2000 tokens |
| 2 | lean.v1.txt | parsed clean, 5–7s each, but GLM dropped the 4 empty NSFW keys 2/3 times |
| 3 | lean.v1.txt + `<<END>>` stop string + audit-relaxed | 3/3 clean parse, BUT tags were invented English compounds (`hooded grey eyes`, `bony shoulders`, `center part`, `oval face`, `slim`, `japanese`) — not in Danbooru |
| 4 | **lean.v2.txt** with vocabulary blocks + canonical-tag audit + auto-correction | **3/3 clean parse, ALL tags canonical Danbooru, correction pass never had to fire** |

### Key learnings

- **GLM-4.6 invents English compounds when asked for tags.** Negative rules ("don't invent") bounce off; concrete vocabulary lists stick. The v2 prompt embeds 30–60 canonical tags per bucket as an allow-list. ~6.7-8kb prompt size — well within context.
- **`<<END>>` stop string fixed GLM's looping** (it would emit the JSON, then "revise" it, then alternate names, until token cap). Critical when the response is small (~400 chars) and the cap is large (2000).
- **Auto-correction pass is insurance, not the workhorse.** Vocabulary alone got us to 0 unknown tags. The correction call (second LLM call mapping unknown→canonical) is wired and tested but didn't trigger in run 4. Keep it for future regressions.
- **Danbooru eye-shape vocabulary is sparse**: `hooded`, `monolid`, `narrow`, `almond` are all invented. Real Danbooru uses Japanese cosmetic vocab (`tsurime`/`tareme`/`jitome`/`sanpaku`) plus `upturned eyes`/`downturned eyes`/`narrowed eyes`/`half-closed eyes`. The v2 prompt teaches GLM this.
- **GLM uses nationality words by default** (`japanese`, `roman`, `british`) which Danbooru does NOT tag with. Use skin tone + features + marks. The v2 prompt forbids nationality words explicitly.
- **`mature female` is 40+** — fixed in v2 prompt by moving age-specific tags to a separate sub-section with a clear "USE ONLY when age clearly fits" caveat.
- **GLM-4.6 on `/oa/v1/completions` is non-deterministic at temperature 0.95.** Same prompt produces different outputs run-to-run. The audit must be the final word, not visual eyeballing.

### Files changed

- `lab/prompts/character.lean.v1.txt` — first lean prompt iteration
- `lab/prompts/character.lean.v2.txt` — current winning prompt
- `lab/audit.dart` — `CharacterShape` enum, lean-shape audit branch, `loadCanonicalTags()` + unknown-tag check
- `lib/features/characters/gen/character_gen_prompts.dart` — `substituteLeanCharacterPrompt(...)`
- `test/lab/character_lab_test.dart` — new env vars, lean prompt path, `<<END>>` stop string, auto-correction pass, expanded JSON run dumps
- `docs/CHARACTER_FEATURES_PLAN.md` — §4 v2 spec
- `lab/README.md` — v2-spec note for future lab runs

### Wardrobe path: still on baseline

- We did NOT touch wardrobe-gen in this session.
- Known issues from baseline runs:
  - Modern Tokyo wardrobe parse-failed entirely (0 outfits returned, two API calls both unparseable). Root cause not yet diagnosed — harness doesn't capture raw response on the wardrobe path.
  - Historical wardrobe outputs trip the same invented-tag problem as character did: `iron muscle cuirass (lorica musculata)`, `leather sole sandals` (no color), `hobnailed caligae` (no color), `light woolen tunic`. Same lever to pull: vocabulary blocks + canonical validation + correction pass.

## Next-up (in order)

### 1. Wardrobe canonical validation + correction (this is what we're doing NEXT)

Apply the lean-character pattern to wardrobe. Three sub-steps:

a. **Harness fix**: capture raw response in wardrobe runs (today `_runWardrobe` only saves the parsed outfit list — when parsing fails we have nothing to debug). Save `raw` and `prompt_actual` per call.

b. **Diagnose the modern-Tokyo parse failure**: with raw captured, re-run modern Tokyo and read what GLM actually emitted. Was it prose? Was it `{"outfits": []}` with no entries? Was it markdown-wrapped + valid? This determines whether the fix is the prompt or the parser.

c. **Wardrobe.v3.txt with vocabulary blocks**: era-aware vocabulary (modern garment terms / Victorian terms / Roman terms — see bri's `_PERIOD_CLOTHING_HINTS` at `D:\bri\app\dashboard\routes\wardrobe_routes.py:686-697`). Plus the canonical-tag check applied to each outfit's `tags` string. Plus correction pass when unknowns are found.

### 2. Promote lean v2 → in-code, swap ✨ default

- Extract `lab/prompts/character.lean.v2.txt` content into a Dart string constant in `character_gen_prompts.dart`. Add `CharacterGenPrompts.buildLeanGeneration(inputs)` mirroring the existing `buildGeneration` API.
- Add `CharacterGenService.generateAppearanceOnly(form)` — single LLM call, parse, build a `SavedCharacter` with the four base tag buckets + four NSFW slots, leave `soulMd` / `personalitySummary` / `theme` / `characterDescription` null.
- The ✨ button on the Characters list pane (`characters_page.dart`) calls `generateAppearanceOnly` by default. Add a "Generate with personality (soul_md)" entry to a More-actions menu for users who want the old flow.

### 3. Per-outfit prompt area

Per your spec: free-text input → `{name, tags}` only. No seasons/weather/activities/temperature_range/slots/primary.

- New `buildSingleOutfitPrompt({characterTags, userPrompt, eraHint})` in `wardrobe_generator_service.dart`. Same TAG SCOPE / COLOR / PATTERN-COMPOUND / CHEST-COVERAGE rules + the canonical-tag vocabulary block.
- New `WardrobeGeneratorService.generateOne(...)` returning `GeneratedOutfit?`. Parser accepts top-level `{name, tags}` directly (not wrapped in `{"outfits": [...]}`).
- UI: small "Add outfit from prompt" textarea in the Wardrobe sub-section of the character editor.

### 4. Per-character / per-outfit negative tags + NAI character scaffolding

Three additions to `SavedCharacter` / `ClosetOutfit`:

```dart
class SavedCharacter {
  // existing fields…
  final String negativeTags;     // global negatives applied whenever this character is in the prompt
  final String? naiCharacterPrefix; // optional NAI character-scaffold block (e.g. "char1, blue eyes, blonde hair, ...")
}

class ClosetOutfit {
  // existing fields…
  final String negativeTags;     // outfit-specific negatives (e.g. "topless, panties_aside")
}
```

How the autocomplete `expansion` changes:
- `[OCNAME]` → expands to `body_tags + primary_outfit_tags` (positive prompt) AND signals the UI to append `character.negativeTags + primary_outfit.negativeTags` to the negative prompt at insertion time.
- `[OCNAME (OUTFITNAME)]` → `body_tags + outfit_tags` positive; `character.negativeTags + outfit.negativeTags` negative.
- The negative-prompt injection needs a new path because `DanbooruTag.expansion` is positive-only today. Either (a) add `DanbooruTag.negativeExpansion` and have the tag-suggestion overlay write to both positive + negative controllers, or (b) make the saved-character entry insert into the positive box only and have a separate notifier hook reconcile negatives on every character-tag-in-prompt scan. Lean toward (a) — simpler.
- **NAI character scaffolding** is a positive-prompt prefix that some NAI-trained characters need (the `{name}, blue eyes, blonde hair...` block before the rest of the prompt). When present, the expansion prepends `naiCharacterPrefix + ', '`.

Editor UI: two new text fields in the character editor (`negativeTags`, `naiCharacterPrefix`) and one new field per outfit (`negativeTags`).

### 5. Sunset Text Gen sidebar tile

- The Text Gen panel at Tools Hub → Text Gen exists primarily for prompt exploration / pasted-prompt debugging. With character-gen + wardrobe + per-outfit prompt all living in the Characters tab, the standalone Text Gen page no longer serves a user-facing purpose.
- **Keep** `TextGenService` / `NaiTextService` / `TextGenNotifier` — the character pipeline depends on these.
- **Remove** the Tools Hub tile registration for Text Gen + the `text_gen_panel.dart` widget. `TextGenNotifier` stays wired into `MultiProvider` because the character pipeline still uses `.service`.
- One PR, no behavior change to character flow.

### 6. Photoshoot mode (formerly "modeling mode")

Dedicated generation mode (NOT the regular `[OCNAME]` autocomplete insertion path — that's #4 above). Pick character + outfit, the outfit-state panel is front-and-center, pick a style (artist tag set), select from preselected pose presets + environment presets, render via existing image-gen path. The outfit renderer (`outfit_renderer.dart`) already handles the state→tags translation including concealment and `nsfw` appending; what's new is the screen + the pose/environment preset library + the style selector wiring.

### 7. New "Characters" tab layout (the user-facing shell that ties all this together)

A single Characters tab containing:
- **List pane** — saved characters, search, ＋ new, ✨ generate.
- **Editor pane** — name, gender, the four appearance buckets (base/face/hair/body) + NSFW buckets, **character-level positive prompt** field, **character-level negative prompt** field, optional `naiCharacterPrefix`, theme color (optional), notes.
- **Wardrobe sub-section** — outfit grid (cards with name + tags chip + primary star + edit/delete/wear). Per outfit: per-bucket tags (top/bottom/outer/footwear/accessories/nsfw_top/nsfw_bottom) + per-outfit negative-tag field + ＋ new outfit (manual or "Add outfit from prompt" #3) + ✨ Generate wardrobe.
- **Photoshoot button** (#6) — opens the dedicated modeling-mode screen for the currently-selected character+outfit.

When saved, each character → tag library entry `[OCNAME]` (= character + primary outfit). Each closet outfit → tag library entry `[OCNAME (OUTFITNAME)]`. Both with positive AND negative expansions. Routing per §"Negative-tag injection — context-aware routing" above.

## Decisions locked in (2026-05-17 turn 2)

### Negative-tag injection — context-aware routing

The saved-character autocomplete entry carries BOTH a positive expansion and a negative expansion. The routing depends on which prompt controller the tag is being inserted into:

- If inserted **inside the character editor's per-character prompt field**: the negatives go to that character's **per-character** negative prompt field (NOT the global one).
- If inserted **in the general / global prompt**: the negatives go to the **global** negative prompt controller.
- Implementation: `DanbooruTag` gains a `negativeExpansion` field. The autocomplete-overlay tag-insertion path takes a "scope" (`character` | `general`) and writes negatives to the matching negative controller.

### NAI character scaffolding — structured per-bucket, rendered to single string

Per-bucket fields exist at TWO layers:

**Character-level fields** (live on `SavedCharacter`):
- `tags.base`, `tags.face`, `tags.hair`, `tags.body` — appearance tags (already on SavedCharacter)
- `tags.nsfwTop`, `tags.nsfwBottom`, `tags.nsfwAlways` — NSFW slots (already on SavedCharacter)
- NEW: `negativeTags` — character-wide negatives (always applied when character is referenced)
- NEW: `naiCharacterPrefix` — OPTIONAL NAI-trained character prefix (rare; mostly for users who have specific trained characters they want to scaffold)

**Outfit-level fields** (live on `ClosetOutfit`):
- `tags` — clothing tags (already on ClosetOutfit, single string today; **change to per-bucket** to mirror character)
  - NEW shape: `outfitTags.top`, `outfitTags.bottom`, `outfitTags.outer`, `outfitTags.footwear`, `outfitTags.accessories`, `outfitTags.nsfwTop`, `outfitTags.nsfwBottom`
  - Rationale: outfit-state tracking (modeling mode) needs to know which tag is which slot; today this is reconstructed by the classifier. Storing structured is simpler.
- NEW: `negativeTags` — outfit-specific negatives (e.g. for a "wet shirt" outfit you might want `dry` as a negative)

When the autocomplete inserts `[OCNAME]`, the rendered expansion is a single comma-joined string: `<character.base + face + hair + body>, <primary_outfit's flat tags>`. Same for `[OCNAME (OUTFITNAME)]` with a specific outfit.

### Audit fixes (from wardrobe diagnostic findings)

- **`missingColor` is over-strict.** Today it flags ANY tag without a color word. But Danbooru has plenty of legitimate attribute-only tags (`long sleeves`, `high collar`, `lace trim`, `scoop neck`, `short sleeves`, `ribbon trim`, `hooded`, `floor-length`, `ankle-high`). These don't need colors — they describe garment attributes. Fix: only require color on tags that match a known **garment word list** (shirt, dress, skirt, pants, jacket, coat, boots, shoes, sweater, etc.). Attribute-only tags pass through.
- **Drop `tan` and `chestnut` from the colors set.** They cause hair/skin drift in NAI image gen — when the model sees "tan" it doesn't know if you mean a skin tone, a coat color, or pants. Same with "chestnut" for hair vs. leather. Use specific replacements (`brown`, `beige`, `khaki`).
- **`forbiddenMaterial` → soft warning, not blocking.** NAI 4.5 uses a Flux text decoder which handles non-Danbooru material words (`linen`, `silk`, `velvet`, `corduroy`) reasonably. Keep as informational so we know the prompt drift exists, but don't treat as a finding.
- **Canonical-tag check for wardrobe outfit tags.** Tokenized: split each tag on whitespace, validate each word against the canonical list (skipping recognized colors). E.g., `cream knit sweater` → `cream` (color, skip), `knit sweater` (canonical), passes. `iron muscle cuirass (lorica musculata)` → `iron`, `muscle`, `cuirass`, `(lorica musculata)` → fails the parenthetical, flag.

### Pax Romana wardrobe — keep the period-prose tags

Pax Romana baseline output (`ivory linen tunic`, `cream silk chemise`, `terracotta leather sandals`) reads as Danbooru drift but NAI 4.5's Flux decoder handles these material words. **Don't fight them.** Demote `forbiddenMaterial` to a warning per above.

### Photoshoot mode (new — was "modeling mode") + outfit-state toggle in regular gen

Outfit state respect is a **toggle, not a separate code path**. Two surfaces use the same underlying rendering:

1. **Regular generation** — when `[OCNAME (OUTFITNAME)]` is inserted, the user can toggle "Honor outfit state" (on by default). With it on: expansion routes through `outfit_renderer.renderItemsToTags()` using the outfit's current saved state (intact by default), plus the dishevelled `nsfw` append. With it off: expansion is the flat tag string.

2. **Photoshoot mode** — a dedicated screen. Pick character + outfit. The outfit-state panel is front-and-centre and editable in-place (cycle each slot's state — intact, unbuttoned, open, lifted, pulled_down, aside, around_ankles, removed — the panel already exists in `outfit_state_panel.dart`). Select style (artist tag set), pose preset, environment preset. Renders the image prompt as `<style> + <character body tags> + <outfit rendered via outfit_renderer at current states> + <pose preset> + <environment preset>`, `nsfw` appended if dishevelled. Generates via existing image-gen path.

What's already there (reuse): `outfit/outfit_classifier.dart`, `outfit/outfit_renderer.dart`, `outfit/outfit_delta.dart`, `widgets/outfit_state_panel.dart`. What's NEW: pose/environment preset libraries, style selector wiring, the toggle in the autocomplete-expansion path, the photoshoot screen.

## Investigations to do later (don't act on now)

- **Batching vs single-shot accuracy.** In the 2026-05-17 wardrobe diagnostic, the single-shot 5-outfit call produced noticeably tidier output than the batched (5×1) prod-pipeline call on the same Victorian prompt. bri batches the same way we do, so this may just be a one-off. Plan: in a future session, run BOTH paths against the 3 baseline scenarios with stable seeds/temperatures and compare audit tallies. Could simplify `_batchSizeFor` if the difference holds.

## Remaining open questions (defer)

- **Migration**: `ClosetOutfit.tags` is a single string today. Moving to per-bucket structure breaks existing on-disk data. Either ship a migration (parse the single string using the existing `outfit_classifier.dart` → write back per-bucket) or keep a `tags` denormalized field and add the per-bucket fields side-by-side. Decide when implementing.

## Reference

- `Tags/high-frequency-tags-list.json` — 41,756 canonical Danbooru tags shipped with the app
- `D:\bri\app\dashboard\routes\wardrobe_routes.py:686-697` — `_PERIOD_CLOTHING_HINTS` (era vocabulary, not yet ported)
- `D:\bri\app\dashboard\routes\wardrobe_routes.py:732-743` — `_PERIOD_UNDERWEAR_HINTS` (per-era underwear, not yet ported)
- `D:\bri\app\dashboard\routes\wardrobe_routes.py:703-714` — `_PERIOD_GOOD_EXAMPLES` (per-era GOOD/BAD pairs, not yet ported)
