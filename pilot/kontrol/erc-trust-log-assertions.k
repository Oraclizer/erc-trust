module ERC-TRUST-LOG-ASSERTIONS
    imports KONTROL-MAIN

    rule [erc-trust.assert-last-two-logs]:
        <k> #cheatcode_call SELECTOR ARGS => .K ... </k>
        <log>
            _
            ListItem({ EMITTER
                     | ListItem(FROZEN_SIGNATURE) ListItem(SUBJECT)
                     | FROZEN_DATA })
            ListItem({ EMITTER
                     | ListItem(RECEIPT_SIGNATURE) ListItem(ACTION_ID) ListItem(CASE_ID) ListItem(ACTION_KIND)
                     | RECEIPT_DATA })
        </log>
      requires SELECTOR ==Int 2658458667
       andBool lengthBytes(ARGS) ==Int 576
       andBool EMITTER          ==Int Bytes2Int(substrBytes(ARGS,   0,  32), BE, Unsigned)
       andBool FROZEN_SIGNATURE ==Int Bytes2Int(substrBytes(ARGS,  32,  64), BE, Unsigned)
       andBool SUBJECT          ==Int Bytes2Int(substrBytes(ARGS,  64,  96), BE, Unsigned)
       andBool lengthBytes(FROZEN_DATA) ==Int 32
       andBool Bytes2Int(FROZEN_DATA, BE, Unsigned) ==Int Bytes2Int(substrBytes(ARGS, 96, 128), BE, Unsigned)
       andBool RECEIPT_SIGNATURE ==Int Bytes2Int(substrBytes(ARGS, 128, 160), BE, Unsigned)
       andBool ACTION_ID          ==Int Bytes2Int(substrBytes(ARGS, 160, 192), BE, Unsigned)
       andBool CASE_ID            ==Int Bytes2Int(substrBytes(ARGS, 192, 224), BE, Unsigned)
       andBool ACTION_KIND        ==Int Bytes2Int(substrBytes(ARGS, 224, 256), BE, Unsigned)
       andBool lengthBytes(RECEIPT_DATA) ==Int 320
       andBool RECEIPT_DATA ==K substrBytes(ARGS, 256, 576)

    rule [erc-trust.assert-only-constructor-transfer]:
        <k> #cheatcode_call SELECTOR ARGS => .K ... </k>
        <log>
            ListItem({ EMITTER
                     | ListItem(TRANSFER_SIGNATURE) ListItem(FROM) ListItem(TO)
                     | TRANSFER_DATA })
        </log>
      requires SELECTOR ==Int 1192607536
       andBool lengthBytes(ARGS) ==Int 160
       andBool EMITTER            ==Int Bytes2Int(substrBytes(ARGS,  0,  32), BE, Unsigned)
       andBool TRANSFER_SIGNATURE ==Int Bytes2Int(substrBytes(ARGS, 32,  64), BE, Unsigned)
       andBool FROM               ==Int Bytes2Int(substrBytes(ARGS, 64,  96), BE, Unsigned)
       andBool TO                 ==Int Bytes2Int(substrBytes(ARGS, 96, 128), BE, Unsigned)
       andBool lengthBytes(TRANSFER_DATA) ==Int 32
       andBool Bytes2Int(TRANSFER_DATA, BE, Unsigned) ==Int Bytes2Int(substrBytes(ARGS, 128, 160), BE, Unsigned)
endmodule
