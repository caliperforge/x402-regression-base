# Base mainnet run - 2026-07-18

**Facilitator contract:** [`0x0E0CBf222eca590e56A0200D6eDa55EA651FD4F0`](https://basescan.org/address/0x0E0CBf222eca590e56A0200D6eDa55EA651FD4F0)
**Operator wallet:** `0x5730fA096e4Bc475695dA69a837a5C960B67D467` (burner; not user-holding)
**USDC token (canonical Coinbase-issued Base USDC):** [`0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`](https://basescan.org/address/0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913)
**Chain ID:** 8453

## Transactions

| Step | Description | Tx hash | Basescan | Status |
|---|---|---|---|---|
| 1 | Deploy X402Facilitator (constructor binds canonical USDC) | `0x4e21a6a75776864c78288ae9729f6252ce3d8a2a1db7d1013e353f139eee6cca` | [link](https://basescan.org/tx/0x4e21a6a75776864c78288ae9729f6252ce3d8a2a1db7d1013e353f139eee6cca) | 1 |
| 2 | Operator `approve(facilitator, 0)` on canonical USDC | `0x3810cb39f1f9ff2411a36698d716e4a24c34a0c37a0f40f31d1a31fba4984384` | [link](https://basescan.org/tx/0x3810cb39f1f9ff2411a36698d716e4a24c34a0c37a0f40f31d1a31fba4984384) | 1 |
| 3 | **Clean EIP-712 `settle()` — signed against Base mainnet domain (chainId=8453, verifyingContract=facilitator)** | `0x22fe01758810e16bb90cd83da8e10c2d2dd882f1a0532c1161ae471f1732b7b5` | [link](https://basescan.org/tx/0x22fe01758810e16bb90cd83da8e10c2d2dd882f1a0532c1161ae471f1732b7b5) | 1 |
| 4 | **Planted-twin fire: replay same auth → reverts `AuthorizationConsumed()` (selector `0x1dd22e14`)** | `0xd15f9fe55777b9c35a2c331bb37129f9f033712e97b395ed7b5c24f496ec8c46` | [link](https://basescan.org/tx/0xd15f9fe55777b9c35a2c331bb37129f9f033712e97b395ed7b5c24f496ec8c46) | **0 (expected — the screen caught the fault)** |

## Planted-twin fire narrative (row 4)

Row 4 replays the exact successful `settle()` calldata from row 3. The
facilitator's V03/V04 defense (checks-effects-interactions with
`_authConsumed[h]` set to `true` *before* the token `transferFrom`)
rejects the second submission with the custom error
`AuthorizationConsumed()`. Selector `0x1dd22e14` is the return-data
of the on-chain revert; `cast keccak "AuthorizationConsumed()"` reproduces
that selector. This is a real on-chain fault-catch on Base mainnet — the
same defense the six planted twins under `test/planted/` exercise off-chain.

## Gas + burner balance

| Item | Value |
|---|---|
| Burner starting balance | 10000000000000000 wei (0.01 ETH) |
| Burner ending balance | 9996457145637013 wei (~0.009996 ETH) |
| Total gas consumed | 3542854362987 wei (~0.00000354 ETH; ~0.035% of drip) |
| Hard cap enforced | $10 (never approached; total spend far under $0.05 at typical ETH prices) |

Per-tx receipts:

| Tx | Gas used | Block |
|---|---|---|
| Deploy | 505794 | 48810612 |
| Approve | 35501 | 48810660 |
| Settle | 79594 | 48810661 |
| Planted replay | 29490 | 48810684 |

## Verify locally

```
cast receipt 0x4e21a6a75776864c78288ae9729f6252ce3d8a2a1db7d1013e353f139eee6cca --rpc-url https://mainnet.base.org
cast receipt 0x22fe01758810e16bb90cd83da8e10c2d2dd882f1a0532c1161ae471f1732b7b5 --rpc-url https://mainnet.base.org
cast receipt 0xd15f9fe55777b9c35a2c331bb37129f9f033712e97b395ed7b5c24f496ec8c46 --rpc-url https://mainnet.base.org
cast code    0x0E0CBf222eca590e56A0200D6eDa55EA651FD4F0                         --rpc-url https://mainnet.base.org
```

Row 4 will show `status: 0 (failed)` — that is the recorded proof the
defense caught the replay. All other txs show `status: 1 (success)`.

## Reproduce full run

```
git clone <repo>
cd <repo>
export X402_RPC_URL='<Base mainnet RPC>'
export OPERATOR_KEY='<burner key with Base mainnet ETH>'
export X402_USDC=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
export X402_SETTLE_VALUE=0
export X402_SKIP_MINT=true
./ci/live_mainnet.sh
```

Runner: `ci/live_mainnet.sh` (symlink → `live_sepolia.sh`; the chain
label is derived from the invocation name). See SECURITY.md for the
Actions-secrets contract; keys never land in the repo or in logs.

## Notes for engineering_lead §4b pre-verification

- Facilitator constructor was called with canonical USDC address — no
  MockUSDC path on mainnet (guarded by `X402_USDC` being set).
- Settle used `X402_SETTLE_VALUE=0`; operator holds no USDC, so a
  non-zero value would revert `ERC20InsufficientAllowance` (still a
  valid fault-catch, but the dispatch scope is "clean settle" — zero
  value clears with allowance zero on Circle USDC).
- `X402_SKIP_MINT=true` bypasses the Sepolia-only `MockUSDC.mint()`
  attempt inside `SettleSmoke.s.sol` (would otherwise revert
  `FiatToken: caller is not a minter` on canonical USDC and abort the
  broadcast). One-line env-guarded change on the script; Sepolia
  behavior unchanged.
- Domain-separator binding: settle recovered `signer == auth.from`
  against `chainId=8453` and `verifyingContract=0x0E0C…d4F0`; a
  chainId=1 or wrong-facilitator signature would `ecrecover` to a
  different address and revert `InvalidSignature()` (V05 defense).
