requires "../../../trust-runtime-verification.k"
// FAIL-03 exact-runtime candidate: dependency_revert_is_typed_operational_failure.
// Binding/config validation succeeds; assessment STATICCALL reverts with empty data.
// TrustToken must produce exact TrustOperationalFailure(actionId, reason=202, bindingHash).
module TRUST-FAIL-03-DEPENDENCY-REVERT-TYPED-OPERATIONAL-FAILURE-SPEC
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
            <output> .Bytes => #parseByteStack("0x386ecc5835b1579e83ead3c64fb48412aa5db240fd262656a3670afa90a6e8e82b3f0d3700000000000000000000000000000000000000000000000000000000000000ca7a43b2280c44530c2fa32cf59735b5b3f94fadc54f45605ccc13d9f76f6aa91e") </output>
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
                  (70261111376701690725733953820364622379453661677821037389800363853899272551819 |-> 26959946667150639797519366020136605360117210205495530584368188301926)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519003 |-> 57005)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519004 |-> 58743939867573131714496169731129964339398497250841071210251183763811109942074)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519005 |-> 38837340546427561671602894515252489243801845989255916242590307996588992858431)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519006 |-> 86779927970467439776383038685190470981239986807654703420750592918712636592221)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519007 |-> 1)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519008 |-> 55301775871038101067855490479240704455438138209087086058854658757863678847262) TOKEN_STORAGE:Map </storage>
                  <origStorage> (29 |-> 0)
                  (70261111376701690725733953820364622379453661677821037389800363853899272551819 |-> 26959946667150639797519366020136605360117210205495530584368188301926)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519003 |-> 57005)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519004 |-> 58743939867573131714496169731129964339398497250841071210251183763811109942074)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519005 |-> 38837340546427561671602894515252489243801845989255916242590307996588992858431)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519006 |-> 86779927970467439776383038685190470981239986807654703420750592918712636592221)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519007 |-> 1)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519008 |-> 55301775871038101067855490479240704455438138209087086058854658757863678847262) TOKEN_STORAGE </origStorage>
                  <transientStorage> .Map </transientStorage>
                  <nonce> 1 </nonce>
                </account>
                <account>
                  <acctID> 57005 </acctID>
                  <balance> 0 </balance>
                  <code> #parseByteStack("0x60003560e01c633f1fe95d1460215760003560e01c638d2f868f146049575f5ffd5b7f55dd27e04fbf2dc78f7a5244c8f931fdef009300901dd0f47ff601d6b6ab893f5f5260205ff35b5f5ffd") </code>
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
                  (70261111376701690725733953820364622379453661677821037389800363853899272551819 |-> 26959946667150639797519366020136605360117210205495530584368188301926)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519003 |-> 57005)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519004 |-> 58743939867573131714496169731129964339398497250841071210251183763811109942074)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519005 |-> 38837340546427561671602894515252489243801845989255916242590307996588992858431)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519006 |-> 86779927970467439776383038685190470981239986807654703420750592918712636592221)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519007 |-> 1)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519008 |-> 55301775871038101067855490479240704455438138209087086058854658757863678847262) TOKEN_STORAGE:Map </storage>
                  <origStorage> (29 |-> 0)
                  (70261111376701690725733953820364622379453661677821037389800363853899272551819 |-> 26959946667150639797519366020136605360117210205495530584368188301926)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519003 |-> 57005)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519004 |-> 58743939867573131714496169731129964339398497250841071210251183763811109942074)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519005 |-> 38837340546427561671602894515252489243801845989255916242590307996588992858431)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519006 |-> 86779927970467439776383038685190470981239986807654703420750592918712636592221)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519007 |-> 1)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519008 |-> 55301775871038101067855490479240704455438138209087086058854658757863678847262) TOKEN_STORAGE </origStorage>
                  <transientStorage> .Map </transientStorage>
                  <nonce> 1 </nonce>
                </account>
                <account>
                  <acctID> 57005 </acctID>
                  <balance> 0 </balance>
                  <code> #parseByteStack("0x60003560e01c633f1fe95d1460215760003560e01c638d2f868f146049575f5ffd5b7f55dd27e04fbf2dc78f7a5244c8f931fdef009300901dd0f47ff601d6b6ab893f5f5260205ff35b5f5ffd") </code>
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
                <data> #parseByteStack("0x9da235398f99afa60666700eaaef54913dd2d5deee2e8189907e4b356645a90710d5907c35b1579e83ead3c64fb48412aa5db240fd262656a3670afa90a6e8e82b3f0d370000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001622850bf916ea1b8d556c11e4d42e362cdd474ba79438b98910a76b9e4bef9b554155343b9e9d652e929d92e2924749ee3c1483325b765ad34dd7f6a26c4e6b57a43b2280c44530c2fa32cf59735b5b3f94fadc54f45605ccc13d9f76f6aa91ed10ce7b843279edb93a87fe2f8ef985b76242934bf07be374b962bd9d67797df00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000043f33868d820fce59226dc5ca2fb715adc61aafa64ce3cd9380221512c342a7000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000077359400") </data>
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
      andBool notBool 70261111376701690725733953820364622379453661677821037389800363853899272551819 in_keys(TOKEN_STORAGE)
      andBool notBool 97814209156763238538131666302374884380137901711825452363602787872977421519003 in_keys(TOKEN_STORAGE)
      andBool notBool 97814209156763238538131666302374884380137901711825452363602787872977421519004 in_keys(TOKEN_STORAGE)
      andBool notBool 97814209156763238538131666302374884380137901711825452363602787872977421519005 in_keys(TOKEN_STORAGE)
      andBool notBool 97814209156763238538131666302374884380137901711825452363602787872977421519006 in_keys(TOKEN_STORAGE)
      andBool notBool 97814209156763238538131666302374884380137901711825452363602787872977421519007 in_keys(TOKEN_STORAGE)
      andBool notBool 97814209156763238538131666302374884380137901711825452363602787872977421519008 in_keys(TOKEN_STORAGE)
endmodule
