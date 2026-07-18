#!/usr/bin/env bash
# ci/live_sepolia.sh - deploy + smoke against a live Base-substrate RPC.
#
# Contract per M1 spec §4.2 (W2) + §2.4 (tx-hash record shape):
#
#   1. Deploy X402Facilitator (and MockUSDC on Sepolia if X402_USDC unset).
#   2. Capture the deploy tx hash + contract address.
#   3. Fire one clean-leg settle() via SettleSmoke.
#   4. Capture the settle tx hash.
#   5. Append a `docs/basescan/<chain>_run_<YYYY-MM-DD>.md` record.
#
# Env inputs (required):
#
#   X402_RPC_URL          Base Sepolia (or mainnet) RPC. For CI: dropped in
#                         via GH Actions secret BASE_SEPOLIA_RPC_URL /
#                         BASE_MAINNET_RPC_URL.
#   OPERATOR_KEY          Burner wallet private key (0x-prefixed hex).
#                         Never logged, never written to disk. Masked
#                         at CI entrypoint before this script runs.
#
# Env inputs (optional):
#
#   X402_USDC             Canonical USDC address. Sepolia default = deploy
#                         MockUSDC same-run; mainnet MUST set this to
#                         0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913.
#   X402_CHAIN_LABEL      Label for the record filename. Default: sepolia
#                         (accepts: sepolia | mainnet).
#   BASESCAN_API_KEY      Enables --verify on forge script (Basescan
#                         source-verification). Optional; W2 does not
#                         hard-block on verification (per §4.2 AC 5).
#   X402_SKIP_HARNESS     If "1", skip the planted-twin harness run step.
#                         Default: run it against the live facilitator.
#
# Outputs:
#
#   docs/basescan/<chain>_run_<date>.md   populated template with
#                                         deploy + settle tx hashes.
#
# Exit codes:
#
#   0  deploy + smoke ok; record written.
#   2  missing required env.
#   3  forge script failure.
#   4  tx-hash capture failure (broadcast file missing / malformed).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Chain label derives from invocation name (live_sepolia.sh -> sepolia,
# live_mainnet.sh -> mainnet) so W6 can symlink to this file without a
# second copy. Override with X402_CHAIN_LABEL if calling directly.
SCRIPT_BASENAME="$(basename "${BASH_SOURCE[0]}" .sh)"
CHAIN_LABEL="${X402_CHAIN_LABEL:-${SCRIPT_BASENAME#live_}}"
[ "$CHAIN_LABEL" = "$SCRIPT_BASENAME" ] && CHAIN_LABEL="sepolia"
DATE_TAG="$(date -u +%F)"
RECORD_PATH="docs/basescan/${CHAIN_LABEL}_run_${DATE_TAG}.md"

log()  { printf '[live-%s] %s\n' "$CHAIN_LABEL" "$*" >&2; }
fail() { printf '[live-%s] FAIL: %s\n' "$CHAIN_LABEL" "$*" >&2; exit "${2:-1}"; }

# --- Preflight ---------------------------------------------------------

: "${X402_RPC_URL:?X402_RPC_URL must be set to a Base $CHAIN_LABEL RPC endpoint}" || exit 2
: "${OPERATOR_KEY:?OPERATOR_KEY (burner wallet) must be set}" || exit 2

if ! command -v forge >/dev/null 2>&1; then
    fail "forge (Foundry) not installed; see README quickstart" 3
fi
if ! command -v jq >/dev/null 2>&1; then
    fail "jq required to parse broadcast files" 3
fi
if ! command -v cast >/dev/null 2>&1; then
    fail "cast required to derive operator address" 3
fi

# Mask key immediately if we are in GH Actions.
if [ -n "${GITHUB_ACTIONS:-}" ]; then
    printf '::add-mask::%s\n' "$OPERATOR_KEY"
fi

OPERATOR_ADDR="$(cast wallet address "$OPERATOR_KEY")"
CHAIN_ID="$(cast chain-id --rpc-url "$X402_RPC_URL")"
log "operator=$OPERATOR_ADDR chainId=$CHAIN_ID"

