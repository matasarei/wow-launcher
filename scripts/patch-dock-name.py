#!/usr/bin/env python3
"""Patch the bare 'wine\\0' process-name constant in winerosetta's ntdll.so to
'WoW \\0' so the game's Dock entry shows 'WoW' instead of 'wine'. Idempotent;
verifies the expected bytes before writing. Cosmetic only."""
import sys
OFFSET = 627328
path = sys.argv[1]
data = bytearray(open(path, "rb").read())
cur = bytes(data[OFFSET:OFFSET+5])
if cur == b"WoW \x00":
    print("dock name already patched")
elif cur == b"wine\x00":
    data[OFFSET:OFFSET+5] = b"WoW \x00"
    open(path, "wb").write(data)
    print("dock name patched")
else:
    print(f"unexpected bytes at {OFFSET}: {cur!r} — skipping (different ntdll build; cosmetic patch not applied)")
