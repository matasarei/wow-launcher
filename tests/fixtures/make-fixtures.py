#!/usr/bin/env python3
"""Generate the hermetic font fixtures for tests/run-tests.sh:

  tests/fixtures/locale-ruRU.MPQ   four synthetic TTFs WITH Cyrillic glyphs
  tests/fixtures/locale-enUS.MPQ   four synthetic TTFs WITHOUT Cyrillic

Synthetic = generated here from scratch (square outlines, no Blizzard data),
packed into a minimal MPQ exactly the way the real locale archives store the
fonts (v0 header, 4 KB zlib sectors, sector CRC table, encrypted hash/block
tables). Dev-only: needs fontTools; the committed archives are what the test
suite uses. Re-run after changing the layout: python3 tests/fixtures/make-fixtures.py
"""
import os, struct, zlib
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

HERE = os.path.dirname(os.path.abspath(__file__))

# ------------------------------------------------------------------ fonts
def square(w):
    pen = TTGlyphPen(None)
    pen.moveTo((50, 0)); pen.lineTo((50, 600)); pen.lineTo((w - 50, 600)); pen.lineTo((w - 50, 0)); pen.closePath()
    return pen.glyph()

def make_font(name, cps, shuffle):
    """A TTF mapping every codepoint in cps to its own glyph. shuffle=True
    scrambles the glyph order so cmap segments need idRangeOffset/glyphIdArray
    (exercises the non-trivial format 4 path)."""
    names = ['uni%04X' % cp for cp in cps]
    if shuffle:
        names = names[::-1]
    order = ['.notdef', 'space'] + names
    cmap = {0x20: 'space'}
    cmap.update({cp: 'uni%04X' % cp for cp in cps})
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap(cmap)
    glyphs = {'.notdef': square(500), 'space': TTGlyphPen(None).glyph()}
    for i, n in enumerate(names):
        glyphs[n] = square(400 + (i % 7) * 30)
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics({n: (600, 50) for n in order})
    fb.setupHorizontalHeader(ascent=800, descent=-200)
    fb.setupNameTable({'familyName': name, 'styleName': 'Regular'})
    fb.setupOS2()
    fb.setupPost()
    path = os.path.join(HERE, name + '.tmp.ttf')
    fb.save(path)
    data = open(path, 'rb').read()
    os.remove(path)
    return data

LATIN = list(range(0x41, 0x5B)) + list(range(0x61, 0x7B)) + list(range(0x30, 0x3A))
CYRILLIC = list(range(0x410, 0x450)) + [0x401, 0x451, 0x406, 0x456, 0x407, 0x457, 0x404, 0x454, 0x490, 0x491, 0x40E, 0x45E, 0x2116]

# ------------------------------------------------------------------ MPQ writer
def crypt_table():
    t = [0] * 0x500
    seed = 0x00100001
    for i in range(0x100):
        j = i
        for _ in range(5):
            seed = (seed * 125 + 3) % 0x2AAAAB; a = (seed & 0xFFFF) << 16
            seed = (seed * 125 + 3) % 0x2AAAAB; b = seed & 0xFFFF
            t[j] = a | b
            j += 0x100
    return t

T = crypt_table()

def mpq_hash(s, kind):
    s1, s2 = 0x7FED7FED, 0xEEEEEEEE
    for ch in s.upper().replace('/', '\\').encode():
        s1 = T[(kind << 8) + ch] ^ ((s1 + s2) & 0xFFFFFFFF)
        s2 = (ch + s1 + s2 + (s2 << 5) + 3) & 0xFFFFFFFF
    return s1

def encrypt(words, key):
    s1, s2 = key, 0xEEEEEEEE
    out = []
    for v in words:
        s2 = (s2 + T[0x400 + (s1 & 0xFF)]) & 0xFFFFFFFF
        out.append(v ^ ((s1 + s2) & 0xFFFFFFFF))
        s1 = ((((~s1) & 0xFFFFFFFF) << 0x15) + 0x11111111) & 0xFFFFFFFF | (s1 >> 0x0B)
        s2 = (v + s2 + (s2 << 5) + 3) & 0xFFFFFFFF
    return out

SECTOR = 4096
FLAGS = 0x80000000 | 0x200 | 0x04000000   # EXISTS | COMPRESS | SECTOR_CRC (as in the real archives)

def pack_file(data):
    sectors = [data[i:i + SECTOR] for i in range(0, len(data), SECTOR)] or [b'']
    blobs, crcs = [], []
    for s in sectors:
        z = b'\x02' + zlib.compress(s, 9)
        blobs.append(z if len(z) < len(s) else s)
        crcs.append(zlib.crc32(s) & 0xFFFFFFFF)
    crc_blob = struct.pack('<%dI' % len(crcs), *crcs)
    blobs.append(crc_blob)
    table_len = 4 * (len(blobs) + 1)
    positions, pos = [], table_len
    for b in blobs:
        positions.append(pos); pos += len(b)
    positions.append(pos)
    return struct.pack('<%dI' % len(positions), *positions) + b''.join(blobs)

def write_mpq(path, files):
    HASH_N = 16
    header_size = 32
    body = b''
    blocks = []
    for name, data in files:
        packed = pack_file(data)
        blocks.append((header_size + len(body), len(packed), len(data), FLAGS))
        body += packed
    hash_tab = [(0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF)] * HASH_N
    for idx, (name, _) in enumerate(files):
        i = mpq_hash(name, 0) & (HASH_N - 1)
        while hash_tab[i][3] != 0xFFFFFFFF:
            i = (i + 1) & (HASH_N - 1)
        hash_tab[i] = (mpq_hash(name, 1), mpq_hash(name, 2), 0, idx)   # locale/platform = 0
    hash_words = encrypt([w for e in hash_tab for w in e], mpq_hash('(hash table)', 3))
    block_words = encrypt([w for e in blocks for w in e], mpq_hash('(block table)', 3))
    hash_off = header_size + len(body)
    block_off = hash_off + 16 * HASH_N
    total = block_off + 16 * len(blocks)
    header = b'MPQ\x1a' + struct.pack('<IIHHIIII', header_size, total, 0, 3, hash_off, block_off, HASH_N, len(blocks))
    with open(path, 'wb') as f:
        f.write(header + body + struct.pack('<%dI' % len(hash_words), *hash_words) + struct.pack('<%dI' % len(block_words), *block_words))

NAMES = ['FRIZQT__', 'ARIALN', 'MORPHEUS', 'SKURRI']
for locale, cps in (('ruRU', LATIN + CYRILLIC), ('enUS', LATIN)):
    files = [('Fonts\\%s.TTF' % n, make_font('Fixture %s %s' % (n, locale), cps, shuffle=(i % 2 == 0))) for i, n in enumerate(NAMES)]
    files.append(('(listfile)', '\r\n'.join(n for n, _ in files).encode()))
    out = os.path.join(HERE, 'locale-%s.MPQ' % locale)
    write_mpq(out, files)
    print(out, os.path.getsize(out), 'bytes')
