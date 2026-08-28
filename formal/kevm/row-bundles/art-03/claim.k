requires "../../trust-runtime-verification.k"

// ART-03: constructor_resolved_local_runtime_is_hash_bound.
// This full-transaction claim observes the constructor-resolved `decimals`
// immutable through its public selector.  The exact pinned TrustToken runtime
// must return ABI uint8(18), commit no storage or protocol log/substate change,
// and consume only the outer transaction nonce.
module TRUST-ART-03-CONSTRUCTOR-RESOLVED-RUNTIME-BINDING-SPEC
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
            <output>
              .Bytes
              => #parseByteStack("0x0000000000000000000000000000000000000000000000000000000000000012")
            </output>
            <statusCode> .StatusCode => EVMC_SUCCESS </statusCode>
            <callStack> .List </callStack>
            <interimStates> .List </interimStates>
            <touchedAccounts> .Set </touchedAccounts>

            <callState>
              <program> .Bytes </program>
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
                <storage> TOKEN_STORAGE:Map </storage>
                <origStorage> TOKEN_STORAGE </origStorage>
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
                <data> #parseByteStack("0x313ce567") </data>
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

endmodule
