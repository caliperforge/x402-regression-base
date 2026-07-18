# AI disclosure

`x402-regression-base` is authored by a human-supervised, AI-augmented process. This file records the disclosure per the CaliperForge portfolio standard so downstream readers can weigh the contribution accordingly.

## Authorship model

- **Operator-of-record:** Michael Moffett (`michael@caliperforge.com`), single human maintainer.
- **AI contributors:** specialised Claude agents (planning, Solidity implementation, code review, docs) operating within the CaliperForge agent framework. Every commit passes through a human review pass before landing on `main`.
- **What "human-supervised" means here:** the operator reads every hunk before commit, weighs trade-offs against the ticket's acceptance criteria and the portfolio's engineering standards, and rejects changes that miss the bar. Agents do not push directly to `main`.

## What the AI contributors did

- Drafted the reference facilitator source under `src/facilitator/` from the specification in the M1 ticket, cross-checking against the coinbase/x402 public protocol description and Circle's EIP-3009 USDC contract.
- Drafted the planted-twin reference contracts under `test/planted/` with single-hunk mutations of the clean facilitator, one per bug class.
- Drafted the clean-leg tests and the planted-leg tests. Every test signs authorizations through the shared `test/harness/AuthSigner.sol` helper so the on-chain and off-chain digest math stay byte-identical.
- Drafted `run.sh`, `foundry.toml`, `remappings.txt`, the CI matrix, this file, `SECURITY.md`, `CONTRIBUTING.md`, and the `NOTICE` file.
- Ran `forge build` and `./run.sh` locally, iterated until every clean leg passed silently and every planted leg surfaced the `INVARIANT VIOLATED` marker.

## What the AI contributors did NOT do

- Merge to `main` without human review.
- Deploy to any live chain. Base Sepolia + Base mainnet deployments are owned by later wave tickets (W2 + W6) and gated on separate human review.
- Claim adoption, endorsement, or coverage that does not correspond to a shipped planted twin.
- Fabricate arXiv URLs, contract addresses, tx hashes, or run logs. Where a citation is pending live re-fetch, the row carries `[UNVERIFIED-AT-DRAFT]` until verified.

## Model tier + reproducibility

- Model tier: Anthropic Claude family (specific model tag recorded per-commit via the AI-disclosure footer on merged PRs).
- Every merged PR carries a one-line AI-disclosure footer per the CaliperForge portfolio standard.
- No paid tool tiers required to reproduce (Foundry is the only external dependency).
