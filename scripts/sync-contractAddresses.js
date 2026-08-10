#!/usr/bin/env node
/**
 * sync-deployed-addresses.js
 *
 * Ports the lookup logic of foundry-devops's DevOpsTools.get_most_recent_deployment:
 *   address token = DevOpsTools.get_most_recent_deployment("GovernanceToken", block.chainid);
 *
 * Like DevOpsTools, this does NOT read a single fixed run-latest.json path. It walks
 * the broadcast directory recursively (broadcast/<ScriptName>/<chainId>/*.json),
 * collects every run file under a matching chain-id folder (skipping anything with
 * "dry-run" in its path), and for each contract picks the address from whichever
 * matching run file has the highest ".timestamp" -- i.e. the truly most recent
 * deployment, not just the most recently modified file.
 *
 * This version processes BOTH chains in one run and writes each to its own frontend
 * env file:
 *   Anvil   (31337)     -> frontend/.env.local
 *   Sepolia (11155111)  -> frontend/.env
 *
 * Keys are written as NEXT_PUBLIC_<CONTRACT_NAME>_ADDRESS, e.g.
 *   NEXT_PUBLIC_GOVERNANCE_TOKEN_ADDRESS=0x...
 *
 * Broadcast directory resolution: if BROADCAST_DIR is unset, the script checks
 * ./broadcast, ./contracts/broadcast, ./packages/contracts/broadcast, and
 * ./foundry/broadcast (relative to cwd) and uses whichever exists first.
 *
 * Usage:
 *   node sync-deployed-addresses.js
 *   node sync-deployed-addresses.js GovernanceToken Timelock   # limit to specific contracts
 *   BROADCAST_DIR=./contracts/broadcast FRONTEND_DIR=./frontend node sync-deployed-addresses.js
 */

'use strict';

const fs = require('fs');
const path = require('path');

// ---------------------------------------------------------------------------
// Chains this script keeps in sync, each mapped to its target env file
// ---------------------------------------------------------------------------

const CHAIN_TARGETS = [
  { name: 'Anvil', chainId: String(process.env.ANVIL_CHAIN_ID || 31337), envFile: '.env.local' },
  { name: 'Sepolia', chainId: String(process.env.SEPOLIA_CHAIN_ID || 11155111), envFile: '.env' },
];

// ---------------------------------------------------------------------------
// Broadcast directory resolution
// ---------------------------------------------------------------------------

function resolveBroadcastDir() {
  if (process.env.BROADCAST_DIR) {
    const explicit = path.resolve(process.env.BROADCAST_DIR);
    if (!fs.existsSync(explicit)) {
      throw new Error(`BROADCAST_DIR was set to "${explicit}" but that directory does not exist.`);
    }
    return explicit;
  }

  const candidates = [
    'broadcast',
    'contracts/broadcast',
    'packages/contracts/broadcast',
    'foundry/broadcast',
  ];

  for (const candidate of candidates) {
    const full = path.join(process.cwd(), candidate);
    if (fs.existsSync(full)) return full;
  }

  throw new Error(
    `Could not find a broadcast directory. Looked in: ${candidates.join(', ')} (relative to ${process.cwd()}). ` +
    `Set BROADCAST_DIR explicitly, e.g. BROADCAST_DIR=./contracts/broadcast node ${path.basename(__filename)}`
  );
}

// ---------------------------------------------------------------------------
// Broadcast directory walk (mirrors vm.readDir(relativeBroadcastPath, 3))
// ---------------------------------------------------------------------------

function normalizePath(p) {
  return p.split(path.sep).join('/');
}

function walk(dir, maxDepth, depth = 0, results = []) {
  if (depth > maxDepth || !fs.existsSync(dir)) return results;

  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(fullPath, maxDepth, depth + 1, results);
    } else {
      results.push(fullPath);
    }
  }

  return results;
}

/**
 * Finds every run-artifact JSON file for the given chain id under broadcastDir,
 * excluding dry-run files -- matching DevOpsTools' path filter:
 *   normalizedPath.contains("/<chainId>/") && contains(".json") && !contains("dry-run")
 */
function findRunFiles(broadcastDir, chainId) {
  const chainSegment = `/${chainId}/`;
  return walk(broadcastDir, 3)
    .map(normalizePath)
    .filter((p) => p.includes(chainSegment) && p.endsWith('.json') && !p.includes('dry-run'));
}

// ---------------------------------------------------------------------------
// Per-run parsing (mirrors DevOpsTools.processRun)
// ---------------------------------------------------------------------------

function findAddressInRun(runJson, contractName) {
  let found = null;
  for (const tx of runJson.transactions || []) {
    const isCreate = tx.transactionType === 'CREATE' || tx.transactionType === 'CREATE2';
    if (isCreate && tx.contractName === contractName && tx.contractAddress) {
      found = tx.contractAddress;
    }
  }
  return found;
}

