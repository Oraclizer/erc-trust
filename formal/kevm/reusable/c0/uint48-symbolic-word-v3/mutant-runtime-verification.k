// SPDX-License-Identifier: BSD-3-Clause
// UINT48 family-local mutant proof definition using only pinned upstream KEVM lemmas.
requires "../uint48-symbolic-word-v1/mutant-runtime-bridge.k"
requires "driver.md"
requires "lemmas/lemmas.k"

module TRUST-RUNTIME-VERIFICATION
    imports TRUST-RUNTIME-BRIDGE
    imports ETHEREUM-SIMULATION
    imports LEMMAS-WITHOUT-SLOT-UPDATES
endmodule
