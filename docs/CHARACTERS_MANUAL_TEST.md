# Characters module — manual test checklist

The Characters module lives in **Tools Hub → Characters**. It has no LLM
dependency for Phase A; Phase B's "✨ Generate outfits" needs a NovelAI text
token (set one in **Tools Hub → Text Gen** settings).

## Phase A — characters, wardrobe, outfit state

1. **Create a character**
   - Open Tools Hub → Characters → click **＋** (top-right of the list pane).
   - A new "New Character" appears and opens in the editor. Rename it (e.g. `Yuki`).
   - Set the four identity tag buckets:
     - `base`: `1girl, japanese`
     - `face`: `blue eyes`
     - `hair`: `long black hair`
     - `body`: `slender`
   - There should be a **"no clothing here"** style hint near the buckets.
   - Click the disk icon (or press Enter in the name field) to save.
   - Optionally: expand **NSFW sub-buckets** and **Style identity & description**;
     set an `artist tag` / `style prefix`; pick a **TINT** swatch (long-press a
     swatch to clear it).

2. **Add an outfit manually**
   - In the **WARDROBE** section click **NEW OUTFIT**.
   - Name: `Rainy Day Chic`. Tags: `yellow raincoat, white shirt, blue jeans, rubber boots`.
   - Pick a couple of season/weather/activity chips, drag the temperature range,
     pick a time slot. Tick **"Set as primary outfit"**. Save.
   - The outfit card appears with a filled ★, the rendered-tag preview, and the
     season/weather chips.

3. **Combined tags preview**
   - The **COMBINED TAGS** box under the editor should now read roughly:
     `1girl, japanese, blue eyes, long black hair, slender, yellow raincoat, white shirt, blue jeans, rubber boots`
     (clothing run through concealment; an intact raincoat over the shirt is fine).

4. **Autocomplete in the main prompt**
   - Go back to the generator. In the **positive prompt** box type `yuk`.
   - The suggestion dropdown should show (green-tinted) entries:
     `Yuki` and `Yuki (Rainy Day Chic)`, ranked above ordinary danbooru tags.
   - Pick `Yuki (Rainy Day Chic)` → the expanded tag block is inserted at the
     cursor (body tags + outfit tags through concealment), followed by `, `.
   - Repeat in a per-character caption (add a character in the multi-char shelf,
     open its prompt field, type the name) → same entry appears and inserts.
   - Repeat in **Tools Hub → Presets** (prompt field) and **Styles** (content
     field) and **Cascade → Director** (a beat prompt field) — entries appear
     there too.

5. **Outfit State mode**
   - Back in the Characters editor, click **STATE** on the `Rainy Day Chic` card.
     A panel appears below the wardrobe with one row per parsed slot.
   - Change `outerwear` (the raincoat) → `removed`. The **→ RENDERED TAGS**
     readout drops the raincoat (raincoat removal renders nothing) and the white
     shirt becomes visible. No `nsfw` yet (only outerwear changed).
   - Change `top` (the white shirt) → `unbuttoned`. The readout now shows
     `… unbuttoned shirt, partially unbuttoned …`, and a red **DISHEVELLED**
     badge appears.
   - Click **APPLY TO PROMPT** → the rendered string (+ `nsfw`) is inserted into
     the current generation prompt at the cursor; a snackbar confirms.
   - Click **RESET** → everything returns to intact, badge disappears.
   - Edit the outfit's tags (via **EDIT**), then click **RE-PARSE** on the state
     panel → the slot rows rebuild from the new tags.
   - Underwear concealment: add `white cotton bra, white cotton panties` to the
     outfit tags, re-parse → the bra/panties rows show `(concealed)` and are
     read-only while the shirt/jeans are intact. Set `top` → `removed` → the bra
     row stops being concealed; the readout shows the bra (no `topless` because
     the bra provides coverage).

6. **Persistence**
   - Restart the app. The character, its wardrobe, the primary star, and any
     outfit-state you left set on an outfit should all still be there
     (`<appSupport>/characters/{id}.json` and `.../characters/{id}/closet.json`).

7. **Delete**
   - Delete an outfit (trash icon on the card) — if it was primary the star
     pointer clears. Delete the character (trash icon in the editor header) — its
     closet directory is removed too.

## Phase B — wardrobe generation (needs a text token)

8. With a NovelAI `pst-` token set in Text Gen settings:
   - In the Characters editor's WARDROBE section the **✨ GENERATE OUTFITS**
     button is enabled (it's disabled with a "requires text generation" tooltip
     otherwise).
   - Click it → a dialog asks how many outfits (default 6) plus optional
     era/setting and vibe hints.
   - On a low-tier (Tablet) token the service auto-batches 2 outfits per call;
     on Scroll/Opus it does up to 7 at once. Either way a spinner shows and a
     snackbar reports `ADDED N OUTFIT(S)` on success.
   - The new outfits appear in the wardrobe grid; review and delete any you don't
     like. If exactly one came back flagged `primary`, it's set as the primary
     outfit (only when the character had none).
   - Sanity-check a couple: every garment should have a color tag, 4–7 garments,
     one outer layer, no body/pose/weather tags.
   - Restart → the generated outfits persist.

## Regression checks

- Image generation still works (the autocomplete change only adds entries to the
  suggestion list; picking a normal tag still behaves exactly as before).
- The multi-character scene shelf still works — saved characters are a separate
  library that feeds the prompt via autocomplete, not a replacement for scene
  slots.
- `flutter analyze` clean, `flutter test` green.
