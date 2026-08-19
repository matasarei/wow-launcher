#!/usr/bin/env python3
"""Extract the client's own locale fonts from its MPQ archive and add the
CP1251 input remap (Cyrillic glyphs at Latin-1 positions U+00C0-U+00FF,
Ё/ё at U+00A8/U+00B8). Writes FRIZQT__.TTF, ARIALN.TTF, MORPHEUS.TTF,
skurri.ttf into the output dir. Requires the mpyq and fonttools modules;
exits non-zero when they're missing, extraction fails, or the client's
fonts have no Cyrillic glyphs (e.g. enUS clients).

Usage: wow-client-fonts.py <game-dir> <out-dir>
"""
import sys, os, glob, io

try:
    from mpyq import MPQArchive
    from fontTools.ttLib import TTFont
except ImportError:
    sys.exit(1)

game, out = sys.argv[1], sys.argv[2]
locales = [os.path.basename(p.rstrip('/')) for p in glob.glob(f'{game}/Data/????/')]
if not locales:
    sys.exit(1)
loc = locales[0]
mpq_path = f'{game}/Data/{loc}/locale-{loc}.MPQ'
if not os.path.exists(mpq_path):
    sys.exit(1)

MAPPING = {0xC0 + i: 0x410 + i for i in range(0x40)}
MAPPING[0xA8] = 0x401
MAPPING[0xB8] = 0x451

def remap(data):
    f = TTFont(io.BytesIO(data))
    best = f.getBestCmap()
    if 0x410 not in best:      # no Cyrillic glyphs in this font
        return None
    for t in f['cmap'].tables:
        if not t.isUnicode():
            continue
        for dst_cp, src_cp in MAPPING.items():
            g = best.get(src_cp)
            if g:
                t.cmap[dst_cp] = g
    buf = io.BytesIO()
    f.save(buf)
    return buf.getvalue()

archive = MPQArchive(mpq_path, listfile=True)
wanted = {
    b'Fonts\\FRIZQT__.TTF': 'FRIZQT__.TTF',
    b'Fonts\\ARIALN.TTF':   'ARIALN.TTF',
    b'Fonts\\MORPHEUS.TTF': 'MORPHEUS.TTF',
    b'Fonts\\SKURRI.TTF':   'skurri.ttf',
}
# All-or-nothing: a partial font set is worse than none (e.g. enUS ARIALN has
# Cyrillic but FRIZQT/MORPHEUS/SKURRI don't — installing just one leaves the UI
# half-remapped). Collect everything first; write only when all four succeed.
results = {}
for src, dst in wanted.items():
    try:
        data = archive.read_file(src)
    except Exception:
        data = None
    if not data:
        continue
    remapped = remap(data)
    if remapped:
        results[dst] = remapped
if len(results) != 4:
    sys.exit(1)
os.makedirs(out, exist_ok=True)
for dst, data in results.items():
    open(f'{out}/{dst}', 'wb').write(data)
sys.exit(0)
