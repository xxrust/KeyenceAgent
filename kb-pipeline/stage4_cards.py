"""Stage 4: extract ontology cards and attach evidence.

Card sources (all deterministic, no LLM; confidence says how far to trust each):
  FunctionBlock  htmlhelp 03_xx_FBFUN_* pages: name/cn_name/kind/ST call/params/behavior   [manual]
  Instruction    chm KVSREF / Script / ST pages grouped by instruction page               [manual]
  Unit           manuals named after a unit model (KV-XXXX.pdf) + operator unit catalog    [manual]
  Concept        synonyms.tsv + manual name<->desc pairs (bridge from colloquial words)    [extracted]
  ErrorCode /    ontology/field_findings.yaml, transcribed from kv-studio-operator and
  FieldFinding   keyence-plc-programmer live-run notes                                     [field_verified]

Writes tables `cards` and `cards_fts` into wiki.v3.db. Card evidence = v3 chunk_ids.
"""
from __future__ import annotations

import argparse
import json
import re
import sqlite3
from collections import defaultdict
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
V2 = Path(r"H:\llm-wiki-v2-keyence\wiki.v2.cleaned.db")
DB = Path(r"H:\llm-wiki-v2-keyence\v3\wiki.v3.db")
FIELD = HERE / "ontology" / "field_findings.yaml"

LINK_RE = re.compile(r"\[([^\]]*)\]\([^)]*\)")
IDENT = re.compile(r"^[A-Za-z_*][A-Za-z0-9_.*+\-]*$")
CJK = re.compile(r"[\u4e00-\u9fff]")


def strip_links(s: str) -> str:
    return LINK_RE.sub(r"\1", s or "").strip()


def cells(line: str) -> list[str]:
    return [strip_links(c).strip() for c in line.strip().strip("|").split("|")]


def section(text: str, heading: str) -> str:
    m = re.search(r"^#+\s*" + re.escape(heading) + r"\s*$(.*?)(?=^#+\s|\Z)", text, re.M | re.S)
    if not m:
        return ""
    body = re.sub(r"!\[[^\]]*\]\([^)]*\)", "", m.group(1))
    body = strip_links(body)
    body = re.sub(r"^\|.*$", "", body, flags=re.M)
    return re.sub(r"\s+", " ", body).strip()[:600]


class V3Ids:
    """map v2 chunk ids (parents) -> v3 chunk ids"""

    def __init__(self, conn):
        self.by_parent = defaultdict(list)
        for cid, parent in conn.execute("select chunk_id, parent_id from chunks order by id"):
            self.by_parent[parent].append(cid)

    def of(self, parents: list[str], limit: int = 6) -> list[str]:
        out = []
        for p in parents:
            out += self.by_parent.get(p, [])
        return out[:limit]


def fb_cards(v2, ids: V3Ids) -> list[dict]:
    rows = v2.execute("""select chunk_id, title, page_title, source, chunk from wiki_chunks
                         where source_type='htmlhelp' and source like '03\\_%' escape '\\'
                         order by source, cast(sort_key as integer), chunk_id""").fetchall()
    pages = defaultdict(list)   # FB name -> chunks (main + "(n)" continuations)
    order = []
    for cid, title, page_title, source, chunk in rows:
        base = re.sub(r"\s*\(\d+\)$", "", title or "").strip()
        if not IDENT.match(base) and base not in ("*_TO_**", "TO_**", "TRUNC_**", "IS_***"):
            continue
        key = (source, base)
        if key not in pages:
            order.append(key)
        pages[key].append((cid, page_title, chunk))
    cards = []
    for source, name in order:
        chunks = pages[(source, name)]
        text = "\n".join(c[2] for c in chunks)
        cn, kind, st_call = "", "", ""
        params = []
        lines = text.splitlines()
        for i, line in enumerate(lines):
            if not line.startswith("|"):
                continue
            c = [x for x in cells(line)]
            nonempty = [x for x in c if x]
            if nonempty and nonempty[0] == name and len(nonempty) >= 2 and not cn and CJK.search(nonempty[1]):
                cn = nonempty[1]
            if nonempty and nonempty[0] == name and any(x in ("FB", "FUN") for x in nonempty):
                kind = next(x for x in nonempty if x in ("FB", "FUN"))
                st_call = next((x for x in nonempty if "(" in x and ";" in x), st_call)
            if len(c) >= 5 and c[1] in ("IN", "OUT", "IN-OUT", "UNIT", "返回值") and c[0]:
                params.append({"name": c[0], "direction": c[1], "data_type": c[2],
                               "default": c[3], "comment": c[4]})
        if not (kind or params):
            continue
        behavior = section(text, "动作说明")
        error = section(text, "Error变为TRUE的条件")
        category = chunks[0][1] or ""
        evidence = ids.of([c[0] for c in chunks])
        summary = f"{name}（{cn}）{kind}. {st_call} {behavior[:200]}".strip()
        cards.append({
            "card_id": f"fb:{name}", "type": "FunctionBlock", "name": name, "cn_name": cn,
            "aliases": [], "series": "KV-X",
            "summary": summary,
            "body": {"kind": kind, "category": category, "st_call": st_call, "params": params,
                     "behavior": behavior, "error_condition": error, "source": source},
            "evidence": evidence, "confidence": "manual", "origin": "htmlhelp",
        })
    return cards


