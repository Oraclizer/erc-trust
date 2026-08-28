## Summary

Describe the smallest reviewable change and why it is needed.

Closes:

## Change type

- [ ] Specification or semantics
- [ ] Solidity implementation
- [ ] SDK, schema, or vectors
- [ ] Formal or bounded verification
- [ ] Documentation or repository operations
- [ ] Dependency or toolchain update

## Claim impact

- [ ] No public claim changes
- [ ] Claim/evidence matrix updated
- [ ] Formal model or dependency lock updated
- [ ] External truth or deployment remains outside scope

Explain any changed claim, profile, compatibility, trust boundary, or
deployment assumption:

## Verification

- [ ] `forge fmt --check`
- [ ] `forge build --sizes`
- [ ] `forge test --fuzz-runs 256 -vv`
- [ ] `forge lint`
- [ ] `pnpm --dir sdk test`
- [ ] Relevant Certora/Kontrol rules or an explicit N/A explanation
- [ ] Relevant negative mutation
- [ ] `node scripts/generate-vectors.mjs` with the regenerated file committed
- [ ] `node scripts/generate-release-manifest.mjs` + `node scripts/verify-release.mjs`
- [ ] `node scripts/verify-links.mjs`
- [ ] `node scripts/verify-public-surface.mjs`
- [ ] `node scripts/verify-repository-health.mjs`

Paste concise results or link the exact Continuous Integration run:

## Security and provenance

- [ ] No credentials, local absolute paths, caches, or raw private logs
- [ ] SPDX and third-party license/provenance reviewed
- [ ] Generated manifest and vectors regenerated when affected
- [ ] New dependency or GitHub Action pins are exact and justified
- [ ] No audit, deployment, legal-truth, or production claim is implied

## Reviewer focus

Identify the highest-risk assumption, invariant, or compatibility edge that
reviewers should examine.

This project is unaudited and not for production.
