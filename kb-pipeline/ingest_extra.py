"""Ingest non-manual assets into wiki.v3m.db: textbooks (MinerU markdown), official sample
programs (mnm -> markdown) and the KV-X standardised project snapshot.

Order of operations: run AFTER stage1 (which recreates `chunks`) and BEFORE stage2 (which rebuilds
the FTS indexes and term_df from `chunks`). Chunk ids are prefixed `x:` so they never collide with
the v2-derived ids; re-running deletes and rewrites only those rows.

source_type values and how they are meant to be used:
  textbook           Keyence teaching material (MinerU text, page/section anchors)
  program_example    official sample ladder/ST programs shipped as .mnm
  project_snapshot   the KVX样例程序_v100 project: real FB interfaces, bodies, program modules

Two different variable-naming conventions coexist here and must not be mixed:
  textbook      x/ui/i/udi/di/r/lr/str/tim/a/st/un/fb  + scope prefix g/l
  sample        b/aui/r/di..., FB instances `inst*`, structs `str*`, Chinese global names
That is recorded in the `keywords` field as `convention=textbook|sample` so a retriever or agent
can tell where a snippet came from.

Usage:
  python ingest_extra.py --dry-run            # counts and samples, no DB write
  python ingest_extra.py                      # write into the DB + report
"""
from __future__ import annotations

import argparse
import glob
import json
import re
import sqlite3
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
DB = Path(r"H:\llm-wiki-v2-keyence\v3\wiki.v3m.db")
MINERU = HERE / "extra_docs" / "mineru"
ZIP_SRC = Path(r"H:\KeyenceAgent\其他文件\official-examples.zip")
SNAP = Path(r"H:\kvOp\regression13_real_20260923_final\13_project_text_snapshot_20260923_130026_242_32dd2104"
            r"\workflow\snapshot\project")
SOURCE_PRIORITY = {"htmlhelp": 0, "chm": 1, "t_language_example": 2, "dockinghelp": 3,
                   "table": 4, "pdf": 5, "htmlnavi_meta": 9}
MAX = 2400          # hard cap per chunk (same order of magnitude as stage1)
TARGET = 1600       # preferred size when splitting

TEXTBOOKS = {
    "st_book": dict(doc="AS_155351_使用实例_ST语言.pdf", series="KV-X",
                    kind="ST 语言实例教材（67 个常用函数 + 现场示例）"),
    "standardization": dict(doc="AS_147562_程序标准化_变量ST_FB.pdf", series="KV-X",
                            kind="程序标准化教材（变量/ST/FB 篇）"),
    "motion": dict(doc="AS_143610_PLC编程教材_运动控制篇.pdf", series="KV-X",
                   kind="PLC 编程教材（运动控制篇）"),
}
BOILER = re.compile(r"\n{3,}")
IMG = re.compile(r"!\[[^\]]*\]\([^)]*\)")


def clean(md: str) -> str:
    md = IMG.sub("", md)
    md = md.replace("\u00a0", " ")
    return BOILER.sub("\n\n", md).strip()


def split_text(text: str, heading: str = "") -> list[str]:
    """Split into <=MAX pieces on blank lines, repeating the heading in each piece."""
    if len(text) <= MAX:
        return [text]
    paras, cur, size = text.split("\n\n"), [], 0
    out = []
    for p in paras:
        if size + len(p) + 2 > TARGET and cur:
            out.append("\n\n".join(cur))
            cur, size = [], 0
        cur.append(p)
        size += len(p) + 2
    if cur:
        out.append("\n\n".join(cur))
    if heading:
        out = [p if p.lstrip().startswith("#") else f"# {heading}\n\n{p}" for p in out]
    return out


# ---------------------------------------------------------------- textbooks
def _heading_ok(h: str) -> bool:
    """MinerU sometimes glues a code fragment into the heading; those make useless titles."""
    return 0 < len(h) <= 40 and ";" not in h and "//" not in h and ":=" not in h and h.count("|") < 2


