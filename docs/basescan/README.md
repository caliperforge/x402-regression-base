# docs/basescan/

Real-network deployment + settle receipts populated by `ci/live_sepolia.sh`
(W2) and `ci/live_mainnet.sh` (W6). Each run writes one file:
`sepolia_run_<YYYY-MM-DD>.md` or `mainnet_run_<YYYY-MM-DD>.md`. Every tx
hash in these files resolves on Basescan; that is the load-bearing proof
per M1 spec §5.1 (scaffold-verified before README's "Live on Base"
section flips to load-bearing).

Local anvil-based dry-runs of the runner machinery live under
`../local_dryrun/` and are clearly marked "NOT A REAL BASE RUN." Do not
confuse the two.

## Empty at W2 close

W2 (this wave) shipped the deploy + settle machinery + fork-mode
harness runner + `.github/workflows/live-sepolia.yml`. Actual population
of a `sepolia_run_*.md` file requires the `workflow_dispatch` step
firing under the two Actions secrets `BASE_SEPOLIA_RPC_URL` +
`OPERATOR_KEY_SEPOLIA` (see W2 result §4 + §5). Second-machine
reproduction per §5.1 attaches to the W2 close-note the same day the
record lands.
