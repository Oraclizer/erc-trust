// SPDX-License-Identifier: BSD-3-Clause
// Pure K support lemma with the pinned KEVM test harness shape.
module C0-UINT48-REJECT-SUPPORT-HARNESS
  imports TRUST-RUNTIME-VERIFICATION

  syntax StepSort ::= Int | Bool
  syntax KItem ::= runLemma ( StepSort ) [symbol(runLemma)]
                 | doneLemma ( StepSort )
  rule runLemma ( T ) => doneLemma ( T )
endmodule

module C0-UINT48-REJECT-SUPPORT-V2-SPEC
  imports C0-UINT48-REJECT-SUPPORT-HARNESS

  claim [c0-uint48-high-mask-is-not-self]:
    <k>
      runLemma ( chop ( W -Int ( maxUInt48 &Int W ) ) ==Int 0 )
      => doneLemma ( false )
      ...
    </k>
    requires (2 ^Int 48) <=Int W andBool W <Int (2 ^Int 256)

endmodule
