"""KEYENCE knowledge-base search (Wiki v3m: cleaned chunks + hybrid index + ontology cards).

Built by H:/KeyenceAgent/kb-pipeline (see its PROGRESS.md); this file is the runtime entry.
DB resolution: --db > KEYENCE_WIKI_V3_DB > config `wiki_v3_db` > config `wiki_root`/v3/wiki.v3m.db.
The default is **wiki.v3m.db** (PDF pages with a garbled text layer replaced by MinerU output, plus cards and
vectors); wiki.v3.db is kept as the control library and needs an explicit --db.
config = KEYENCE_AGENT_CONFIG | KV_STUDIO_OPERATOR_CONFIG | %APPDATA%/Codex/kv-studio-operator/config.json.

Hybrid retriever over wiki.v3.db.

Channels (each produces a ranked list; fused with reciprocal-rank fusion):
  seg_q / seg_x   jieba-word bm25 on the user's own words / on lexicon expansions
  tri_q / tri_x   trigram substring bm25 on the user's own words / on expansions
  name_q / name_x exact identifier hit on chunk title or section (FB/instruction pages)
  vec             dense vector similarity (only when vectors were built; stage 5)
Then: source-type prior, address-intent switch, one result per parent chunk.

CLI:
  python search_v3.py "伺服回原点怎么写" [-k 5] [--mode hybrid|seg|tri|fts|hybrid_novec] [--explain] [--text]
"""
from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

import os


def resolve_db(explicit: Path | None = None) -> Path:
    if explicit:
        return explicit
    env = os.environ.get("KEYENCE_WIKI_V3_DB")
    if env:
        return Path(os.path.expandvars(env))
    cfgs = [os.environ.get("KEYENCE_AGENT_CONFIG"), os.environ.get("KV_STUDIO_OPERATOR_CONFIG")]
    if os.environ.get("APPDATA"):
        cfgs.append(str(Path(os.environ["APPDATA"]) / "Codex" / "kv-studio-operator" / "config.json"))
    for c in cfgs:
        if c and Path(c).exists():
            data = json.loads(Path(c).read_text(encoding="utf-8-sig"))
            if data.get("wiki_v3_db"):
                return Path(os.path.expandvars(data["wiki_v3_db"]))
            if data.get("wiki_root"):
                return Path(os.path.expandvars(data["wiki_root"])) / "v3" / "wiki.v3m.db"
            break
    return Path(r"H:\llm-wiki-v2-keyence\v3\wiki.v3m.db")


DB = resolve_db()
RRF_K = 60
CAND = 200

# Expansion control (see analyse/_curated_expansions).
#   df_match: a synonym term/key that appears in more than this share of chunks is too common to
#             treat as a concept trigger (它就是日常词, e.g. "位置"), so it does not expand.
#   df_exp:   a target that appears in more than this share of chunks is too generic to expand to.
#   cap:      hard limit on expansion terms per query (bm25 OR-list length).
DF_MATCH = float(os.environ.get("KB_DF_MATCH", "0.10"))
DF_EXP = float(os.environ.get("KB_DF_EXP", "0.06"))
EXP_CAP = int(os.environ.get("KB_EXP_CAP", "32"))
USE_SYN = os.environ.get("KB_SYN", "1") != "0"
USE_MANPAIR = os.environ.get("KB_MANPAIR", "1") != "0"
# Cross-encoder reranker (BAAI/bge-reranker-v2-m3). Off by default so the library keeps working
# without torch; `--rerank` or KB_RERANK=1 turns it on.
RERANK = os.environ.get("KB_RERANK", "0") != "0"
RERANK_N = int(os.environ.get("KB_RERANK_N", "24"))       # candidates reranked per query
RERANK_A = float(os.environ.get("KB_RERANK_A", "0.7"))    # weight of the reranker vs the fusion
RERANK_CHARS = int(os.environ.get("KB_RERANK_CHARS", "900"))
# what the cross-encoder reads: "mixed" = card header + title/section/text, "only" = the card
# summary alone when the chunk has one (a distilled description reads much better than a table)
RERANK_CARD = os.environ.get("KB_RERANK_CARD", "mixed")