def textbook_chunks() -> list[dict]:
    rows = []
    for key, meta in TEXTBOOKS.items():
        files = sorted(glob.glob(str(MINERU / key / "**" / "*.md"), recursive=True),
                       key=lambda p: Path(p).stat().st_size, reverse=True)
        if not files:
            print(f"  ! no MinerU markdown for {key} yet ({MINERU / key})")
            continue
        md = clean(Path(files[0]).read_text(encoding="utf-8", errors="ignore"))
        blocks = []
        for i, block in enumerate(re.split(r"\n(?=#{1,4}\s)", md), 1):
            block = block.strip()
            if not block:
                continue
            m = re.match(r"(#{1,4})\s*(.+)", block)
            heading = m.group(2).strip() if m else ""
            level = len(m.group(1)) if m else 9
            body = block[m.end():].strip() if m else block
            size = len(re.sub(r"\s", "", body))
            if size or heading:
                blocks.append(dict(heading=heading, level=level, body=body, n=i, size=size))
        # merge consecutive headings into ~TARGET pieces: one teaching slide per heading is too small
        groups, cur, cur_size = [], [], 0
        for b in blocks:
            if cur and (cur_size + b["size"] > TARGET or b["level"] <= 1):
                groups.append(cur)
                cur, cur_size = [], 0
            cur.append(b)
            cur_size += b["size"]
        if cur:
            groups.append(cur)
        for g in groups:
            total = sum(x["size"] for x in g)
            has_code = any("```" in x["body"] or "<table" in x["body"] for x in g)
            if total < 80 and not has_code:
                continue                      # page numbers, running heads, one-word slides
            good = [x["heading"] for x in g if _heading_ok(x["heading"])]
            head = next((h for h in good if re.match(r"^(\d+(\.\d+)*|第)", h)),
                        max(good, key=len) if good else "")
            title = head or f"{meta['kind']} 第 {g[0]['n']} 节"
            text = "\n\n".join(f"## {x['heading']}\n{x['body']}" if x["heading"] else x["body"]
                               for x in g)
            anchor = re.sub(r"\s+", "-", title)[:60]
            pieces = split_text(text, title)
            for j, piece in enumerate(pieces, 1):
                cid = f"x:tb:{key}:{g[0]['n']:04d}" + (f"#p{j}" if j > 1 else "")
                rows.append(dict(
                    chunk_id=cid, parent_id=f"x:tb:{key}:{g[0]['n']:04d}", part=j,
                    parts=len(pieces), title=title[:120], section=meta["kind"],
                    doc=meta["doc"], source=f"{meta['doc']}#{anchor}",
                    source_type="textbook", series=meta["series"], text=piece[:MAX * 2],
                    keywords="convention=textbook", extractor="mineru-standard"))
    return rows


# ------------------------------------------------------------ sample programs
def program_example_chunks() -> list[dict]:
    rows = []
    if not ZIP_SRC.exists():
        print(f"  ! {ZIP_SRC} missing")
        return rows
    z = zipfile.ZipFile(ZIP_SRC)
    for name in z.namelist():
        if not name.endswith(".md"):
            continue
        doc = Path(name).name
        md = clean(z.read(name).decode("utf-8-sig", errors="ignore"))
        for i, block in enumerate(re.split(r"\n(?=##\s)", md), 1):
            block = block.strip()
            m = re.match(r"##\s*(.+)", block)
            if not m:
                continue
            heading = m.group(1).strip()
            if ".mnm" not in heading:
                continue                      # skip the table of contents and the converter's summary
            file_name = re.sub(r"^\d+\.\s*", "", heading)
            # the .mnm carries a Chinese comment like ";Axis1 origin return (轴1原点回归)";
            # lift it into the title so a Chinese question can actually match the file name
            cn = ""
            for line in block.split("\n"):
                m2 = re.search(r"[；;]\s*[^（(]*[（(]([^）)]*[\u4e00-\u9fff][^）)]*)[）)]", line)
                if m2:
                    cn = m2.group(1).strip()
                    break
            if not cn:
                for line in block.split("\n"):
                    m2 = re.search(r"[；;]\s*([^\n]*[\u4e00-\u9fff][^\n]*)", line)
                    if m2 and len(m2.group(1)) <= 40:
                        cn = m2.group(1).strip()
                        break
            title = f"{file_name}（{cn}，示例程序）" if cn else f"{file_name}（示例程序）"
            for j, piece in enumerate(split_text(block), 1):
                cid = f"x:pe:{doc}:{i:03d}" + (f"#p{j}" if j > 1 else "")
                rows.append(dict(
                    chunk_id=cid, parent_id=f"x:pe:{doc}:{i:03d}", part=j,
                    parts=len(split_text(block)),
                    title=title[:140], section=doc.replace(".md", ""),
                    doc=doc, source=f"{doc}#{file_name}", source_type="program_example",
                    series="KV-X", text=piece[:MAX * 2], keywords="convention=sample",
                    extractor="text"))
    return rows


