# Decision 05: reason classes

Status: frozen in kernel version 2 machine source (`reasonClasses`).

## Decision

The `uint16` reason carried by `TrustInvalidCommand`, `TrustRejected`, and
`TrustOperationalFailure` is partitioned into normative classes:

| Class | Range | Error | Meaning |
| --- | --- | --- | --- |
| 1 | 1 to 99 | `TrustInvalidCommand` | the command itself is malformed, stale, mis-shaped, replayed against case state, or mis-paired |
| 100 | 100 to 199 | `TrustRejected` | a completed dependency assessment denied the command |
| 200 | 200 to 299 | `TrustOperationalFailure` | a bound dependency was missing, changed, unreachable, or returned malformed or mismatched data |
| 300 | 300 to 399 | `TrustOperationalFailure` | the endpoint's own topology (a sealed profile) is not in the state required to execute |
| 400 | 400 to 499 | `TrustOperationalFailure` | an upstream token call of an adapter profile failed or produced a wrong post-state |

The listed codes inside each class are normative. An implementation MAY add
codes inside a class and MUST NOT reuse a listed code with a different
meaning. The reason is diagnostic; conformance tests key on the error
selector and the class, not on a specific unlisted code.

## Why

Version 1 used two unrelated numbering schemes: the native token used 1 to 9
and 100 to 205, the adapter used 401 to 411, and neither was written down as
a registry. An indexer could not tell a shape error from a topology error by
looking at the number, and the two profiles disagreed about what 4xx meant.
Classes give a stable coarse meaning without forcing every implementation to
emit identical fine-grained codes.

## Alternatives considered

- Fully normative codes with no room for implementation-defined ones.
  Rejected: it forces every implementation to invent the same failure taxonomy
  down to the last check.
- No registry at all. Rejected: it leaves the observable failure taxonomy of
  the standard undefined.

## Reopen when

- A profile needs a failure class that fits none of the five.
