"""Load MinerU page text (mineru_batch/pages_text/*.jsonl) and turn it into plain markdown for the KB.

HTML tables are expanded to a full grid (colspan/rowspan values repeated into every column they cover),
so a merged cell like "30VDC 0.2A" spanning two unit columns appears in both columns of the row.
"""
from __future__ import annotations

import json
import re
from html.parser import HTMLParser
from pathlib import Path

DIR = Path(__file__).resolve().parent / "mineru_batch" / "pages_text"
DITTO = "〃"      # a cell covered by a merged (col/row-spanning) cell: same as the cell to its left/above
TABLE_RE = re.compile(r"<table.*?</table>", re.S | re.I)
IMG_RE = re.compile(r"<img\b[^>]*>", re.I)
DATA_RE = re.compile(r"data:image/(\w+);base64,([^\"'>\s]+)", re.I)
IMG_DIR = Path(__file__).resolve().parent / "mineru_batch" / "images"


def _externalise_image(m) -> str:
    """Save an inline base64 image once (content-addressed) and leave a short reference in the text."""
    import base64
    import hashlib
    d = DATA_RE.search(m.group(0))
    if not d:                       # an <img> that is not inline data (e.g. a path): keep a plain marker
        return "[图]"
    ext = {"jpeg": "jpg"}.get(d.group(1).lower(), d.group(1).lower())
    try:
        raw = base64.b64decode(re.sub(r"\s+", "", d.group(2)))
    except Exception:
        return "[图]"
    name = hashlib.sha1(raw).hexdigest()[:12] + "." + ext
    IMG_DIR.mkdir(parents=True, exist_ok=True)
    f = IMG_DIR / name
    if not f.exists():
        f.write_bytes(raw)
    return f"[图:{name}]"


class _Grid(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.rows, self._row, self._cell, self._span = [], None, None, None
        self.pending = {}      # col -> [remaining_rows, text]

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "tr":
            self._row = []
        elif tag in ("td", "th"):
            self._cell = []
            self._span = (int(re.sub(r"\D", "", a.get("colspan") or "1") or 1),
                          int(re.sub(r"\D", "", a.get("rowspan") or "1") or 1))
        elif tag == "br" and self._cell is not None:
            self._cell.append(" ")

    def handle_data(self, data):
        if self._cell is not None:
            self._cell.append(data)

    def handle_endtag(self, tag):
        if tag in ("td", "th") and self._cell is not None and self._row is not None:
            text = re.sub(r"\s+", " ", "".join(self._cell)).strip()
            self._row.append((text, *self._span))
            self._cell = None
        elif tag == "tr" and self._row is not None:
            self._flush_row()
            self._row = None

    def _flush_row(self):
        out, col, cells = [], 0, list(self._row)

        def fill_pending():
            nonlocal col
            while col in self.pending:
                rem, txt = self.pending[col]
                out.append(DITTO)
                if rem <= 1:
                    del self.pending[col]
                else:
                    self.pending[col][0] = rem - 1
                col += 1

        for text, cs, rs in cells:
            fill_pending()
            for j in range(cs):
                out.append(text if j == 0 else DITTO)
                if rs > 1:
                    self.pending[col] = [rs - 1, text]
                col += 1
        fill_pending()
        self.rows.append(out)


def table_to_md(html: str) -> str:
    p = _Grid()
    p.feed(html)
    p.close()
    lines = ["| " + " | ".join(r) + " |" for r in p.rows if any(c for c in r)]
    if any(DITTO in r for r in p.rows):
        lines.append("(" + DITTO + " = 合并单元格,与左侧/上方同一格)")
    return "\n".join(lines)


def to_markdown(text: str) -> str:
    text = IMG_RE.sub(_externalise_image, text)
    return TABLE_RE.sub(lambda m: "\n" + table_to_md(m.group(0)) + "\n", text).strip()


def load(dir_: Path = DIR) -> dict[tuple[str, int], dict]:
    pages = {}
    if dir_.exists():
        for f in dir_.glob("*.jsonl"):
            for line in f.read_text(encoding="utf-8").splitlines():
                if line.strip():
                    d = json.loads(line)
                    pages[(d["pdf"], d["page"])] = d
    return pages


def range_text(pages: dict, pdf: str, a: int, b: int) -> tuple[str, str] | None:
    """Markdown for pages a..b if every page was extracted, else None. Returns (text, tier)."""
    parts, tiers = [], set()
    for n in range(a, b + 1):
        d = pages.get((pdf, n))
        if not d or not d["text"].strip():
            return None
        parts.append(to_markdown(d["text"]))
        tiers.add(d["tier"])
    return "\n\n".join(parts), "+".join(sorted(tiers))


if __name__ == "__main__":       # quick look: python mineru_pages.py KVSHARDX3H.pdf 56
    import sys
    pg = load()
    d = pg.get((sys.argv[1], int(sys.argv[2])))
    print(to_markdown(d["text"]) if d else "page not extracted yet")