# ------------------------------------------------------------ project snapshot
def _tsv(path: Path) -> list[list[str]]:
    if not path.exists():
        return []
    return [l.rstrip("\n").split("\t") for l in path.read_text(encoding="utf-8-sig").splitlines() if l.strip()]


def _cell(row: list[str], i: int) -> str:
    return row[i] if len(row) > i else ""


def _comment(row: list[str], after: int = 2) -> str:
    """The comment column is the right-most non-boolean cell (the TSV layout differs per artifact)."""
    for c in reversed(row[after:]):
        if c and c not in ("True", "False"):
            return c
    return ""


def _fb_rows(entity_path: Path, ent: dict) -> list[dict]:
    args = _tsv(entity_path / "arguments.tsv")
    locals_ = _tsv(entity_path / "locals.tsv")
    body_p = entity_path / "body.mnm"
    body = body_p.read_text(encoding="utf-8", errors="ignore") if body_p.exists() else ""
    head = [f"# {ent.get('display_name') or ent.get('source_name')}（{ent.get('source_name')}，功能块）",
            f"路径：{ent.get('path')}"]
    if args:
        head.append("\n## 自变量（IN/OUT）")
        head += [f"- {a[0]}（{_cell(a, 1)}）：{_cell(a, 3)}" + (f"  // {c}" if (c := _comment(a, 2)) else "")
                 for a in args if a and a[0]]
    if locals_:
        head.append("\n## 局部变量")
        head += [f"- {l[0]}：{_cell(l, 1)}" + (f"  // {c}" if (c := _comment(l, 2)) else "")
                 for l in locals_ if l and l[0]]
    text = "\n".join(head)
    if body:
        text += "\n\n## ST/梯形图程序体\n\n```mnm\n" + body[:1800] + "\n```"
    body_parts = split_text(text) if len(text) > MAX else [text]
    out = []
    for j, piece in enumerate(body_parts, 1):
        cid = f"x:snap:fb:{ent.get('source_name','fb')}" + (f"#p{j}" if j > 1 else "")
        out.append(dict(chunk_id=cid, parent_id=cid.split("#")[0], part=j, parts=len(body_parts),
                        title=f"{ent.get('source_name')}（{ent.get('display_name')}，功能块）",
                        section="KVX样例程序_v100 功能块", doc="KVX样例程序_v100",
                        source=f"KVX样例程序_v100#{ent.get('path')}", source_type="project_snapshot",
                        series="KV-X", text=piece, keywords="convention=sample;kind=fb",
                        extractor="text"))
    return out


def _prog_rows(entity_path: Path, ent: dict) -> list[dict]:
    body_p = entity_path / "body.mnm"
    body = body_p.read_text(encoding="utf-8", errors="ignore") if body_p.exists() else ""
    text = (f"# 程序模块：{ent.get('source_name')}（执行顺序 {ent.get('execution_order')}，"
            f"{ent.get('category')}）\n\n路径：{ent.get('path')}\n\n"
            f"## 程序体\n\n```mnm\n{body[:1800]}\n```")
    parts = split_text(text) if len(text) > MAX else [text]
    out = []
    for j, piece in enumerate(parts, 1):
        cid = f"x:snap:prog:{ent.get('source_name','prog')}" + (f"#p{j}" if j > 1 else "")
        out.append(dict(chunk_id=cid, parent_id=cid.split("#")[0], part=j, parts=len(parts),
                        title=f"程序模块：{ent.get('source_name')}（{ent.get('category')}）",
                        section="KVX样例程序_v100 程序", doc="KVX样例程序_v100",
                        source=f"KVX样例程序_v100#{ent.get('path')}", source_type="project_snapshot",
                        series="KV-X", text=piece, keywords="convention=sample;kind=program",
                        extractor="text"))
    return out


