# Character Generation — manual test checklist

The character generator (Tools → Characters → ✨ Generate) builds a complete
`SavedCharacter` — name, Danbooru appearance tags, a long-form `soul_md`
personality doc, theme colours, and a starter wardrobe — from a small form, by
making several `TextGenService` calls. It is an orchestrator over the text-gen
backend (PROMPT 1) and the Characters module + wardrobe generator (PROMPT 2).

Run through this with a real NovelAI `pst-` token set (Settings → API key). The
"✨ Generate" button in the Characters list pane is disabled (greyed) until a
token is present.

## Happy path — modern character

1. Tools → Characters → click **✨** next to **+**.
2. Form: Vibe = **Mysterious**, Gender = **Female**, Era = **Present Day**,
   Location = `Lisbon`, NSFW off, Image style = **Anime**, Wardrobe = **5**.
3. Click **✨ GENERATE**. The progress dialog shows the steps:
   _Preparing… → Creating character… → Completing fields… → Generating
   wardrobe (n/5)… → Saving…_, then closes.
4. Expect:
   - A new character is selected in the editor; a "CHARACTER GENERATED" snackbar.
   - `base/face/hair/body` tag fields are filled with sane Danbooru tags
     (`1girl`, an ethnicity, `20yo` or similar, eye/hair/body tags), **no
     clothing** in them.
   - The "Personality / soul" expander has a one-sentence summary at the top
     and a 600–1000-word second-person "You are…" doc that reads like a real
     person, not a wiki entry — has a turning point, speech-style notes (not
     catchphrases), behavioural rules.
   - The character card swatch picks up a theme accent colour.
   - The wardrobe has a **Meet Outfit** (primary ⭐) plus ~5 more outfits with
     colour-tagged Danbooru clothing.
5. Type the character's name in the main positive prompt → it appears in the
   autocomplete with `[Name]` and `[Name (Meet Outfit)]` etc. → pick one → the
   expanded body + outfit tags are inserted.
6. Restart the app → the character + its wardrobe persist (loaded from
   `<appSupport>/characters/{id}.json` + `{id}/closet.json`).

## Historical character — knowledge boundary

1. **✨** → Vibe = **Traditional**, Gender = **Male**, Era = **(any medieval
   one — e.g. The Black Death Arrives / Third Crusade Aftermath)**,
   Location = `a monastery`, Wardrobe = **5**.
2. Generate. Expect:
   - The `soul_md` includes a KNOWLEDGE BOUNDARY paragraph with 5–8 specific
     post-era concepts the character has never heard of.
   - Appearance/outfit tags are period-appropriate (robes, tunic, etc.) — **no
     modern bra/panties tags** in the wardrobe outfits (the wardrobe generator's
     era base-layer rule fires when the era hint is non-modern).
   - Occupation fits the era.

## Custom & addicted vibes

- Vibe = **Custom** → the form requires the free-text "describe the vibe" field
  before **✨ GENERATE** enables; the text is injected as `VIBE -- CUSTOM: …`.
- Vibe = **Addicted** → an optional "addiction subject" field appears; leaving
  it blank lets the model pick; filling it (e.g. `gambling`) is reflected in the
  generated soul.

## Free / Tablet tier (max_length ≈ 150)

- On a low-tier token, the soul_md will NOT come back in one call. Verify the
  progress dialog shows _Completing fields… — extending personality (1), (2)…_:
  the chunked-continuation loop fires and stitches a **complete** soul_md (ends
  on sentence-final punctuation), not a 150-token stub. The wardrobe step also
  batches (2–3 outfits per call).

## Error / cancel paths

- No token set → the **✨** button is disabled; tooltip explains why.
- Bad token (401) → generation fails with a clear error snackbar, no character
  saved, no half-written files.
- **Cancel** mid-run (the progress dialog's CANCEL button) → the run aborts;
  the dialog closes; no character is saved (nothing is written to disk until the
  final "Saving…" step). A subsequent generation works normally.
- The wardrobe step failing (e.g. the model returns garbage for outfits) is
  non-fatal — the character still saves with just the Meet Outfit.

## Notes

- `aliases`, `reaction_patterns`, `preview_scene` and `meet_cute` from the LLM
  response are stashed in the character's `notes` field (the model only persists
  `soul_md`, the tags, the description, the summary and the theme as first-class
  fields).
- Step 5 from the original spec (auto-generating a preview portrait via the
  image-gen path) is **not implemented** — TODO. Generate a preview manually
  via the normal image-gen flow if you want one.
