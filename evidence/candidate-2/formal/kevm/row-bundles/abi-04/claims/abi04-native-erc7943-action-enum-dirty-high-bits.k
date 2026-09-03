requires "../../../trust-runtime-verification.k"
// GENERATED ABI-04 theorem-grade exact-runtime claim. DO NOT EDIT.
// Case: ABI04-native-erc7943-action-enum-dirty-high-bits
// Malformed class: high_bits
// Endpoint: executeERC7943Action((bytes32,bytes32,uint8,address,address,address,address,uint256,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,uint64,uint64,uint256,uint48,uint48))
module ABI04_NATIVE_ERC7943_ACTION_ENUM_DIRTY_HIGH_BITS_SPEC
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
            <output> .Bytes </output>
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

            <blockhashes> .List </blockhashes>
            <previousExcessBlobGas> 0 </previousExcessBlobGas>
            <previousBlobGasUsed> 0 </previousBlobGasUsed>

            <block>
              <previousHash> 0 </previousHash>
              <ommersHash> 13478047122767188135818125966132228187941283477090363246179690878162135454535 </ommersHash>
              <coinbase> 0 </coinbase>
              <stateRoot> 0 </stateRoot>
              <transactionsRoot> 0 </transactionsRoot>
              <receiptsRoot> 0 </receiptsRoot>
              <logsBloom> #parseByteStack("0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000") </logsBloom>
              <difficulty> 0 </difficulty>
              <number> 1 </number>
              <gasLimit> 30000000 </gasLimit>
              <gasUsed> 0:Gas </gasUsed>
              <timestamp> 1 </timestamp>
              <extraData> .Bytes </extraData>
              <mixHash> 0 </mixHash>
              <blockNonce> 0 </blockNonce>
              <baseFee> 0 </baseFee>
              <withdrawalsRoot> 0 </withdrawalsRoot>
              <blobGasUsed> 0 </blobGasUsed>
              <excessBlobGas> 0 </excessBlobGas>
              <beaconRoot> 0 </beaconRoot>
              <requestsRoot> 0 </requestsRoot>
              <ommerBlockHeaders> [ .JSONs ] </ommerBlockHeaders>
            </block>
            ...
          </evm>

          <network>
            <chainID> 31337 </chainID>
            // Whole-cell rewrite fixes the three keyed accounts on both sides.
            <accounts>
              (
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
                  <nonce> 0 </nonce>
                </account>
                <account>
                  <acctID> 1324161310598743833836268493538283093091898295570 </acctID>
                  <balance> 0 </balance>
                  <code> #trustTrustTokenRuntime() </code>
                  <storage> (29 |-> 0) ENDPOINT_STORAGE:Map </storage>
                  <origStorage> (29 |-> 0) ENDPOINT_STORAGE </origStorage>
                  <transientStorage> .Map </transientStorage>
                  <nonce> 1 </nonce>
                </account>
              =>
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
                  <nonce> 1 </nonce>
                </account>
                <account>
                  <acctID> 1324161310598743833836268493538283093091898295570 </acctID>
                  <balance> 0 </balance>
                  <code> #trustTrustTokenRuntime() </code>
                  <storage> (29 |-> 0) ENDPOINT_STORAGE:Map </storage>
                  <origStorage> (29 |-> 0) ENDPOINT_STORAGE </origStorage>
                  <transientStorage> .Map </transientStorage>
                  <nonce> 1 </nonce>
                </account>
              )
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
                <data> #parseByteStack("0x9295b54c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000") </data>
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
    requires 1000000 >=Int maxInt(G0(CANCUN, #parseByteStack("0x9295b54c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"), 0, lengthBytes(#parseByteStack("0x9295b54c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")), 0) +Int 21000, 0)
      andBool notBool 29 in_keys(ENDPOINT_STORAGE)
endmodule
