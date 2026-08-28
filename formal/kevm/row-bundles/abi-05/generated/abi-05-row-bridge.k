requires "../../../trust-runtime-verification.k"
// Generated ABI-05 schema bridge. Metadata only; not a claim or proof.
module TRUST-ABI-05-ROW-BRIDGE
  imports TRUST-RUNTIME-VERIFICATION
  syntax Int ::= #abi05SelectorBytes [function]
  rule #abi05SelectorBytes => 4
  syntax Int ::= #abi05ActionTupleWords [function]
  rule #abi05ActionTupleWords => 21
  syntax Int ::= #abi05ReversalTupleWords [function]
  rule #abi05ReversalTupleWords => 9
  syntax Int ::= #abi05ActionCalldataBytes [function]
  rule #abi05ActionCalldataBytes => 676
  syntax Int ::= #abi05ReversalCalldataBytes [function]
  rule #abi05ReversalCalldataBytes => 292
  syntax Int ::= #abi05EndpointFamilyCount [function]
  rule #abi05EndpointFamilyCount => 6
  syntax Int ::= #abi05CalldataBackedTypedFieldCount [function]
  rule #abi05CalldataBackedTypedFieldCount => 30
  syntax Int ::= #abi05StateDerivedTypedFieldCount [function]
  rule #abi05StateDerivedTypedFieldCount => 1
endmodule
