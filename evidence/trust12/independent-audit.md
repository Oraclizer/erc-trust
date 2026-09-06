# TRUST 1.2 independent functional audit

Status: PASS for the exact local development source sealed by
evidence/trust12/input-seal.json SHA-256
14d76cb54ea8cbd5f566bc274a1a6cc15f2682e3cd27099899f520bb16c28331.

The independent auditor recalculated every sealed file, rebuilt the actual pinned
T-REX integration in a separate output/cache root, reran the nine integration tests,
and inspected all six semantic mutations. The first review returned one mutation
because its malformed endpoint reverted before the factory could accept it. The
Building writer replaced that fixture with a constructible 492-byte endpoint that
implements the factory's three reads and reports full=true without implementing
TRUST behavior.

The repair audit reproduced both sides:

- the unmodified factory rejects that endpoint at the exact creation-code pin;
- with only the pin consumer removed, the factory creates the endpoint, completes
  all three reads, emits HookUnitCreated, returns successfully, and the test fails
  at factory accepted bypass endpoint.

The auditor also confirmed the actual inbound hook, callback rollback, actual
restriction receipt, exact fresh source, sole Agent, callback caller, and preserved
Native/Partial/governor source and runtime results. The legacy Partial descriptor
continues to report full=false.

This PASS approves the named development reference's functional conformance for the
exact Tokeny T-REX 4.1.3 source and compiler profile. It is not a production audit,
deployment result, legal approval, claim about every ERC-3643 implementation, or a
discharge of the Native, Partial, or Hook runtime_link.

The raw read-only reports and isolated replay outputs are stored locally under
out/trust12/final-independent-audit/; they are not tracked release inputs.
