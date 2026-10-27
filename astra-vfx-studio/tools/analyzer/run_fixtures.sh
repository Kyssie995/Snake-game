#!/usr/bin/env bash
# Prueft astra-analyze gegen das Fixture-Projekt in fixtures/src.
#
#   ./run_fixtures.sh                      # Standard: /root/tools/bin/astra-analyze + /root/tools/ref/globalTypes.d.luau
#   ASTRA_ANALYZE=./build/astra-analyze ASTRA_DEFS=/pfad/globalTypes.d.luau ./run_fixtures.sh
#
# Erwartungen:
#   1. Alle "guten" Dateien (alles ausser Effects/Broken.luau) liefern 0 Diagnosen, Exit-Code 0.
#   2. Der Gesamtlauf liefert Exit-Code 1; ALLE Fehler liegen in Effects/Broken.luau und die Menge
#      (Zeile, Fehlercode) entspricht exakt den "-- EXPECT <Code>"-Markierungen in dieser Datei.
#   3. Zusaetzliche Textfragmente (Tippfehler-Vorschlag, modulübergreifender Typ, ...) sind enthalten.
#   4. Shared/Loose.luau (--!nonstrict) ist im Standardlauf fehlerfrei, mit --force-strict nicht.
#   5. --json liefert gueltiges JSON mit identischen Fehlern.
# Alles wird fuer den alten (Standard) und den neuen Luau-Solver geprueft.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${ASTRA_ANALYZE:-/root/tools/bin/astra-analyze}"
DEFS="${ASTRA_DEFS:-/root/tools/ref/globalTypes.d.luau}"
SOLVERS="${ASTRA_SOLVERS:-old new}"

cd "$HERE/fixtures" || exit 2

if [ ! -x "$BIN" ]; then
    echo "astra-analyze nicht gefunden: $BIN (ASTRA_ANALYZE setzen)" >&2
    exit 2
fi
if [ ! -f "$DEFS" ]; then
    echo "Definitionsdatei nicht gefunden: $DEFS (ASTRA_DEFS setzen)" >&2
    exit 2
fi

BROKEN="src/Effects/Broken.luau"
FAILURES=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
    echo "  FAIL: $*"
    FAILURES=$((FAILURES + 1))
}
pass() {
    echo "  ok:   $*"
}

# Erwartete (Zeile, Code)-Paare aus den Markierungen in Broken.luau
grep -n -- '-- EXPECT ' "$BROKEN" | sed -E 's/^([0-9]+):.*-- EXPECT ([A-Za-z]+).*/\1 \2/' | sort -u >"$TMP/expected.txt"

GOOD_FILES=$(find src -type f \( -name '*.luau' -o -name '*.lua' \) ! -path "$BROKEN" | sort)

