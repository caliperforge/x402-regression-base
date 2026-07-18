# Security Policy

`x402-regression-base` is a CI-runnable library of planted-twin regressions for x402 payment facilitators on Base. We take security reports against the library itself seriously and aim to acknowledge every credible report within seven days.

## This library is NOT an audit

Before filing a report, please read:

- A passing run of `x402-regression-base` against a Base x402 facilitator or resource-server does NOT certify the integration is safe. The library catches the bug classes the planted twins encode (see `coverage_map.md`); the residual surface belongs to the integrator.
- An `INVARIANT VIOLATED <name>` marker firing in a `test/planted/` twin (or in any documented planted-hunk reference) is the library **working as intended**. That output is not a vulnerability in `x402-regression-base`.
- This library is not a runtime monitor and does not encode every failure mode contemplated by the x402 protocol. Read the x402 protocol description at the coinbase/x402 repository directly.

## What to report through this policy

Report to the responsible-disclosure contact below if you find any of the following in the library **itself** (not in a fork or in a downstream integrator):

- A planted twin whose clean leg fires `INVARIANT VIOLATED` on the pinned toolchain (a false-positive clean leg is a correctness bug in the library).
- A planted twin whose planted leg passes silently on the pinned toolchain (a missed catch is a coverage bug in the library).
- A code path in `src/` that would compile into a downstream integrator fork and introduce a new failure mode not present in the reference implementation being reproduced.
- Any information leakage in the repo itself (accidental key commit, private-endpoint URL, etc.).

## What to report elsewhere

- **Bugs you find in a downstream Base x402 facilitator or resource-server by running a fork of this harness against it.** Report those to that integrator's security contact directly. If the integrator has no security contact and you want help routing the disclosure, we can help; see the disclosure workflow in `disclosures/TEMPLATE.md`. The primary responsible-disclosure surface is the integrator, not us.
- **Bugs in the x402 protocol description or the Coinbase x402 reference SDK.** Report to the coinbase/x402 repository via its own security channel.
- **Bugs in Foundry, `forge`, or any upstream dependency this library pins.** Report to that upstream project.

## How to report

- **Email:** `michael@caliperforge.com` (single-operator address; the operator-of-record monitors directly per §"What we do NOT commit to" below).
- **GitHub security advisory:** enable "Report a vulnerability" once the repo is public; that surface routes to the same role contact.
- **PGP:** optional. A key will be published under `docs/pgp.asc` if a reporter requests encrypted communication. Reporters who need PGP can request the key at the email address above.

Please include:

- A clear statement of what you observed and what you expected.
- The toolchain versions you ran (`forge --version` output; OS + arch).
- A minimal reproducer (branch, commit, command sequence). The closer to a one-command reproduction, the faster the turn.

## Secrets contract (adopter-facing)

If you are adopting this library via the `base-x402-ci` GitHub Action:

- Never commit an operator private key. Use GitHub Actions Secrets (`OPERATOR_KEY`) with a burner wallet that holds only enough funds to pay test-gas.
- Never reuse a wallet with production balances as the operator wallet.
- Rotate the operator key on any suspected exposure. Regenerating a Base wallet is free.
- RPC endpoint URLs with API keys (Alchemy, Infura, QuickNode) are also secrets. Store as `BASE_MAINNET_RPC_URL` / `BASE_SEPOLIA_RPC_URL` in Actions Secrets, never in-repo.

## Disclosure window

- **Default:** 90 days from acknowledgement to public disclosure. This matches the industry-standard responsible-disclosure window used by CERT/CC and most maintainer surfaces.
- **Extension:** we may request an extension if the fix requires coordination with a downstream integrator; the extension will be justified in writing and capped.
- **Short window:** if the bug is under active abuse in the wild or exposes end-user funds, we will move to a shorter window and coordinate with the affected integrator.

## What we commit to

- Acknowledge every credible report within seven calendar days.
- Confirm reproduction or ask specific clarifying questions within fourteen calendar days.
- Publish a fix (or a documented won't-fix rationale) before the disclosure window closes.
- Credit the reporter in the release notes and in `disclosures/` unless the reporter requests anonymity.

## What we do NOT commit to

- A bug-bounty payout. This library is Apache-2.0 open source with no funding line. Credible reports receive credit, not cash.
- Formal SLA commitments beyond the above. The operator-of-record is a single human; response times outside those windows depend on availability.

## Scope of this policy

- `x402-regression-base` at any commit under the `caliperforge/` org.
- Forks are out of scope; report fork issues to the fork maintainer.
