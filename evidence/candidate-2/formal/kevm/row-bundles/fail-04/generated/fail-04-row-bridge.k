requires "../../../trust-runtime-verification.k"
// Generated FAIL-04 row metadata bridge; not a proof.
module TRUST-FAIL-04-ROW-BRIDGE
  imports TRUST-RUNTIME-VERIFICATION
  syntax Int ::= #fail04OperationalSelector [function]
  rule #fail04OperationalSelector => 946785368
  syntax Int ::= #fail04MalformedLength [function]
  rule #fail04MalformedLength => 127
  syntax Int ::= #fail04Reason [function]
  rule #fail04Reason => 202
endmodule
