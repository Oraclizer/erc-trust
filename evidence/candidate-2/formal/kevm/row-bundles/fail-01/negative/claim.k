requires "../../../trust-runtime-verification.k"
// FAIL-01 exact-runtime candidate: semantic_rejection_reverts_and_stutters.
// A known typed selector and exact 21-word tuple pass ABI and length checks.
// domain=0 then produces TrustInvalidCommand(actionId=0, REASON_DOMAIN=1).
module TRUST-FAIL-01-TYPED-DOMAIN-REJECTION-STUTTER-SPEC
    imports TRUST-RUNTIME-VERIFICATION

    claim
      <kevm>
        <k>
          loadTx(1390849295786071768276380950238675083608645509734)
          => #finalizeBlock
        </k>
        <exit-code> 1 </exit-code>
        <mode> NORMAL </mode>
        <schedule> CANCUN </schedule>
        <useGas> false </useGas>

        <ethereum>
          <evm>
            <output> .Bytes => #parseByteStack("0xed623c1300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001") </output>
            <statusCode> .StatusCode => EVMC_REVERT </statusCode>
            <callStack> .List </callStack>
            <interimStates> .List </interimStates>
            <touchedAccounts> .Set </touchedAccounts>

            <callState>
              <program> .Bytes </program>
              <static> false </static>
              ...
            </callState>

            <substate>
              <selfDestruct> .Set </selfDestruct>
              <log> .List </log>
              <refund> 0 </refund>
              <accessedAccounts> .Set </accessedAccounts>
              <accessedStorage> .Map </accessedStorage>
              <createdAccounts> .Set </createdAccounts>
            </substate>

            <gasPrice> 0 </gasPrice>
            <origin>
              .Account
              => 1390849295786071768276380950238675083608645509734
            </origin>

            <block>
              <coinbase> 0 </coinbase>
              <gasLimit> 30000000 </gasLimit>
              <gasUsed> 0:Gas </gasUsed>
              <baseFee> 0 </baseFee>
              ...
            </block>
            ...
          </evm>

          <network>
            <chainID> 31337 </chainID>
            <accounts>
              <account>
                <acctID> 0 </acctID>
                <balance> 0 </balance>
                <code> .Bytes </code>
                <storage> .Map </storage>
                <origStorage> .Map </origStorage>
                <transientStorage> .Map </transientStorage>
                <nonce> 0 </nonce>
              </account>
              <account>
                <acctID> 1390849295786071768276380950238675083608645509734 </acctID>
                <balance> 1000000000 </balance>
                <code> .Bytes </code>
                <storage> .Map </storage>
                <origStorage> .Map </origStorage>
                <transientStorage> .Map </transientStorage>
                <nonce> 0 => 1 </nonce>
              </account>
              <account>
                <acctID> 1324161310598743833836268493538283093091898295570 </acctID>
                <balance> 0 </balance>
                <code> #trustTrustTokenRuntime() </code>
                <storage> (29 |-> 0) TOKEN_STORAGE:Map </storage>
                <origStorage> (29 |-> 0) TOKEN_STORAGE </origStorage>
                <transientStorage> .Map </transientStorage>
                <nonce> 1 </nonce>
              </account>
            </accounts>

            <txOrder> .List </txOrder>
            <txPending> ListItem(0) => .List </txPending>
            <messages>
              <message>
                <msgID> 0 </msgID>
                <txNonce> 0 </txNonce>
                <txGasPrice> 0 </txGasPrice>
                <txGasLimit> 1000000 </txGasLimit>
                <to> 1324161310598743833836268493538283093091898295570 </to>
                <value> 0 </value>
                <sigV> 0 </sigV>
                <sigR> .Bytes </sigR>
                <sigS> .Bytes </sigS>
                <data> #parseByteStack("0x9da23539000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000") </data>
                <txAccess> [ .JSONs ] </txAccess>
                <txChainID> 31337 </txChainID>
                <txPriorityFee> 0 </txPriorityFee>
                <txMaxFee> 0 </txMaxFee>
                <txType> Legacy </txType>
                <txMaxBlobFee> 0 </txMaxBlobFee>
                <txVersionedHashes> .List </txVersionedHashes>
                <txAuthList> .List </txAuthList>
              </message>
            </messages>
            <withdrawalsPending> .List </withdrawalsPending>
            <withdrawalsOrder> .List </withdrawalsOrder>
            <withdrawals> .Bag </withdrawals>
            <requests>
              <depositRequests> .Bytes </depositRequests>
              <withdrawalRequests> .Bytes </withdrawalRequests>
              <consolidationRequests> .Bytes </consolidationRequests>
            </requests>
            ...
          </network>
        </ethereum>
      </kevm>
    requires notBool 29 in_keys(TOKEN_STORAGE)
endmodule
