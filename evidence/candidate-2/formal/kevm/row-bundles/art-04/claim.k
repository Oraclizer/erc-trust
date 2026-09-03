requires "../../trust-runtime-verification.k"

// ART-04: storage_layout_abi_ast_and_immutable_references_are_hash_bound.
// The exact resolved TrustToken runtime receives canonical totalSupply()
// calldata. Slot 2 and adjacent slot 3 deliberately contain different words,
// so the required uint256(42) return observes the compiler-bound slot-2 layout.
module TRUST-ART-04-ARTIFACT-SURFACE-BINDING-SPEC
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
              => #parseByteStack("0x000000000000000000000000000000000000000000000000000000000000002a")
            </output>
            <statusCode> .StatusCode => EVMC_SUCCESS </statusCode>
            <callStack> .List </callStack>
            <interimStates> .List </interimStates>
            <touchedAccounts> .Set </touchedAccounts>
            <callState> <program> .Bytes </program> ... </callState>
            <substate>
              <selfDestruct> .Set </selfDestruct>
              <log> .List </log>
              <refund> 0 </refund>
              <accessedAccounts> .Set </accessedAccounts>
              <accessedStorage> .Map </accessedStorage>
              <createdAccounts> .Set </createdAccounts>
            </substate>
            <gasPrice> 0 </gasPrice>
            <origin> .Account => 1390849295786071768276380950238675083608645509734 </origin>
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
                <storage> 2 |-> 42 3 |-> 99 </storage>
                <origStorage> 2 |-> 42 3 |-> 99 </origStorage>
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
                <data> #parseByteStack("0x18160ddd") </data>
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

