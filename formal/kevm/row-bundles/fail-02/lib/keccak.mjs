const MASK64 = (1n << 64n) - 1n;

const ROTATION = [
  0, 1, 62, 28, 27,
  36, 44, 6, 55, 20,
  3, 10, 43, 25, 39,
  41, 45, 15, 21, 8,
  18, 2, 61, 56, 14,
];

const ROUND_CONSTANTS = [
  0x0000000000000001n, 0x0000000000008082n,
  0x800000000000808an, 0x8000000080008000n,
  0x000000000000808bn, 0x0000000080000001n,
  0x8000000080008081n, 0x8000000000008009n,
  0x000000000000008an, 0x0000000000000088n,
  0x0000000080008009n, 0x000000008000000an,
  0x000000008000808bn, 0x800000000000008bn,
  0x8000000000008089n, 0x8000000000008003n,
  0x8000000000008002n, 0x8000000000000080n,
  0x000000000000800an, 0x800000008000000an,
  0x8000000080008081n, 0x8000000000008080n,
  0x0000000080000001n, 0x8000000080008008n,
];

const rotateLeft = (value, shift) => {
  if (shift === 0) return value & MASK64;
  const amount = BigInt(shift);
  return ((value << amount) | (value >> (64n - amount))) & MASK64;
};

const permute = (state) => {
  for (const roundConstant of ROUND_CONSTANTS) {
    const column = Array(5).fill(0n);
    const delta = Array(5).fill(0n);
    for (let x = 0; x < 5; x += 1) {
      for (let y = 0; y < 5; y += 1) column[x] ^= state[x + 5 * y];
    }
    for (let x = 0; x < 5; x += 1) {
      delta[x] = column[(x + 4) % 5] ^ rotateLeft(column[(x + 1) % 5], 1);
    }
    for (let x = 0; x < 5; x += 1) {
      for (let y = 0; y < 5; y += 1) state[x + 5 * y] ^= delta[x];
    }

    const moved = Array(25).fill(0n);
    for (let x = 0; x < 5; x += 1) {
      for (let y = 0; y < 5; y += 1) {
        moved[y + 5 * ((2 * x + 3 * y) % 5)] = rotateLeft(state[x + 5 * y], ROTATION[x + 5 * y]);
      }
    }
    for (let x = 0; x < 5; x += 1) {
      for (let y = 0; y < 5; y += 1) {
        state[x + 5 * y] = (moved[x + 5 * y]
          ^ ((~moved[(x + 1) % 5 + 5 * y]) & moved[(x + 2) % 5 + 5 * y])) & MASK64;
      }
    }
    state[0] ^= roundConstant;
  }
};

export const keccak256 = (input) => {
  const bytes = Buffer.isBuffer(input) ? Buffer.from(input) : Buffer.from(input);
  const rate = 136;
  const padLength = rate - (bytes.length % rate);
  const padded = Buffer.concat([bytes, Buffer.alloc(padLength)]);
  padded[bytes.length] = 0x01;
  padded[padded.length - 1] |= 0x80;
  const state = Array(25).fill(0n);

  for (let offset = 0; offset < padded.length; offset += rate) {
    for (let lane = 0; lane < rate / 8; lane += 1) {
      let value = 0n;
      for (let byte = 0; byte < 8; byte += 1) {
        value |= BigInt(padded[offset + lane * 8 + byte]) << BigInt(8 * byte);
      }
      state[lane] ^= value;
    }
    permute(state);
  }

  const output = Buffer.alloc(32);
  for (let index = 0; index < output.length; index += 1) {
    output[index] = Number((state[Math.floor(index / 8)] >> BigInt(8 * (index % 8))) & 0xffn);
  }
  return output;
};

export const keccakHex = (input) => `0x${keccak256(input).toString("hex")}`;
export const keccakUtf8 = (input) => keccakHex(Buffer.from(input, "utf8"));
export const selector = (signature) => keccakUtf8(signature).slice(0, 10);

export const selfTestKeccak = () => {
  if (keccakHex(Buffer.alloc(0)) !== "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470") {
    throw new Error("Keccak-256 empty-string self-test failed");
  }
  if (keccakUtf8("abc") !== "0x4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45") {
    throw new Error("Keccak-256 abc self-test failed");
  }
};
