# expected_output: what a green run and a planted-fire run look like

> **This file is a prose reference, not a screenshot.** Per the parent repo's asset policy (M1 spec §5.7), no simulated CI-page image is authored: no live Sepolia or mainnet capture exists yet, and mocking one would fabricate. When W2 lands a real Sepolia deploy (and W6 lands mainnet), this file is either superseded by a real terminal recording or extended with the verbatim live-Sepolia log.
>
> The blocks below reflect the shape `run.sh` + `entrypoint.sh` actually print on the local V01–V06 matrix (which is already green in CI on the parent repo). Line-shape is truthful; the specific hashes are placeholders written as `<hash-1>`, `<hash-2>`, etc.

---

## 1. Green run: job log shape

The `base-x402-ci` job (`base-x402-ci (planted-twin regression against live facilitator)` in the CI page) is expected to look like this:

```
Run caliperforge/x402-regression-base@v0.1.0
  with:
    facilitator:  ***                (masked by GH Actions)
    chain:        base-sepolia
    rpc-url:      ***                (masked)
    operator-key: ***                (masked; ::add-mask:: fired as first line of entrypoint.sh)
    variants:     V01,V02,V03,V04,V05,V06
    fail-on:      fail

[entrypoint] chain=base-sepolia variants=V01,V02,V03,V04,V05,V06 fail-on=fail
[entrypoint] preflight OK
[entrypoint] launching harness against facilitator ***

[run.sh] forge build ... OK
[run.sh] clean legs
  V01_Replay        clean  PASS
  V02_ExpiryBypass  clean  PASS
  V03_NonceReuse    clean  PASS
  V04_DoubleGrant   clean  PASS
  V05_CrossDomainReplay  clean  PASS
  V06_DelegationCap clean  PASS
[run.sh] planted legs
  V01_Replay        planted  FIRE   INVARIANT VIOLATED V01_Replay
  V02_ExpiryBypass  planted  FIRE   INVARIANT VIOLATED V02_ExpiryBypass
  V03_NonceReuse    planted  FIRE   INVARIANT VIOLATED V03_NonceReuse
  V04_DoubleGrant   planted  FIRE   INVARIANT VIOLATED V04_DoubleGrant
  V05_CrossDomainReplay  planted  FIRE   INVARIANT VIOLATED V05_CrossDomainReplay
  V06_DelegationCap planted  FIRE   INVARIANT VIOLATED V06_DelegationCap
[run.sh] summary: clean=6/6 passed, planted=6/6 fired

[entrypoint] harness_ec=0 any_bad=0
[entrypoint] wrote report: /github/workspace/x402-ci-report.json
[entrypoint] exit_code=0 fail-on=fail - clean pass path
```

Outputs surfaced to downstream steps:

```
variants-passed: V01,V02,V03,V04,V05,V06
variants-fired:  V01,V02,V03,V04,V05,V06
report-path:     /github/workspace/x402-ci-report.json
```

The uploaded `x402-ci-report.json` artifact contains one JSON object per variant with `id`, `clean_status` (`pass` | `fail`), `planted_status` (`fire` | `miss`), and a `marker_line` field carrying the exact `INVARIANT VIOLATED` string per planted leg. Schema in the parent repo at `docs/report_schema.json`.

---

## 2. Planted-fire run: the intended fail signal shape

If your facilitator carries one of the bug classes the planted twin encodes, the planted leg does not fire the marker (the specification violation is already live rather than newly introduced by the planted mutation). The runner surfaces that as a red CI job:

```
[run.sh] planted legs
  V01_Replay        planted  MISS   (expected marker not surfaced)
  V02_ExpiryBypass  planted  FIRE   INVARIANT VIOLATED V02_ExpiryBypass
  V03_NonceReuse    planted  FIRE   INVARIANT VIOLATED V03_NonceReuse
  V04_DoubleGrant   planted  FIRE   INVARIANT VIOLATED V04_DoubleGrant
  V05_CrossDomainReplay  planted  FIRE   INVARIANT VIOLATED V05_CrossDomainReplay
  V06_DelegationCap planted  FIRE   INVARIANT VIOLATED V06_DelegationCap
[run.sh] summary: clean=6/6 passed, planted=5/6 fired

::error::[entrypoint] planted variant V01_Replay did not fire; see coverage_map.md row V01
[entrypoint] harness_ec=0 any_bad=1
[entrypoint] wrote report: /github/workspace/x402-ci-report.json
[entrypoint] exit_code=1 fail-on=fail - surfacing as failure (harness_ec=0)
```

Outputs in the failing case:

```
variants-passed: V01,V02,V03,V04,V05,V06         (clean legs still all pass)
variants-fired:  V02,V03,V04,V05,V06             (V01 is the miss)
report-path:     /github/workspace/x402-ci-report.json
```

The `::error::` annotation lands in the GH Actions job summary with a direct pointer at the `coverage_map.md` row for the class. Read the row, patch the facilitator, re-run.

---

## 3. What is guaranteed not to appear in the log

Per the parent repo's honesty rails (M1 spec §5), the runner never prints:

- Any hex string longer than 40 characters that could be an `OPERATOR_KEY` (masked via `::add-mask::` as the first executable line of `entrypoint.sh`; defense-in-depth against later `set -x`).
- The verbatim RPC URL (also secret-shaped in GH Actions; masked by the same mechanism when passed as `${{ secrets.BASE_SEPOLIA_RPC_URL }}`).
- Any of the framing tokens the parent repo's register discipline bans (`agents/engineering_lead/templates/planted_twin_framing_discipline.md`). The planted twins are our own synthetic specification violations against the reference facilitator, not claimed catches on a live surface.

If any of the above surfaces in a run log you can reproduce, that is a bug in the runner and should be reported per `SECURITY.md` in the parent repo.

---

## 4. Live-Sepolia capture (deferred)

Once W2 lands the reference facilitator on Base Sepolia and captures Basescan tx hashes, this section will carry:

- The verbatim `./run.sh --live-sepolia` log block (redacted secrets).
- A pointer to `docs/basescan/sepolia_run_<date>.md` in the parent repo, listing the deploy tx + settle tx + planted-fire tx hashes.
- A pointer to the corresponding GH Actions run page on the parent repo's `live-sepolia.yml` nightly job.

No content in that section until a real run has executed. Placeholder omitted deliberately.

---

## 5. Live-mainnet capture (deferred)

Same shape as §4, sourced from `docs/basescan/mainnet_run_<date>.md` once W6 lands. Held for the parent repo's public flip + Base Builder Grants nomination surface; not required for a Sepolia-only adopter to derive value from the template.
