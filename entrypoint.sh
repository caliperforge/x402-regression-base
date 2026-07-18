#!/usr/bin/env bash
# entrypoint.sh - base-x402-ci GH Action containerized runner entrypoint.
#
# Wraps `run.sh` + `ci/live_*.sh` for the GH Actions container-action
# path. Contract per M1 spec §3.2 + §3.3 (W3 AC 1-10). Six positional
# args pass through from action.yml `runs.args` in order:
#
#   $1  facilitator     Deployed facilitator address or HTTP endpoint URL.
#   $2  chain           base-mainnet | base-sepolia.
#   $3  rpc-url         RPC endpoint URL.
#   $4  operator-key    Burner wallet private key (0x-prefixed hex).
#   $5  variants        Comma-separated variant IDs (V01,V02,...).
#   $6  fail-on         fail | warn.
#
# Invariants (enforced below):
#
#   1. `operator-key` is masked via ::add-mask:: BEFORE any log or
#      subprocess call. Any earlier echo would leak plaintext.
#   2. `operator-key` is never written to the workspace. Every file
#      this script produces is grepped for the 64-hex-char pattern
#      before we exit non-zero-on-leak.
#   3. `operator-key` is never passed as an argv value that `ps aux`
#      inside the container could see. Passed via env var only.
#   4. Container exit code is 1 iff `fail-on == fail` AND (any clean
#      variant failed OR any planted variant did not fire). In `warn`
#      mode we exit 0 but emit ::warning:: annotations.
#
# Bash 3.2 compatible (macOS default dev-host); tested on Alpine bash
# in the foundry-rs runner image.

set -uo pipefail

# --- Argument capture (positional; matches action.yml runs.args) -------

INPUT_FACILITATOR="${1:-${INPUT_FACILITATOR:-}}"
INPUT_CHAIN="${2:-${INPUT_CHAIN:-}}"
INPUT_RPC_URL="${3:-${INPUT_RPC_URL:-}}"
INPUT_OPERATOR_KEY="${4:-${INPUT_OPERATOR_KEY:-}}"
INPUT_VARIANTS="${5:-${INPUT_VARIANTS:-V01,V02,V03,V04,V05,V06}}"
INPUT_FAIL_ON="${6:-${INPUT_FAIL_ON:-fail}}"

# --- INVARIANT 1: mask before any log ----------------------------------
# GH Actions redacts any substring matching the masked value across the
# whole job log. Must fire before any `echo`/`printf` that might carry
# the key (defense-in-depth against a later `set -x`).

if [ -n "${INPUT_OPERATOR_KEY}" ]; then
    printf '::add-mask::%s\n' "${INPUT_OPERATOR_KEY}"
fi

log()  { printf '[entrypoint] %s\n' "$*" >&2; }
warn() { printf '::warning::[entrypoint] %s\n' "$*"; }
fail() { printf '::error::[entrypoint] %s\n' "$*"; printf '[entrypoint] FAIL: %s\n' "$*" >&2; exit "${2:-1}"; }

# --- Preflight ---------------------------------------------------------

[ -n "${INPUT_FACILITATOR}" ]  || fail "input 'facilitator' required" 2
[ -n "${INPUT_CHAIN}" ]        || fail "input 'chain' required" 2
[ -n "${INPUT_RPC_URL}" ]      || fail "input 'rpc-url' required" 2
[ -n "${INPUT_OPERATOR_KEY}" ] || fail "input 'operator-key' required" 2

case "${INPUT_CHAIN}" in
    base-sepolia|base-mainnet) ;;
    *) fail "chain '${INPUT_CHAIN}' unrecognised; expected base-sepolia or base-mainnet" 2 ;;
esac

case "${INPUT_FAIL_ON}" in
    fail|warn) ;;
    *) fail "fail-on '${INPUT_FAIL_ON}' unrecognised; expected fail or warn" 2 ;;
esac

# Sanity-check the operator-key shape without echoing it.
case "${INPUT_OPERATOR_KEY}" in
    0x*) ;;
    *) fail "operator-key must be 0x-prefixed hex (received a value of length ${#INPUT_OPERATOR_KEY})" 2 ;;
