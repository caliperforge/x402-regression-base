# x402-regression-base

**A CI-runnable planted-twin regression pack for x402 payment facilitators on Base.**

Status and roadmap:

- **Local matrix:** shipped. `./run.sh` runs the six-variant clean-and-planted matrix against the in-repo reference facilitator. Every clean leg passes silently; every planted leg surfaces the `INVARIANT VIOLATED <name>` marker.
- **Sepolia reference deploy:** shipped 2026-07-18. Reference facilitator on Base Sepolia (chainId 84532); receipts in [`docs/basescan/sepolia_run_2026-07-18.md`](docs/basescan/sepolia_run_2026-07-18.md). See §4.
- **Mainnet reference deploy:** shipped 2026-07-18. Same reference facilitator on Base mainnet (chainId 8453); receipts in [`docs/basescan/mainnet_run_2026-07-18.md`](docs/basescan/mainnet_run_2026-07-18.md). See §4.
- **GitHub Action:** pending. The paired `base-x402-ci` Action for five-line-YAML CI adoption is queued for publication at `v0`; see §2 and §6 for the target interface.

---

## 1. What this is

`x402-regression-base` is a CI-runnable planted-twin regression pack for x402 payment facilitators on Base. Add the paired `caliperforge/base-x402-ci` GitHub Action to your workflow in five lines of YAML; your CI runs a planted-twin regression suite against your live x402 facilitator or resource-server on Base, and fails if a planted variant of the published bug classes does not surface.

Each planted twin ships as a `clean` + `planted` pair against our own reference x402 facilitator, with a CI matrix that asserts the clean leg passes silently and the planted leg surfaces an `INVARIANT VIOLATED <name>` marker. The pack covers four published bug classes from the x402 arXiv corpus (V01 Replay, V02 ExpiryBypass, V03 NonceReuse, V04 DoubleGrant) plus two novel variants against synthesized minimal contracts (V05 CrossDomainReplay, V06 DelegationCap).

## 2. Quick start

Add to your `.github/workflows/x402-ci.yml`:

```yaml
name: x402 CI
on: [push, pull_request]
jobs:
  x402-ci:
    runs-on: ubuntu-latest
    steps:
      - uses: caliperforge/x402-regression-base@v0
        with:
          facilitator: ${{ secrets.FACILITATOR_URL }}
          chain: base-sepolia
          rpc-url: ${{ secrets.BASE_SEPOLIA_RPC }}
          operator-key: ${{ secrets.OPERATOR_KEY }}
```

Expected output: `clean-legs-pass` job green, `planted-legs-fire` job green when your facilitator carries the defenses. If a planted variant does not fire when your facilitator carries the corresponding bug class, the CI fails and points at the row.

> _The Action itself is queued for publication under `action.yml` at v0. Until it publishes, the block above reads as the target interface. Local runs against your own facilitator are already supported via `./run.sh`; see §5._

## 3. What this catches

| ID | Class | One-line description (Base substrate) |
|---|---|---|
| V01_Replay | Payment replay | Signed authorization consumed by the token, replayed against the facilitator |
| V02_ExpiryBypass | Expiry not enforced | `validBefore` bound missing; settlement accepted past window |
| V03_NonceReuse | Narrow dedup key | Facilitator dedups on `(from, nonce)` not full-auth-hash; distinct signed authorizations conflate |
| V04_DoubleGrant | Reentrancy on callback | Resource callback fires before consumption marker; re-entrant resource receives a second grant |
| V05_CrossDomainReplay | Stripped EIP-712 domain | Domain omits `chainId` + `verifyingContract`; chainId=1 signature settles on Base |
| V06_DelegationCap | Cumulative-cap not enforced | `SpendPermission` allowance spent past cap across unbounded calls within one period |

Full coverage rows with source citations in [`coverage_map.md`](coverage_map.md).

## 4. Live on Base

This section is load-bearing and is filled in only from real Basescan tx-hash receipts. Each slot below is backed by a record file under `docs/basescan/`.

