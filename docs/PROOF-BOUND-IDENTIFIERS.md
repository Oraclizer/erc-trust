# Proof-bound historical identifiers

The public candidate retains a finite set of historical identifiers only where
renaming the file or token would change a verified source or an immutable
qualification record. These identifiers are development provenance, not current
workflow stages, approval gates, security roles, or external endorsements.

| Identifier family | Public meaning | Canonical source | Assurance boundary |
| --- | --- | --- | --- |
| `M4` and `TRUST_M4_*` | Historical label for the mandatory current-profile refinement campaign | Isabelle theories and immutable qualification records listed in the allowlist | The label adds no proof credit and must not appear in new source |
| `C0` through `C6` | Stable identifiers for the seven reusable verification packages | Package aggregate and K/Isabelle source | Each package is limited by its recorded assumptions and nonclaims |
| `ACT-*`, `STATE-*`, `BAL-*`, `REV-*`, `ABI-*`, `AUTH-*`, `FAIL-*`, `EXT-*`, `SEP-*`, `ART-*` | Stable row identifiers defined by the refinement inventory | Current-profile row index and named theorem source | A row identifier is not a deployment or legal-truth claim |
| `FV*` in frozen historical source | Historical property label retained only when listed by exact hash | Exact allowlisted source | It has no current repository-process meaning |

The machine-readable allowlist is
`evidence/public-release/proof-bound-identifiers-v1.json`. The public-tree
verifier rejects a new path, a new occurrence, an occurrence-count increase,
or a byte change in an allowlisted file. Credentials, personal paths, private
branch names, external secrets, and tool attribution are never allowlisted.
