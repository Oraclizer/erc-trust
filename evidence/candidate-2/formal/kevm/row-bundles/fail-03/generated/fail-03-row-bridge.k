requires "../../../trust-runtime-verification.k"
// Generated FAIL-03 metadata bridge; not proof evidence.
module TRUST-FAIL-03-ROW-BRIDGE
  imports TRUST-RUNTIME-VERIFICATION
  syntax Int ::= #fail03OperationalSelector [function]
  rule #fail03OperationalSelector => 946785368
  syntax Int ::= #fail03Reason [function]
  rule #fail03Reason => 202
  syntax Int ::= #fail03DependencyRuntimeBytes [function]
  rule #fail03DependencyRuntimeBytes => 77
endmodule