STOPWORDS = set("""怎么 怎样 如何 什么 哪个 哪些 为什么 可以 能 能否 是否 一下 一个 一段 一些 这个 那个
的 了 吗 呢 吧 啊 和 与 及 或 把 被 在 用 让 给 对 从 到 里 中 上 下 时 后 前 写 做 实现 使用 进行 需要 要
请问 请 帮 我 你 有 没有 是 不 一直 所有 某个 这些 那些 时候 方法 功能 程序 怎么写 怎么办""".split())
ASCII_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_\-./]*[A-Za-z0-9_]|[A-Za-z]")
CJK_RUN_RE = re.compile(r"[\u4e00-\u9fff]{3,}")
ADDRESS_RE = re.compile(r"软元件|地址|缓冲存储器|DeviceMap|分配|继电器|寄存器|\bDM\b|\bEM\b|\bCM\b|\bCR\b", re.I)
UI_RE = re.compile(r"注册|添加|登录|设定|编辑器|窗口|画面|对话框|菜单|拖放|新建工程|导入|导出")
MODEL_RE = re.compile(r"KV-?[A-Z]{1,4}\d*[A-Z0-9]*", re.I)
IDENT_LIKE = re.compile(r"^[A-Za-z_*][A-Za-z0-9_.*+\-/]*$")

PRIOR = {"htmlhelp": 1.0, "chm": 0.95, "t_language_example": 0.9, "dockinghelp": 0.8,
         "pdf": 0.85, "table": 0.55, "htmlnavi_meta": 0.25, "card": 1.15,
         # 2026-11-03 extra assets. Deliberately *below* the reference manuals: the manuals are the
         # authority on syntax, and the teaching material covers overlapping ground (it would
         # otherwise displace the manual page the engineer is expected to quote). The samples and
         # the standardised project are reference implementations, one notch lower again.
         "textbook": 0.8, "program_example": 0.75, "project_snapshot": 0.8, "kb_note": 1.0}
# Channel weights (RRF votes). Expansion channels were re-measured on 2026-11-03 with the
# expanded synonym table:
#   tri_x 0.6 -> 0     the trigram channel over expansions was the slowest (300-600 ms) and
#                      measurably hurt the blind set (hit@5 0.842 -> 0.783); Chinese manual
#                      wording is already covered by seg_x, the vector channel and the cards.
#   seg_x 0.7 -> 0.35  same direction, smaller effect; keeps the manual-wording bridge.
# Identifier expansions (name_x) and cards carry the real value of a synonym, not text blobs.
WEIGHTS = {"name_q": 2.0, "name_x": 1.4, "seg_q": 1.0, "tri_q": 0.9,
           "seg_x": float(os.environ.get("KB_W_SEGX", "0.35")),
           "tri_x": float(os.environ.get("KB_W_TRIX", "0")),
           "vec": float(os.environ.get("KB_VEC_W", "2.0")), "card": 1.6, "card_weak": float(__import__("os").environ.get("KB_CARD_WEAK", "0"))}
# KB_WEIGHTS="tri_x=0,seg_x=0.5" overrides single channel weights (ablation without code edits)
for _kv in filter(None, (os.environ.get("KB_WEIGHTS") or "").split(",")):
    _k, _, _v = _kv.partition("=")
    if _k.strip() in WEIGHTS:
        WEIGHTS[_k.strip()] = float(_v)


def fts_quote(term: str) -> str:
    return '"' + term.replace('"', '""') + '"'


CJK_TERM = re.compile(r"[\u4e00-\u9fff]")
# Chinese negation right before/after a matched surface ("不是急停那种", "不用回原点")
NEG_PRE = ("不是", "不要", "不用", "不能", "不会", "不是要", "别", "勿", "非", "否", "没")
NEG_PRE_SHORT = ("不", "别", "非", "否", "没")
NEG_POST = ("不是", "不要", "不用", "不行", "不能", "不会", "以外", "别")