function getMostRecentDeployment(broadcastDir, contractName, chainId) {
  const runFiles = findRunFiles(broadcastDir, chainId);
  if (runFiles.length === 0) {
    throw new Error(`No deployment artifacts were found for chain ${chainId} under ${broadcastDir}`);
  }

  let bestAddress = null;
  let bestTimestamp = -Infinity;

  for (const filePath of runFiles) {
    let runJson;
    try {
      runJson = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    } catch {
      continue;
    }

    const address = findAddressInRun(runJson, contractName);
    if (address === null) continue;

    const timestamp = typeof runJson.timestamp === 'number' ? runJson.timestamp : 0;
    if (timestamp >= bestTimestamp) {
      bestTimestamp = timestamp;
      bestAddress = address;
    }
  }

  if (bestAddress === null) {
    throw new Error(`No contract named '${contractName}' has been deployed on chain ${chainId}`);
  }

  return bestAddress;
}

function discoverContractNames(broadcastDir, chainId) {
  const runFiles = findRunFiles(broadcastDir, chainId);
  const names = new Set();

  for (const filePath of runFiles) {
    let runJson;
    try {
      runJson = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    } catch {
      continue;
    }
    for (const tx of runJson.transactions || []) {
      const isCreate = tx.transactionType === 'CREATE' || tx.transactionType === 'CREATE2';
      if (isCreate && tx.contractName) names.add(tx.contractName);
    }
  }

  return [...names];
}

// ---------------------------------------------------------------------------
// Contract name -> env key
// ---------------------------------------------------------------------------

function toEnvKey(contractName) {
  const snake = contractName
    .replace(/([a-z0-9])([A-Z])/g, '$1_$2')
    .replace(/[^a-zA-Z0-9]+/g, '_')
    .toUpperCase();
  return `NEXT_PUBLIC_${snake}_ADDRESS`;
}

// ---------------------------------------------------------------------------
// .env read / update / write
// ---------------------------------------------------------------------------

function upsertEnvFile(envPath, updates) {
  let lines = [];
  if (fs.existsSync(envPath)) {
    lines = fs.readFileSync(envPath, 'utf8').split('\n');
  }

  const remainingKeys = new Set(Object.keys(updates));

  const updatedLines = lines.map((line) => {
    const match = line.match(/^([A-Za-z_][A-Za-z0-9_]*)\s*=/);
    if (match && remainingKeys.has(match[1])) {
      const key = match[1];
      remainingKeys.delete(key);
      return `${key}=${updates[key]}`;
    }
    return line;
  });

  while (updatedLines.length && updatedLines[updatedLines.length - 1] === '') {
    updatedLines.pop();
  }

  for (const key of remainingKeys) {
    updatedLines.push(`${key}=${updates[key]}`);
  }

  fs.mkdirSync(path.dirname(envPath), { recursive: true });
  fs.writeFileSync(envPath, updatedLines.join('\n') + '\n', 'utf8');
}

// ---------------------------------------------------------------------------
// Per-chain sync
// ---------------------------------------------------------------------------

function syncChain(broadcastDir, frontendDir, target, filterNames) {
  const { name, chainId, envFile } = target;
  console.log(`\n== ${name} (chain ${chainId}) ==`);

  const contractNames = filterNames.length > 0
    ? filterNames
    : discoverContractNames(broadcastDir, chainId);

  if (contractNames.length === 0) {
    console.warn(`No CREATE/CREATE2 deployments found under ${broadcastDir} for chain ${chainId}. Skipping.`);
    return;
  }

  const updates = {};
  for (const contractName of contractNames) {
    let address;
    try {
      address = getMostRecentDeployment(broadcastDir, contractName, chainId);
    } catch (err) {
      console.warn(`Skipping ${contractName}: ${err.message}`);
      continue;
    }
    const key = toEnvKey(contractName);
    updates[key] = address;
    console.log(`${contractName} -> ${key}=${address}`);
  }

  if (Object.keys(updates).length === 0) {
    console.warn('Nothing to write for this chain.');
    return;
  }

  const envPath = path.join(frontendDir, envFile);
  upsertEnvFile(envPath, updates);
  console.log(`Updated ${envPath}`);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

function main() {
  const broadcastDir = resolveBroadcastDir();
  const frontendDir = process.env.FRONTEND_DIR || path.join(process.cwd(), 'frontend');
  const filterNames = process.argv.slice(2); // optional: only sync specific contract names

  console.log(`Broadcast dir: ${broadcastDir}`);
  console.log(`Frontend dir:  ${frontendDir}`);

  for (const target of CHAIN_TARGETS) {
    syncChain(broadcastDir, frontendDir, target, filterNames);
  }
}

main();