def instruction_cards(v2, ids: V3Ids) -> list[dict]:
    rows = v2.execute("""select chunk_id, title, page_title, source, chunk, doc_id from wiki_chunks
                         where source_type='chm' order by doc_id, cast(sort_key as integer), chunk_id""").fetchall()
    groups = defaultdict(list)
    for cid, title, page_title, source, chunk, doc_id in rows:
        page = (page_title or "").strip()
        if not page:
            continue
        manual = "ladder" if "InstructionRef" in cid else "script" if "KVSSCR" in cid else \
                 "st" if "KVSST" in cid else "other"
        groups[(page, manual)].append((cid, title, chunk))
    by_page = defaultdict(dict)
    for (page, manual), chunks in groups.items():
        by_page[page][manual] = chunks
    cards = []
    for page, manuals in by_page.items():
        names = [n.strip() for n in re.split(r"[,，/]", page) if n.strip()]
        if not names or not all(IDENT.match(n) for n in names):
            continue
        cn, st_call, behavior = "", "", ""
        all_chunks = []
        for manual, chunks in manuals.items():
            all_chunks += chunks
            for cid, title, chunk in chunks:
                for line in chunk.splitlines():
                    if line.startswith("|"):
                        ne = [x for x in cells(line) if x]
                        if len(ne) >= 2 and ne[0] in names and CJK.search(ne[1]) and not cn:
                            cn = ne[1]
                        if manual == "st" and not st_call:
                            m = re.search(r"\[?R?:?=?\]?\s*" + re.escape(names[0]) + r"\s*\([^)]*\);", line)
                            if m:
                                st_call = m.group(0)
                if title == "操作说明" and not behavior:
                    behavior = re.sub(r"\s+", " ", strip_links(chunk.replace("## 操作说明", "")))[:500]
        kind = "Instruction" if "ladder" in manuals else "FunctionBlock"
        cards.append({
            "card_id": f"ins:{page}", "type": kind if kind == "Instruction" else "FunctionBlock",
            "name": names[0], "cn_name": cn, "aliases": names[1:], "series": "",
            "summary": f"{page}（{cn}） {st_call} {behavior[:200]}".strip(),
            "body": {"variants": names, "manuals": sorted(manuals), "st_call": st_call, "behavior": behavior},
            "evidence": ids.of([c[0] for c in all_chunks], 8),
            "confidence": "manual", "origin": "chm",
        })
    return cards


UNIT_MODEL = re.compile(r"^(KV-[A-Z0-9]+(?:[_/][A-Z0-9]+)*)")
UNIT_CATEGORY = [
    (r"AD|DA|SAD|SDA", "analog"), (r"SSC|SC20|CA", "counter"), (r"SH04PL|SimplePos", "positioning"),
    (r"XHEC|XH\d|XHECL", "motion_ethercat"), (r"ML", "motion_ml"), (r"EC01", "coupler"),
    (r"XLE|LE2|EP02", "ethernet"), (r"L2\dV|XL|LH20|LM21|SerialPlcLink", "serial"),
    (r"TF40|TP40", "temperature"), (r"DN20", "devicenet"), (r"FL20", "fl-net"), (r"CL20", "cc-link"),
]


def unit_cards(conn, ids: V3Ids) -> list[dict]:
    docs = conn.execute("""select doc, count(*), min(chunk_id) from chunks where source_type in ('pdf','table')
                           group by doc""").fetchall()
    cards = []
    for doc, n, _ in docs:
        m = UNIT_MODEL.match(doc or "")
        if not m:
            continue
        model = m.group(1)
        cat = next((c for pat, c in UNIT_CATEGORY if re.search(pat, model)), "other")
        ev = [r[0] for r in conn.execute(
            "select chunk_id from chunks where doc=? order by id limit 4", (doc,))]
        intro = conn.execute("select text from chunks where doc=? and source_type='pdf' order by id limit 1",
                             (doc,)).fetchone()
        cards.append({
            "card_id": f"unit:{doc}", "type": "Unit", "name": model, "cn_name": "",
            "aliases": [doc], "series": "", "summary": f"{model} 单元手册/地址表 {doc}（{n} 块）",
            "body": {"category": cat, "manual": doc, "chunks": n,
                     "intro": re.sub(r"\s+", " ", (intro[0] if intro else ""))[:300]},
            "evidence": ev, "confidence": "manual", "origin": "doc_index",
        })
    return cards


