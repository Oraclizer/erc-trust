// GENERATED ABI-04 row-local metadata bridge. DO NOT EDIT.
requires "edsl.md"

module TRUST-ABI-04-ROW-BRIDGE
    imports EDSL
    syntax String ::= "#trustAbi04CaseMatrixRootSha256" [macro]
    rule #trustAbi04CaseMatrixRootSha256 => "ccc802bec2da08aa07eae5d7ae32a2b3d0b87f58348c96bb9f2505f1275e2678"
    syntax Int ::= "#trustAbi04EndpointCount" [macro]
    rule #trustAbi04EndpointCount => 6
    syntax Int ::= "#trustAbi04CaseCount" [macro]
    rule #trustAbi04CaseCount => 69
    // executeRegulatoryAction((bytes32,bytes32,uint8,address,address,address,address,uint256,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,uint64,uint64,uint256,uint48,uint48))
    syntax Int ::= "#trustAbi04NativeRegulatoryActionSelector" [macro]
    rule #trustAbi04NativeRegulatoryActionSelector => 2644653369
    // executeERC7943Action((bytes32,bytes32,uint8,address,address,address,address,uint256,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,uint64,uint64,uint256,uint48,uint48))
    syntax Int ::= "#trustAbi04NativeErc7943ActionSelector" [macro]
    rule #trustAbi04NativeErc7943ActionSelector => 2459284812
    // executeRegulatoryAction((bytes32,bytes32,uint8,address,address,address,address,uint256,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,uint64,uint64,uint256,uint48,uint48))
    syntax Int ::= "#trustAbi04ProfileRegulatoryActionSelector" [macro]
    rule #trustAbi04ProfileRegulatoryActionSelector => 2644653369
    // executeRegulatoryReversal((bytes32,bytes32,bytes32,uint8,bytes32,uint64,uint256,uint48,uint48))
    syntax Int ::= "#trustAbi04NativeRegulatoryReversalSelector" [macro]
    rule #trustAbi04NativeRegulatoryReversalSelector => 2058032795
    // executeERC7943Reversal((bytes32,bytes32,bytes32,uint8,bytes32,uint64,uint256,uint48,uint48))
    syntax Int ::= "#trustAbi04NativeErc7943ReversalSelector" [macro]
    rule #trustAbi04NativeErc7943ReversalSelector => 1975684502
    // executeRegulatoryReversal((bytes32,bytes32,bytes32,uint8,bytes32,uint64,uint256,uint48,uint48))
    syntax Int ::= "#trustAbi04ProfileRegulatoryReversalSelector" [macro]
    rule #trustAbi04ProfileRegulatoryReversalSelector => 2058032795
endmodule
