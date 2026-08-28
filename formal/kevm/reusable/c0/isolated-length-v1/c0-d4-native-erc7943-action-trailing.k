// Generated isolated C0 D4 claim. Canonical and mutant lanes use
// this exact package byte-for-byte with resume disabled.
module C0-D4-NATIVE-ERC7943-ACTION-TRAILING-SPEC
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
                <data> #parseByteStack("0x9295b54c8f99afa60666700eaaef54913dd2d5deee2e8189907e4b356645a90710d5907c267ed8d0dbac5764ff09d71d9ed92214bf5c0c11bbe14ac9fed90fb53267e2f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a100000000000000000000000000000000000000000000000000000000000000a10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014699b2f24d4a20754c052759b911fdf0344a157233bb1966fdeba64c7db0868c214aefe7d78a50bc8754a3c51dc2e9fcd1007fdf38e3c5743616ee8e0e1493df9a83cc652dc23991331f8ff46a8f1d83124f58d91629566709737d581978104136fc17f252101a3fbaf8b810bcf3b3aa51b948ba6295037e9880384a42006363000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000843b48dccc6ff192f9330133622b0536f7b94feca0cf36e7e46fc50060b6f8820000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000c900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffffffffff0000000000000000000000000000000000000000000000000000000000000000") </data>
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
    requires 1000000 >=Int maxInt(G0(CANCUN, #parseByteStack("0x9295b54c8f99afa60666700eaaef54913dd2d5deee2e8189907e4b356645a90710d5907c267ed8d0dbac5764ff09d71d9ed92214bf5c0c11bbe14ac9fed90fb53267e2f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a100000000000000000000000000000000000000000000000000000000000000a10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014699b2f24d4a20754c052759b911fdf0344a157233bb1966fdeba64c7db0868c214aefe7d78a50bc8754a3c51dc2e9fcd1007fdf38e3c5743616ee8e0e1493df9a83cc652dc23991331f8ff46a8f1d83124f58d91629566709737d581978104136fc17f252101a3fbaf8b810bcf3b3aa51b948ba6295037e9880384a42006363000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000843b48dccc6ff192f9330133622b0536f7b94feca0cf36e7e46fc50060b6f8820000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000c900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffffffffff0000000000000000000000000000000000000000000000000000000000000000"), 0, lengthBytes(#parseByteStack("0x9295b54c8f99afa60666700eaaef54913dd2d5deee2e8189907e4b356645a90710d5907c267ed8d0dbac5764ff09d71d9ed92214bf5c0c11bbe14ac9fed90fb53267e2f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a100000000000000000000000000000000000000000000000000000000000000a10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014699b2f24d4a20754c052759b911fdf0344a157233bb1966fdeba64c7db0868c214aefe7d78a50bc8754a3c51dc2e9fcd1007fdf38e3c5743616ee8e0e1493df9a83cc652dc23991331f8ff46a8f1d83124f58d91629566709737d581978104136fc17f252101a3fbaf8b810bcf3b3aa51b948ba6295037e9880384a42006363000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000843b48dccc6ff192f9330133622b0536f7b94feca0cf36e7e46fc50060b6f8820000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000c900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffffffffff0000000000000000000000000000000000000000000000000000000000000000")), 0) +Int 21000, 0)
      andBool notBool 29 in_keys(ENDPOINT_STORAGE)

endmodule
