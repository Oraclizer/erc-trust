// SPDX-License-Identifier: BSD-3-Clause

import assert from "node:assert/strict";
import test from "node:test";
import {
  KERNEL_DOMAIN,
  KERNEL_INTERFACE_ID,
  KERNEL_VERSION,
  ReceiptKind,
} from "./index.js";

test("the package root exposes kernel version 2", () => {
  assert.equal(KERNEL_VERSION, 2);
  assert.equal(KERNEL_DOMAIN, "0xb5303e4083d2781d6c7d6a68d30b6354ebda11f0a2a037b946d87b3eec40b74e");
  assert.equal(KERNEL_INTERFACE_ID, "0x2b020308");
  assert.equal(ReceiptKind.ACTION, 1);
  assert.equal(ReceiptKind.REVERSAL, 2);
});
