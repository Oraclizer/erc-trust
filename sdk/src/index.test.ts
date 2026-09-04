// SPDX-License-Identifier: BSD-3-Clause

import assert from "node:assert/strict";
import test from "node:test";
import {
  KERNEL_DOMAIN,
  KERNEL_INTERFACE_ID,
  KERNEL_VERSION,
  PROFILE_IDS,
  ProfileKind,
  ReceiptKind,
} from "./index.js";

test("the package root exposes kernel version 2", () => {
  assert.equal(KERNEL_VERSION, 2);
  assert.equal(KERNEL_DOMAIN, "0xb5303e4083d2781d6c7d6a68d30b6354ebda11f0a2a037b946d87b3eec40b74e");
  assert.equal(KERNEL_INTERFACE_ID, "0x2b020308");
  assert.deepEqual(Object.keys(PROFILE_IDS).sort(), ["erc3643-partial", "erc3643-verified-full", "native-full"]);
  assert.equal(PROFILE_IDS["erc3643-partial"], "0xa57a63d1a6def0dfce48359b5a32ef71ae339ac73fcb1cf8d123c03b7ada1fe6");
  assert.equal(PROFILE_IDS["erc3643-verified-full"], "0xad56e54f83cc255e391dd3838f7dc4befa1b0306b42d8ed7974588f27fec41ad");
  assert.equal(ProfileKind.PARTIAL, 3);
  assert.equal(ReceiptKind.ACTION, 1);
  assert.equal(ReceiptKind.REVERSAL, 2);
});
