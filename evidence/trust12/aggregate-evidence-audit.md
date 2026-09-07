# Independent review of aggregate evidence admission

Status: PASS for the reviewed local development change, with open refinement obligations.

The reviewer did not build or edit this change. It independently recomputed the
current and Git input inventories, actual local logs, proof exports and artifact
hashes. The final reviewed input manifest contains 32 changed files and has
SHA-256 `cf75fea7f574aa27bd838aeacbb74701037ef3faf9792f81fb8b700bd74b6628`.
Its files were unchanged at the start, middle and end of the final review.
Subsequent audit documentation and seal/render updates do not change the reviewed
executable checks, model sources or execution inputs.

## Reproduced defects and repairs

The initial review returned three defects: an unbuilt ADS directory could be
recorded against an old build; changed formal sources and receipt metadata could
be rehashed together; and the entire Hook compiler bundle could be omitted while
its subjects kept replay credit. The first repair rejected these cases, but a
second review found paired dependency-receipt changes were still admitted.

The final implementation captures the actual directories and input bytes before
and after the clean build, requires the recorder inputs to match that capture,
checks an independently recomputed admission digest over the execution commit,
formal source, complete dependency inventory and both proof-audit exports, and
requires every compiler bundle, subject and stored input/output file.

All four original counterexamples were rejected by actual isolated runs. The
reviewer inspected their runner, results and log hashes. It independently
recomputed admission digest
`54cf33dc4f49df53d50e1093a9a9b89bf7f9b466894597553155e1aaa7e2c483`
from the original execution materials, rather than importing the recorder helper.
It also checked the 32 regular admission controls against the test/verifier hashes.

## Verified scope

- Existing 37-input historical and 32-input Hook inventories match their Git blobs.
- The original local Foundry log contains the same 102 successful named tests,
  including nine actual T-REX integration tests.
- The actual clean build captured 32 formal inputs, 12 foundation overlay inputs,
  six ADS inputs, and matching before/after bytes. Parent and child exports retain
  412 and 12 explicit roots respectively, with zero oracle dependencies.
- Three compiler bundles cover seven runtime subjects and three files per bundle.
- The reviewer executed all four normal consistency verifiers with exit zero and
  observed `--require-release` reject the development state.

Raw review inputs, snapshots and counterexample logs remain under
`out/trust12/aggregate-audit-*` and `out/trust12/audit-negative-*`.
This receipt is an independent review of evidence admission and consistency. It
is not complete Assurance of TRUST 1.2, an implementation mutation rerun, a new
Kontrol/Certora result, a deployment audit or a discharge of any runtime link.
The six current mandatory obligations remain open. Input, dependency, session or
admission changes reopen the affected execution and review.

## Additional symbolic timeout review

A subsequent read-only review checked the distinct Booster timeout receipt and
its required-gate control. The 42 input files equal the named commit and current
source, all 22 copied proof files match their hashes, and the 20-node graph uses
CANCUN. The saved Native program differs from the template only at declared
immutable positions. The four normal gates passed; the 33 admission controls
include rejection of a fabricated Booster PASS. The original two no-Booster
receipts and all mandatory obligations remain unchanged in status. This review
credits an incomplete diagnostic result, not a symbolic proof. The reviewer did
not rerun the backend binary, WSL cleanup or solver; it inspected the captured
identity, scripts, logs and the runner's observations for those facts.

## Model execution admission and linked-run completion

A fresh read-only reviewer checked the 91-file frozen admission input
`92e3320d92e3ae00063e0f1c8292bffcccd4de3df08c9bc66e429852446f1b5d` and independently
reconstructed staged tree `932757c04abe53e965888ff82e7f9c1188eee513`. The source,
current bytes and execution commit `16a01c7f6ed252baa56ef504a224eccae3abc8bd` agree
for all 44 formal inputs and 33 theories. The actual before/after capture is
byte-exact at `78ef6bc9798f9ce8986762e7a7fab49884b177f631b0afcb613209204f5aaf53`.
The actual foundation overlay has 12 files and ADS has 6, with matching bytes.

