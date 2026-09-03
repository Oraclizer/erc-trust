requires "../../../trust-runtime-verification.k"

// Exact-runtime theorem for BAL-06.
// A successful ordinary transfer can spend only the sender's own, unfrozen
// physical tokens. It preserves custody backing and the frozen target while
// moving exactly AMOUNT between the two physical balance slots.
module TRUST-BAL-06-ORDINARY-TRANSFER-PRESERVES-FLOOR-SPEC
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
            <caller> SOURCE_ID </caller>
            <callData>
              b"\xa9\x05\x9c\xbb\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
                +Bytes #buf(20, DESTINATION_ID)
                +Bytes #buf(32, AMOUNT)
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
          <origin> SOURCE_ID </origin>
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
                #hashedLocation("Solidity", 3, SOURCE_ID)
                  |-> (SOURCE_BALANCE => SOURCE_BALANCE -Int AMOUNT)
                #hashedLocation("Solidity", 3, DESTINATION_ID)
                  |-> (DESTINATION_BALANCE => DESTINATION_BALANCE +Int AMOUNT)
                #hashedLocation("Solidity", 5, SOURCE_ID) |-> FROZEN
                #hashedLocation("Solidity", 5, DESTINATION_ID) |-> DESTINATION_FROZEN
                #hashedLocation("Solidity", 6, SOURCE_ID) |-> 0
                #hashedLocation("Solidity", 6, DESTINATION_ID) |-> 0
                #hashedLocation("Solidity", 7, SOURCE_ID) |-> BACKING
                #hashedLocation("Solidity", 7, DESTINATION_ID) |-> DESTINATION_BACKING
                29 |-> 0
                #hashedLocation("Solidity", 3, OTHER_ID) |-> OTHER_BALANCE
                TOKEN_STORAGE:Map
              </storage>
              <origStorage>
                #hashedLocation("Solidity", 3, SOURCE_ID) |-> SOURCE_BALANCE
                #hashedLocation("Solidity", 3, DESTINATION_ID) |-> DESTINATION_BALANCE
                #hashedLocation("Solidity", 5, SOURCE_ID) |-> FROZEN
                #hashedLocation("Solidity", 5, DESTINATION_ID) |-> DESTINATION_FROZEN
                #hashedLocation("Solidity", 6, SOURCE_ID) |-> 0
                #hashedLocation("Solidity", 6, DESTINATION_ID) |-> 0
                #hashedLocation("Solidity", 7, SOURCE_ID) |-> BACKING
                #hashedLocation("Solidity", 7, DESTINATION_ID) |-> DESTINATION_BACKING
                29 |-> 0
                #hashedLocation("Solidity", 3, OTHER_ID) |-> OTHER_BALANCE
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
        b"\xa9\x05\x9c\xbb\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
          +Bytes #buf(20, DESTINATION_ID)
          +Bytes #buf(32, AMOUNT)
      ) ==Int 68
      andBool 0 <Int TOKEN_ID andBool TOKEN_ID <Int (2 ^Int 160)
      andBool 0 <Int SOURCE_ID andBool SOURCE_ID <Int (2 ^Int 160)
      andBool 0 <Int DESTINATION_ID andBool DESTINATION_ID <Int (2 ^Int 160)
      andBool SOURCE_ID =/=Int DESTINATION_ID
      andBool TOKEN_ID =/=Int SOURCE_ID
      andBool TOKEN_ID =/=Int DESTINATION_ID
      andBool 0 <Int OTHER_ID andBool OTHER_ID <Int (2 ^Int 160)
      andBool OTHER_ID =/=Int SOURCE_ID
      andBool OTHER_ID =/=Int DESTINATION_ID
      andBool OTHER_ID =/=Int TOKEN_ID
      andBool 0 <=Int CALL_DEPTH andBool CALL_DEPTH <Int 1024
      andBool 0 <=Int AMOUNT andBool AMOUNT <Int (2 ^Int 256)
      andBool 0 <=Int SOURCE_BALANCE andBool SOURCE_BALANCE <Int (2 ^Int 256)
      andBool 0 <=Int DESTINATION_BALANCE andBool DESTINATION_BALANCE <Int (2 ^Int 256)
      andBool 0 <=Int FROZEN andBool FROZEN <Int (2 ^Int 256)
      andBool 0 <=Int BACKING andBool BACKING <Int (2 ^Int 256)
      andBool 0 <=Int DESTINATION_FROZEN andBool DESTINATION_FROZEN <Int (2 ^Int 256)
      andBool 0 <=Int DESTINATION_BACKING andBool DESTINATION_BACKING <Int (2 ^Int 256)
      andBool 0 <=Int OTHER_BALANCE andBool OTHER_BALANCE <Int (2 ^Int 256)
      andBool 0 <Int AMOUNT
      andBool 0 <Int BACKING
      andBool 0 <Int FROZEN
      andBool BACKING +Int FROZEN +Int AMOUNT <=Int SOURCE_BALANCE
      andBool DESTINATION_BALANCE +Int AMOUNT <Int (2 ^Int 256)
      andBool (notBool #hashedLocation("Solidity", 3, SOURCE_ID) in_keys(TOKEN_STORAGE))
      andBool (notBool #hashedLocation("Solidity", 3, DESTINATION_ID) in_keys(TOKEN_STORAGE))
      andBool (notBool #hashedLocation("Solidity", 3, OTHER_ID) in_keys(TOKEN_STORAGE))
      andBool (notBool #hashedLocation("Solidity", 5, SOURCE_ID) in_keys(TOKEN_STORAGE))
      andBool (notBool #hashedLocation("Solidity", 5, DESTINATION_ID) in_keys(TOKEN_STORAGE))
      andBool (notBool #hashedLocation("Solidity", 6, SOURCE_ID) in_keys(TOKEN_STORAGE))
      andBool (notBool #hashedLocation("Solidity", 6, DESTINATION_ID) in_keys(TOKEN_STORAGE))
      andBool (notBool #hashedLocation("Solidity", 7, SOURCE_ID) in_keys(TOKEN_STORAGE))
      andBool (notBool #hashedLocation("Solidity", 7, DESTINATION_ID) in_keys(TOKEN_STORAGE))
      andBool (notBool 29 in_keys(TOKEN_STORAGE))
      andBool #hashedLocation("Solidity", 3, SOURCE_ID) =/=Int #hashedLocation("Solidity", 3, DESTINATION_ID)
      andBool #hashedLocation("Solidity", 3, SOURCE_ID) =/=Int #hashedLocation("Solidity", 5, SOURCE_ID)
      andBool #hashedLocation("Solidity", 3, SOURCE_ID) =/=Int #hashedLocation("Solidity", 6, SOURCE_ID)
      andBool #hashedLocation("Solidity", 3, SOURCE_ID) =/=Int #hashedLocation("Solidity", 6, DESTINATION_ID)
      andBool #hashedLocation("Solidity", 3, SOURCE_ID) =/=Int #hashedLocation("Solidity", 7, SOURCE_ID)
      andBool #hashedLocation("Solidity", 3, SOURCE_ID) =/=Int 29
      andBool #hashedLocation("Solidity", 3, DESTINATION_ID) =/=Int #hashedLocation("Solidity", 5, SOURCE_ID)
      andBool #hashedLocation("Solidity", 3, DESTINATION_ID) =/=Int #hashedLocation("Solidity", 6, SOURCE_ID)
      andBool #hashedLocation("Solidity", 3, DESTINATION_ID) =/=Int #hashedLocation("Solidity", 6, DESTINATION_ID)
      andBool #hashedLocation("Solidity", 3, DESTINATION_ID) =/=Int #hashedLocation("Solidity", 7, SOURCE_ID)
      andBool #hashedLocation("Solidity", 3, DESTINATION_ID) =/=Int 29
      andBool #hashedLocation("Solidity", 5, SOURCE_ID) =/=Int #hashedLocation("Solidity", 6, SOURCE_ID)
      andBool #hashedLocation("Solidity", 5, SOURCE_ID) =/=Int #hashedLocation("Solidity", 6, DESTINATION_ID)
      andBool #hashedLocation("Solidity", 5, SOURCE_ID) =/=Int #hashedLocation("Solidity", 7, SOURCE_ID)
      andBool #hashedLocation("Solidity", 5, SOURCE_ID) =/=Int 29
      andBool #hashedLocation("Solidity", 6, SOURCE_ID) =/=Int #hashedLocation("Solidity", 6, DESTINATION_ID)
      andBool #hashedLocation("Solidity", 6, SOURCE_ID) =/=Int #hashedLocation("Solidity", 7, SOURCE_ID)
      andBool #hashedLocation("Solidity", 6, SOURCE_ID) =/=Int 29
      andBool #hashedLocation("Solidity", 6, DESTINATION_ID) =/=Int #hashedLocation("Solidity", 7, SOURCE_ID)
      andBool #hashedLocation("Solidity", 6, DESTINATION_ID) =/=Int 29
      andBool #hashedLocation("Solidity", 7, SOURCE_ID) =/=Int 29
      andBool #hashedLocation("Solidity", 3, OTHER_ID) =/=Int #hashedLocation("Solidity", 3, SOURCE_ID)
      andBool #hashedLocation("Solidity", 3, OTHER_ID) =/=Int #hashedLocation("Solidity", 3, DESTINATION_ID)
      andBool #hashedLocation("Solidity", 3, OTHER_ID) =/=Int #hashedLocation("Solidity", 5, SOURCE_ID)
      andBool #hashedLocation("Solidity", 3, OTHER_ID) =/=Int #hashedLocation("Solidity", 6, SOURCE_ID)
      andBool #hashedLocation("Solidity", 3, OTHER_ID) =/=Int #hashedLocation("Solidity", 6, DESTINATION_ID)
      andBool #hashedLocation("Solidity", 3, OTHER_ID) =/=Int #hashedLocation("Solidity", 7, SOURCE_ID)
      andBool #hashedLocation("Solidity", 3, OTHER_ID) =/=Int 29
      andBool #hashedLocation("Solidity", 5, DESTINATION_ID) =/=Int #hashedLocation("Solidity", 3, SOURCE_ID)
      andBool #hashedLocation("Solidity", 5, DESTINATION_ID) =/=Int #hashedLocation("Solidity", 3, DESTINATION_ID)
      andBool #hashedLocation("Solidity", 5, DESTINATION_ID) =/=Int #hashedLocation("Solidity", 5, SOURCE_ID)
      andBool #hashedLocation("Solidity", 5, DESTINATION_ID) =/=Int #hashedLocation("Solidity", 6, SOURCE_ID)
      andBool #hashedLocation("Solidity", 5, DESTINATION_ID) =/=Int #hashedLocation("Solidity", 6, DESTINATION_ID)
      andBool #hashedLocation("Solidity", 5, DESTINATION_ID) =/=Int #hashedLocation("Solidity", 7, SOURCE_ID)
      andBool #hashedLocation("Solidity", 5, DESTINATION_ID) =/=Int 29
      andBool #hashedLocation("Solidity", 5, DESTINATION_ID) =/=Int #hashedLocation("Solidity", 3, OTHER_ID)
      andBool #hashedLocation("Solidity", 7, DESTINATION_ID) =/=Int #hashedLocation("Solidity", 3, SOURCE_ID)
      andBool #hashedLocation("Solidity", 7, DESTINATION_ID) =/=Int #hashedLocation("Solidity", 3, DESTINATION_ID)
      andBool #hashedLocation("Solidity", 7, DESTINATION_ID) =/=Int #hashedLocation("Solidity", 5, SOURCE_ID)
      andBool #hashedLocation("Solidity", 7, DESTINATION_ID) =/=Int #hashedLocation("Solidity", 6, SOURCE_ID)
      andBool #hashedLocation("Solidity", 7, DESTINATION_ID) =/=Int #hashedLocation("Solidity", 6, DESTINATION_ID)
      andBool #hashedLocation("Solidity", 7, DESTINATION_ID) =/=Int #hashedLocation("Solidity", 7, SOURCE_ID)
      andBool #hashedLocation("Solidity", 7, DESTINATION_ID) =/=Int 29
      andBool #hashedLocation("Solidity", 7, DESTINATION_ID) =/=Int #hashedLocation("Solidity", 3, OTHER_ID)
      andBool #hashedLocation("Solidity", 7, DESTINATION_ID) =/=Int #hashedLocation("Solidity", 5, DESTINATION_ID)

endmodule