for SOLVER in $SOLVERS; do
    echo "== Solver: $SOLVER =="
    COMMON=(--defs "$DEFS" --root src --solver="$SOLVER" --quiet)

    # 1. gute Dateien
    # shellcheck disable=SC2086
    "$BIN" "${COMMON[@]}" $GOOD_FILES >"$TMP/good.txt" 2>&1
    rc=$?
    if [ $rc -eq 0 ] && [ ! -s "$TMP/good.txt" ]; then
        pass "gute Dateien: Exit 0, keine Diagnosen ($(echo "$GOOD_FILES" | wc -l) Dateien)"
    else
        fail "gute Dateien: Exit $rc, Ausgabe:"
        sed 's/^/        /' "$TMP/good.txt"
    fi

    # 2. Gesamtlauf
    "$BIN" "${COMMON[@]}" >"$TMP/all.txt" 2>&1
    rc=$?
    echo "  --- Ausgabe Gesamtlauf ---"
    sed 's/^/    /' "$TMP/all.txt"
    echo "  ---"
    if [ $rc -eq 1 ]; then pass "Gesamtlauf: Exit 1"; else fail "Gesamtlauf: Exit $rc (erwartet 1)"; fi

    if grep ': error: ' "$TMP/all.txt" | grep -v "^$BROKEN:" >"$TMP/stray.txt"; then
        fail "Fehler ausserhalb von $BROKEN:"
        sed 's/^/        /' "$TMP/stray.txt"
    else
        pass "alle Fehler liegen in $BROKEN"
    fi

    grep "^$BROKEN:[0-9]*:[0-9]*: error: " "$TMP/all.txt" |
        sed -E 's/^[^:]+:([0-9]+):[0-9]+: error: .*\[([A-Za-z]+)\]$/\1 \2/' | sort -u >"$TMP/actual.txt"
    if diff -u "$TMP/expected.txt" "$TMP/actual.txt" >"$TMP/diff.txt"; then
        pass "(Zeile, Code) entspricht exakt den EXPECT-Markierungen ($(wc -l <"$TMP/expected.txt") Stellen)"
    else
        fail "(Zeile, Code) weicht von den EXPECT-Markierungen ab (- erwartet, + tatsaechlich):"
        sed 's/^/        /' "$TMP/diff.txt"
    fi

    # 3. Textfragmente
    while IFS='|' read -r line fragment; do
        if grep -F "$BROKEN:$line:" "$TMP/all.txt" | grep -qF -- "$fragment"; then
            pass "Zeile $line enthaelt: $fragment"
        else
            fail "Zeile $line ohne erwarteten Text: $fragment"
        fi
    done <<'EOF'
10|Key 'Ratee' not found in external type 'ParticleEmitter' (did you mean 'Rate'?)
11|Expected this to be 'number', but got 'string'
14|Expected this to be 'ColorSequence', but got 'Color3'
16|Expected this to be 'string', but got 'number'
17|Key 'DefaultRatee' not found in table 'Config' (did you mean 'DefaultRate'?)
18|Expected this to be 'number', but got 'string'
19|Expected this to be 'Attachment', but got 'ParticleEmitter'
22|Value of type 'Instance?' could be nil
24|'PartcleEmitter' is not a valid Roblox class name for Instance.new (did you mean 'ParticleEmitter'?)
25|Key 'Neonn' not found
26|Unknown require: 'DoesNotExist' is not a child of ModuleScript 'Effects'
27|'TweenServce' is not a valid Roblox service name (did you mean 'TweenService'?)
EOF

    # 4. Modus pro Datei / --force-strict
    "$BIN" "${COMMON[@]}" src/Shared/Loose.luau >"$TMP/loose.txt" 2>&1
    rc1=$?
    "$BIN" "${COMMON[@]}" --force-strict src/Shared/Loose.luau >"$TMP/loose-strict.txt" 2>&1
    rc2=$?
    if [ $rc1 -eq 0 ] && [ $rc2 -eq 1 ] && grep -q "src/Shared/Loose.luau:5:.*Gravityy.*\[UnknownProperty\]" "$TMP/loose-strict.txt"; then
        pass "--!nonstrict wird respektiert, --force-strict meldet Loose.luau:5"
    else
        fail "--!nonstrict/--force-strict: Exit $rc1/$rc2"
        sed 's/^/        /' "$TMP/loose.txt" "$TMP/loose-strict.txt"
    fi

    # 5. JSON
    "$BIN" "${COMMON[@]}" --json >"$TMP/all.json" 2>/dev/null
    if command -v python3 >/dev/null 2>&1; then
        if python3 -I - "$TMP/all.json" "$(grep -c ': error: ' "$TMP/all.txt")" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
errors = [d for d in data["diagnostics"] if d["severity"] == "error"]
assert len(errors) == int(sys.argv[2]), (len(errors), sys.argv[2])
assert data["summary"]["errors"] == len(errors)
assert all(d["file"].endswith("Effects/Broken.luau") for d in errors)
PY
        then pass "--json ist gueltig und konsistent"; else fail "--json ungueltig/inkonsistent"; fi
    fi
done

echo
if [ $FAILURES -eq 0 ]; then
    echo "ALLE FIXTURE-PRUEFUNGEN BESTANDEN"
    exit 0
fi
echo "$FAILURES PRUEFUNG(EN) FEHLGESCHLAGEN"
exit 1