mkdir -p docs/basescan

# --- Stage 1: deploy ---------------------------------------------------

log "forge script DeployFacilitator (broadcast to $CHAIN_LABEL)..."
DEPLOY_LOG="$(mktemp)"
trap 'rm -f "$DEPLOY_LOG" "${SMOKE_LOG:-}"' EXIT

deploy_extra_args=()
if [ -n "${BASESCAN_API_KEY:-}" ]; then
    deploy_extra_args+=(--verify --etherscan-api-key "$BASESCAN_API_KEY")
fi
if [ -n "${X402_USDC:-}" ]; then
    export X402_USDC
fi

set +e
forge script script/DeployFacilitator.s.sol:DeployFacilitator \
    --rpc-url "$X402_RPC_URL" \
    --private-key "$OPERATOR_KEY" \
    --broadcast \
    --slow \
    ${deploy_extra_args[@]+"${deploy_extra_args[@]}"} \
    -vvv >"$DEPLOY_LOG" 2>&1
deploy_ec=$?
set -e

if [ $deploy_ec -ne 0 ]; then
    cat "$DEPLOY_LOG"
    fail "DeployFacilitator broadcast exited $deploy_ec" 3
fi

# Prefer parsing the broadcast/run-latest.json for authoritative tx hashes.
BROADCAST_JSON="broadcast/DeployFacilitator.s.sol/${CHAIN_ID}/run-latest.json"
if [ ! -f "$BROADCAST_JSON" ]; then
    cat "$DEPLOY_LOG"
    fail "expected broadcast file missing: $BROADCAST_JSON" 4
fi

FACILITATOR_ADDR="$(jq -r '.transactions[] | select(.contractName=="X402Facilitator") | .contractAddress' "$BROADCAST_JSON" | head -n1)"
DEPLOY_TX_HASH="$(jq -r '.transactions[] | select(.contractName=="X402Facilitator") | .hash' "$BROADCAST_JSON" | head -n1)"
USDC_ADDR="${X402_USDC:-$(jq -r '.transactions[] | select(.contractName=="MockUSDC") | .contractAddress' "$BROADCAST_JSON" | head -n1)}"
USDC_TX_HASH="$(jq -r '.transactions[] | select(.contractName=="MockUSDC") | .hash' "$BROADCAST_JSON" | head -n1)"

[ -n "$FACILITATOR_ADDR" ] && [ "$FACILITATOR_ADDR" != "null" ] || fail "facilitator address not captured" 4
[ -n "$DEPLOY_TX_HASH" ] && [ "$DEPLOY_TX_HASH" != "null" ] || fail "deploy tx hash not captured" 4

log "facilitator=$FACILITATOR_ADDR deploy-tx=$DEPLOY_TX_HASH"

# --- Stage 2: settle smoke --------------------------------------------

# SettleSmoke needs OPERATOR_KEY_UINT (uint form) because vm.envUint
# is what forge exposes; converted here so the key stays out of the
# script's env parsing path.
OPERATOR_KEY_UINT="$(cast to-dec "$OPERATOR_KEY")"

log "forge script SettleSmoke (broadcast)..."
SMOKE_LOG="$(mktemp)"
export X402_FACILITATOR="$FACILITATOR_ADDR"
export X402_USDC="$USDC_ADDR"
export OPERATOR_KEY_UINT

set +e
forge script script/SettleSmoke.s.sol:SettleSmoke \
    --rpc-url "$X402_RPC_URL" \
    --broadcast \
    --slow \
    -vvv >"$SMOKE_LOG" 2>&1
smoke_ec=$?
set -e

unset OPERATOR_KEY_UINT

if [ $smoke_ec -ne 0 ]; then
    cat "$SMOKE_LOG"
    fail "SettleSmoke broadcast exited $smoke_ec" 3
fi

