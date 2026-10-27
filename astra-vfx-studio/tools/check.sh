#!/usr/bin/env bash
# Runs every automated check of ASTRA VFX Studio. Exit code != 0 if any check fails.
#
#   tools/check.sh            # all checks
#   tools/check.sh --quick    # syntax + tests only
#
# Tools (see rokit.toml): lune, rojo, selene, stylua, and astra-analyze (tools/analyzer, optional).
# Environment overrides: ASTRA_ANALYZE (binary), ASTRA_DEFS (Roblox definitions file).

set -u
cd "$(dirname "$0")/.."

QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

ANALYZE="${ASTRA_ANALYZE:-$(command -v astra-analyze || echo /root/tools/bin/astra-analyze)}"
DEFS="${ASTRA_DEFS:-/root/tools/ref/globalTypes.d.luau}"

failed=()
run() {
	local name="$1"
	shift
	echo "── $name"
	if "$@"; then
		echo "   ✓ $name"
	else
		echo "   ✗ $name"
		failed+=("$name")
	fi
}

run "syntax" lune run tools/syntax-check.luau -- src tests tools
run "tests" lune run tests/lune/run.luau

if [ "$QUICK" = 0 ]; then
	if [ -x "$ANALYZE" ] && [ -f "$DEFS" ]; then
		run "types (astra-analyze)" "$ANALYZE" --defs "$DEFS" --project default.project.json --quiet
	else
		echo "── types: SKIPPED (astra-analyze or definitions not found; see tools/analyzer/README.md)"
	fi
	run "lint (selene)" selene --display-style quiet src tests/framework tests/specs tools
	run "format (stylua)" stylua --check src tests tools
	mkdir -p build
	run "build plugin (rojo)" rojo build default.project.json -o build/AstraVFXStudio.rbxmx
	run "build runtime (rojo)" rojo build runtime.project.json -o build/AstraVFX.rbxm
fi

echo
if [ ${#failed[@]} -eq 0 ]; then
	echo "ALL CHECKS PASSED"
	exit 0
else
	echo "FAILED: ${failed[*]}"
	exit 1
fi
