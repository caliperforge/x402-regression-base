# example-adopter: Base facilitator CI template

## 1. What this template is

A drop-in `.github/workflows/x402-ci.yml` that a Base x402 facilitator or resource-server maintainer can copy into their own repo to run the `caliperforge/x402-regression-base` planted-twin regression suite against their live facilitator on every push and pull request.

This example adopter is a template repository showing what the integration looks like from a Base builder's perspective. No external facilitator team has integrated as of publication.

The template is fictional in the sense that it does not point at a real production facilitator; the workflow file is production-shaped. Copy it, adjust the secrets, and it runs.

## 2. Secrets to create in your repo

Add four repo-level secrets (Settings → Secrets and variables → Actions → New repository secret). Names and shapes:

| Secret | Shape | Notes |
|---|---|---|
| `FACILITATOR_URL` | `0x`-prefixed address of your deployed facilitator, or an `https://` endpoint if your facilitator is HTTP-mode | Value is not sensitive on its own but should be a secret so it does not leak into forks |
| `BASE_SEPOLIA_RPC_URL` | Full RPC URL including any API key | Alchemy, Infura, QuickNode, self-hosted; keyed RPC is safer than the public `sepolia.base.org` under CI load |
| `BASE_MAINNET_RPC_URL` | Full RPC URL including any API key | Only required if you flip `chain:` to `base-mainnet`; keep it as a secret regardless |
| `OPERATOR_KEY` | `0x`-prefixed 64-hex-char private key of a burner wallet | See §3 for the burner-wallet posture |

The four `gh secret set` commands (never paste the key value into a chat log; use `gh secret set` interactive stdin):

```
gh secret set FACILITATOR_URL       --body "<your facilitator address or URL>"
gh secret set BASE_SEPOLIA_RPC_URL  # opens editor; paste RPC URL, save, close
gh secret set BASE_MAINNET_RPC_URL  # opens editor; paste RPC URL, save, close
gh secret set OPERATOR_KEY          # opens editor; paste 0x-prefixed key, save, close
```

## 3. Burner-wallet posture

Four rules. All four are load-bearing on your safety.

