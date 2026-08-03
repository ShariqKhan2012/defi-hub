#!/usr/bin/env node
// Run from project root: node scripts/sync-abis.js
// Reads Foundry build artifacts and writes bare ABI arrays to frontend/src/abi/

const fs = require("fs");
const path = require("path");

const CONTRACTS_OUT = path.resolve(__dirname, "../contracts/out");
const ABI_OUT = path.resolve(__dirname, "../frontend/src/abi");

const CONTRACTS = [
  "GovernanceToken",
  "StakingPool",
  "MerkleAirdrop",
  "SimpleDAO",
];

fs.mkdirSync(ABI_OUT, { recursive: true });

let ok = 0;
let failed = 0;

for (const name of CONTRACTS) {
  const src = path.join(CONTRACTS_OUT, `${name}.sol`, `${name}.json`);
  const dest = path.join(ABI_OUT, `${name}.ts`);

  if (!fs.existsSync(src)) {
    console.error(`SKIP  ${name} — artifact not found (run forge build first)`);
    failed++;
    continue;
  }

  const artifact = JSON.parse(fs.readFileSync(src, "utf-8"));
  const ts = `export default ${JSON.stringify(artifact.abi, null, 2)} as const;\n`;
  fs.writeFileSync(dest, ts);
  console.log(`OK    ${name} → frontend/src/abi/${name}.ts  (${artifact.abi.length} entries)`);
  ok++;
}

console.log(`\n${ok} synced, ${failed} skipped`);
if (failed > 0) process.exit(1);
