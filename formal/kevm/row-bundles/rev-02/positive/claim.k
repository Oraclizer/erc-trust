requires "../../../trust-runtime-verification.k"

// REV-02 exact-runtime, same-transaction route-consumption slice.
//
// The full authorization wrapper is deliberately outside this claim.  STATE-02
// supplies the history invariant that the prepared ActionRecord.commandHash is
// the digest of the original request.  This claim makes that digest relation
// explicit, consumes the exact route ticket, and observes the concrete native
// runtime writes performed by setFrozenTokens(address,uint256).
module TRUST-REV-02-FREEZE-EFFECT-HEAD-HASH-BOUND-SPEC
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
            <caller> TOKEN_ID </caller>
            <callData>
              #buf(4, 3957611706)
              +Bytes #buf(32, SUBJECT_ID)
              +Bytes #buf(32, TARGET)
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
          <origin> ORIGIN_ID </origin>
          ...
        </evm>

        <network>
          <chainID> CHAIN_ID </chainID>
          <accounts>
            <account>
              <acctID> TOKEN_ID </acctID>
              <balance> _ </balance>
              <code> PROGRAM </code>
              <storage>
                (
                #hashedLocation("Solidity", 5, SUBJECT_ID) |-> PRIOR_TARGET

                #hashedLocation("Solidity", 8, SUBJECT_ID) |-> PARENT_ACTION_ID
                (#hashedLocation("Solidity", 8, SUBJECT_ID) +Int 1) |-> PARENT_EFFECT_HASH
                (#hashedLocation("Solidity", 8, SUBJECT_ID) +Int 2) |-> GENERATION

                #hashedLocation("Solidity", 15, ACTION_ID)
                  |-> (256 +Int SUBJECT_ID *Int 65536)
                (#hashedLocation("Solidity", 15, ACTION_ID) +Int 4) |-> TARGET
                (#hashedLocation("Solidity", 15, ACTION_ID) +Int 9)
                  |-> (AUTHORITY_EPOCH +Int POLICY_EPOCH *Int (2 ^Int 64))
                (#hashedLocation("Solidity", 15, ACTION_ID) +Int 10) |-> COMMAND_DIGEST

                (#hashedLocation("Solidity", 23, 0) +Int 4) |-> POLICY_EPOCH
                (#hashedLocation("Solidity", 23, 0) +Int 5) |-> BINDING_HASH

                24 |-> ACTION_ID
                25 |-> ROUTE_KEY
                26 |-> CALLDATA_HASH
                27 |-> BINDING_HASH
                28 |-> (3957611706
                  +Int (2 ^Int 32)
                  +Int AUTHORITY_EPOCH *Int (2 ^Int 48)
                  +Int POLICY_EPOCH *Int (2 ^Int 112)
                  +Int (2 ^Int 176))
                ) => ?FINAL_STORAGE:Map
              </storage>
              <origStorage> _ </origStorage>
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
        #buf(4, 3957611706)
        +Bytes #buf(32, SUBJECT_ID)
        +Bytes #buf(32, TARGET)) ==Int 68
      andBool 0 <Int TOKEN_ID andBool TOKEN_ID <Int (2 ^Int 160)
      andBool 0 <Int SUBJECT_ID andBool SUBJECT_ID <Int (2 ^Int 160)
      andBool 0 <=Int ORIGIN_ID andBool ORIGIN_ID <Int (2 ^Int 160)
      andBool 0 <=Int CHAIN_ID andBool CHAIN_ID <Int (2 ^Int 256)
      andBool 0 <Int ACTION_ID andBool ACTION_ID <Int (2 ^Int 256)
      andBool 0 <=Int PARENT_ACTION_ID andBool PARENT_ACTION_ID <Int (2 ^Int 256)
      andBool 0 <=Int PARENT_EFFECT_HASH andBool PARENT_EFFECT_HASH <Int (2 ^Int 256)
      andBool 0 <=Int TARGET andBool TARGET <Int (2 ^Int 256)
      andBool 0 <=Int PRIOR_TARGET andBool PRIOR_TARGET <Int (2 ^Int 256)
      andBool 0 <=Int BINDING_HASH andBool BINDING_HASH <Int (2 ^Int 256)
      andBool 0 <=Int AUTHORITY_EPOCH andBool AUTHORITY_EPOCH <Int (2 ^Int 64)
      andBool 0 <=Int POLICY_EPOCH andBool POLICY_EPOCH <Int (2 ^Int 64)
      andBool 0 <=Int GENERATION andBool GENERATION <Int ((2 ^Int 64) -Int 1)
      andBool 0 <=Int CALL_DEPTH andBool CALL_DEPTH <Int 1024
      andBool CALLDATA_HASH ==Int keccak(
        #buf(4, 3957611706)
        +Bytes #buf(32, SUBJECT_ID)
        +Bytes #buf(32, TARGET))
      andBool COMMAND_DIGEST ==Int keccak(
        #buf(32, 64952277229954035620835332762096480469321475681130754459434635126959871725692)
        +Bytes #buf(32, TOKEN_ID)
        +Bytes #buf(32, CHAIN_ID)
        +Bytes #buf(32, 64952277229954035620835332762096480469321475681130754459434635126959871725692)
        +Bytes #buf(32, ACTION_ID)
        +Bytes #buf(32, 0)
        +Bytes #buf(32, SUBJECT_ID)
        +Bytes #buf(32, 0)
        +Bytes #buf(32, 0)
        +Bytes #buf(32, 0)
        +Bytes #buf(32, TARGET)
        +Bytes #buf(32, 0)
        +Bytes #buf(32, 0)
        +Bytes #buf(32, BINDING_HASH)
        +Bytes #buf(32, 0)
        +Bytes #buf(32, 0)
        +Bytes #buf(32, 0)
        +Bytes #buf(32, 0)
        +Bytes #buf(32, 0)
        +Bytes #buf(32, AUTHORITY_EPOCH)
        +Bytes #buf(32, POLICY_EPOCH)
        +Bytes #buf(32, 0)
        +Bytes #buf(32, 0)
        +Bytes #buf(32, 281474976710655))
      andBool ROUTE_KEY ==Int keccak(
        #buf(32, 64952277229954035620835332762096480469321475681130754459434635126959871725692)
        +Bytes #buf(32, TOKEN_ID)
        +Bytes #buf(32, 3957611706 *Int (2 ^Int 224))
        +Bytes #buf(32, CALLDATA_HASH)
        +Bytes #buf(32, BINDING_HASH)
        +Bytes #buf(32, AUTHORITY_EPOCH)
        +Bytes #buf(32, POLICY_EPOCH)
        +Bytes #buf(32, ACTION_ID))
    ensures #lookup(?FINAL_STORAGE,
        #hashedLocation("Solidity", 5, SUBJECT_ID)) ==Int TARGET
      andBool #lookup(?FINAL_STORAGE,
        #hashedLocation("Solidity", 8, SUBJECT_ID)) ==Int ACTION_ID
      andBool #lookup(?FINAL_STORAGE,
        #hashedLocation("Solidity", 8, SUBJECT_ID) +Int 1)
          ==Int keccak(
            #buf(32, COMMAND_DIGEST)
            +Bytes #buf(32, PARENT_ACTION_ID)
            +Bytes #buf(32, GENERATION +Int 1)
            +Bytes #buf(32, PRIOR_TARGET)
            +Bytes #buf(32, 0))
      andBool #lookup(?FINAL_STORAGE,
        #hashedLocation("Solidity", 8, SUBJECT_ID) +Int 2) ==Int GENERATION +Int 1
      andBool #lookup(?FINAL_STORAGE,
        #hashedLocation("Solidity", 15, ACTION_ID) +Int 5) ==Int PRIOR_TARGET
      andBool #lookup(?FINAL_STORAGE,
        #hashedLocation("Solidity", 16, ACTION_ID)) ==Int PARENT_ACTION_ID
      andBool #lookup(?FINAL_STORAGE,
        #hashedLocation("Solidity", 16, ACTION_ID) +Int 1)
          ==Int keccak(
            #buf(32, COMMAND_DIGEST)
            +Bytes #buf(32, PARENT_ACTION_ID)
            +Bytes #buf(32, GENERATION +Int 1)
            +Bytes #buf(32, PRIOR_TARGET)
            +Bytes #buf(32, 0))
      andBool #lookup(?FINAL_STORAGE,
        #hashedLocation("Solidity", 16, ACTION_ID) +Int 2) ==Int GENERATION +Int 1

endmodule
