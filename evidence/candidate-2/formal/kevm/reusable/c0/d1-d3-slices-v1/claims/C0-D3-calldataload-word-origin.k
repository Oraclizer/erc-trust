// SPDX-License-Identifier: BSD-3-Clause
// Generated C0 D1-D3 strict representative slice: C0-D3-calldataload-word-origin.
module C0-D3-CALLDATALOAD-WORD-ORIGIN-SPEC
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
            <callData> CALLDATA </callData>
            <wordStack>
              68 : .WordStack
              => #asWord(#range(CALLDATA, 68, 32)) : .WordStack
            </wordStack>
            <pc> 13604 => 13605 </pc>
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
    requires 100 <=Int lengthBytes(CALLDATA)

endmodule