The reviewer directly read both Cleaned/Finished messages, parent 181 seconds,
child 124 seconds, total build 317 seconds, wrapper exit 0, and the two actual
proof exports. Parent remains 412 roots/413 facts; child is 219 roots/236 facts;
both report zero oracle dependencies. The earlier 12-root child receipt was
read from the execution commit's Git blob. Its execution identity was not
rewritten into the new result.

Independently recomputed admission values:

- Formal input root: `63e69742a093fd80d95b69c6bfcafff5063cd02b55c99e23d5284e9b239cb6fe`.
- Execution/dependency/export digest: `4fe8d225182e8dcd34e85f68158650cd0c1e2f43e9e285105024719ee33639d3`.
- Model result: `7572efbbef9689c69dfc318e9d72902a8f87b32ba1d5df9b711418f29d989bce`.
- Formal replay: `d388eda901481cf3ded651f97a625bda19abff2fc6baeae25a184734039806fa`.
- Global Isabelle receipt: `4bf7795e439189a3904809aea081e5ae937776b09e3860ebc53b0cd6b373b3a9`.

The required gate consumes the exact model result and its source/audit
references. The new generator, capture helper, formal-input code and local
runner are included in the recorded formal inputs. The source-review scopes
and both reversible line-ending rules were independently reconciled. Four
normal verifiers were directly executed by the reviewer with exit 0. The
preserved release-denial raw reports exit 1 and `release mode required`.

MODEL-REGULATORY-PRESERVATION and MODEL-LINKED-RUN are CLOSED as abstract model
results. The symbolic FREEZE and three runtime producer rows remain mandatory,
with INCOMPLETE propagated into the global summary, closure and index. The
19 implementation source files remain byte-exact against the first Hook
checkpoint. Existing Foundry, deterministic, mutation and runtime identities
retain their own evidence ownership; the Partial profile stays full=false.

## Runtime feasibility admission: affected review

The follow-up read-only review checked the 32-file delta
`0a3647bd3d14811f6b9bba073ed8dbf09a46d1cfda25c125140c90ead8640705`, independently
reconstructing staged tree `be412370f25edae1aa3ca8f706028c8a2bc3f032`. Ten files
from the earlier input changed and were all declared in the delta; no other
drift was found. Formal input, model result and the four mandatory rows remain
unchanged. Main independently compared all 32 final hashes before this entry.

The runtime feasibility receipt is bound at
`5e79eeefba7228515868535bbb43150d1d84e724103ed3542f1d81338751939e`.
The reviewer checked its eight source anchors, seven raw references, exact
1,261.947-second duration, installed 18-file Kontrol/123-file pyk census and
12 selected package-source hashes. It confirmed Solidity/K/KEVM output paths
and the absence of an operational Isabelle receiver in the inspected source.
This is a bounded source inspection, not an impossibility result.

The saved APRProof has admitted=false. Current graph data contains 22 files,
20 nodes, 14 edges, zero covers and two splits. The current file-inventory root
is `df20fafd53ece4921267ef109d55b134e27471aaa55ede48ccb1e1cf76765e98`.
The data parser called KCFG.from_dict and reported a successful before/after
comparison. Its historical per-file before/after list was not itself saved,
so an independent historical comparison of every node file is not claimed.
The source program, raw result, graph identities and current inventory were
checked. This carries data-format credit only, with no new prover execution.

The two added negatives reject missing feasibility evidence and fabricated
feasibility completion. All earlier 47 controls remain and all 49 unique
negative fixtures are REJECTED. Raw and curated controls match at
`7df81db7d1df82e9c85515c71f7754c4d81ec7b067f78a950347582ed9d8b957`.
The reviewer matched verifier `08382cbf87748f5af9f73e52c89465875a89646657a963cd0486bfea13d678c0`
and test `dce0e6b0569a75c4c1ce3833e264f5404bf640ab042043d2da8c508da324c24e`
to the recorded source identities, and directly ran all four normal verifiers.

Both admission reviews returned PASS with no required source repair. They did
not rerun Isabelle, the mutation fixtures or external provers. Final evidence
and checkpoint accounting are Main responsibilities. No review closes the
runtime_link assumption, constructor/storage decoding, EVM word correspondence,
legal truth or support for every ERC-3643 implementation.
