"""Build the wiki-descriptions.json asset shipped with the app.

Reads the danbooru-wiki-2024 Parquet, joins to the existing tag library by
slug, drops noise (deleted, very short bodies), converts DText -> markdown,
and writes a single compact JSON file consumed by WikiService at runtime.

Output schema (one row per tag with a wiki entry):
[
  {
    "t": "1girl",                      // tag name (spaces, matches library)
    "d": "<markdown body>",
    "n": ["女の子", "女性", "少女"]    // other_names (japanese/aliases), <=8
  },
  ...
]

Keys are short to save bytes — this file ships in the app bundle.
"""

from __future__ import annotations

import json
from pathlib import Path

import pandas as pd

from dtext_to_markdown import convert

SCRIPT_DIR = Path(__file__).parent
PARQUET_PATH = SCRIPT_DIR / "_wiki_raw" / "danbooru-wiki-2024.parquet"
TAGS_PATH = SCRIPT_DIR / "high-frequency-tags-list.json"
OUTPUT_PATH = SCRIPT_DIR / "wiki-descriptions.json"

MIN_BODY_CHARS = 20
MAX_OTHER_NAMES = 8

# Note: meta wiki pages (tag_group:*, help:*, howto:*) are NOT in the HF
# danbooru-wiki-2024 dataset (it filters to tags used 100+ times). Wiki links
# to them resolve via the browser-fallback path in TagDetailSheet instead.


def main() -> None:
    print("Loading tag library...")
    with open(TAGS_PATH, encoding="utf-8") as f:
        library = json.load(f)
    # Slug = name with spaces -> underscores; this is what the wiki dataset uses.
    library_slugs = {t["tag"].replace(" ", "_"): t["tag"] for t in library}
    print(f"  {len(library_slugs):,} library tags")

    print("Loading wiki Parquet...")
    df = pd.read_parquet(PARQUET_PATH)
    print(f"  {len(df):,} wiki rows")

    # Filter: not deleted, body has substance, in our library
    print("Filtering...")
    before = len(df)
    df = df[~df["is_deleted"]]
    df = df[df["body"].str.len() >= MIN_BODY_CHARS]
    df = df[df["title"].isin(library_slugs.keys())]
    print(f"  {len(df):,} rows after filter (dropped {before - len(df):,})")

    # If a tag has multiple wiki entries (rare — but the data has duplicates),
    # keep the most recently updated.
    if df["title"].duplicated().any():
        dup_count = int(df["title"].duplicated().sum())
        print(f"  collapsing {dup_count} duplicate titles -> keep newest")
        df = df.sort_values("updated_at").drop_duplicates(subset=["title"], keep="last")

    print("Converting DText -> markdown...")
    out: list[dict] = []
    failures = 0
    for _, row in df.iterrows():
        try:
            md = convert(row["body"])
        except Exception as e:  # noqa: BLE001
            failures += 1
            print(f"  convert failed for {row['title']}: {e}")
            continue
        if not md or len(md) < MIN_BODY_CHARS:
            continue

        other = list(row["other_names"]) if row["other_names"] is not None else []
        # Strip empties, dedupe (preserve order), cap
        seen = set()
        clean_other: list[str] = []
        for n in other:
            n = (n or "").strip()
            if not n or n in seen:
                continue
            seen.add(n)
            clean_other.append(n)
            if len(clean_other) >= MAX_OTHER_NAMES:
                break

        out.append({
            "t": library_slugs[row["title"]],  # use library spelling (spaces)
            "d": md,
            "n": clean_other,
        })

    if failures:
        print(f"  {failures} conversion failures")

    # Sort by tag name for stable diffs and (mildly) better gzip
    out.sort(key=lambda r: r["t"])

    print(f"Writing {OUTPUT_PATH} ({len(out):,} entries)...")
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))

    size_mb = OUTPUT_PATH.stat().st_size / 1024 / 1024
    print(f"Done. {size_mb:.1f} MB")

    # Stats
    body_lens = [len(r["d"]) for r in out]
    print()
    print(f"Coverage: {len(out):,} / {len(library_slugs):,} library tags ({100*len(out)/len(library_slugs):.1f}%)")
    print(f"Body length: min={min(body_lens)}, median={sorted(body_lens)[len(body_lens)//2]}, max={max(body_lens)}")


if __name__ == "__main__":
    main()
