## DeFI Hub

A web3 application that acts as a hub for 4 independent DeFi features: Staking, Merkle Airdrop, DAO Voting, and Gasless Transactions.

### Setup

git init
mkdir contracts
cd contracts
forge init . --no-git
forge install OpenZeppelin/openzeppelin-contracts --no-git
forge install smartcontractkit/chainlink-brownie-contracts --no-git

#add a .gitignore file to the 'contracts' directory of the project
echo "# Compiler files
cache/
out/

# Ignores development broadcast logs

!/broadcast
/broadcast/\*/31337/
/broadcast/\*\*/dry-run/

# Docs

docs/

# Dotenv file

.env" > .gitignore

cd contracts

# Create the standard .gitignore

# (with the contents above)

# Remove lib from regular git tracking

git rm -r --cached lib/

# From inside contracts/

rm -rf lib/forge-std
rm -rf lib/openzeppelin-contracts
rm -rf lib/chainlink-brownie-contracts

# Then register as submodules

git submodule add https://github.com/foundry-rs/forge-std lib/forge-std
git submodule add https://github.com/openzeppelin/openzeppelin-contracts lib/openzeppelin-contracts
git submodule add https://github.com/smartcontractkit/chainlink-brownie-contracts lib/chainlink-brownie-contracts

git add .
git commit -m "add standard .gitignore, switch lib to git submodules"
git push

npx create-next-app@latest frontend
cd frontend
npm install wagmi@^2.9.0 viem @tanstack/react-query
npm install @rainbow-me/rainbowkit

## Running the deployer script:

```bash
forge script script/Deploy.s.sol \ --rpc-url <RPC_URL> \
 --broadcast \
 --verify \ # optional: verifies on Etherscan
--sender <YOUR_ADDRESS> --ffi
```

OR

```bash
forge script script/Deploy.s.sol --rpc-url <rpc_url> --account <ACCOUNT_NAME> --broadcast --ffi
```

## Running the test:

Test `GovernanceToken`

```bash
forge test test/GovernanceToken.t.sol
```

Test `test/StakingPool.t.sol`
Uses `Upgrades` — requires `--ffi`

```bash
forge test test/StakingPool.t.sol --ffi
```

## Upgrading to StakingPoolV2

```bash
forge script script/Upgrade.s.sol \
 --rpc-url <RPC_URL> \
 --broadcast \
 --sender <OWNER_ADDRESS> \
 --ffi
```

OR

```bash
forge script script/Upgrade.s.sol --rpc-url <rpc_url> --account <ACCOUNT_NAME> --broadcast --ffi
```

# Run inside contracts/

# 1. Upgrade to V2 (fixes getMaxStakeLimit revert)

forge script script/Upgrade.s.sol --account shariq-foundry-dev --broadcast --ffi --rpc-url 127.0.0.1:8545

# 2. Fund rewards pool so claims work (owner account)

cast send 0x9a676e781a523b5d0c0e43731313a708cb607508 \
 "fundRewardsPool(uint256)" 1000000000000000000000 \
 --account shariq-foundry-dev \
 --rpc-url http://127.0.0.1:8545

## Environmental variables:

```
NEXT_PUBLIC_CHAIN_ID=
NEXT_PUBLIC_GOVERNANCE_TOKEN_ADDRESS=
#NEXT_PUBLIC_STAKING_POOL_ADDRESS=
NEXT_PUBLIC_MERKLE_AIRDROP_ADDRESS=
#NEXT_PUBLIC_ERC1967_PROXY_ADDRESS=
NEXT_PUBLIC_STAKING_POOL_ADDRESS=
NEXT_PUBLIC_SIMPLE_DAO_ADDRESS=
NEXT_PUBLIC_LOTTERY_ADDRESS=
NEXT_PUBLIC_PAYMASTER_ADDRESS=
NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=
GRAPHQL_API_URL=
NEXT_GRAPHQL_API_URL=
CIRCLE_API_KEY=TEST_API_KEY:
ENABLE_COMPLIANCE_CHECK=
```