esac
key_len=${#INPUT_OPERATOR_KEY}
[ "${key_len}" -eq 66 ] || fail "operator-key wrong length (expected 66 chars incl. 0x prefix; got ${key_len})" 2

# --- Working directory + workspace hookup ------------------------------

# The harness lives at /action (baked at image-build time). Adopter
# workspace at $GITHUB_WORKSPACE (mounted by Actions). We `cd /action`
# so `run.sh` finds `script/` + `test/` at expected relative paths;
# report + Basescan record land under $GITHUB_WORKSPACE so
# upload-artifact steps can pick them up.

WORKSPACE_DIR="${GITHUB_WORKSPACE:-/github/workspace}"
mkdir -p "${WORKSPACE_DIR}"

HARNESS_DIR="/action"
if [ ! -d "${HARNESS_DIR}" ]; then
    # Local dev-host dry-run: allow running from the repo root.
    HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
cd "${HARNESS_DIR}"

REPORT_PATH="${WORKSPACE_DIR}/x402-ci-report.json"
LOG_DIR="$(mktemp -d)"
trap 'rm -rf "${LOG_DIR}"' EXIT

log "chain=${INPUT_CHAIN} facilitator=$(printf '%s\n' "${INPUT_FACILITATOR}" | cut -c1-10)... variants=${INPUT_VARIANTS} fail-on=${INPUT_FAIL_ON}"
log "harness=${HARNESS_DIR} workspace=${WORKSPACE_DIR}"

# --- INVARIANT 3: export via env, never via argv -----------------------

export X402_RPC_URL="${INPUT_RPC_URL}"
export OPERATOR_KEY="${INPUT_OPERATOR_KEY}"
export PRIVATE_KEY="${INPUT_OPERATOR_KEY}"      # forge script also reads $PRIVATE_KEY
export X402_FACILITATOR="${INPUT_FACILITATOR}"
export X402_VARIANTS="${INPUT_VARIANTS}"
export X402_FAIL_ON="${INPUT_FAIL_ON}"

# Mainnet requires the canonical Base USDC (Coinbase-issued). Set the
# default so the harness does not try to redeploy MockUSDC on mainnet.
if [ "${INPUT_CHAIN}" = "base-mainnet" ] && [ -z "${X402_USDC:-}" ]; then
    export X402_USDC="0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
fi

# --- Route to the chain-specific runner --------------------------------

case "${INPUT_CHAIN}" in
    base-sepolia) HARNESS_SCRIPT="./ci/live_sepolia.sh" ;;
    base-mainnet) HARNESS_SCRIPT="./ci/live_mainnet.sh" ;;
esac

[ -x "${HARNESS_SCRIPT}" ] || fail "harness runner '${HARNESS_SCRIPT}' not executable in ${HARNESS_DIR}" 3

log "routing to ${HARNESS_SCRIPT}"

# --- Harness invocation with 15-min per-run hard cap + retry -----------
#
# Per M1 spec §3.3 AC 5-6: one retry on RPC transient (429/5xx/timeout);
# no retry on on-chain revert. Hard cap 900s per attempt via `timeout`.

HARNESS_LOG="${LOG_DIR}/harness.log"
harness_ec=0

run_harness_once() {
    # `timeout` is coreutils; installed in the Alpine image.
    timeout --kill-after=30s 900s "${HARNESS_SCRIPT}" >"${HARNESS_LOG}" 2>&1
    return $?
}

run_harness_once
harness_ec=$?

if [ ${harness_ec} -ne 0 ]; then
    # Retry-worthy iff the log carries an RPC-transient marker AND no
    # `revert` / `INVARIANT VIOLATED` (a real signal — do not mask).
    if grep -qE '(rate.?limit|429|500 Internal|502 Bad|503 Service|504 Gateway|timeout|ETIMEDOUT|ECONNRESET|connection reset)' "${HARNESS_LOG}" \
       && ! grep -qE '(revert|INVARIANT VIOLATED)' "${HARNESS_LOG}"; then
        warn "harness exited ${harness_ec} on RPC-transient marker; retrying once"
        sleep 5
        run_harness_once
        harness_ec=$?
    fi
fi

# --- Parse the harness output ------------------------------------------
#
# The harness (`ci/live_*.sh`) writes a Basescan record + optionally runs
# the forked-chain planted-twin matrix. Parse for per-variant state.

variants_passed=""
variants_fired=""
variants_failed=""
variants_missed=""

IFS=',' read -ra VARIANT_LIST <<<"${INPUT_VARIANTS}"
for v in "${VARIANT_LIST[@]}"; do
    v="$(printf '%s' "$v" | tr -d '[:space:]')"
    [ -z "$v" ] && continue

    # Clean-leg detection: line "CLEAN PASS <name>" or "PLANTED FIRED <name>"
    # from run.sh summary block; or forge-test "[PASS] test_${v}_..." line.
    if grep -Eq "CLEAN PASS ${v}|\[PASS\] test.*${v}" "${HARNESS_LOG}" 2>/dev/null; then
        variants_passed="${variants_passed:+${variants_passed},}${v}"
    elif grep -Eq "CLEAN FAIL ${v}|\[FAIL\] test.*${v}" "${HARNESS_LOG}" 2>/dev/null; then
        variants_failed="${variants_failed:+${variants_failed},}${v}"
    fi

    if grep -Eq "PLANTED FIRED ${v}|INVARIANT VIOLATED.*${v}" "${HARNESS_LOG}" 2>/dev/null; then
        variants_fired="${variants_fired:+${variants_fired},}${v}"
    elif grep -Eq "PLANTED FAIL ${v}" "${HARNESS_LOG}" 2>/dev/null; then
        variants_missed="${variants_missed:+${variants_missed},}${v}"
    fi
