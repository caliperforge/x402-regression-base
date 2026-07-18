# Contributing to x402-regression-base

Thanks for your interest. `x402-regression-base` is an Apache-2.0 library of planted-twin regressions for x402 payment facilitators on Base. Contributions that sharpen the harness against real Base x402 integrations are welcome.

## How decisions get made

Single human operator-of-record (CaliperForge) reviews and merges. AI specialists draft and review under final human pass. There is no separate maintainer group at v0.

## What we accept

| Contribution shape | Default response | Notes |
|---|---|---|
| Bug reports with a reproducer | Welcome | Open a GitHub issue with `forge --version`, OS + arch, and a minimal reproducer |
| Documentation fixes | Welcome | Typos, broken links, README clarifications: PR directly |
| New planted twins (`src/*.sol` + `test/<Name>/<Name>.t.sol` + `test/planted/<Name>.planted.t.sol`) | Discuss first in an issue | Must ship as **clean + planted pair** with the `INVARIANT VIOLATED <name>` marker; must cite a public source (arXiv paper, spec section, post-mortem) for the bug class |
| Additional coverage against Base x402 reference implementations | Discuss first in an issue | Must map to a row in `coverage_map.md`; new rows require a public source citation |
| Refactors with no behavior change | Discuss first | Land if they meaningfully reduce surface |
| Security reports | Do **not** open a public issue | See `SECURITY.md` |
| Findings against downstream Base x402 integrations | Route through `disclosures/` workflow | The disclosure record ships in-repo after coordination with the affected integrator |

## PR checklist for a new planted twin

Every new planted twin ships with all of the following or the PR will be held:

1. **Reference facilitator hunk in `src/facilitator/X402Facilitator.sol`** (or a new primitive under `src/facilitator/` if the class needs one): the CLEAN reference behavior, all defenses on.
2. **`test/<Name>/<Name>.t.sol`**: the clean-leg test. Passes silently under the pinned toolchain.
3. **`test/planted/<Name>.planted.t.sol`**: the planted-leg test. Declares an inline `BrokenX402Facilitator<Name>` (or equivalent primitive) with a single-hunk mutation, surfaces at least one `INVARIANT VIOLATED <name>` marker, and exits non-zero under the pinned toolchain.
4. **CI wiring**: no workflow edits typically needed; `run.sh` discovers the new twin by path convention.
5. **`coverage_map.md` row**: updates the catalog row for the reproduced bug class, with a source citation.
6. **NatSpec on the twin**: explains the bug class, cites the public source, and names the single-hunk mutation semantics.

## What we do NOT accept

- New planted twins without a public source citation. Every bug class in the harness must trace to a paper, a spec section, a post-mortem, or an equivalent published artifact. First-party novel-variant twins are welcome but must be marked as such (like V05 / V06 in the M1 shipping set) and must not claim adoption or endorsement.
- Cross-substrate contributions. This library covers x402 on Base only. Contributions targeting other agentic-payments rails or other chains should route to the appropriate `caliperforge/` sibling repo.
- Runtime-monitoring code. This is a pre-deploy CI library. Runtime monitoring is out of scope.
- Contributions that strip the `INVARIANT VIOLATED <name>` marker or the clean/planted twin convention. The marker + twin shape is load-bearing for both the local runner and the CI matrix.
- Naming that trips the anti-bloat rules: no `Manager` / `Helper` / `Util` / `Factory` scaffolding, no `_v2` / `enhanced_` / `comprehensive_` / `robust_` naming.

## Toolchain

- Solidity 0.8.28 pinned in `foundry.toml`.
- Foundry (`forge`, `cast`, `anvil`).
- No paid tool tiers. `slither` (free) and `forge inspect` are the static-analysis baseline.

## AI disclosure

This repository is authored by a human-supervised AI-augmented process. See `AI_DISCLOSURE.md` for the full disclosure. Contributors are asked to disclose AI assistance in their own PRs at the level of specificity they are comfortable with. A one-line note in the PR description is sufficient.
