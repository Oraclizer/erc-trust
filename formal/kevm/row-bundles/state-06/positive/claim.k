requires "../../../trust-runtime-verification.k"

// Exact-runtime observation skeleton for STATE-06.
// The queried nonce is stored at the exact nested mapping location for
// (authorityRef, authorityEpoch, nonce). This is not a row discharge.
module TRUST-STATE-06-NONCE-PROJECTION-EXACT-SPEC
  imports TRUST-RUNTIME-VERIFICATION

  claim
    <kevm>
      <k> #execute => #halt </k>
      <exit-code> 1 </exit-code>
      <mode> NORMAL </mode>
      <schedule> CANCUN </schedule>
      <useGas> false </useGas>

      <ethereum>
        <evm>
          <output> _ => #buf(32, 1) </output>
          <statusCode> _ => EVMC_SUCCESS </statusCode>
          <callStack> _ </callStack>
          <interimStates> _ </interimStates>
          <touchedAccounts> _ => ?_ </touchedAccounts>

          <callState>
            <program> PROGRAM </program>
            <jumpDests> #computeValidJumpDests(PROGRAM) </jumpDests>
            <id> TOKEN_ID </id>
            <codeAddr> TOKEN_ID </codeAddr>
            <caller> CALLER_ID </caller>
            <callData> #abiCallData("nonceUsed", #bytes32(AUTHORITY_REF), #uint64(AUTHORITY_EPOCH), #uint256(NONCE)) </callData>
            <callValue> 0 </callValue>
            <wordStack> .WordStack => ?_ </wordStack>
            <localMem> .Bytes => ?_ </localMem>
            <pc> 0 => ?_ </pc>
            <gas> #gas(VGAS) => ?_ </gas>
            <memoryUsed> 0 => ?_ </memoryUsed>
            <callGas> _ => ?_ </callGas>
            <static> false </static>
            <callDepth> CALL_DEPTH </callDepth>
          </callState>
          <versionedHashes> _ </versionedHashes>

          <substate>
            <selfDestruct> _ </selfDestruct>
            <log> _ => ?_ </log>
            <refund> _ => ?_ </refund>
            <accessedAccounts> _ => ?_ </accessedAccounts>
            <accessedStorage> _ => ?_ </accessedStorage>
            <createdAccounts> _ => ?_ </createdAccounts>
          </substate>
          <gasPrice> _ </gasPrice>
          <origin> CALLER_ID </origin>
          ...
        </evm>

        <network>
          <chainID> _ </chainID>
          <accounts>
            <account>
              <acctID> TOKEN_ID </acctID>
              <balance> _ </balance>
              <code> PROGRAM </code>
              <storage>
                #hashedLocation("Solidity", #hashedLocation("Solidity", #hashedLocation("Solidity", 12, AUTHORITY_REF), AUTHORITY_EPOCH), NONCE) |-> 1
                TOKEN_STORAGE:Map
              </storage>
              <origStorage>
                #hashedLocation("Solidity", #hashedLocation("Solidity", #hashedLocation("Solidity", 12, AUTHORITY_REF), AUTHORITY_EPOCH), NONCE) |-> 1
                TOKEN_STORAGE
              </origStorage>
              <nonce> _ </nonce>
              <transientStorage> _ </transientStorage>
            </account>
          </accounts>
          <txOrder> _ </txOrder>
          <txPending> _ </txPending>
          <messages> _ </messages>
          ...
        </network>
      </ethereum>
    </kevm>
    requires PROGRAM ==K #trustTrustTokenRuntime()
      andBool lengthBytes(#abiCallData("nonceUsed", #bytes32(AUTHORITY_REF), #uint64(AUTHORITY_EPOCH), #uint256(NONCE))) ==Int 100
      andBool 0 <Int TOKEN_ID andBool TOKEN_ID <Int (2 ^Int 160)
      andBool 0 <Int CALLER_ID andBool CALLER_ID <Int (2 ^Int 160)
      andBool TOKEN_ID =/=Int CALLER_ID
      andBool 0 <=Int CALL_DEPTH andBool CALL_DEPTH <Int 1024
      andBool 0 <Int AUTHORITY_REF andBool AUTHORITY_REF <Int (2 ^Int 256)
      andBool 0 <Int AUTHORITY_EPOCH andBool AUTHORITY_EPOCH <Int (2 ^Int 64)
      andBool 0 <=Int NONCE andBool NONCE <Int ((2 ^Int 256) -Int 1)
      andBool (notBool #hashedLocation("Solidity", #hashedLocation("Solidity", #hashedLocation("Solidity", 12, AUTHORITY_REF), AUTHORITY_EPOCH), NONCE) in_keys(TOKEN_STORAGE))
      andBool (notBool #hashedLocation("Solidity", #hashedLocation("Solidity", #hashedLocation("Solidity", 12, 0), 0), NONCE +Int 1) in_keys(TOKEN_STORAGE))
      andBool #hashedLocation("Solidity", #hashedLocation("Solidity", #hashedLocation("Solidity", 12, AUTHORITY_REF), AUTHORITY_EPOCH), NONCE)
        =/=Int #hashedLocation("Solidity", #hashedLocation("Solidity", #hashedLocation("Solidity", 12, 0), 0), NONCE +Int 1)

endmodule
