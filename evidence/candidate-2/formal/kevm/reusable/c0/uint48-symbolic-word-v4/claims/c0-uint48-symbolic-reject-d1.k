// SPDX-License-Identifier: BSD-3-Clause
// D1: original W carrier and runtime, exactly two machine-proved redundant hypotheses.
module C0-UINT48-SYMBOLIC-REJECT-D1-SPEC
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
            <wordStack> W : .WordStack => ?_ </wordStack>
            <pc> 13474 => 2767 </pc>
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
    requires (2 ^Int 48) <=Int W andBool W <Int (2 ^Int 256) andBool 0 <=Int (maxUInt48 &Int W) andBool (maxUInt48 &Int W) <=Int maxUInt48

endmodule
