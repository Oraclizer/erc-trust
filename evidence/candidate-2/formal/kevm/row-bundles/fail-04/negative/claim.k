requires "../../../trust-runtime-verification.k"
// FAIL-04 exact-runtime candidate: malformed_dependency_return_is_typed_operational_failure.
// Binding/config validation succeeds; assessment STATICCALL returns a malformed 127-byte tuple.
// TrustToken must produce exact TrustOperationalFailure(actionId, reason=202, bindingHash).
module TRUST-FAIL-04-MALFORMED-DEPENDENCY-RETURN-TYPED-OPERATIONAL-FAILURE-SPEC
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
            <output> .Bytes => #parseByteStack("0x386ecc58926e22ec3af659bd49b84e11b3a322655edf26665d8d8f242d86208cebb0c41800000000000000000000000000000000000000000000000000000000000000ca2c610e8b0bab6d41c89b08a27cda421c4cd5d95e308a05d3eb48963a88f1764a") </output>
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
            <origin> .Account => 1390849295786071768276380950238675083608645509734 </origin>
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
                  <storage> (29 |-> 0)
                    (96400170334845132523755579829183185904585038478981631800690591416773997163733 |-> 26959946667150639797519366020136605360117210205495530584368188301926)
                    (97814209156763238538131666302374884380137901711825452363602787872977421519003 |-> 57005)
                    (97814209156763238538131666302374884380137901711825452363602787872977421519004 |-> 79910164987673145237785110345122138088608379767313601445419186825292762398628)
                    (97814209156763238538131666302374884380137901711825452363602787872977421519005 |-> 14027071133953831645763036236343326637300039140217649722223837234688495771954)
                    (97814209156763238538131666302374884380137901711825452363602787872977421519006 |-> 113123538183488139194523769213191775348895561046504543183364064446337531833037)
                    (97814209156763238538131666302374884380137901711825452363602787872977421519007 |-> 1)
                    (97814209156763238538131666302374884380137901711825452363602787872977421519008 |-> 20073249876057622267584681105245356516103973134628625601710682275354550302282) TOKEN_STORAGE:Map </storage>
                  <origStorage> (29 |-> 0)
                    (96400170334845132523755579829183185904585038478981631800690591416773997163733 |-> 26959946667150639797519366020136605360117210205495530584368188301926)
                    (97814209156763238538131666302374884380137901711825452363602787872977421519003 |-> 57005)
                    (97814209156763238538131666302374884380137901711825452363602787872977421519004 |-> 79910164987673145237785110345122138088608379767313601445419186825292762398628)
                    (97814209156763238538131666302374884380137901711825452363602787872977421519005 |-> 14027071133953831645763036236343326637300039140217649722223837234688495771954)
                    (97814209156763238538131666302374884380137901711825452363602787872977421519006 |-> 113123538183488139194523769213191775348895561046504543183364064446337531833037)
                    (97814209156763238538131666302374884380137901711825452363602787872977421519007 |-> 1)
                    (97814209156763238538131666302374884380137901711825452363602787872977421519008 |-> 20073249876057622267584681105245356516103973134628625601710682275354550302282) TOKEN_STORAGE </origStorage>
                  <transientStorage> .Map </transientStorage>
                  <nonce> 1 </nonce>
                </account>
                <account>
                  <acctID> 57005 </acctID>
                  <balance> 0 </balance>
                  <code> #parseByteStack("0x60003560e01c633f1fe95d1460215760003560e01c638d2f868f146049575f5ffd5b7f1f030a79430ce25f67ea3556dfee990aa5002cc734a2ba75338242fee9c8e1325f5260205ff35b60005f5260043560205260a4356040527f6ed60309cf341f5f91cbe955589b3df989336195ff488bd52f3adc93b9589d51606052607f5ff3") </code>
                  <storage> .Map </storage>
                  <origStorage> .Map </origStorage>
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
                  <storage> (29 |-> 0)
                    (96400170334845132523755579829183185904585038478981631800690591416773997163733 |-> 26959946667150639797519366020136605360117210205495530584368188301926)
                    (97814209156763238538131666302374884380137901711825452363602787872977421519003 |-> 57005)
                    (97814209156763238538131666302374884380137901711825452363602787872977421519004 |-> 79910164987673145237785110345122138088608379767313601445419186825292762398628)
                    (97814209156763238538131666302374884380137901711825452363602787872977421519005 |-> 14027071133953831645763036236343326637300039140217649722223837234688495771954)
                    (97814209156763238538131666302374884380137901711825452363602787872977421519006 |-> 113123538183488139194523769213191775348895561046504543183364064446337531833037)
                    (97814209156763238538131666302374884380137901711825452363602787872977421519007 |-> 1)
                    (97814209156763238538131666302374884380137901711825452363602787872977421519008 |-> 20073249876057622267584681105245356516103973134628625601710682275354550302282) TOKEN_STORAGE:Map </storage>
                  <origStorage> (29 |-> 0)
                    (96400170334845132523755579829183185904585038478981631800690591416773997163733 |-> 26959946667150639797519366020136605360117210205495530584368188301926)
                    (97814209156763238538131666302374884380137901711825452363602787872977421519003 |-> 57005)
                    (97814209156763238538131666302374884380137901711825452363602787872977421519004 |-> 79910164987673145237785110345122138088608379767313601445419186825292762398628)
                    (97814209156763238538131666302374884380137901711825452363602787872977421519005 |-> 14027071133953831645763036236343326637300039140217649722223837234688495771954)
                    (97814209156763238538131666302374884380137901711825452363602787872977421519006 |-> 113123538183488139194523769213191775348895561046504543183364064446337531833037)
                    (97814209156763238538131666302374884380137901711825452363602787872977421519007 |-> 1)
                    (97814209156763238538131666302374884380137901711825452363602787872977421519008 |-> 20073249876057622267584681105245356516103973134628625601710682275354550302282) TOKEN_STORAGE </origStorage>
                  <transientStorage> .Map </transientStorage>
                  <nonce> 1 </nonce>
                </account>
                <account>
                  <acctID> 57005 </acctID>
                  <balance> 0 </balance>
                  <code> #parseByteStack("0x60003560e01c633f1fe95d1460215760003560e01c638d2f868f146049575f5ffd5b7f1f030a79430ce25f67ea3556dfee990aa5002cc734a2ba75338242fee9c8e1325f5260205ff35b60005f5260043560205260a4356040527f6ed60309cf341f5f91cbe955589b3df989336195ff488bd52f3adc93b9589d51606052607f5ff3") </code>
                  <storage> .Map </storage>
                  <origStorage> .Map </origStorage>
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
                <txGasLimit> 3000000 </txGasLimit>
                <to> 1324161310598743833836268493538283093091898295570 </to>
                <value> 0 </value>
                <sigV> 0 </sigV>
                <sigR> .Bytes </sigR>
                <sigS> .Bytes </sigS>
                <data> #parseByteStack("0x9da235398f99afa60666700eaaef54913dd2d5deee2e8189907e4b356645a90710d5907c926e22ec3af659bd49b84e11b3a322655edf26665d8d8f242d86208cebb0c4180000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001e994b1eaedcb8a1f68e4885b84a55b64f80c644b82e92641be694866e0c8298fe8e4795d2ab97b60edcd805dc52692654089fbd8ef03e1d6d638d4257ba78f5a2c610e8b0bab6d41c89b08a27cda421c4cd5d95e308a05d3eb48963a88f1764a578e040c4050a92cfbed638eafb2f35ee5673691a83f4e249148c9c1fa91cecf0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000dee43eb65730959046a030214feb4bf7baa93c078e2623d379da3f9b91ba56f00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000077359400") </data>
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
      andBool notBool 96400170334845132523755579829183185904585038478981631800690591416773997163733 in_keys(TOKEN_STORAGE)
      andBool notBool 97814209156763238538131666302374884380137901711825452363602787872977421519003 in_keys(TOKEN_STORAGE)
      andBool notBool 97814209156763238538131666302374884380137901711825452363602787872977421519004 in_keys(TOKEN_STORAGE)
      andBool notBool 97814209156763238538131666302374884380137901711825452363602787872977421519005 in_keys(TOKEN_STORAGE)
      andBool notBool 97814209156763238538131666302374884380137901711825452363602787872977421519006 in_keys(TOKEN_STORAGE)
      andBool notBool 97814209156763238538131666302374884380137901711825452363602787872977421519007 in_keys(TOKEN_STORAGE)
      andBool notBool 97814209156763238538131666302374884380137901711825452363602787872977421519008 in_keys(TOKEN_STORAGE)
endmodule
