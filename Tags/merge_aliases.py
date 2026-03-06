"""Merge alias data from danbooru CSV into high-frequency-tags-list.json."""

import csv
import json
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
JSON_PATH = SCRIPT_DIR / "high-frequency-tags-list.json"
CSV_PATH = SCRIPT_DIR / "danbooru_tags(1).csv"


def main():
    # 1. Read CSV and build alias lookup: normalized_tag -> list of aliases
    alias_lookup: dict[str, list[str]] = {}
    csv_count = 0
    with open(CSV_PATH, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            csv_count += 1
            tag = row["tag"].strip()
            raw_aliases = row.get("alias", "").strip()
            if raw_aliases:
                alias_lookup[tag] = [a.strip() for a in raw_aliases.split(",") if a.strip()]
            else:
                alias_lookup[tag] = []

    print(f"CSV tags loaded: {csv_count}")
    print(f"CSV tags with aliases: {sum(1 for v in alias_lookup.values() if v)}")

    # 2. Read JSON
    with open(JSON_PATH, "r", encoding="utf-8") as f:
        tags = json.load(f)

    print(f"JSON tags loaded: {len(tags)}")

    # 3. Merge: for each JSON tag, look up aliases by normalizing spaces to underscores
    matched = 0
    with_aliases = 0
    for tag_obj in tags:
        key = tag_obj["tag"].replace(" ", "_")
        if key in alias_lookup:
            matched += 1
            aliases = alias_lookup[key]
            tag_obj["aliases"] = aliases
            if aliases:
                with_aliases += 1
        else:
            tag_obj["aliases"] = []

    # 4. Write JSON back (compact, preserving Unicode)
    with open(JSON_PATH, "w", encoding="utf-8") as f:
        json.dump(tags, f, ensure_ascii=False, separators=(",", ":"))

    # 5. Print summary
    unmatched = len(tags) - matched
    print(f"\nResults:")
    print(f"  Matched (JSON tag found in CSV): {matched}")
    print(f"  With aliases:                    {with_aliases}")
    print(f"  Unmatched (no CSV entry):        {unmatched}")


if __name__ == "__main__":
    main()
