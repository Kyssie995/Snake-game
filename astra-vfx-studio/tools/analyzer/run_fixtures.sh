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
#   6. --project default.project.json: Instanznamen aus der Projektdatei ("Lib" = src/, "Tools" = $className-Folder,
#      Einzeldatei-$path, JSON-Modul). Gute Dateien inkl. project/Consumer.luau fehlerfrei; Fehler nur in
#      Broken.luau und project/Misnamed.luau (Verzeichnisname statt Instanzname), jeweils exakt wie markiert.
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

MISNAMED="project/Misnamed.luau"

# Erwartete "Datei Zeile Code"-Tripel aus den "-- EXPECT <Code>"-Markierungen der angegebenen Dateien
expected_for() {
    for f in "$@"; do
        grep -n -- '-- EXPECT ' "$f" | sed -E "s|^([0-9]+):.*-- EXPECT ([A-Za-z]+).*|$f \\1 \\2|"
    done | sort -u
}
# Tatsaechliche "Datei Zeile Code"-Tripel aller Fehler einer Textausgabe
actual_errors() {
    grep -E '^[^:]+:[0-9]+:[0-9]+: error: ' "$1" | sed -E 's/^([^:]+):([0-9]+):[0-9]+: error: .*\[([A-Za-z]+)\]$/\1 \2 \3/' | sort -u
}
compare_errors() { # $1 = Ausgabe, Rest = Dateien mit EXPECT-Markierungen
    local out="$1"
    shift
    expected_for "$@" >"$TMP/expected.txt"
    actual_errors "$out" >"$TMP/actual.txt"
    if diff -u "$TMP/expected.txt" "$TMP/actual.txt" >"$TMP/diff.txt"; then
        pass "Fehler (Datei, Zeile, Code) entsprechen exakt den EXPECT-Markierungen ($(wc -l <"$TMP/expected.txt") Stellen)"
    else
        fail "Fehler weichen von den EXPECT-Markierungen ab (- erwartet, + tatsaechlich):"
        sed 's/^/        /' "$TMP/diff.txt"
    fi
}

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

    compare_errors "$TMP/all.txt" "$BROKEN"

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

    # 6. --project
    PCOMMON=(--defs "$DEFS" --project default.project.json --solver="$SOLVER" --quiet)
    # shellcheck disable=SC2086
    "$BIN" "${PCOMMON[@]}" $GOOD_FILES project/Consumer.luau >"$TMP/pgood.txt" 2>&1
    rc=$?
    if [ $rc -eq 0 ] && [ ! -s "$TMP/pgood.txt" ]; then
        pass "--project: gute Dateien inkl. project/Consumer.luau fehlerfrei"
    else
        fail "--project: gute Dateien: Exit $rc, Ausgabe:"
        sed 's/^/        /' "$TMP/pgood.txt"
    fi
    "$BIN" "${PCOMMON[@]}" >"$TMP/pall.txt" 2>&1
    rc=$?
    echo "  --- Ausgabe --project (nur project/) ---"
    grep '^project/' "$TMP/pall.txt" | sed 's/^/    /'
    echo "  ---"
    if [ $rc -eq 1 ]; then pass "--project Gesamtlauf: Exit 1"; else fail "--project Gesamtlauf: Exit $rc (erwartet 1)"; fi
    compare_errors "$TMP/pall.txt" "$BROKEN" "$MISNAMED"
    if grep -F "$MISNAMED:3:" "$TMP/pall.txt" | grep -qF "'src' is not a child of Folder 'AstraFixture'"; then
        pass "Verzeichnisname statt Instanzname wird erkannt"
    else
        fail "Misnamed.luau: erwartete Meldung fehlt"
    fi
done

echo
if [ $FAILURES -eq 0 ]; then
    echo "ALLE FIXTURE-PRUEFUNGEN BESTANDEN"
    exit 0
fi
echo "$FAILURES PRUEFUNG(EN) FEHLGESCHLAGEN"
exit 1
