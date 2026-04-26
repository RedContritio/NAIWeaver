"""DText -> simplified Markdown converter for Danbooru wiki bodies.

DText is Danbooru's house markup ("BBCode + MediaWiki + Markdown + HTML").
We target ~90% fidelity: prose, headers, lists, links, formatting. Tables and
embeds degrade. Output is consumed by flutter_markdown on-device, with a custom
inline element [[wiki_link]] preserved verbatim so the Flutter side can detect
it and make it tappable.

Spec references:
- https://donmai.moe/wiki_pages/help:dtext
- https://github.com/danbooru/dtext_rb (official Ruby parser)

Design decisions:
- We keep [[wiki_link]] and [[wiki_link|alt]] as-is; flutter_markdown will get
  a custom inline syntax to render them as tappable spans.
- post #N / pixiv #N etc. become plain text (no useful target inside the app).
- Tables, [expand], image embeds (!post #N) are stripped to a plain note.
- We collapse \r\n -> \n early.
"""

from __future__ import annotations

import re


# --- Block-level patterns ------------------------------------------------

# h4. Header  -> #### Header
# h4#anchor.  -> ####
_RE_HEADER = re.compile(r"^h([4-6])(?:#[A-Za-z0-9_\-]+)?\.\s*(.+)$", re.MULTILINE)

# [hr] (alone on a line)
_RE_HR = re.compile(r"^\s*\[hr\]\s*$", re.MULTILINE | re.IGNORECASE)

# [quote]...[/quote] -> blockquote (line-prefixed)
_RE_QUOTE = re.compile(r"\[quote\](.*?)\[/quote\]", re.DOTALL | re.IGNORECASE)

# [expand]...[/expand]   or   [expand=Title]...[/expand]   -> "Title:\n..." in italics
_RE_EXPAND = re.compile(
    r"\[expand(?:=([^\]]+))?\](.*?)\[/expand\]", re.DOTALL | re.IGNORECASE
)

# [code]...[/code]  /  [nodtext]...[/nodtext] -> fenced code block / verbatim
_RE_CODE = re.compile(r"\[code\](.*?)\[/code\]", re.DOTALL | re.IGNORECASE)
_RE_NODTEXT = re.compile(r"\[nodtext\](.*?)\[/nodtext\]", re.DOTALL | re.IGNORECASE)

# [table]...[/table] -> stripped (replaced with placeholder)
_RE_TABLE = re.compile(r"\[table\].*?\[/table\]", re.DOTALL | re.IGNORECASE)

# Image embeds: !post #1234   or   !post #1234: caption
# Match anywhere (popular at line start, but also after "* " list markers).
_RE_POST_EMBED = re.compile(r"!post\s+#(\d+)(?::\s*([^\n]+))?", re.IGNORECASE)

# --- Inline patterns -----------------------------------------------------

# [b]...[/b], [i]...[/i], [u]...[/u], [s]...[/s]
_RE_B = re.compile(r"\[b\](.*?)\[/b\]", re.DOTALL | re.IGNORECASE)
_RE_I = re.compile(r"\[i\](.*?)\[/i\]", re.DOTALL | re.IGNORECASE)
_RE_U = re.compile(r"\[u\](.*?)\[/u\]", re.DOTALL | re.IGNORECASE)
_RE_S = re.compile(r"\[s\](.*?)\[/s\]", re.DOTALL | re.IGNORECASE)

# [tn]...[/tn] (translator's note) -> just italics
_RE_TN = re.compile(r"\[tn\](.*?)\[/tn\]", re.DOTALL | re.IGNORECASE)

# [spoilers]...[/spoilers] (or [spoiler]) -> render as plain (markdown has no spoiler)
_RE_SPOILER = re.compile(r"\[spoilers?\](.*?)\[/spoilers?\]", re.DOTALL | re.IGNORECASE)

# {{tag1 tag2}} or {{tag1 tag2|alt}} -> alt text (or joined tags) as plain text
_RE_TAGSEARCH = re.compile(r"\{\{([^}|]+?)(?:\|([^}]*))?\}\}")

# BBCode-style "text":url   -> [text](url)
_RE_BBLINK = re.compile(r'"([^"]+?)":(https?://\S+)')

