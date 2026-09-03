// SPDX-License-Identifier: BSD-3-Clause
// Pure K support lemma for the frozen UINT48 reject branch.
module C0-UINT48-REJECT-SUPPORT-SPEC
  imports TRUST-RUNTIME-VERIFICATION

  claim [c0-uint48-high-mask-is-not-self]:
    <k>
      runLemma ( chop ( W -Int ( maxUInt48 &Int W ) ) ==Int 0 )
      => doneLemma ( false )
      ...
    </k>
    requires (2 ^Int 48) <=Int W andBool W <Int (2 ^Int 256)

endmodule