SMOKE_BROADCAST="broadcast/SettleSmoke.s.sol/${CHAIN_ID}/run-latest.json"
SETTLE_TX_HASH="$(jq -r '.transactions[] | select((.transactionType=="CALL") and (.function|test("^settle\\("))) | .hash' "$SMOKE_BROADCAST" | head -n1)"
[ -n "$SETTLE_TX_HASH" ] && [ "$SETTLE_TX_HASH" != "null" ] || fail "settle tx hash not captured" 4

log "settle-tx=$SETTLE_TX_HASH"

# --- Stage 3: harness against live facilitator ------------------------

HARNESS_OUT="[skipped via X402_SKIP_HARNESS=1]"
if [ "${X402_SKIP_HARNESS:-0}" != "1" ]; then
    log "planted-twin harness against live facilitator..."
    HARNESS_LOG="$(mktemp)"
    trap 'rm -f "$DEPLOY_LOG" "$SMOKE_LOG" "$HARNESS_LOG"' EXIT

    # Live-fork the deployed facilitator into forge test; the twins re-run
    # in a fork against the same bytecode + storage layout for a matrix
    # smoke against the on-chain contract. Full at-chain twin replay lands
    # once eng_lead reviews the fork-mode budget (M1 spec §5.1).
    set +e
    FOUNDRY_ETH_RPC_URL="$X402_RPC_URL" \
        forge test --fork-url "$X402_RPC_URL" \
                   --match-path 'test/V0*/**/*.t.sol' \
                   -vv >"$HARNESS_LOG" 2>&1
    harness_ec=$?
    set -e

    if [ $harness_ec -eq 0 ]; then
        HARNESS_OUT="PASS (forked-Sepolia; clean legs green)"
    else
        HARNESS_OUT="FAIL (see $HARNESS_LOG; harness_ec=$harness_ec)"
        cat "$HARNESS_LOG"
    fi
fi

# --- Stage 4: Basescan record -----------------------------------------

if [ "$CHAIN_LABEL" = "sepolia" ]; then
    SCAN_BASE="https://sepolia.basescan.org"
else
    SCAN_BASE="https://basescan.org"
fi

cat >"$RECORD_PATH" <<RECORD
# Base $CHAIN_LABEL run - $DATE_TAG

**Facilitator contract:** [\`$FACILITATOR_ADDR\`]($SCAN_BASE/address/$FACILITATOR_ADDR)
**Operator wallet:** \`$OPERATOR_ADDR\` (burner; not user-holding)
**USDC token:** [\`$USDC_ADDR\`]($SCAN_BASE/address/$USDC_ADDR)
**Chain ID:** $CHAIN_ID

## Transactions

| Step | Description | Tx hash | Basescan |
|---|---|---|---|
| 1 | Deploy X402Facilitator | \`$DEPLOY_TX_HASH\` | [link]($SCAN_BASE/tx/$DEPLOY_TX_HASH) |
$([ -n "$USDC_TX_HASH" ] && [ "$USDC_TX_HASH" != "null" ] && printf '| 1a | Deploy MockUSDC (same-run) | `%s` | [link](%s/tx/%s) |\n' "$USDC_TX_HASH" "$SCAN_BASE" "$USDC_TX_HASH")
| 2 | Signed EIP-712 settle (clean smoke) | \`$SETTLE_TX_HASH\` | [link]($SCAN_BASE/tx/$SETTLE_TX_HASH) |

## Harness against live facilitator

$HARNESS_OUT

## Reproduce

\`\`\`
git clone <repo>
cd <repo>
export X402_RPC_URL='<Base $CHAIN_LABEL RPC>'
export OPERATOR_KEY='<burner key with $CHAIN_LABEL ETH>'
$([ "$CHAIN_LABEL" = "mainnet" ] && printf 'export X402_USDC=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913\n')./ci/live_$CHAIN_LABEL.sh
\`\`\`

Runner file: \`ci/live_${CHAIN_LABEL}.sh\`. See SECURITY.md for the
Actions-secrets contract; keys never land in the repo or in logs.
RECORD

log "record written: $RECORD_PATH"
log "OK. deploy=$DEPLOY_TX_HASH settle=$SETTLE_TX_HASH"
exit 0