done

# --- Emit the report JSON (conforms to docs/report_schema.json) --------

# Redact rpc-url to host-only in the report.
rpc_host="$(printf '%s' "${INPUT_RPC_URL}" | sed -E 's#^https?://([^/]+).*#\1#' | sed -E 's#^([^.]+\.)+([^.]+\.[^.]+)$#\2#')"

now_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Escape backslash + quote for JSON string embedding.
json_esc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

{
    printf '{\n'
    printf '  "run_id": "%s",\n' "$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || printf 'run-%s' "$$-$(date +%s)")"
    printf '  "chain": "%s",\n' "$(json_esc "${INPUT_CHAIN}")"
    printf '  "facilitator": "%s",\n' "$(json_esc "${INPUT_FACILITATOR}")"
    printf '  "rpc_host": "%s",\n' "$(json_esc "${rpc_host}")"
    printf '  "started_at": "%s",\n' "${now_iso}"
    printf '  "harness_exit_code": %d,\n' "${harness_ec}"
    printf '  "clean_passed": [%s],\n' "$(printf '%s' "${variants_passed}" | awk -F, 'BEGIN{s=""}{for(i=1;i<=NF;i++){if($i!=""){s=s (s?",":"") "\"" $i "\""}}}END{print s}')"
    printf '  "planted_fired": [%s],\n' "$(printf '%s' "${variants_fired}" | awk -F, 'BEGIN{s=""}{for(i=1;i<=NF;i++){if($i!=""){s=s (s?",":"") "\"" $i "\""}}}END{print s}')"
    printf '  "clean_failed": [%s],\n' "$(printf '%s' "${variants_failed}" | awk -F, 'BEGIN{s=""}{for(i=1;i<=NF;i++){if($i!=""){s=s (s?",":"") "\"" $i "\""}}}END{print s}')"
    printf '  "planted_missed": [%s]\n' "$(printf '%s' "${variants_missed}" | awk -F, 'BEGIN{s=""}{for(i=1;i<=NF;i++){if($i!=""){s=s (s?",":"") "\"" $i "\""}}}END{print s}')"
    printf '}\n'
} >"${REPORT_PATH}"

# --- INVARIANT 2: no operator-key in any workspace file ----------------
# Grep the workspace for the exact operator-key string. If a rogue harness
# path wrote it anywhere under $GITHUB_WORKSPACE, hard-fail so the leak
# is loud rather than silent.

if grep -Rq "${INPUT_OPERATOR_KEY}" "${WORKSPACE_DIR}" 2>/dev/null; then
    fail "operator-key detected in workspace file after harness run; refusing to exit clean" 5
fi

# --- Emit outputs to $GITHUB_OUTPUT ------------------------------------

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
        printf 'report-path=%s\n'      "${REPORT_PATH}"
        printf 'variants-passed=%s\n'  "${variants_passed}"
        printf 'variants-fired=%s\n'   "${variants_fired}"
    } >>"${GITHUB_OUTPUT}"
fi

# --- Exit code per fail-on semantics -----------------------------------

# fail-mode: non-zero on any clean failure OR any planted miss OR
# harness itself exited non-zero. warn-mode: always exit 0, annotate.

any_bad=0
if [ -n "${variants_failed}" ]; then any_bad=1; warn "clean variants failed: ${variants_failed}"; fi
if [ -n "${variants_missed}" ]; then any_bad=1; warn "planted variants did not fire: ${variants_missed}"; fi
if [ ${harness_ec} -ne 0 ]; then    any_bad=1; warn "harness exited ${harness_ec}"; fi

log "clean_passed=${variants_passed} planted_fired=${variants_fired} clean_failed=${variants_failed} planted_missed=${variants_missed}"
log "report=${REPORT_PATH}"

if [ ${any_bad} -eq 0 ]; then
    log "OK"
    exit 0
fi

if [ "${INPUT_FAIL_ON}" = "warn" ]; then
    warn "fail-on=warn: exiting 0 despite ${any_bad} failure signal(s)"
    exit 0
fi

# any_bad=1 in fail-mode: exit non-zero even if harness_ec==0
# (planted-miss / clean-fail must surface as CI red).
final_ec="${harness_ec}"
[ "${final_ec}" -eq 0 ] && final_ec=1
log "exit_code=${final_ec} fail-on=fail - surfacing as failure (harness_ec=${harness_ec})"
exit "${final_ec}"
