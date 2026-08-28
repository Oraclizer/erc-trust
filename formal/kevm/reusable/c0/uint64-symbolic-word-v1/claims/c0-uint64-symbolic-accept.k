// SPDX-License-Identifier: BSD-3-Clause
// Jay-approved UINT64 universal accept on the frozen W carrier and stack prefix.
module C0-UINT64-SYMBOLIC-ACCEPT-SPEC
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
            <pc> 13537 => 13564 </pc>
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
    requires 0 <=Int W andBool W <Int (2 ^Int 64)

endmodule
