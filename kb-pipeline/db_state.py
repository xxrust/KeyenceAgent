"""Quick state dump of the wiki.v3m.db after an ingest or rebuild (diagnostic)."""
import sqlite3
import sys

db = sys.argv[1] if len(sys.argv) > 1 else r"H:\llm-wiki-v2-keyence\v3\wiki.v3m.db"
c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
print("chunks total:", c.execute("select count(*) from chunks").fetchone()[0])
print("x: rows:", dict(c.execute(
    "select source_type, count(*) from chunks where chunk_id like 'x:%' group by 1")))
print("by source_type:", dict(c.execute("select source_type, count(*) from chunks group by 1 order by 2 desc")))
print("cards:", c.execute("select count(*) from cards").fetchone()[0],
      "| vectors:", c.execute("select model, n from vectors").fetchall())
print("note assets length:", c.execute(
    "select length(text) from chunks where chunk_id='x:note:assets'").fetchone())
