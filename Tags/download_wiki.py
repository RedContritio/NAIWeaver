"""Download isek-ai/danbooru-wiki-2024 Parquet snapshot.

Saves to Tags/_wiki_raw/ for downstream preprocessing.
"""

from pathlib import Path
import sys
import urllib.request

SCRIPT_DIR = Path(__file__).parent
OUT_DIR = SCRIPT_DIR / "_wiki_raw"
OUT_DIR.mkdir(exist_ok=True)

# Single-file Parquet on HF
URL = "https://huggingface.co/datasets/isek-ai/danbooru-wiki-2024/resolve/main/data/train-00000-of-00001.parquet"
OUT_FILE = OUT_DIR / "danbooru-wiki-2024.parquet"


def main():
    if OUT_FILE.exists():
        size_mb = OUT_FILE.stat().st_size / 1024 / 1024
        print(f"Already downloaded ({size_mb:.1f} MB): {OUT_FILE}")
        return

    print(f"Downloading {URL}")
    print(f"  -> {OUT_FILE}")

    def _hook(block, block_size, total_size):
        if total_size <= 0:
            return
        pct = min(100, block * block_size * 100 / total_size)
        sys.stdout.write(f"\r  {pct:5.1f}%")
        sys.stdout.flush()

    urllib.request.urlretrieve(URL, OUT_FILE, _hook)
    print()

    size_mb = OUT_FILE.stat().st_size / 1024 / 1024
    print(f"Done. {size_mb:.1f} MB")


if __name__ == "__main__":
    main()
