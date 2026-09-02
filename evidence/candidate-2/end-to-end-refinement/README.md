# End-to-end refinement evidence

This directory contains the replay inputs and qualification records for the
mandatory Native Full current profile. It is an evidence map, not a claim of
compiler correctness, deployment verification, or external legal truth.

## Public replay

From the repository root on Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/replay-current-profile-release.ps1
```

The replay checks the public release index, the seven-package aggregate, the
49 Core rows, the 24 Supporting rows, the two-layer runtime binding, hostile
runtime mutations, and the release manifest.

## Canonical files

| File | Role | Current result |
| --- | --- | --- |
| `../current-profile-release-index-v2.json` | Public release entry point | Packages 7/7, Core 49/49, Supporting 24/24, optional backlog 0/6 |
| `c-series-terminal-qualification-v2.json` | Repaired-candidate package successor | C0 rebound; C1-C6 checked-delta carry-forward with named current evidence |
| `current-profile-row-qualifications-v2.json` | Repaired-candidate row successor | All 73 mandatory rows rebound or checked-delta carried forward; frozen rows 0 |
| `c-series-terminal-qualification-v1.json` | Byte-exact historical package aggregate | Candidate 1 only |
| `m4-current-profile-row-qualifications-v1.json` | Proof-bound historical row index | Candidate 1 only |
| `runtime-binding-current-v2/manifest.json` | Current compiler and runtime input manifest | Pinned compiler replay and seven subject bindings |
| `runtime-binding-current-profile-qualification-v3.json` | Current runtime qualification | Six semantic projections per subject pass; hostile mutations fail closed |
| `../public-release/supersession-manifest-v1.json` | Historical-to-public identity map | Private coordinates removed without overwriting expectations |
| `../public-release/formal-foundation-supersession-v1.json` | Public formal-foundation succession | Fourteen mapped files and the temporary session fail closed on semantic or identity drift |
| `../public-release/diet-manifest-v2.json` | Successor public-tree accounting | Current retained tree plus the byte-exact v1 archive removal set |

## Source ownership

- `formal/isabelle/ERC_TRUST/` owns the abstract model, refinement statements,
  and proof-audit source.
- `formal/kevm/` owns the human-authored EVM reachability claims and pinned
  replay contracts.
- `implementation/` owns the Solidity reference, tests, Certora rules, and
  Kontrol inputs.
- `evidence/end-to-end-refinement/runtime-binding-current-v2/` owns current compiler inputs,
  compiler outputs, source identities, and runtime bridge projections.
- `formal-dependencies-public-v1.lock.json` owns the reachable public
  foundation pin and the temporary compatibility-session retirement rule.

## Archive boundary

Raw proof graphs, timestamp logs, failed formulations, private job manifests,
and development narratives are preserved in
`Oraclizer/erc-trust-archive` at the commit and tree recorded in the diet
manifest. They are not public replay inputs. The public tree retains the
authoritative Solidity, K, Isabelle, and Certora sources plus the smallest
qualification interface needed to reproduce the published boundary.

## Nonclaims

The evidence does not establish compiler correctness, a live deployment,
proxy or migration safety, arbitrary external policy truth, identity truth,
settlement truth, entitlement truth, or legal compliance. The optional six-row
assurance backlog remains outside the completed mandatory profile.
