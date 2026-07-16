export const GOVERNANCE_TOKEN_ADDRESS =
  (process.env.NEXT_PUBLIC_GOVERNANCE_TOKEN_ADDRESS as `0x${string}`) ??
  '0x0000000000000000000000000000000000000000';

export const STAKING_POOL_ADDRESS =
  (process.env.NEXT_PUBLIC_STAKING_POOL_ADDRESS as `0x${string}`) ??
  '0x0000000000000000000000000000000000000000';

export const GOVERNANCE_TOKEN_ABI = [
  {
    name: 'balanceOf',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'allowance',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'approve',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'value', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    name: 'symbol',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'string' }],
  },
  {
    name: 'faucet',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [],
    outputs: [],
  },
] as const;

export const STAKING_POOL_ABI = [
  // ── View ────────────────────────────────────────────────────────────
  {
    name: 'getPoolInfo',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [
      { name: 'totalStaked', type: 'uint256' },
      { name: 'rewardsPool', type: 'uint256' },
      { name: 'protocolRate', type: 'uint256' },
    ],
  },
  {
    name: 'getUserInfo',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'user', type: 'address' }],
    outputs: [
      { name: 'stakedAmount', type: 'uint256' },
      { name: 'pendingReward', type: 'uint256' },
      { name: 'lastClaimTime', type: 'uint256' },
      { name: 'rewardRate', type: 'uint256' },
    ],
  },
  {
    name: 'getMaxStakeLimit',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'owner',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'address' }],
  },
  // ── Write ────────────────────────────────────────────────────────────
  {
    name: 'stake',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'amountInWei', type: 'uint256' }],
    outputs: [],
  },
  {
    name: 'unstake',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'amountInWei', type: 'uint256' }],
    outputs: [],
  },
  {
    name: 'claimRewards',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [],
    outputs: [],
  },
  {
    name: 'fundRewardsPool',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'amountInWei', type: 'uint256' }],
    outputs: [],
  },
  {
    name: 'setRewardRate',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'newRewardRate', type: 'uint256' }],
    outputs: [],
  },
  {
    name: 'setStakeLimit',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'newLimitInWei', type: 'uint256' }],
    outputs: [],
  },
] as const;