def negated(q: str, start: int, end: int) -> bool:
    """True when the matched surface is negated, so it must not drive query expansion.

    "想让它稳稳停下来，不是急停那种" contains 急停 but asks for the opposite thing.
    """
    pre = q[max(0, start - 3):start]
    return (pre.endswith(NEG_PRE) or q[max(0, start - 1):start].endswith(NEG_PRE_SHORT)
            or q[end:end + 2].startswith(NEG_POST))


class Searcher:
    def __init__(self, db: Path = DB):
        import jieba  # local import keeps CLI startup cheap when unused
        jieba.setLogLevel(60)
        udict = db.parent / "jieba_userdict.txt"
        if udict.exists():
            jieba.load_userdict(str(udict))
        self.jieba = jieba
        self.db = db
        self.conn = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        self.conn.row_factory = sqlite3.Row
        self.lex_curated = defaultdict(list)
        self.lex_manual = defaultdict(list)
        for term, target, kind in self.conn.execute("select term, target, kind from lexicon"):
            (self.lex_curated if kind == "curated" else self.lex_manual)[term].append(target)
        # corpus document frequency of every lexicon term/target (stage2 fills term_df); a target
        # with df=0 does not exist in the corpus and must never be expanded to.
        self.df: dict[str, int] = {}
        try:
            self.df = dict(self.conn.execute("select term, df from term_df"))
        except sqlite3.OperationalError:
            pass
        self.n_chunks = self.conn.execute("select count(*) from chunks").fetchone()[0] or 1
        self._build_synonym_groups()
        # identifier -> chunk ids whose title/section names it (FB, instruction, help pages)
        self.names = defaultdict(list)
        for cid, title, section in self.conn.execute(
                "select id, title, section from chunks where source_type in "
                "('htmlhelp','chm','dockinghelp','t_language_example')"):
            for field in (title, section):
                for part in re.split(r"[,，、/\s]+", field or ""):
                    if part and IDENT_LIKE.match(part):
                        self.names[part.upper()].append(cid)
        self.has_vec = bool(self.conn.execute(
            "select 1 from sqlite_master where name='vectors'").fetchone())
        self.has_cards = bool(self.conn.execute(
            "select 1 from sqlite_master where name='cards_fts'").fetchone())
        self._vec = None
        self._rr = None
        self._chunk_card: dict[str, str] | None = None

    def chunk_cards(self) -> dict[str, str]:
        """chunk_id -> one-line card summary: the distilled "what this page is" text.

        Used as the reranker passage header, because a raw FB page chunk is a parameter table and a
        cross-encoder reads it as less relevant than any prose page that happens to mention the
        same words. Built lazily: it is only needed when the reranker is on.
        """
        if self._chunk_card is None:
            self._chunk_card = {}
            if self.has_cards:
                for name, cn, summary, ev in self.conn.execute(
                        "select name, cn_name, summary, evidence from cards order by case type "
                        "when 'FunctionBlock' then 0 when 'Instruction' then 1 else 2 end"):
                    brief = f"{name}（{cn or ''}）{(summary or '')[:260]}"
                    for cid in json.loads(ev or "[]")[:3]:
                        self._chunk_card.setdefault(cid, brief)
        return self._chunk_card

    # ---------- query analysis ----------
    def _build_synonym_groups(self):
        """Union-find over the curated edges: a group is one concept's surface forms + targets.

        Curated rows are deliberate mappings written as `口语 -> 手册词|标识符`, so connecting them
        undirected turns the table into a thesaurus: 回原点 / 原点复归 / MC_Home end up in one
        group, and any of them in the query pulls in the others. Manual pair rows are left out
        (they are noisy); they are still used one hop from Chinese members.
        """
        parent: dict[str, str] = {}

        def find(x: str) -> str:
            while parent.setdefault(x, x) != x:
                parent[x] = parent.setdefault(parent[x], parent[x])
                x = parent[x]
            return x

        for term, targets in self.lex_curated.items():
            for t in targets:
                a, b = find(term), find(t)
                if a != b:
                    parent[a] = b
        self.group_of: dict[str, str] = {}
        self.group_members: dict[str, set[str]] = defaultdict(set)
        for x in list(parent):
            root = find(x)
            self.group_of[x] = root
            self.group_members[root].add(x)
        # longest first: a longer surface should win where it contains a shorter one
        self.syn_keys = sorted(self.group_of, key=len, reverse=True)
        # precompile identifier patterns: rebuilding them per query thrashes re's cache
        self.syn_ascii: list[tuple[re.Pattern, str]] = [
            (re.compile(r"(?<![A-Za-z0-9_])" + re.escape(k) + r"(?![A-Za-z0-9_])"), k)
            for k in self.syn_keys if k.isascii() and len(k) >= 2]
        self.syn_cjk = [k for k in self.syn_keys if not k.isascii() and len(k) >= 2]

    def _curated_expansions(self, q: str) -> list[str]:
        df_match = int(self.n_chunks * DF_MATCH)
        groups = set()
        for key in self.syn_cjk:
            pos = q.find(key)
            if pos < 0:
                continue
            if negated(q, pos, pos + len(key)):
                continue
            if self.df.get(key, 0) <= df_match:
                g = self.group_of.get(key)
                if g is not None:
                    groups.add(g)
        if ASCII_RE.search(q):                      # only scan identifier keys when relevant
            for pat, key in self.syn_ascii:
                if pat.search(q) and self.df.get(key, 0) <= df_match:
                    g = self.group_of.get(key)
                    if g is not None:
                        groups.add(g)
        out: list[str] = []
        for g in groups:                          # rare (specific) members first
            out += sorted(self.group_members[g], key=lambda t: self.df.get(t, 10 ** 9))
        for t in list(out):                       # Chinese member -> manual description targets
            if CJK_TERM.search(t):
                out += self.lex_manual.get(t, [])
        return out

    def analyse(self, q: str) -> dict:
        ql = q.lower()
        idents = [m.group(0) for m in ASCII_RE.finditer(q)]
        words = []
        for w in self.jieba.cut_for_search(q):
            w = w.strip()
            if not w or w in STOPWORDS or re.fullmatch(r"[\W_]+", w):
                continue
            if len(w) == 1 and not w.isascii():
                continue
            words.append(w)
        expansions: list[str] = []
        if USE_SYN:
            expansions += self._curated_expansions(q)
        if USE_MANPAIR:
            for term, targets in self.lex_manual.items():
                if len(term) >= 2 and term in q:
                    expansions += targets
        df_exp = int(self.n_chunks * DF_EXP)
        seen, exp = set(w.lower() for w in words + idents), []
        for e in expansions:
            low = e.lower()
            if low in seen:
                continue
            d = self.df.get(e)
            if d is not None and (d == 0 or d > df_exp):   # dead target / too generic to discriminate
                continue
            seen.add(low)
            exp.append(e)
        return {"words": words, "idents": idents, "expansions": exp[:EXP_CAP],
                "cjk_runs": CJK_RUN_RE.findall(q), "address": bool(ADDRESS_RE.search(q)),
                "ui": bool(UI_RE.search(q)), "models": [m.upper() for m in MODEL_RE.findall(q)]}

    # ---------- channels ----------
    def _fts(self, table: str, terms: list[str], weights: str) -> list[int]:
        terms = [t for t in dict.fromkeys(terms) if t]
        if not terms:
            return []
        expr = " OR ".join(fts_quote(t) for t in terms)
        try:
            rows = self.conn.execute(
                f"select rowid from {table} where {table} match ? order by bm25({table}, {weights}) limit ?",
                (expr, CAND)).fetchall()
        except sqlite3.OperationalError:
            return []
        return [r[0] for r in rows]

    def _seg_terms(self, terms: list[str]) -> list[str]:
        out = []
        for t in terms:
            if t.isascii():
                out.append(t)
            else:
                parts = [w for w in self.jieba.cut(t) if w.strip() and w not in STOPWORDS]
                out.append(" ".join(parts) if len(parts) > 1 else t)
        return out

    def _names(self, terms: list[str]) -> list[int]:
        ids = []
        for t in terms:
            ids += self.names.get(t.upper(), [])
        return list(dict.fromkeys(ids))

    def _vec_channel(self, q: str) -> list[int]:
        if not self.has_vec:
            return []
        if self._vec is None:
            from kb_vectors import VectorIndex  # same directory
            import os
            self._vec = VectorIndex(self.db, os.environ.get("KB_VEC_MODEL") or None)
        return self._vec.search(q, CAND)

    def _card_channel(self, a: dict, strong: bool = True) -> list[int]:
        """Cards point at evidence chunks; a card hit votes for its evidence."""
        if not self.has_cards:
            return []
        terms = a["words"] + a["idents"] + a["expansions"]
        terms = [t for t in dict.fromkeys(terms) if t]
        if not terms:
            return []
        expr = " OR ".join(fts_quote(t) for t in terms)
        if strong:
            expr = "{name cn} : (" + expr + ")"
        try:
            rows = self.conn.execute(
                "select c.evidence from cards_fts f join cards c on c.rowid=f.rowid "
                "where cards_fts match ? order by bm25(cards_fts, 10, 4, 2, 1) limit 30", (expr,)).fetchall()
        except sqlite3.OperationalError:
            return []
        ids = []
        for (ev,) in rows:
            for chunk_id in json.loads(ev or "[]")[:3]:
                r = self.conn.execute("select id from chunks where chunk_id=?", (chunk_id,)).fetchone()
                if r:
                    ids.append(r[0])
        return list(dict.fromkeys(ids))

    # ---------- cards for the agent ----------
    def card(self, name: str) -> dict | None:
        r = self.conn.execute("select * from cards where card_id=? or name=? collate nocase "
                              "order by case type when 'FunctionBlock' then 0 when 'Instruction' then 1 else 2 end "
                              "limit 1", (name, name)).fetchone()
        return self._card_dict(r) if r else None

    def _card_dict(self, r) -> dict:
        d = dict(r)
        for f in ("aliases", "body_json", "evidence"):
            d[f] = json.loads(d[f] or "null")
        d["body"] = d.pop("body_json")
        return d

    def related_cards(self, q: str, k: int = 3) -> list[dict]:
        """Cards whose name / Chinese name / aliases match the query (strong match only)."""
        if not self.has_cards:
            return []
        a = self.analyse(q)
        terms = [t for t in dict.fromkeys(a["words"] + a["idents"] + a["expansions"]) if t]
        if not terms:
            return []
        expr = "{name cn} : (" + " OR ".join(fts_quote(t) for t in terms) + ")"
        try:
            rows = self.conn.execute(
                "select c.* from cards_fts f join cards c on c.rowid=f.rowid where cards_fts match ? "
                "order by (c.type='Concept'), bm25(cards_fts, 10, 4, 2, 1) limit ?", (expr, k)).fetchall()
        except sqlite3.OperationalError:
            return []
        return [self._card_dict(r) for r in rows]

    # ---------- main ----------
    def search(self, q: str, k: int = 5, mode: str = "hybrid", explain: bool = False) -> list[dict]:
        a = self.analyse(q)
        q_terms = a["words"] + a["idents"]
        tri_q = [t for t in q_terms + a["cjk_runs"] if len(t) >= 3]
        tri_x = [t for t in a["expansions"] if len(t) >= 3]
        lists: dict[str, list[int]] = {}
        use = {
            "seg": {"seg_q", "seg_x", "name_q", "name_x"},
            "tri": {"tri_q", "tri_x", "name_q", "name_x"},
            "fts": {"seg_q", "seg_x", "tri_q", "tri_x", "name_q", "name_x"},
            "hybrid_novec": {"seg_q", "seg_x", "tri_q", "tri_x", "name_q", "name_x", "card", "card_weak"},
            "hybrid": {"seg_q", "seg_x", "tri_q", "tri_x", "name_q", "name_x", "card", "card_weak", "vec"},
            "vec": {"vec"},
        }[mode]
        def on(name: str) -> bool:
            """channel active: in this mode and not zero-weighted (zero means 'off', skip the work)"""
            return name in use and bool(WEIGHTS.get(name))
        if on("seg_q"):
            lists["seg_q"] = self._fts("fts_seg", self._seg_terms(q_terms), "8.0, 3.0, 1.0")
        if on("seg_x"):
            lists["seg_x"] = self._fts("fts_seg", self._seg_terms(a["expansions"]), "8.0, 3.0, 1.0")
        if on("tri_q"):
            lists["tri_q"] = self._fts("fts_tri", tri_q, "8.0, 3.0, 1.0")
        if on("tri_x"):
            lists["tri_x"] = self._fts("fts_tri", tri_x, "8.0, 3.0, 1.0")
        if on("name_q"):
            lists["name_q"] = self._names(a["idents"])
        if on("name_x"):
            lists["name_x"] = self._names([e for e in a["expansions"] if IDENT_LIKE.match(e)])
        if on("card"):
            lists["card"] = self._card_channel(a, strong=True)
        if on("card_weak"):
            lists["card_weak"] = self._card_channel(a, strong=False)
        if on("vec"):
            lists["vec"] = self._vec_channel(q)

        score: dict[int, float] = defaultdict(float)
        why: dict[int, list[str]] = defaultdict(list)
        for ch, ids in lists.items():
            w = WEIGHTS[ch]
            if a["ui"] and ch.startswith("card"):
                w *= 0.5
            for rank, cid in enumerate(ids, 1):
                score[cid] += w / (RRF_K + rank)
                if explain and rank <= 20:
                    why[cid].append(f"{ch}#{rank}")
        if not score:
            return []
        top = sorted(score, key=score.get, reverse=True)[:400]
        meta = {r["id"]: r for r in self.conn.execute(
            f"select id, chunk_id, parent_id, title, section, source, source_type, series, text "
            f"from chunks where id in ({','.join('?' * len(top))})", top)}
        results, seen_parent = [], set()
        for cid in top:
            r = meta[cid]
            prior = PRIOR.get(r["source_type"], 0.8)
            if a["address"] and r["source_type"] == "table":
                prior = 1.2
            if a["ui"] and r["source_type"] == "pdf":
                prior *= 1.3
            doc = (r["source"] or "").split("#")[0].upper()
            if any(m in doc for m in a["models"]):
                prior *= 1.6
            score[cid] *= prior
        cand = sorted(top, key=score.get, reverse=True)
        if RERANK:
            cand = self._rerank(q, cand, meta, score, explain, why)
        for cid in cand:
            r = meta[cid]
            if r["parent_id"] in seen_parent:
                continue
            seen_parent.add(r["parent_id"])
            item = {"chunk_id": r["chunk_id"], "title": r["title"], "section": r["section"],
                    "source": r["source"], "source_type": r["source_type"], "series": r["series"],
                    "score": round(score[cid] * 1000, 2), "text": r["text"]}
            if explain:
                item["why"] = why[cid]
            results.append(item)
            if len(results) >= k:
                break
        if explain and results:
            results[0]["analysis"] = a
        return results

    def _rerank(self, q: str, ids: list[int], meta, score, explain=False, why=None) -> list[int]:
        """Re-order the head of the fused list with a cross-encoder.

        The fusion ranks channels; a cross-encoder can instead read "does this page answer this
        question". Only the head is reranked (RERANK_N) because each pair costs a forward pass.
        The fused score is min-max scaled into the same [0,1] band and blended by RERANK_A.
        """
        if not ids:
            return ids
        if self._rr is None:
            from kb_rerank import Reranker  # same directory
            self._rr = Reranker()
        head, tail = ids[:RERANK_N], ids[RERANK_N:]
        cards = self.chunk_cards()
        passages = []
        for cid in head:
            r = meta[cid]
            card = cards.get(r["chunk_id"], "")
            if card and RERANK_CARD == "only":
                passages.append(card)
            else:
                passages.append(f"{card} {r['title']} | {r['section'] or ''} | "
                                f"{(r['text'] or '')[:RERANK_CHARS]}")
        rr = self._rr.score(q, passages)
        base = [score[c] for c in head]
        lo, hi = min(base), max(base)
        span = (hi - lo) or 1.0
        final = [(1 - RERANK_A) * ((b - lo) / span) + RERANK_A * s for b, s in zip(base, rr)]
        order = sorted(range(len(head)), key=lambda i: -final[i])
        if explain and why is not None:
            for i, s in zip(order, sorted(rr, reverse=True)):
                why[head[i]].append(f"rr{s:.2f}")
        return [head[i] for i in order] + tail