**Mainnet.** A self-deployed reference x402 facilitator, contract at [`0x0E0CBf222eca590e56A0200D6eDa55EA651FD4F0`](https://basescan.org/address/0x0E0CBf222eca590e56A0200D6eDa55EA651FD4F0) on Base mainnet, Basescan tx [`0x22fe01758810e16bb90cd83da8e10c2d2dd882f1a0532c1161ae471f1732b7b5`](https://basescan.org/tx/0x22fe01758810e16bb90cd83da8e10c2d2dd882f1a0532c1161ae471f1732b7b5) shows a settlement call executed by this harness on 2026-07-18 (status 1; a `Settled(bytes32,address,address,uint256)` event was emitted by the facilitator). This is not Coinbase's production facilitator; it is our reference implementation used to prove the harness runs against real Base rails. Record: [`docs/basescan/mainnet_run_2026-07-18.md`](docs/basescan/mainnet_run_2026-07-18.md).

**Sepolia (en-route de-risk milestone).** A self-deployed reference x402 facilitator, contract at [`0x647a7b1b99eb416b8ba1ac3907779d2f98345409`](https://sepolia.basescan.org/address/0x647a7b1b99eb416b8ba1ac3907779d2f98345409) on Base Sepolia, Basescan tx [`0x906a7a0a05aa7f5187b0cbc49f17222a4cb413bb0bb66801a701eeccd2a5c6d8`](https://sepolia.basescan.org/tx/0x906a7a0a05aa7f5187b0cbc49f17222a4cb413bb0bb66801a701eeccd2a5c6d8) shows a settlement call executed by this harness on 2026-07-18 (status 1). Record: [`docs/basescan/sepolia_run_2026-07-18.md`](docs/basescan/sepolia_run_2026-07-18.md).

**Planted-twin caught on mainnet.** The V03/V04 replay defense also fired on mainnet, on purpose. Basescan tx [`0xd15f9fe55777b9c35a2c331bb37129f9f033712e97b395ed7b5c24f496ec8c46`](https://basescan.org/tx/0xd15f9fe55777b9c35a2c331bb37129f9f033712e97b395ed7b5c24f496ec8c46) replayed the exact settled authorization from the mainnet clean-settle tx above; the facilitator rejected it with the custom error `AuthorizationConsumed()` (selector `0x1dd22e14`) and the receipt shows `status 0`. This is the intended catch, the same defense the six planted twins under `test/planted/` exercise off-chain, now recorded on Base mainnet.

## 5. How to run locally

Prerequisites:

- Foundry (`forge`, `cast`, `anvil`). The bootstrap script detects a missing `forge` and prints a single actionable install line.
- `git submodule` support (the bootstrap script initialises submodules on first run).
- macOS or Linux. Windows via WSL is expected to work but is not part of the CI matrix at v0.

Once cloned:

```
./run.sh
```

Behaviour:

1. Detects missing dependencies; prints an install line and exits non-zero if `forge` is absent.
2. Initialises submodules recursively.
3. Runs `forge build`.
4. Runs the clean/planted matrix: every clean leg must pass silently; every planted leg must surface at least one `INVARIANT VIOLATED <name>` marker and exit non-zero.
5. Prints a summary block.
6. Exits 0 if all clean pass AND all planted fire; non-zero otherwise.

CI (`.github/workflows/ci.yml`) runs the same matrix on `ubuntu-latest` + `macos-latest` and gates `main`.

## 6. Adopter integration

Copy `example-adopter/.github/workflows/x402-ci.yml` into your repo, then set the two secrets (`FACILITATOR_URL`, `OPERATOR_KEY`) plus one RPC URL. The five-line YAML is the entire adopter surface. `example-adopter/README.md` walks through the burner-wallet posture and what a passing / firing CI run looks like.

> _The `example-adopter/` directory is queued alongside the Action publication. Until then, the five-line YAML above is the entire integration; use it against your own `./run.sh` locally to shake out the operator-wallet posture before wiring the Action._

## 7. What this is NOT

- **Not an audit.** A passing CI run against a Base x402 integration does not certify the integration is safe. The library catches the bug classes the planted twins encode (see `coverage_map.md`); the residual surface belongs to the integrator.
- **Not endorsed by Coinbase or Base.** No endorsement is claimed or implied. The self-deployed reference facilitator (§4) is our own contract; it is not Coinbase's production facilitator.
- **No implied adoption.** No external facilitator team has integrated as of publication. If a team integrates later, that fact is added only with the team's public confirmation.
- **Not a runtime monitor.** The properties are pre-deploy CI gates. Runtime monitoring of live facilitators is out of scope.
- **Not a substitute for the x402 protocol's own security review.** Read the coinbase/x402 protocol description directly.
- **Not cross-chain.** This library covers x402 on Base only. No Solana / Uniswap / Taiko / BSC artifacts.

## 8. How to disclose a bug

See [`SECURITY.md`](SECURITY.md). Summary: 90-day default disclosure window on any bug found in this library itself; responsible-disclosure contact is a role email.

## 9. Coverage map

See [`coverage_map.md`](coverage_map.md).

## 10. License + attribution

Apache-2.0. See `LICENSE` for the full text. Vendored third-party components (currently: `forge-std`) are recorded in [`NOTICE`](NOTICE) with license terms. Attribution to the coinbase/x402 protocol shape and Circle's EIP-3009 pattern preserved per `NOTICE`.

Authored under a human-supervised AI-augmented process. See [`AI_DISCLOSURE.md`](AI_DISCLOSURE.md).
