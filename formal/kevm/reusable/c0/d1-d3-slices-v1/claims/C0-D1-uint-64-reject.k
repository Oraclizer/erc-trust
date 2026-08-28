// SPDX-License-Identifier: BSD-3-Clause
// Generated C0 D1-D3 strict representative slice: C0-D1-uint-64-reject.
module C0-D1-UINT-64-REJECT-SPEC
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
            <wordStack> 18446744073709551616 : 0 : 0 : 0 : 0 : .WordStack => ?_ </wordStack>
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
    requires true

endmodule