def snapshot_chunks() -> list[dict]:
    rows: list[dict] = []
    if not SNAP.exists():
        print(f"  ! snapshot missing: {SNAP}")
        return rows
    for ent_p in sorted(glob.glob(str(SNAP / "功能块" / "**" / "entity.json"), recursive=True)):
        ent = json.loads(Path(ent_p).read_text(encoding="utf-8-sig"))
        rows += _fb_rows(Path(ent_p).parent, ent)
    for ent_p in sorted(glob.glob(str(SNAP / "程序" / "**" / "entity.json"), recursive=True)):
        ent = json.loads(Path(ent_p).read_text(encoding="utf-8-sig"))
        rows += _prog_rows(Path(ent_p).parent, ent)
    # configuration: global variables, structures, unit/EtherCAT topology
    var = _tsv(SNAP / "配置" / "全局变量" / "variables.tsv")
    user = [v for v in var if len(v) > 2 and v[0] != "(System)"]
    if user:
        lines = [f"# 全局变量表（{len(user)} 个用户变量，另有系统变量 {len(var) - len(user)} 个）",
                 "", "| 变量名 | 类型 | 软元件 | 注释 |", "|---|---|---|---|"]
        lines += [f"| {v[1]} | {v[2]} | {v[3] if len(v) > 3 else ''} | {v[4] if len(v) > 4 else ''} |"
                  for v in user[:80]]
        for j, piece in enumerate(split_text("\n".join(lines)), 1):
            cid = f"x:snap:cfg:globalvars" + (f"#p{j}" if j > 1 else "")
            rows.append(dict(chunk_id=cid, parent_id=cid.split("#")[0], part=j, parts=1,
                             title="全局变量表（KVX样例程序_v100）", section="KVX样例程序_v100 配置",
                             doc="KVX样例程序_v100", source="KVX样例程序_v100#配置/全局变量",
                             source_type="project_snapshot", series="KV-X", text=piece,
                             keywords="convention=sample;kind=config", extractor="text"))
    sd = SNAP / "类型" / "structure_definitions.json"
    if sd.exists():
        data = json.loads(sd.read_text(encoding="utf-8-sig"))
        lines = ["# 结构体定义（KVX样例程序_v100）", ""]
        items = data if isinstance(data, list) else data.get("structures") or data.get("definitions") or []
        for st in items[:40]:
            if isinstance(st, dict):
                name = st.get("name") or st.get("source_name")
                mem = st.get("members") or st.get("fields") or []
                lines.append(f"## {name}")
                lines += [f"- {m.get('name')}：{m.get('data_type') or m.get('type')}"
                          for m in mem if isinstance(m, dict)][:20]
        if len(lines) > 3:
            for j, piece in enumerate(split_text("\n".join(lines)), 1):
                cid = f"x:snap:cfg:types" + (f"#p{j}" if j > 1 else "")
                rows.append(dict(chunk_id=cid, parent_id=cid.split("#")[0], part=j, parts=1,
                                 title="结构体定义（KVX样例程序_v100）", section="KVX样例程序_v100 配置",
                                 doc="KVX样例程序_v100", source="KVX样例程序_v100#类型/结构体",
                                 source_type="project_snapshot", series="KV-X", text=piece,
                                 keywords="convention=sample;kind=config", extractor="text"))
    ov = SNAP / "overview.md"
    if ov.exists():
        text = clean(ov.read_text(encoding="utf-8", errors="ignore"))[:3000]
        rows.append(dict(chunk_id="x:snap:overview", parent_id="x:snap:overview", part=1, parts=1,
                         title="KVX样例程序_v100 项目总览（实体与恢复顺序）",
                         section="KVX样例程序_v100", doc="KVX样例程序_v100",
                         source="KVX样例程序_v100#overview", source_type="project_snapshot",
                         series="KV-X", text=text, keywords="convention=sample;kind=overview",
                         extractor="text"))
    return rows