def concept_cards(conn, name_to_card: dict) -> list[dict]:
    """Concept = a Chinese task phrase -> implementing FB/instructions (+ their evidence)."""
    implemented = defaultdict(set)
    aliases = defaultdict(set)
    for term, target, kind in conn.execute("select term, target, kind from lexicon"):
        if kind == "manual_pair":
            implemented[term].add(target)
        else:
            if target in name_to_card:
                implemented[term].add(target)
            else:
                aliases[target].add(term)   # target is itself a concept phrase
    cards = []
    for concept in sorted(set(implemented) | set(aliases)):
        impl = set(implemented.get(concept, set()))
        for alias in aliases.get(concept, []):
            impl |= implemented.get(alias, set())
        impl = sorted(i for i in impl if i in name_to_card)
        if not impl:
            continue
        evidence = []
        for i in impl[:5]:
            evidence += name_to_card[i]["evidence"][:1]
        cards.append({
            "card_id": f"concept:{concept}", "type": "Concept", "name": concept, "cn_name": concept,
            "aliases": sorted(aliases.get(concept, [])), "series": "",
            "summary": f"{concept} → {', '.join(impl[:8])}",
            "body": {"implemented_by": impl},
            "evidence": evidence, "confidence": "extracted", "origin": "lexicon",
        })
    return cards


def field_cards() -> list[dict]:
    if not FIELD.exists():
        return []
    data = yaml.safe_load(FIELD.read_text(encoding="utf-8")) or []
    cards = []
    for item in data:
        t = item["type"]
        key = item.get("code") or item["title"]
        cards.append({
            "card_id": f"{t.lower()}:{key}", "type": t, "name": str(key), "cn_name": item.get("title", ""),
            "aliases": item.get("aliases", []), "series": item.get("cpu", ""),
            "summary": f"{item.get('title','')} 现象:{item.get('symptom','')} 处理:{item.get('fix','')}",
            "body": {k: v for k, v in item.items() if k not in ("type",)},
            "evidence": [], "confidence": "field_verified", "origin": item.get("field_evidence", ""),
        })
    return cards


def write(conn, cards: list[dict]):
    conn.executescript("""
    drop table if exists cards; drop table if exists cards_fts;
    create table cards (card_id TEXT PRIMARY KEY, type TEXT, name TEXT, cn_name TEXT, aliases TEXT,
        series TEXT, summary TEXT, body_json TEXT, evidence TEXT, confidence TEXT, origin TEXT);
    create index cards_name on cards(name);
    """)
    import jieba
    jieba.setLogLevel(60)
    ud = DB.parent / "jieba_userdict.txt"
    if ud.exists():
        jieba.load_userdict(str(ud))
    seg = lambda s: " ".join(w for w in jieba.cut_for_search(s or "") if w.strip())
    conn.execute("create virtual table cards_fts using fts5(name, cn, summary, body, tokenize='unicode61')")
    seen = set()
    for c in cards:
        if c["card_id"] in seen:
            continue
        seen.add(c["card_id"])
        conn.execute("insert into cards values (?,?,?,?,?,?,?,?,?,?,?)", (
            c["card_id"], c["type"], c["name"], c["cn_name"], json.dumps(c["aliases"], ensure_ascii=False),
            c["series"], c["summary"], json.dumps(c["body"], ensure_ascii=False, default=str),
            json.dumps(c["evidence"], ensure_ascii=False), c["confidence"], c["origin"]))
        rowid = conn.execute("select rowid from cards where card_id=?", (c["card_id"],)).fetchone()[0]
        body_txt = json.dumps(c["body"], ensure_ascii=False, default=str)
        conn.execute("insert into cards_fts(rowid, name, cn, summary, body) values (?,?,?,?,?)",
                     (rowid, c["name"] + " " + " ".join(c["aliases"]),
                      seg(c["cn_name"] + " " + " ".join(c["aliases"])), seg(c["summary"]), seg(body_txt[:3000])))
    conn.commit()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", type=Path, default=DB)
    a = ap.parse_args()
    v2 = sqlite3.connect(f"file:{V2}?mode=ro", uri=True)
    conn = sqlite3.connect(a.db)
    ids = V3Ids(conn)
    fbs = fb_cards(v2, ids)
    ins = instruction_cards(v2, ids)
    name_to_card = {}
    for c in fbs + ins:                 # htmlhelp FB card wins over chm page on name clash
        for n in [c["name"]] + c["aliases"]:
            name_to_card.setdefault(n, c)
    units = unit_cards(conn, ids)
    concepts = concept_cards(conn, name_to_card)
    field = field_cards()
    cards = fbs + ins + units + concepts + field
    write(conn, cards)
    stats = defaultdict(int)
    for c in cards:
        stats[c["type"]] += 1
    no_ev = sum(1 for c in cards if not c["evidence"] and c["confidence"] != "field_verified")
    stats["without_evidence"] = no_ev
    conn.execute("insert or replace into build_meta values ('stage4', ?)", (json.dumps(stats),))
    conn.commit()
    print(json.dumps(stats, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
