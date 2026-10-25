"""Colonist in an EVA-style pressure suit, realistic adult proportions (replaces the chibi villager).

Run: python3 tools/colonist.py <out_dir> [preview]
Writes <out_dir>/villager.glb (the game loads that name) and, with "preview", colonist_preview.png.
Uses the helpers (materials, lathe, sphere, box, ...) from tools/villager.py and the body in
tools/colonist_body.py; node names match what scripts/world/villager.gd animates and tints.
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, "villager.py")).read()
helpers = src.split("# ---------------- body ----------------")[0]
exec(compile(helpers, "villager.py", "exec"))
exec(compile(open(os.path.join(HERE, "colonist_body.py")).read(), "colonist_body.py", "exec"))
