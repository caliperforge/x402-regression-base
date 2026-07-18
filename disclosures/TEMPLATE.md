# Disclosure record template

Copy this file to `disclosures/YYYY-MM-DD_<slug>.md` when a finding lands against a downstream Base x402 integrator. The record ships in-repo after coordinated disclosure per `SECURITY.md`.

## Summary

- **Reported to:** `<integrator name + security contact>`.
- **Report date:** `<YYYY-MM-DD>`.
- **Acknowledged:** `<YYYY-MM-DD>`.
- **Fix landed:** `<YYYY-MM-DD>` (`<PR / commit link>`).
- **Public disclosure:** `<YYYY-MM-DD>`.

## Class

Map to a row in `coverage_map.md`. Example: `V02_ExpiryBypass`.

## What we observed

`<one paragraph: the specific manifestation in the integrator's code path, referencing the file / line / behavior>`.

## What we expected

`<one paragraph: the invariant that would hold if the class were defended against>`.

## Reproducer

`<git ref + one-command reproduction. Ideally: `git clone; ./run.sh --facilitator <address> --chain base-sepolia`>`.

## Fix

`<summary of the fix the integrator landed; link to the PR or commit>`.

## Credit

Reporter: `<name or "anonymous per reporter request">`.
