"""Render selected PDF pages to PNG for visual verification.
usage: python -I render_pages.py <pdf> <first> <last> [zoom]   (1-based PDF page numbers)
Output: selection/pages/<pdfstem>_p<N>.png ; also prints the printed header text of each page."""
import sys
from pathlib import Path
import fitz

MAN = Path(r"C:\Users\Public\Documents\KEYENCE\KVS12\ManualHelp\2052")
OUT = Path(__file__).resolve().parent / "pages"
name, a, b = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
zoom = float(sys.argv[4]) if len(sys.argv) > 4 else 1.6
doc = fitz.open(MAN / name)
print(name, "pages:", len(doc))
OUT.mkdir(exist_ok=True)
for n in range(a, b + 1):
    page = doc[n - 1]
    png = OUT / f"{Path(name).stem}_p{n}.png"
    page.get_pixmap(matrix=fitz.Matrix(zoom, zoom)).save(png)
    txt = " ".join(page.get_text().split())[:90]
    print(n, png.name, "|", txt)