# ---------------------------------------------------------------- curated notes
LAYERS = """# 标准化程序的分层结构（KVX样例程序_v100）

基恩士这份标准程序的树只有三层功能块，加上按执行顺序编号的程序模块，就是它的组织方法。

## 功能块（三层）
- `功能块/库/`：与伺服品牌/型号绑定的通用库，命名是「功能_品牌型号_版本」，
  例如 `MC_ParameterRead_PANAS_A6BE_V100`、`MC_ModelCheck_YASKA_SigmaXS_V100`、
  `MC_MultiParameterWrite_INOVA_SV630N_V100`、`MC_ABSEncoderSetup_LEADS_CL3C_EC_V100`、
  `MC_SoftwareReset_…`，另有 `ModbusTCPClient_Connect` / `ModbusTCPClient_Command`。
  这一层只做「对某个品牌驱动器读写某个参数」这一件事，换品牌就换一个 FB。
- `功能块/level1_组件/`：与设备无关的动作组件，`FB_Cylinder`（气缸）、`FB_Vacuum`（真空）、
  `FB_Motion`（轴控）。组件内部封装 `MC_Power/Home/Jog/MoveAbsolute/MoveRelative/MoveToPoint/
  ChangeTargetPosition/ChangeTargetVelocity/Reset/Stop/ResumePositioning/ImmediateStop/MCodeOff`
  等运动 FB 的实例（`instMC_*`），对外只暴露 `AxisCtrl/AxisParam/AxisStatus` 等结构体与少量 BOOL。
- `功能块/level3_设备/`：`FB_McMode`，设备层（把组件按一台设备组合起来）。

## 程序（24 个模块，按执行顺序）
1 IO输入 · 2 高速计数器输入 · 3 模拟量输入 · 4 初始化 · 5 调用气缸FB · 6 调用真空FB · 7 调用轴控FB ·
8 ST00_插针_演示 · 9–14 ST01–ST06 上料A/B/C、传送带、旋转点胶、下料 · 15 设备状态 · 16 Alarm报警 ·
17 HMI · 18 IO输出 · 19 A1_气缸控制 · 20 A2_真空控制 · 21 A3_轴控制 · 22 A4_ModbusTCP · 23 A5_手自动 ·
24 后备模块/版本管理

## 配置
`配置/单元`（单元构成）、`配置/EtherCAT`（拓扑）、`配置/全局变量`（145 个用户变量 + 系统变量）、
`类型/结构体`（`strAxisCtrl`/`strAxisParam`/`strAxisStatus` 等）。

## 复用方式
程序模块 → 调用 level1 组件（Cylinder/Vacuum/Motion）→ 组件内部调用 `MC_*` FB；
与品牌相关的读写走 `功能块/库` 里的品牌专用 FB。回答“标准程序怎么分层/怎么组织”时按这个顺序讲，
不要把它和《程序标准化（变量、ST、FB 篇）》教材的章节混为一谈——教材讲方法论，这里讲这套样例的落地结构。"""


