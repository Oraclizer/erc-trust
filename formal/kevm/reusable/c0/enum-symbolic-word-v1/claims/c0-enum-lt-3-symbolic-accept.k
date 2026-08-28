// SPDX-License-Identifier: BSD-3-Clause
// Frozen universal ENUM_LT_3 universal-accept claim over the exact canonical runtime.
module C0-ENUM-LT-3-SYMBOLIC-ACCEPT-SPEC
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
            <pc> 11322 => 11332 </pc>
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
    requires 0 <=Int W andBool W <Int 3

endmodule