1. **Never a wallet with production balances.** The `OPERATOR_KEY` signs test EIP-3009 authorizations that get replayed and mutated across variants. Treat it as compromised the moment it is stored as an Actions secret.
2. **Minimum viable funding.** For Sepolia, faucet-derived Sepolia ETH is enough. For mainnet, fund with just enough to cover deploy + a handful of settle calls at current L2 gas (a couple of cents plus a small cushion). Do not stockpile.
3. **Regenerate per repo.** Do not reuse the same burner key across your repos, our repo, or any friend's repo. One burner per Actions secret slot.
4. **Rotate on suspected exposure.** If a workflow log ever surfaces a value that looks like the key (should not happen; `::add-mask::` fires as the first line of the runner's `entrypoint.sh`), rotate immediately: `cast wallet new`, replace the secret, sweep any residual balance out of the old address.

## 4. The five-line YAML

Copy `./.github/workflows/x402-ci.yml` into your repo at the same path. Each `with:` field:

```yaml
      - uses: caliperforge/x402-regression-base@v0.1.0
        with:
          facilitator:  ${{ secrets.FACILITATOR_URL }}       # target: your facilitator
          chain:        base-sepolia                          # or base-mainnet once you are ready
          rpc-url:      ${{ secrets.BASE_SEPOLIA_RPC_URL }}   # matches the chain: field
          operator-key: ${{ secrets.OPERATOR_KEY }}           # burner; see §3
```

Optional inputs (defaults are usually correct):

- `variants: V01,V02,V03,V04,V05,V06`: subset the run if you want to iterate on a single class.
- `fail-on: fail`: flip to `warn` if you want annotations without a red CI while onboarding.

Pin to a specific release tag (`@v0.1.0`) rather than the rolling `@v0` alias so your CI stays stable across our releases. Bump the tag deliberately when a new release lands.

## 5. Append to an existing workflow file (do not replace)

If you already have a `.github/workflows/ci.yml`, add the job to that file rather than replacing it. The pattern:

```yaml
# your existing ci.yml
name: CI
on: [push, pull_request]
jobs:
  your-existing-job:
    # ... unchanged ...

  # NEW: the x402 CI job
  x402-ci:
    name: base-x402-ci (planted-twin regression against live facilitator)
    runs-on: ubuntu-latest
    timeout-minutes: 25
    steps:
      - uses: caliperforge/x402-regression-base@v0.1.0
        with:
          facilitator:  ${{ secrets.FACILITATOR_URL }}
          chain:        base-sepolia
          rpc-url:      ${{ secrets.BASE_SEPOLIA_RPC_URL }}
          operator-key: ${{ secrets.OPERATOR_KEY }}
```

Keeps the surface area small: one new job, no changes to your existing `on:` triggers or job graph.

## 6. What a green run looks like

Prose reference (representative of a passing local matrix; a real Sepolia CI capture will replace this once W2 lands the reference facilitator on Sepolia):

- Job `base-x402-ci (planted-twin regression against live facilitator)` completes green.
- The runner log shows the six clean variants settling one after another, then the six planted variants each surfacing an `INVARIANT VIOLATED V0X_Name` marker on the planted leg.
- The step summary lists `variants-passed` = all six IDs and `variants-fired` = all six IDs.
- The report artifact `x402-ci-report.json` uploads with counts + per-variant status.

Full shape (log lines you should expect to see) is in [`docs/expected_output.md`](docs/expected_output.md).

## 7. What a planted-fire run looks like (the intended fail signal)

If your facilitator carries one of the bug classes the planted twins encode, the corresponding planted leg will **not** fire the `INVARIANT VIOLATED` marker, because the specification violation is already live rather than newly introduced. In that case:

- The job fails with `::error::` annotations naming the variant IDs that did not fire.
- `variants-fired` is the subset that DID fire (i.e. the classes your facilitator already defends against).
- The step summary points at the row that failed to fire, with a pointer back to `coverage_map.md` for the class description and remediation guidance.

This is the intended signal that surfaces the class on your side. Read the pointed-at row in `coverage_map.md`, patch the facilitator, re-run.

Full shape in [`docs/expected_output.md`](docs/expected_output.md).

## 8. Switching chain: base-sepolia vs. base-mainnet

Start on `base-sepolia` for de-risk. Once your facilitator is green there for several runs, flip `chain: base-mainnet` and swap the `rpc-url` secret reference to `BASE_MAINNET_RPC_URL`.

Cost note: each settle call on Base mainnet costs on the order of $0.01–0.05 at current L2 gas. A full six-variant run with clean + planted legs is roughly $0.10–0.50 per CI job. Budget the burner accordingly. Public flip to mainnet CI is a decision; do not do it on every PR by default. A common pattern is `chain: base-sepolia` on `pull_request` and `chain: base-mainnet` on a weekly cron.

## 9. Troubleshooting

Three most likely failures on first setup:

1. **RPC 429 or 5xx during a run.** The runner retries once on transient RPC errors; if the retry also fails, the whole run fails with a clear message. Fix: use a keyed RPC endpoint rather than `sepolia.base.org` / `mainnet.base.org`; the free tiers of Alchemy or Infura are sufficient for M1 volume.
2. **`operator-key must be 0x-prefixed hex`.** The `OPERATOR_KEY` secret got truncated or has a stray newline. Re-set it via `gh secret set OPERATOR_KEY` and paste the full 66-character value (`0x` + 64 hex chars).
3. **A planted variant did not fire and CI failed at that row.** This is the intended catch: your facilitator lacks the defense the planted twin exercises. Read the corresponding row in [`coverage_map.md`](https://github.com/caliperforge/x402-regression-base/blob/main/coverage_map.md), patch the facilitator, re-run.

## 10. License + parent

Apache-2.0, same as the parent library. See the parent repo [`caliperforge/x402-regression-base`](https://github.com/caliperforge/x402-regression-base) for the Action source, planted-twin definitions, `coverage_map.md`, SECURITY.md, and CONTRIBUTING.md.
