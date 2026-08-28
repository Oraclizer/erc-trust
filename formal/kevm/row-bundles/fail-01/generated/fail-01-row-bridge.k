// GENERATED FAIL-01 row-local metadata bridge. DO NOT EDIT.
requires "edsl.md"

module TRUST-FAIL-01-ROW-BRIDGE
    imports EDSL
    syntax String ::= "#trustFail01RequiredProperty" [macro]
    rule #trustFail01RequiredProperty => "semantic_rejection_reverts_and_stutters"
    syntax String ::= "#trustFail01ClaimSha256" [macro]
    rule #trustFail01ClaimSha256 => "97697d9b285edb9bc5319a9abe15a17f7a7d3664cddfc558a6d478e65e2961db"
    syntax String ::= "#trustFail01RuntimeSha256" [macro]
    rule #trustFail01RuntimeSha256 => "3697706d4948c34fada47e049d32ad3e1866cf24ded6328f0c209d858614a86d"
    syntax Int ::= "#trustFail01Selector" [macro]
    rule #trustFail01Selector => 2644653369
    syntax Int ::= "#trustFail01TypedErrorSelector" [macro]
    rule #trustFail01TypedErrorSelector => 3982638099
    syntax Int ::= "#trustFail01CalldataBytes" [macro]
    rule #trustFail01CalldataBytes => 676
    syntax Int ::= "#trustFail01TypedErrorBytes" [macro]
    rule #trustFail01TypedErrorBytes => 68
    syntax String ::= "#trustFail01ProofStatus" [macro]
    rule #trustFail01ProofStatus => "NOT_RUN"
    syntax String ::= "#trustFail01ClosureStatus" [macro]
    rule #trustFail01ClosureStatus => "OPEN"
    syntax Int ::= "#trustFail01EligibleForDischarge" [macro]
    rule #trustFail01EligibleForDischarge => 0
endmodule
