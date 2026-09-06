#!/bin/bash
# Localization consistency check — the failure mode AGENTS.md warns about is
# silent: a key missing from one .strings file falls back to English, which
# looks right in en and leaves that language untranslated forever.
#
# Three things are checked, all of them hard failures:
#   1. every .strings file parses (plutil -lint);
#   2. all languages carry exactly the same key set;
#   3. every user-facing literal in main.swift has a key, and every key is
#      still used by main.swift.
#
# Run: make check-strings   (also part of make test)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/main.swift"
LPROJ="$ROOT/assets/lproj"
EN="$LPROJ/en.lproj/Localizable.strings"
fail=0
bad() { fail=$((fail + 1)); echo "  ✗ $*"; }

keys_of() {  # keys_of <strings file> — one key per line, sorted
  sed -nE 's/^"(([^"]|\\")*)" = .*/\1/p' "$1" | sort
}

# --- 1. every file parses --------------------------------------------------
for f in "$LPROJ"/*.lproj/Localizable.strings; do
  plutil -lint "$f" >/dev/null 2>&1 || bad "does not parse: ${f#$ROOT/}"
done

# --- 2. the same keys everywhere -------------------------------------------
# en is the reference: its keys are the English strings themselves.
keys_of "$EN" > "$ROOT/.strings-en.tmp"
for f in "$LPROJ"/*.lproj/Localizable.strings; do
  [ "$f" = "$EN" ] && continue
  lang="$(basename "$(dirname "$f")" .lproj)"
  keys_of "$f" > "$ROOT/.strings-x.tmp"
  while read -r k; do
    [ -n "$k" ] && bad "$lang is missing a key: \"$k\""
  done < <(comm -23 "$ROOT/.strings-en.tmp" "$ROOT/.strings-x.tmp")
  while read -r k; do
    [ -n "$k" ] && bad "$lang has a key en does not: \"$k\""
  done < <(comm -13 "$ROOT/.strings-en.tmp" "$ROOT/.strings-x.tmp")
done

# --- 3a. every localized literal has a key ---------------------------------
# The call sites that localize: L()/LF() explicitly, plus the SwiftUI views and
# modifiers that localize a literal argument on their own. String interpolation
# becomes %@, which is how it is written in the .strings files.
#
# NEVER_TRANSLATED are literals that reach one of those call sites and are meant
# to read the same in every language — the app's own name, a brand, a licence
# line. They fall back to English by design, which is the correct rendering.
NEVER_TRANSLATED='^(WoW Launcher|GitHub|MIT License · © [0-9]{4} .*)$'

grep -oE '(\bL|\bLF|\bText|\bButton|\bLabel|\bSection|\bPicker|\bLink|\bToggle|\bLabeledContent|\.help|\.confirmationDialog)\( *"[^"]*"' "$SRC" \
  | sed -E 's/^[^"]*"//; s/"$//' \
  | sed -E 's/\\\([^)]*\)/%@/g' \
  | grep -vE "$NEVER_TRANSLATED" \
  | sort -u > "$ROOT/.strings-used.tmp"

while read -r k; do
  [ -n "$k" ] && bad "used in main.swift but has no key: \"$k\""
done < <(comm -23 "$ROOT/.strings-used.tmp" "$ROOT/.strings-en.tmp")

# --- 3b. every key is still reachable from the code ------------------------
# Checked against any quoted literal in main.swift, not just the call sites
# above: some strings reach the UI indirectly (the tab titles are an enum's raw
# values), and a key that is merely hard to trace is not a dead key.
while read -r k; do
  [ -z "$k" ] && continue
  # A key whose %@ came from SwiftUI interpolation has no literal form in the
  # source, so fall back to matching everything before the first placeholder.
  probe="$(printf '%s' "$k" | sed -E 's/%@.*$//')"
  grep -qF "\"$k\"" "$SRC" || { [ -n "$probe" ] && grep -qF "\"$probe" "$SRC"; } \
    || bad "key is no longer used by main.swift: \"$k\""
done < "$ROOT/.strings-en.tmp"

rm -f "$ROOT/.strings-en.tmp" "$ROOT/.strings-x.tmp" "$ROOT/.strings-used.tmp"

n=$(grep -c '^"' "$EN")
langs=$(find "$LPROJ" -name Localizable.strings | wc -l | tr -d ' ')
if [ "$fail" -eq 0 ]; then
  echo "strings: OK — $n keys × $langs languages, all present and all used"
else
  echo "strings: $fail problem(s)"
  exit 1
fi
