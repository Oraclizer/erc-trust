requires "../../../trust-runtime-verification.k"

// Exact-runtime theorem skeleton for STATE-04.
// The frozen overlay remains exactly observable while the independent
// restriction overlay is simultaneously active for the same subject.
module TRUST-STATE-04-FREEZE-RESTRICTION-INDEPENDENT-SPEC
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
          <output> _ => #buf(32, FROZEN) </output>
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
            <callData>
              b"\x15\x8b\x1a\x57\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
                +Bytes #buf(20, SUBJECT_ID)
            </callData>
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
                #hashedLocation("Solidity", 5, SUBJECT_ID) |-> FROZEN
                #hashedLocation("Solidity", 6, SUBJECT_ID) |-> 1
                TOKEN_STORAGE:Map
              </storage>
              <origStorage>
                #hashedLocation("Solidity", 5, SUBJECT_ID) |-> FROZEN
                #hashedLocation("Solidity", 6, SUBJECT_ID) |-> 1
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
      andBool lengthBytes(
        b"\x15\x8b\x1a\x57\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
          +Bytes #buf(20, SUBJECT_ID)
      ) ==Int 36
      andBool 0 <Int TOKEN_ID andBool TOKEN_ID <Int (2 ^Int 160)
      andBool 0 <Int CALLER_ID andBool CALLER_ID <Int (2 ^Int 160)
      andBool 0 <Int SUBJECT_ID andBool SUBJECT_ID <Int (2 ^Int 160)
      andBool TOKEN_ID =/=Int CALLER_ID
      andBool TOKEN_ID =/=Int SUBJECT_ID
      andBool 0 <=Int CALL_DEPTH andBool CALL_DEPTH <Int 1024
      andBool 0 <Int FROZEN andBool FROZEN <Int (2 ^Int 256)
      andBool (notBool #hashedLocation("Solidity", 5, SUBJECT_ID) in_keys(TOKEN_STORAGE))
      andBool (notBool #hashedLocation("Solidity", 6, SUBJECT_ID) in_keys(TOKEN_STORAGE))
      andBool #hashedLocation("Solidity", 5, SUBJECT_ID)
        =/=Int #hashedLocation("Solidity", 6, SUBJECT_ID)

endmodule
