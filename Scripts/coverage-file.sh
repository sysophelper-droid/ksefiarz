#!/bin/bash
# Pokrycie pojedynczego pliku źródłowego (linie z zerowym trafieniem).
# Użycie: ./Scripts/coverage-file.sh Sources/.../Plik.swift
# Wymaga wcześniejszego: swift test --enable-code-coverage
set -e
FILE="$1"
BIN="$(swift build --show-bin-path)"
PROF="$BIN/codecov/default.profdata"
XCTEST="$BIN/KsefiarzPackageTests.xctest/Contents/MacOS/KsefiarzPackageTests"
echo "=== Podsumowanie ==="
xcrun llvm-cov report "$XCTEST" -instr-profile="$PROF" "$FILE" 2>/dev/null | grep -E "Filename|TOTAL|$(basename "$FILE")"
echo "=== Linie nieodwiedzone (count 0) ==="
xcrun llvm-cov show "$XCTEST" -instr-profile="$PROF" "$FILE" --show-line-counts 2>/dev/null \
  | awk -F'|' '$2 ~ /^[[:space:]]*0[[:space:]]*$/ {print $1"|"$3}'
