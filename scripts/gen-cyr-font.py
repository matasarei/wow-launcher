#!/usr/bin/env python3
"""Remap a TTF so CP1251 Cyrillic byte positions (as Latin-1 codepoints
U+00C0-U+00FF, plus Ё/ё at U+00A8/U+00B8) render Cyrillic glyphs.

The 3.3.5a enUS-based client inserts chat input bytes as Latin-1 codepoints
without conversion; fonts remapped this way make typed Cyrillic render
correctly (the classic community fix). Proper Unicode Cyrillic (e.g. server
messages) keeps rendering normally. Trade-off: à-ÿ show as Cyrillic.

Usage: gen-cyr-font.py <in.ttf> <out.ttf>
"""
import sys
from fontTools.ttLib import TTFont

src, dst = sys.argv[1], sys.argv[2]
f = TTFont(src)
best = f.getBestCmap()
mapping = {0xC0 + i: 0x410 + i for i in range(0x40)}  # А..я
mapping[0xA8] = 0x401  # Ё
mapping[0xB8] = 0x451  # ё
n = 0
for t in f['cmap'].tables:
    if not t.isUnicode():
        continue
    for dst_cp, src_cp in mapping.items():
        g = best.get(src_cp)
        if g:
            t.cmap[dst_cp] = g
            n += 1
f.save(dst)
print(f"{dst}: remapped ({n} cmap entries)")