# post #N, pixiv #N, twitter #N, topic #N, pool #N, wiki #N, forum #N, comment #N, user #N, @username
_RE_REF = re.compile(
    r"\b(post|pixiv|twitter|topic|pool|wiki|forum|comment|user|appeal|flag|note|ban|artist|ai)\s+#(\d+)\b",
    re.IGNORECASE,
)
_RE_AT_USER = re.compile(r"(?<![A-Za-z0-9_])@([A-Za-z0-9_]+)")

# [br] -> hard break
_RE_BR = re.compile(r"\[br\]", re.IGNORECASE)

# Lists: lines starting with * (one or more) and a space
_RE_LIST_LINE = re.compile(r"^(\*+)\s+(.*)$")

# Wiki link [[target]] / [[target|text]] / [[target#section]] / [[target#section|text]]
# We deliberately keep this in a custom syntax so flutter_markdown can render
# them as tappable spans. Output: [[target|text]] always.
_RE_WIKILINK = re.compile(r"\[\[([^\[\]|#]+?)(?:#[^\[\]|]+)?(?:\|([^\[\]]*))?\]\]")

# Strip remaining unknown bbcode-style tags as last resort.
# Only matches lowercase BBCode-shaped tags like [foo], [foo=bar], [/foo].
# Deliberately conservative so we don't eat markdown link text like [Pixiv](url).
_KNOWN_BBCODE_NAMES = (
    "color|size|font|center|left|right|justify|sub|sup|small|big|h1|h2|h3|h4|h5|h6|"
    "list|li|ol|ul|dl|dt|dd|img|video|audio|url|email|youtube"
)
_RE_UNKNOWN_TAG = re.compile(
    rf"\[/?({_KNOWN_BBCODE_NAMES})(?:=[^\]]*)?\]", re.IGNORECASE
)


def _convert_lists(text: str) -> str:
    """Convert DText * lists to markdown - lists, with proper nesting."""
    out_lines: list[str] = []
    for line in text.split("\n"):
        m = _RE_LIST_LINE.match(line)
        if m:
            depth = len(m.group(1)) - 1  # * = depth 0
            indent = "  " * depth
            out_lines.append(f"{indent}- {m.group(2)}")
        else:
            out_lines.append(line)
    return "\n".join(out_lines)


def _convert_quote(match: re.Match[str]) -> str:
    inner = match.group(1).strip()
    # Prefix each line with "> "
    return "\n" + "\n".join("> " + ln for ln in inner.split("\n")) + "\n"


def _convert_expand(match: re.Match[str]) -> str:
    title = (match.group(1) or "Details").strip()
    inner = match.group(2).strip()
    return f"\n**{title}:**\n{inner}\n"


def _convert_code(match: re.Match[str]) -> str:
    inner = match.group(1)
    if "\n" in inner:
        return f"\n```\n{inner.strip()}\n```\n"
    return f"`{inner}`"


def _convert_post_embed(match: re.Match[str]) -> str:
    post_id = match.group(1)
    caption = match.group(2)
    if caption:
        return f"_(post #{post_id}: {caption.strip()})_"
    return f"_(post #{post_id})_"


def _convert_ref(match: re.Match[str]) -> str:
    kind = match.group(1).lower()
    num = match.group(2)
    return f"{kind} #{num}"  # plain text, no link


def _convert_wikilink(match: re.Match[str]) -> str:
    target = match.group(1).strip()
    raw_label = (match.group(2) or "").strip()
    # Normalize target: lowercase, underscores -> spaces (matches our tag library)
    norm = target.lower().replace("_", " ")
    # If no label given, display = normalized target. Otherwise use the supplied label.
    label = raw_label or norm
    # Custom syntax: [[norm|label]] — preserved for flutter_markdown to detect
    return f"[[{norm}|{label}]]"


