module ERC-TRUST-LOG-ASSERTIONS
    imports KONTROL-MAIN

    rule [erc-trust.assert-final-receipt-log]:
        <k> #cheatcode_call SELECTOR ARGS => .K ... </k>
        <log>
            _
            ListItem({ EMITTER
                     | ListItem(SIGNATURE) ListItem(ACTION_ID) ListItem(ACTION_KIND) ListItem(CASE_ID)
                     | RECEIPT_DATA })
        </log>
      requires SELECTOR ==Int 2333062377
       andBool lengthBytes(ARGS) ==Int 192
       andBool EMITTER     ==Int Bytes2Int(substrBytes(ARGS,   0,  32), BE, Unsigned)
       andBool SIGNATURE   ==Int Bytes2Int(substrBytes(ARGS,  32,  64), BE, Unsigned)
       andBool ACTION_ID   ==Int Bytes2Int(substrBytes(ARGS,  64,  96), BE, Unsigned)
       andBool ACTION_KIND ==Int Bytes2Int(substrBytes(ARGS,  96, 128), BE, Unsigned)
       andBool CASE_ID     ==Int Bytes2Int(substrBytes(ARGS, 128, 160), BE, Unsigned)
       andBool lengthBytes(RECEIPT_DATA) ==Int 32
       andBool Bytes2Int(RECEIPT_DATA, BE, Unsigned)
            ==Int Bytes2Int(substrBytes(ARGS, 160, 192), BE, Unsigned)
endmodule