def main():
    global RERANK, RERANK_N
    ap = argparse.ArgumentParser()
    ap.add_argument("query", nargs="?")
    ap.add_argument("-k", type=int, default=5)
    ap.add_argument("--mode", default="hybrid")
    ap.add_argument("--db", type=Path, default=None)
    ap.add_argument("--explain", action="store_true")
    ap.add_argument("--text", action="store_true", help="print full chunk text")
    ap.add_argument("--card", help="print one card by name or card_id (e.g. MC_Home, fb:MC_Home)")
    ap.add_argument("--no-cards", action="store_true", help="do not print related cards before chunks")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--fast", action="store_true",
                    help="skip the vector channel (~1 s instead of ~8 s cold start; lower recall on colloquial wording)")
    ap.add_argument("--rerank", dest="rerank", action="store_true", default=None,
                    help="rerank the fused top-N with bge-reranker-v2-m3 (adds ~0.2-1 s per query)")
    ap.add_argument("--no-rerank", dest="rerank", action="store_false",
                    help="disable the reranker even if KB_RERANK is set")
    ap.add_argument("--rerank-n", type=int, default=None, help="candidates to rerank (default 24)")
    a = ap.parse_args()
    db = resolve_db(a.db)
    if not db.exists():
        print(f"wiki v3 database not found: {db} (set --db, KEYENCE_WIKI_V3_DB or config wiki_root)", file=sys.stderr)
        return 4
    s = Searcher(db)
    if a.card:
        c = s.card(a.card)
        print(json.dumps(c, ensure_ascii=False, indent=1) if c else f"no card: {a.card}")
        return 0 if c else 3
    if not a.query:
        ap.error("query or --card required")
    mode = "hybrid_novec" if a.fast else a.mode
    if mode == "hybrid" and not s.has_vec:
        mode = "hybrid_novec"
    if mode == "hybrid":
        try:
            import sentence_transformers  # noqa: F401
        except Exception:
            print("vector channel unavailable (sentence-transformers not importable); using hybrid_novec",
                  file=sys.stderr)
            mode = "hybrid_novec"
    global RERANK
    if a.rerank is not None:
        RERANK = a.rerank
    if a.rerank_n:
        RERANK_N = a.rerank_n
    if RERANK:
        try:
            import transformers  # noqa: F401
        except Exception:
            print("reranker unavailable (transformers not importable); continuing without it", file=sys.stderr)
            RERANK = False
    cards = [] if a.no_cards else s.related_cards(a.query)
    res = s.search(a.query, a.k, mode, a.explain)
    if a.json:
        print(json.dumps({"query": a.query, "mode": mode, "cards": cards, "results": res},
                         ensure_ascii=False, indent=1))
        return 0 if res else 2
    if a.explain and res:
        print(json.dumps(res[0].pop("analysis"), ensure_ascii=False))
    for c in cards:
        print(f"[card:{c['type']}] {c['name']} {c['cn_name']} ({c['confidence']}) -> {c['summary'][:160]}")
        print(f"    evidence: {', '.join(c['evidence'][:3])}")
    for i, r in enumerate(res, 1):
        print(f"[{i}] {r['score']:>7} {r['source_type']:10} {r['title']} | {r['section']} | {r['source']} "
              f"{'['+r['series']+']' if r['series'] else ''} chunk_id={r['chunk_id']} {' '.join(r.get('why', []))}")
        if a.text:
            print(r["text"], end="\n\n")
    return 0 if res else 2


if __name__ == "__main__":
    sys.exit(main())
