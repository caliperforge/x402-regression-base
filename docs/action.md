# `base-x402-ci` Action — adopter documentation

Drop this Action into any GitHub Actions workflow to run the planted-twin regression suite against a live x402 facilitator or resource-server on Base.

Repo: `caliperforge/x402-regression-base`.
Action tag: pin to a specific release (e.g. `@v0.1.0`); the rolling `@v0` tag is a convenience alias.

## Quick start

Five lines of YAML under `with:`:

```yaml
name: x402 CI
on: [push, pull_request]
jobs:
  x402-ci:
    runs-on: ubuntu-latest
    steps:
      - uses: caliperforge/x402-regression-base@v0.1.0
        with:
          facilitator: ${{ secrets.FACILITATOR_URL }}
          chain: base-sepolia
          rpc-url: ${{ secrets.BASE_SEPOLIA_RPC_URL }}
          operator-key: ${{ secrets.OPERATOR_KEY }}
```

## Inputs

| Name | Required | Default | Purpose |
|---|---|---|---|
| `facilitator`  | yes | — | Deployed facilitator address (`0x...`) or HTTP endpoint URL. |
| `chain`        | yes | `base-sepolia` | `base-mainnet` or `base-sepolia`. |
| `rpc-url`      | yes | — | RPC endpoint URL. Store as a secret. |
| `operator-key` | yes | — | Private key of the burner wallet used to sign test EIP-3009 authorizations. Store as a secret. |
| `variants`     | no  | `V01,V02,V03,V04,V05,V06` | Comma-separated variant IDs. |
| `fail-on`      | no  | `fail` | `fail` fails CI on any clean miss or planted no-fire; `warn` annotates but exits 0. |

## Outputs

| Name | Purpose |
|---|---|
| `report-path` | Absolute path to `x402-ci-report.json` under `$GITHUB_WORKSPACE`. |
| `variants-passed` | Comma-separated list of clean-leg variants that passed. |
| `variants-fired`  | Comma-separated list of planted-leg variants that surfaced `INVARIANT VIOLATED`. |

The report JSON conforms to the schema at `docs/report_schema.json`.

## Secrets contract

The Action reads four secrets. Configure them under `Settings → Secrets → Actions` in the adopter repo:

| Secret name | What | Notes |
|---|---|---|
| `FACILITATOR_URL` | Deployed facilitator address or endpoint. | Passed to the Action's `facilitator` input. |
| `BASE_SEPOLIA_RPC_URL` | Sepolia RPC URL (Alchemy / Infura / QuickNode / self-hosted). | Free tier suffices for CI volume. |
| `BASE_MAINNET_RPC_URL` | Mainnet RPC URL. | Only needed for `chain: base-mainnet`. |
| `OPERATOR_KEY` | Burner wallet private key (0x-prefixed hex). | Never reuse a wallet with production balances. Fund only enough to cover test gas. Rotate on any suspected exposure. |

### Operator-key handling

The Action treats the `operator-key` input as a load-bearing secret:

- Masked in Actions logs via `::add-mask::` as the first executable line of the entrypoint.
- Never written to any file under `$GITHUB_WORKSPACE`. A post-run grep-guard fails the job if a rogue harness path violates this.
- Passed to subprocess `forge script` calls via env var (`PRIVATE_KEY` / `OPERATOR_KEY`), never as an `argv` value that `ps aux` inside the container would see.
- Never persisted in the container image; `.dockerignore` blacklists `.env*` and the harness image does not `COPY` any secret-adjacent artifact.

If you suspect the burner key has been exposed, rotate it. Regenerating a Base wallet is free; funding a fresh burner takes minutes.

## Chain semantics

| `chain` value | Runner script | USDC token |
|---|---|---|
| `base-sepolia` | `ci/live_sepolia.sh` | `MockUSDC.sol` deployed same-run unless `X402_USDC` env is provided. |
| `base-mainnet` | `ci/live_mainnet.sh` | Canonical Coinbase-issued Base USDC at `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`. |

For mainnet: the Action defaults `X402_USDC` to the canonical address. Override only if you know what you are doing.

## Failure modes + design notes

- **RPC transient errors.** One retry on HTTP 429 / 5xx / connection timeout / `ETIMEDOUT` / `ECONNRESET`. No retry on on-chain revert (a revert is a real signal; masking it would mask a caught bug).
- **Runtime cap.** Hard cap 15 minutes per harness invocation via `timeout --kill-after=30s 900s`. Prevents runaway CI cost on adopter side. On SIGKILL, the report row is written with `state: timeout`.
- **`fail-on: fail` semantics.** Non-zero exit if any clean-leg variant fails OR any planted-leg variant does not surface `INVARIANT VIOLATED` OR the harness itself exits non-zero.
- **`fail-on: warn` semantics.** Always exit 0. Failures surface as `::warning::` annotations only. Use when integrating into a repo that cannot yet block-on-red.

## What this is NOT

- Not an audit. A passing run of `base-x402-ci` against a Base x402 facilitator does not certify the integration is safe. The library catches the bug classes the planted twins encode (see `coverage_map.md`); the residual surface belongs to the integrator.
- Not endorsed by Coinbase or Base. Planted twins are our own synthetic specification violations in a self-deployed reference facilitator; they are not claims about bugs in shipped Base facilitators.
- No external facilitator team has integrated as of publication. This documentation ships alongside a template adopter (see `example-adopter/`) to demonstrate the integration shape.

## Troubleshooting

- **`operator-key must be 0x-prefixed hex`** — the secret was set to a raw 64-char hex string. Prepend `0x` and re-save.
- **`chain 'X' unrecognised`** — only `base-mainnet` and `base-sepolia` are supported. `base-goerli` was deprecated with the network.
- **`harness runner 'X' not executable`** — the container image was rebuilt without executing the `chmod +x` step in the Dockerfile. Rebuild from a clean checkout.
- **`operator-key detected in workspace file after harness run`** — a harness code path wrote the key to a file under `$GITHUB_WORKSPACE`. Do not paper over; file a bug against `caliperforge/x402-regression-base` with the offending file path (redact the key).

## Reporting

- Library bugs: `SECURITY.md` in the repo root.
- Downstream integrator bugs found via a fork of this harness: report to the integrator directly; see `disclosures/TEMPLATE.md` if help routing is needed.
