# Base sepolia run - 2026-07-18

**Facilitator contract:** [`0x647a7b1b99eb416b8ba1ac3907779d2f98345409`](https://sepolia.basescan.org/address/0x647a7b1b99eb416b8ba1ac3907779d2f98345409)
**Operator wallet:** `0x9059E856601a414728d25A2E074738d80258B206` (burner; not user-holding)
**USDC token:** [`0xe84666dab44978c257c2a25c937ba4b38f658758`](https://sepolia.basescan.org/address/0xe84666dab44978c257c2a25c937ba4b38f658758) (MockUSDC, deployed same-run)
**Chain ID:** 84532

## Transactions

| Step | Description | Tx hash | Basescan |
|---|---|---|---|
| 1  | Deploy X402Facilitator                | `0xf61e60cefe6d1fda6275143e7d813ad38b0e18f5b2115941f64eb374af9e6df1` | [link](https://sepolia.basescan.org/tx/0xf61e60cefe6d1fda6275143e7d813ad38b0e18f5b2115941f64eb374af9e6df1) |
| 1a | Deploy MockUSDC (same-run)            | `0x719b5d086cbbd1174c6a9db8abf7fd8720176b877021f42d0007327bf9981671` | [link](https://sepolia.basescan.org/tx/0x719b5d086cbbd1174c6a9db8abf7fd8720176b877021f42d0007327bf9981671) |
| 2a | MockUSDC.mint(operator, 10000)        | `0xedbf49885d13251d945c3f9bf319bd7e0d890d823d9cc9c4871c62f93cf29968` | [link](https://sepolia.basescan.org/tx/0xedbf49885d13251d945c3f9bf319bd7e0d890d823d9cc9c4871c62f93cf29968) |
| 2b | MockUSDC.approve(facilitator, 10000)  | `0xeed85657c0b2eee00b52c35c1d088fcdbdf6f974d6b8e9ec2538aabb83ed94e6` | [link](https://sepolia.basescan.org/tx/0xeed85657c0b2eee00b52c35c1d088fcdbdf6f974d6b8e9ec2538aabb83ed94e6) |
| 2  | Signed EIP-712 settle (clean smoke)   | `0x906a7a0a05aa7f5187b0cbc49f17222a4cb413bb0bb66801a701eeccd2a5c6d8` | [link](https://sepolia.basescan.org/tx/0x906a7a0a05aa7f5187b0cbc49f17222a4cb413bb0bb66801a701eeccd2a5c6d8) |

All above have receipts with `status = 1 (success)` on Base Sepolia. The
deploy landed in block 44320714; the settle landed in block 44320756.

## Harness against live facilitator

Fork-mode replay (`forge test --fork-url https://sepolia.base.org --match-path 'test/V0*/**/*.t.sol'`)
against the deployed facilitator: **10 tests passed, 0 failed, 0 skipped**
across V01-V06 clean legs.

| Suite | Clean | Result |
|---|---|---|
| V01_Replay              | test_singleSettleSucceeds, test_replayReverts                | PASS |
| V02_ExpiryBypass        | test_settleInsideWindowSucceeds, test_settleAfterValidBeforeReverts | PASS |
| V03_NonceReuse          | test_sameNonceDifferentAuthsBothSettle                       | PASS |
| V04_DoubleGrant         | test_singleGrantPerSettle                                    | PASS |
| V05_CrossDomainReplay   | test_baseChainSignatureSettles, test_ethMainnetSignatureRejected | PASS |
| V06_DelegationCap       | test_spendUpToAllowanceSucceeds, test_spendPastAllowanceReverts | PASS |

Local planted-twin matrix (`./run.sh`) fired the fault leg on every vector:
**PLANTED FIRED** on V01-V06 (all six planted twins surface
`INVARIANT VIOLATED`). Clean-vs-planted diff is what proves the invariants
actually bind; a repository that green-lit both is not a regression harness.

## Gas budget used

- Starting burner balance: `100000000000000` wei (0.0001 ETH, per CEO faucet drip).
- Ending burner balance:   `93989275841281` wei (0.0000939... ETH).
- Consumed: `6010724158719` wei (~0.000006 ETH) across five broadcast txs on
  a chain quoting ~0.006-0.011 gwei. Remaining balance covers dozens of
  future nightly cron re-runs of `./ci/live_sepolia.sh` before topping-up.

## Reproduce

```
git clone <repo>
cd <repo>
export X402_RPC_URL='https://sepolia.base.org'
export OPERATOR_KEY='<burner key with sepolia ETH>'
./ci/live_sepolia.sh
```

Runner file: `ci/live_sepolia.sh`. See SECURITY.md for the Actions-secrets
contract; keys never land in the repo or in logs.
