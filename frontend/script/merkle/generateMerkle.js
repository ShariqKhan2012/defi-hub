const { MerkleTree } = require("merkletreejs");
const fs = require("fs");
const { encodeAbiParameters, keccak256, isAddress, toBytes } = require("viem");

function encodeLeaf(address, amount) {
  const encoded = encodeAbiParameters(
    [{ type: "address" }, { type: "uint256" }],
    [address, BigInt(amount)]
  );
  const firstHash = keccak256(encoded);
  // Double hash — defence against pre-image attacks
  return Buffer.from(keccak256(toBytes(firstHash)).slice(2), "hex");
}

function viemKeccak(buffer) {
  const hash = keccak256(toBytes("0x" + buffer.toString("hex")));
  return Buffer.from(hash.slice(2), "hex");
}

const airdropList = JSON.parse(fs.readFileSync("./airdropList.json", "utf-8"));

// ── Input validation ─────────────────────────────────────────
const seen = new Set();
for (const [address, amount] of Object.entries(airdropList)) {
  if (!isAddress(address)) throw new Error(`Invalid address: ${address}`);
  if (BigInt(amount) <= 0n) throw new Error(`Zero amount for: ${address}`);
  if (seen.has(address.toLowerCase())) throw new Error(`Duplicate address: ${address}`);
  seen.add(address.toLowerCase());
}



const leaves = Object.entries(airdropList).map(([address, amount]) => encodeLeaf(address, amount));
const tree = new MerkleTree(leaves, viemKeccak, { sortPairs: true });
const root = tree.getRoot().toString("hex");

console.log("Merkle Root:", root);

const output = { root: "0x" + root, claims: {} };

for (const [address, amount] of Object.entries(airdropList)) {
  const leaf = encodeLeaf(address, amount);
  const proof = tree.getProof(leaf).map(p => "0x" + p.data.toString("hex"));
  output.claims[address] = { amount: amount.toString(), proof };
}

for (const [address, amount] of Object.entries(airdropList)) {
  const leaf = encodeLeaf(address, amount);
  const proof = tree.getProof(leaf);
  const valid = tree.verify(proof, leaf, tree.getRoot());
  if (!valid) throw new Error(`Proof verification failed for ${address}`);
}
console.log("All proofs verified successfully");

// Proofs verified. Now lets write them to the output file
fs.writeFileSync("./merkleOutput.json", JSON.stringify(output, null, 2));
