// GENERATED FAIL-02 row-local metadata bridge. DO NOT EDIT.
requires "edsl.md"

module TRUST-FAIL-02-ROW-BRIDGE
    imports EDSL
    syntax String ::= "#trustFail02RequiredProperty" [macro]
    rule #trustFail02RequiredProperty => "dependency_denial_is_typed_rejection"
    syntax String ::= "#trustFail02ClaimSha256" [macro]
    rule #trustFail02ClaimSha256 => "cf85c6308c163f6ff0693f5c06c34ad49470ee4e0b1b3399c1483b40a670d973"
    syntax String ::= "#trustFail02RuntimeSha256" [macro]
    rule #trustFail02RuntimeSha256 => "3697706d4948c34fada47e049d32ad3e1866cf24ded6328f0c209d858614a86d"
    syntax String ::= "#trustFail02DependencyCodeId" [macro]
    rule #trustFail02DependencyCodeId => "0x8ccc6882c5c546fa0a4b18c09ebf6082dbebd49628b2b08fa22dbdf589ba6fbe"
    syntax Int ::= "#trustFail02ActionSelector" [macro]
    rule #trustFail02ActionSelector => 2644653369
    syntax Int ::= "#trustFail02RejectedSelector" [macro]
    rule #trustFail02RejectedSelector => 2364935023
    syntax Int ::= "#trustFail02OperationalSelector" [macro]
    rule #trustFail02OperationalSelector => 946785368
    syntax Int ::= "#trustFail02CalldataBytes" [macro]
    rule #trustFail02CalldataBytes => 676
    syntax Int ::= "#trustFail02TypedErrorBytes" [macro]
    rule #trustFail02TypedErrorBytes => 68
    syntax String ::= "#trustFail02ProofStatus" [macro]
    rule #trustFail02ProofStatus => "NOT_RUN"
    syntax String ::= "#trustFail02ClosureStatus" [macro]
    rule #trustFail02ClosureStatus => "OPEN"
    syntax Int ::= "#trustFail02EligibleForDischarge" [macro]
    rule #trustFail02EligibleForDischarge => 0
endmodule