def convert(dtext: str) -> str:
    """Convert a DText body to simplified markdown."""
    if not dtext:
        return ""

    text = dtext.replace("\r\n", "\n").replace("\r", "\n")

    # Strip tables entirely
    text = _RE_TABLE.sub("_(table omitted)_", text)

    # Block constructs first (before inline)
    text = _RE_CODE.sub(_convert_code, text)
    text = _RE_NODTEXT.sub(lambda m: m.group(1), text)
    text = _RE_QUOTE.sub(_convert_quote, text)
    text = _RE_EXPAND.sub(_convert_expand, text)

    # Headers (h4. -> ####, h5. -> #####, h6. -> ######)
    text = _RE_HEADER.sub(lambda m: ("#" * (int(m.group(1)))) + " " + m.group(2).strip(), text)

    # HR
    text = _RE_HR.sub("\n---\n", text)

    # Image embeds
    text = _RE_POST_EMBED.sub(_convert_post_embed, text)

    # Inline formatting
    text = _RE_B.sub(r"**\1**", text)
    text = _RE_I.sub(r"*\1*", text)
    text = _RE_U.sub(r"*\1*", text)  # markdown has no underline; render italic
    text = _RE_S.sub(r"~~\1~~", text)
    text = _RE_TN.sub(r"*\1*", text)
    text = _RE_SPOILER.sub(r"||\1||", text)  # custom marker; flutter renders as italic/dim

    # Tag searches: drop the search syntax, keep alt or joined names
    def _ts(m: re.Match[str]) -> str:
        alt = m.group(2)
        if alt:
            return alt.strip()
        return m.group(1).replace("_", " ").strip()
    text = _RE_TAGSEARCH.sub(_ts, text)

    # BBCode links
    text = _RE_BBLINK.sub(r"[\1](\2)", text)

    # References (post #N etc.) -> plain text
    text = _RE_REF.sub(_convert_ref, text)

    # Wiki links last (they may sit inside other constructs but are pure inline)
    text = _RE_WIKILINK.sub(_convert_wikilink, text)

    # Lists
    text = _convert_lists(text)

    # [br] -> two-space hard break
    text = _RE_BR.sub("  \n", text)

    # Strip unknown bbcode-style leftover tags
    text = _RE_UNKNOWN_TAG.sub("", text)

    # Collapse 3+ blank lines
    text = re.sub(r"\n{3,}", "\n\n", text)

    return text.strip()


# --- Smoke tests ---------------------------------------------------------

_TESTS: list[tuple[str, str]] = [
    # bold + italic
    ("[b]hello[/b] [i]world[/i]", "**hello** *world*"),
    # header + list
    ("h4. Title\n\n* one\n* two", "#### Title\n\n- one\n- two"),
    # nested list
    ("* a\n** b\n*** c", "- a\n  - b\n    - c"),
    # wiki link plain + with alt
    ("see [[long_hair]] and [[short hair|short]]", "see [[long hair|long hair]] and [[short hair|short]]"),
    # wiki link with section
    ("[[tag#section]]", "[[tag|tag]]"),
    # bbcode link
    ('see "Pixiv":https://pixiv.net for more', "see [Pixiv](https://pixiv.net) for more"),
    # post ref
    ("(post #1234)", "(post #1234)"),
    # quote
    ("[quote]hi\nthere[/quote]", "> hi\n> there"),
    # expand
    ("[expand=Note]secret[/expand]", "**Note:**\nsecret"),
    # tag search with alt
    ("{{1girl solo|two girls}}", "two girls"),
    # tag search no alt
    ("{{1girl solo}}", "1girl solo"),
    # spoiler
    ("[spoilers]boo[/spoilers]", "||boo||"),
    # post embed
    ("!post #999", "_(post #999)_"),
    # post embed with caption
    ("!post #999: a cat", "_(post #999: a cat)_"),
    # hr
    ("a\n[hr]\nb", "a\n\n---\n\nb"),
]


def _run_tests() -> None:
    passed = 0
    failed: list[tuple[str, str, str]] = []
    for dtext, expected in _TESTS:
        got = convert(dtext)
        if got == expected:
            passed += 1
        else:
            failed.append((dtext, expected, got))

    print(f"{passed}/{len(_TESTS)} converter tests passed")
    for dtext, expected, got in failed:
        print(f"\n  INPUT:    {dtext!r}")
        print(f"  EXPECTED: {expected!r}")
        print(f"  GOT:      {got!r}")

    if failed:
        raise SystemExit(1)


def _real_world() -> None:
    """Render the popular-tag samples to eyeball quality."""
    from pathlib import Path
    import pandas as pd

    df = pd.read_parquet(Path(__file__).parent / "_wiki_raw" / "danbooru-wiki-2024.parquet")
    for tag in ["1girl", "solo", "smile", "long_hair"]:
        sub = df[df["title"] == tag]
        if not len(sub):
            continue
        print(f"\n{'='*60}\n{tag}\n{'='*60}")
        print(convert(sub.iloc[0]["body"]))


if __name__ == "__main__":
    import sys
    _run_tests()
    if "--real" in sys.argv:
        _real_world()
