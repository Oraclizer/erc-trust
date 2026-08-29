// SPDX-License-Identifier: BSD-3-Clause
// UINT64 D1 reject with exactly two Isabelle-proved redundant hypotheses.
module C0-UINT64-SYMBOLIC-REJECT-D1-SPEC
  imports TRUST-RUNTIME-VERIFICATION

  claim
    <kevm>
      <k> #execute => ?_ </k>
      <exit-code> 1 </exit-code>
      <mode> NORMAL </mode>
      <schedule> CANCUN </schedule>
      <useGas> false </useGas>
      <ethereum>
        <evm>
          <statusCode> EVMC_SUCCESS </statusCode>
          <callState>
            <program> #trustTrustTokenRuntime() </program>
            <jumpDests> #computeValidJumpDests(#trustTrustTokenRuntime()) </jumpDests>
            <wordStack> W : 0 : 0 : 0 : 0 : .WordStack => ?_ </wordStack>
            <pc> 13537 => 2767 </pc>
            <gas> #gas(_VGAS) </gas>
            <memoryUsed> _VMEMUSED </memoryUsed>
            <callGas> _CALL_GAS </callGas>
            ...
          </callState>
          ...
        </evm>
        ...
      </ethereum>
    </kevm>
    requires (2 ^Int 64) <=Int W andBool W <Int (2 ^Int 256) andBool 0 <=Int (maxUInt64 &Int W) andBool (maxUInt64 &Int W) <=Int maxUInt64

endmodule
