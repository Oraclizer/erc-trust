// GENERATED ABI-04 finite+symbolic row-local metadata bridge. DO NOT EDIT.
requires "edsl.md"

module TRUST-ABI-04-FINITE-SYMBOLIC-ROW-BRIDGE
    imports EDSL
    syntax String ::= "#trustAbi04FiniteMatrixRootSha256" [macro]
    rule #trustAbi04FiniteMatrixRootSha256 => "3347fd98dcb04769394fb8705a58c644574ff50999da5eea8a7da07de2134833"
    syntax String ::= "#trustAbi04SymbolicClaimsRootSha256" [macro]
    rule #trustAbi04SymbolicClaimsRootSha256 => "3594a2034746c45ab52236b44b381dff00a11ce901dbd55eedb18df034de8ab3"
    syntax String ::= "#trustAbi04CombinedRequirementRootSha256" [macro]
    rule #trustAbi04CombinedRequirementRootSha256 => "63796426169cfe15dca16f0640a7b1861f334f83a405148b3f357f8c08dc2363"
    syntax Int ::= "#trustAbi04FiniteClaimCount" [macro]
    rule #trustAbi04FiniteClaimCount => 69
    syntax Int ::= "#trustAbi04SymbolicClaimCount" [macro]
    rule #trustAbi04SymbolicClaimCount => 12
    syntax Int ::= "#trustAbi04RequiredReplayCount" [macro]
    rule #trustAbi04RequiredReplayCount => 162
    syntax Int ::= "#trustAbi04ActionEndpointCount" [macro]
    rule #trustAbi04ActionEndpointCount => 3
    syntax Int ::= "#trustAbi04ReversalEndpointCount" [macro]
    rule #trustAbi04ReversalEndpointCount => 3
    syntax Int ::= "#trustAbi04SymbolicMissingLengthCardinality" [macro]
    rule #trustAbi04SymbolicMissingLengthCardinality => 2868
    syntax Int ::= "#trustAbi04CompleteShortLengthCardinality" [macro]
    rule #trustAbi04CompleteShortLengthCardinality => 2880
    syntax String ::= "#trustAbi04ProofStatus" [macro]
    rule #trustAbi04ProofStatus => "NOT_RUN"
    syntax String ::= "#trustAbi04ClosureStatus" [macro]
    rule #trustAbi04ClosureStatus => "OPEN"
    syntax Int ::= "#trustAbi04EligibleForDischarge" [macro]
    rule #trustAbi04EligibleForDischarge => 0
    syntax Int ::= "#trustAbi04Abi03CoverageCredit" [macro]
    rule #trustAbi04Abi03CoverageCredit => 0
endmodule
