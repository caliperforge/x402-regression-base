#!/usr/bin/env bash
# run.sh - one-command runner for x402-regression-base M1.
#
# 1. Detect missing `forge`; print a single install line and exit non-zero.
# 2. Initialise submodules recursively (if .gitmodules exists).
# 3. forge build.
# 4. Run clean/planted matrix:
#    - test/V*/**/*.t.sol clean legs must pass; must NOT emit INVARIANT VIOLATED.
#    - test/planted/*.planted.t.sol planted legs must fire INVARIANT VIOLATED
#      AND exit non-zero.
# 5. Print a summary block.
# 6. Exit 0 iff all clean pass AND all planted fire; non-zero otherwise.
#
# Live-chain modes: `--live-sepolia` (W2) and `--live-mainnet` (W6) delegate
# to `ci/live_sepolia.sh` / `ci/live_mainnet.sh` (same runner, chain-label
# derives from basename). Those runners deploy + fire one clean settle +
# capture Basescan tx hashes into `docs/basescan/<chain>_run_<date>.md`.
# Unknown flags fall through to the local twin matrix.
#
# Bash 3.2 compatible (macOS default). Tested on ubuntu-latest CI.

set -uo pipefail

log()  { printf '[run.sh] %s\n' "$*" >&2; }
fail() { printf '[run.sh] FAIL: %s\n' "$*" >&2; exit 1; }

# --- Step 0: live-chain routing ----------------------------------------

case "${1:-}" in
    --live-sepolia)
        exec ./ci/live_sepolia.sh
        ;;
    --live-mainnet)
        exec ./ci/live_mainnet.sh
        ;;
esac

# --- Step 1: dep detect --------------------------------------------------

if ! command -v forge >/dev/null 2>&1; then
    cat >&2 <<'EOF'
[run.sh] FAIL: `forge` (Foundry) is required but not installed.

Install Foundry with:

    curl -L https://foundry.paradigm.xyz | bash && foundryup

See https://book.getfoundry.sh/getting-started/installation for details.
This script does not `curl | sh` on your behalf.
EOF
    exit 2
fi

if ! command -v git >/dev/null 2>&1; then
    fail "\`git\` is required but not installed."
fi

# --- Step 2: submodules --------------------------------------------------

if [ -f .gitmodules ] && [ -d .git ]; then
    log "Initialising submodules recursively..."
    git submodule update --init --recursive || fail "git submodule update failed."
fi

# --- Step 3: build -------------------------------------------------------

log "forge build..."
forge build || fail "forge build failed. See output above for the compiler diagnostic."

# --- Step 4: discover twin pairs ----------------------------------------

clean_tests=()
if [ -d test ]; then
    while IFS= read -r -d '' f; do
        clean_tests+=("$f")
    done < <(find test -mindepth 2 -type f -name '*.t.sol' -not -path 'test/planted/*' -not -path 'test/harness/*' -print0 2>/dev/null || true)
fi

planted_tests=()
if [ -d test/planted ]; then
    while IFS= read -r -d '' f; do
        planted_tests+=("$f")
    done < <(find test/planted -maxdepth 1 -type f -name '*.planted.t.sol' -print0 2>/dev/null || true)
fi

if [ ${#clean_tests[@]} -eq 0 ] && [ ${#planted_tests[@]} -eq 0 ]; then
    log "No twin pairs found; scaffold pre-implementation state. Exiting vacuous-green."
    exit 0
fi

# --- Step 5: run clean legs ---------------------------------------------

clean_summary=()
clean_failed=0
for t in "${clean_tests[@]}"; do
    name=$(basename "$t" .t.sol)
    log "CLEAN: forge test --match-path $t"
    out=$(forge test --match-path "$t" -vv 2>&1)
    ec=$?
    if [ $ec -ne 0 ]; then
        clean_summary+=("CLEAN FAIL $name (forge test exited $ec)")
        clean_failed=$((clean_failed + 1))
        printf '%s\n' "$out"
        continue
    fi
    if printf '%s' "$out" | grep -q "INVARIANT VIOLATED"; then
        clean_summary+=("CLEAN FAIL $name (produced INVARIANT VIOLATED)")
        clean_failed=$((clean_failed + 1))
        printf '%s\n' "$out"
        continue
    fi
    clean_summary+=("CLEAN PASS $name")
done

# --- Step 6: run planted legs -------------------------------------------

planted_summary=()
planted_failed=0
for t in "${planted_tests[@]}"; do
    name=$(basename "$t" .planted.t.sol)
    log "PLANTED: forge test --match-path $t"
    out=$(forge test --match-path "$t" -vv 2>&1)
    ec=$?
    if ! printf '%s' "$out" | grep -q "INVARIANT VIOLATED"; then
        planted_summary+=("PLANTED FAIL $name (did NOT produce INVARIANT VIOLATED)")
        planted_failed=$((planted_failed + 1))
        printf '%s\n' "$out"
        continue
    fi
    if [ $ec -eq 0 ]; then
        planted_summary+=("PLANTED FAIL $name (forge test exited 0)")
        planted_failed=$((planted_failed + 1))
        continue
    fi
    planted_summary+=("PLANTED FIRED $name (INVARIANT VIOLATED)")
done

# --- Step 7: summary ----------------------------------------------------

echo ""
echo "================================================================"
echo " x402-regression-base M1  -  clean/planted twin summary"
echo "================================================================"
for line in "${clean_summary[@]}"; do echo "  $line"; done
for line in "${planted_summary[@]}"; do echo "  $line"; done
echo "----------------------------------------------------------------"
echo "  clean total: ${#clean_tests[@]}    clean failed: $clean_failed"
echo "  planted total: ${#planted_tests[@]}    planted failed: $planted_failed"
echo "================================================================"

if [ $clean_failed -gt 0 ] || [ $planted_failed -gt 0 ]; then
    fail "clean_failed=$clean_failed planted_failed=$planted_failed - see summary above."
fi

log "All clean legs passed; all planted legs surfaced INVARIANT VIOLATED. OK."
exit 0