def note_chunks() -> list[dict]:
    """Two hand-written KB notes. They exist because the new assets contradict each other on
    variable naming, and because an agent that finds a textbook page should know what else is in
    the library. Both are curated text, not extracted, so they are marked source_type=kb_note."""
    naming = """# 变量命名规范：教材版 vs KVX样例程序版（两套，不可混用）

本知识库同时收录了两份基恩士官方资料，它们对“变量命名”给出的规范不同。回答命名问题时先
说明是哪一套，不要把两者混在一段示例里。

## 教材版（《程序标准化：变量、ST、FB 篇》AS_147562，p12）
- 数据类型前缀：BOOL=`x`、UINT=`ui`、INT=`i`、UDINT=`udi`、DINT=`di`、REAL=`r`、LREAL=`lr`、
  STRING=`str`、TIME=`tim`、ARRAY=`a`、结构体=`st`、联合体=`un`、功能块=`fb`
- 作用域前缀：全局变量开头加 `g`，局部变量开头加 `l`
- 例：设备名的 STRING 型全局变量 → `gstrEquipName`

## 样例程序版（KVX样例程序_v100，实际工程）
- BOOL 用 `b`：`bJogFwd`、`bPosStartMan`
- FB 实例用 `inst`：`instMC_Power`、`instR_TRIG_Man`
- 结构体用 `str`：`strAxisCtrl`、`strAxisStatus`
- 全局变量 135/145 直接用中文名（`旋转轴DEMO`、`上料1拨料`、`龙门1小X轴1`），仅少数用 `gb` 前缀
- FB 自变量不带类型前缀（`Axis`、`Mode`、`Safe`、`Reset`）

## 用哪一套
- 写**新程序/对外交付**：按教材版（KEENCE 现行规范）。
- 读**KVX样例程序_v100**：按样例程序版理解，不要把它改写成教材版再引用。
- 两者都基于同一套方法（变量分组、ST 写 FB 体、FB 分层复用），差异只在命名风格。"""
    assets = """# 知识库资料构成（2026-11-03 起）

除 155 本随 KV STUDIO 安装的参考手册（`source_type=pdf` 等）外，本库还收录了三类非手册资料：

## 教材（source_type=textbook，MinerU 识别）
- `AS_147562_程序标准化_变量ST_FB.pdf`：程序标准化的方法论——变量（全局/局部、数据类型、分组、
  TIME、数组、结构体、联合体）、ST 语言写法、FB 与 FUN 的区别与创建步骤
- `AS_155351_使用实例_ST语言.pdf`：67 个常用 ST 函数的现场使用实例（含完整代码）
- `AS_143610_PLC编程教材_运动控制篇.pdf`：用 XY 平台把运动控制从设定到编程到监控串一遍

## 官方示例程序（source_type=program_example，.mnm 转写）
- `SH04PL轴控程序示例.md`：KV-SH04PL 定位单元的 20 个示例（原点回归、JOG、示教、绝对值跟随、
  运行中改速/改坐标、连续立即启动、M 代码输出、写 Flash ROM…）
- `常用主模块程序.md`：44 个常用主模块骨架（数组移位、平均值/方差、累计、Ping 连通检查、
  时间戳、边沿检测等，LD 与 ST 双版本）

## 标准化程序工程快照（source_type=project_snapshot）
- `KVX样例程序_v100`：基恩士公开的标准程序样例。68 个实体、24 个执行型程序模块
  （IO、高速计数、模拟量、初始化、设备状态、Alarm、HMI、A1 气缸/A2 真空/A3 轴控/A4 ModbusTCP/
  A5 手自动、ST00–ST06 工位、后备模块·版本管理）、40 个 FB（四品牌伺服参数读写/初始化/软件复位/
  型号检查、ABS 编码器设定、ModbusTCP 客户端、level1 组件 Cylinder/Motion/Vacuum、level3 设备 McMode）
- 每个 FB 都带 `arguments`、`locals`、ST/梯形图 `body`，可以作为“真实工程里 FB 长什么样”的依据

引用时请标出资料类型：手册讲**语法与约束**，教材讲**方法与步骤**，示例程序/工程快照是**参考实现**。
三类证据的效力不同，不要用示例程序的写法去否定手册的语法说明。"""
    out = []
    for key, title, text in (("naming", "变量命名规范：教材版 vs KVX样例程序版", naming),
                             ("assets", "知识库资料构成：教材/示例程序/工程快照", assets),
                             ("layers", "标准化程序的分层结构（KVX样例程序_v100）", LAYERS)):
        cid = f"x:note:{key}"
        out.append(dict(chunk_id=cid, parent_id=cid, part=1, parts=1, title=title,
                        section="知识库使用说明", doc="KB 使用说明", source=f"KB 使用说明#{key}",
                        source_type="kb_note", series="", text=text,
                        keywords="convention=both", extractor="curated"))
    return out


# ---------------------------------------------------------------- writer
def write(rows: list[dict], db: Path) -> dict:
    conn = sqlite3.connect(db)
    conn.execute("delete from chunks where chunk_id like 'x:%'")
    stats = {}
    for r in rows:
        stats[r["source_type"]] = stats.get(r["source_type"], 0) + 1
        conn.execute("""insert or replace into chunks
            (chunk_id,parent_id,part,parts,title,section,doc,source,source_type,series,text,
             keywords,also_in,sort_key,extractor)
            values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                     (r["chunk_id"], r["parent_id"], r["part"], r["parts"], r["title"],
                      r["section"], r["doc"], r["source"], r["source_type"], r["series"],
                      r["text"], r["keywords"], "", "", r["extractor"]))
    conn.commit()
    total = conn.execute("select count(*) from chunks").fetchone()[0]
    conn.close()
    stats["total_chunks"] = total
    return stats


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", type=Path, default=DB)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--only", choices=["textbook", "program", "snapshot", "note"], default=None)
    a = ap.parse_args()
    rows: list[dict] = []
    if a.only in (None, "textbook"):
        rows += textbook_chunks()
    if a.only in (None, "program"):
        rows += program_example_chunks()
    if a.only in (None, "snapshot"):
        rows += snapshot_chunks()
    if a.only in (None, "note"):
        rows += note_chunks()
    by_type = {}
    for r in rows:
        by_type.setdefault(r["source_type"], []).append(r)
    print("generated chunks:", {k: len(v) for k, v in by_type.items()}, "total", len(rows))
    for t, rs in by_type.items():
        print(f"\n--- {t}: {len(rs)} chunks; samples:")
        for r in rs[:3]:
            print(f"   {r['chunk_id']} | {r['title'][:60]} | {len(r['text'])} chars | {r['source'][:70]}")
    if a.dry_run:
        return
    print("\nwritten:", write(rows, a.db))


if __name__ == "__main__":
    main()
