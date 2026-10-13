"""Builds fonts/NotoSansTC-UI.ttf: Noto Sans TC (OFL) cut down to the characters the game uses.

Usage:  python3 tools/subset_font.py <path to NotoSansTC[wght].ttf>
Get the source font from https://github.com/google/fonts/tree/main/ofl/notosanstc .
Re-run whenever Chinese text is added (scripts/game/loc.gd etc.). Needs `pip install fonttools`.
"""
import glob, os, sys
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools import subset

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "fonts", "NotoSansTC-UI.ttf")

chars = set(chr(c) for c in range(0x20, 0x7F))
chars |= set("·²×–—…•→←↑↓°％：；，。！？（）「」『』、")
for f in glob.glob(os.path.join(ROOT, "scripts", "**", "*.gd"), recursive=True):
    with open(f, encoding="utf8") as fh:
        chars |= {ch for ch in fh.read() if ord(ch) > 0x7F}

font = TTFont(sys.argv[1])
if "fvar" in font:
    font = instancer.instantiateVariableFont(font, {"wght": 500})
opts = subset.Options()
opts.layout_features = ["*"]
opts.name_IDs = ["*"]
opts.notdef_outline = True
sub = subset.Subsetter(opts)
sub.populate(text="".join(sorted(chars)))
sub.subset(font)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
font.save(OUT)
print(f"{len(chars)} characters -> {OUT} ({os.path.getsize(OUT) // 1024} KB)")
