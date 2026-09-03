requires "../../../trust-runtime-verification.k"
// FAIL-02 exact-runtime candidate: dependency_denial_is_typed_rejection.
// Exact validation succeeds, then an explicit bound dependency returns REJECTED.
// TrustToken must produce TrustRejected(actionId, reason=100), not operational failure.
module TRUST-FAIL-02-DEPENDENCY-DENIAL-TYPED-REJECTION-SPEC
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
            <output> .Bytes => #parseByteStack("0x8cf60b6f2486557c3f20900a69d8fb3cbfa79add46def02479eec02ae4a8be4b5d691d780000000000000000000000000000000000000000000000000000000000000064") </output>
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
            <block>
              <coinbase> 0 </coinbase>
              <gasLimit> 30000000 </gasLimit>
              <gasUsed> 0:Gas </gasUsed>
              <timestamp> 1 </timestamp>
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
                <storage> (29 |-> 0)
                  (101266647997309585097405883844426022482893663092309003946043550422221844034009 |-> 26959946667150639797519366020136605360117210205495530584368188301926)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519003 |-> 57005)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519004 |-> 63684956910112894337062200911521869281296065019379977542089255342434361700286)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519005 |-> 104030214055563206544380018964498086408182220148833426368700205517501514240307)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519006 |-> 28277803415836499387621760140637023812364979670848060116482414917801498575512)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519007 |-> 1)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519008 |-> 100395387096110653787269209602546785972489291239522651498509267430628442184529) TOKEN_STORAGE:Map </storage>
                <origStorage> (29 |-> 0)
                  (101266647997309585097405883844426022482893663092309003946043550422221844034009 |-> 26959946667150639797519366020136605360117210205495530584368188301926)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519003 |-> 57005)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519004 |-> 63684956910112894337062200911521869281296065019379977542089255342434361700286)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519005 |-> 104030214055563206544380018964498086408182220148833426368700205517501514240307)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519006 |-> 28277803415836499387621760140637023812364979670848060116482414917801498575512)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519007 |-> 1)
                  (97814209156763238538131666302374884380137901711825452363602787872977421519008 |-> 100395387096110653787269209602546785972489291239522651498509267430628442184529) TOKEN_STORAGE </origStorage>
                <transientStorage> .Map </transientStorage>
                <nonce> 1 </nonce>
              </account>
              <account>
                <acctID> 57005 </acctID>
                <balance> 0 </balance>
                <code> #parseByteStack("0x60003560e01c633f1fe95d1460215760003560e01c638d2f868f146049575f5ffd5b7fe5ff03ba527e5fbaa74d73ffbf51df9ff1ca2d05e97e3b54bc745fc3b651d1335f5260205ff35b60015f5260043560205260a4356040527fa830739f6768f347a579f2a6642ff14c88c112eec130969b0d832b198147859460605260805ff3") </code>
                <storage> .Map </storage>
                <origStorage> .Map </origStorage>
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
                <txGasLimit> 3000000 </txGasLimit>
                <to> 1324161310598743833836268493538283093091898295570 </to>
                <value> 0 </value>
                <sigV> 0 </sigV>
                <sigR> .Bytes </sigR>
                <sigS> .Bytes </sigS>
                <data> #parseByteStack("0x9da235398f99afa60666700eaaef54913dd2d5deee2e8189907e4b356645a90710d5907c2486557c3f20900a69d8fb3cbfa79add46def02479eec02ae4a8be4b5d691d780000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001263c8d4a356169dba42b70e81695400965d3d406b652b81ea94bbbfb6cbbd4ac5e157725b41cf07b9630846b40e040274adcd191fe81ec032afcc0ea48b6eb3bddf5c6812ce5d815597e3d878b85581c776d6c4ad60220821a8946f57a6f1b516f68444d93b77f427d0b0ddf5264acc398f2c2d4543b5685728e2a456a56f84800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000041ba066f96df4127b9c696733b444c8ccb8252970bb8492b7a42ce62b1976ce100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000077359400") </data>
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
      andBool notBool 101266647997309585097405883844426022482893663092309003946043550422221844034009 in_keys(TOKEN_STORAGE)
      andBool notBool 97814209156763238538131666302374884380137901711825452363602787872977421519003 in_keys(TOKEN_STORAGE)
      andBool notBool 97814209156763238538131666302374884380137901711825452363602787872977421519004 in_keys(TOKEN_STORAGE)
      andBool notBool 97814209156763238538131666302374884380137901711825452363602787872977421519005 in_keys(TOKEN_STORAGE)
      andBool notBool 97814209156763238538131666302374884380137901711825452363602787872977421519006 in_keys(TOKEN_STORAGE)
      andBool notBool 97814209156763238538131666302374884380137901711825452363602787872977421519007 in_keys(TOKEN_STORAGE)
      andBool notBool 97814209156763238538131666302374884380137901711825452363602787872977421519008 in_keys(TOKEN_STORAGE)
endmodule
