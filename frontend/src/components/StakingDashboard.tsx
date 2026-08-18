'use client';

import {
  GOVERNANCE_TOKEN_ABI,
  GOVERNANCE_TOKEN_ADDRESS,
  STAKING_POOL_ABI,
  STAKING_POOL_ADDRESS,
} from '@/lib/contracts';
import { useEffect, useState } from 'react';
import { formatEther, maxUint256, parseEther } from 'viem';
import {
  useAccount,
  useReadContracts,
  useWaitForTransactionReceipt,
  useWatchContractEvent,
  useWriteContract,
} from 'wagmi';

// ── Helpers ──────────────────────────────────────────────────────────────────

function fmt(wei: bigint | undefined, dp = 4): string {
  if (wei === undefined || wei === null) return '—';
  const n = Number(formatEther(wei));
  return n.toLocaleString(undefined, { minimumFractionDigits: dp, maximumFractionDigits: dp });
}

function fmtAPR(ratePerSecondE18: bigint | undefined): string {
  if (!ratePerSecondE18) return '—';
  // rate is tokens-per-second per token staked, scaled to 1e18
  const apr = (Number(ratePerSecondE18) / 1e18) * 365 * 24 * 3600 * 100;
  return apr.toFixed(4) + '%';
}

function parseInputSafe(value: string): bigint | null {
  if (!value || value === '0') return null;
  try {
    return parseEther(value);
  } catch {
    return null;
  }
}

// ── Types ─────────────────────────────────────────────────────────────────────

type Tab = 'stake' | 'unstake' | 'claim';

// ── Sub-components ────────────────────────────────────────────────────────────

function StatCard({
  label,
  value,
  unit,
  highlight,
}: {
  label: string;
  value: string;
  unit?: string;
  highlight?: boolean;
}) {
  return (
    <div className="rounded-xl border border-zinc-800 bg-zinc-900 p-5">
      <p className="text-xs font-medium uppercase tracking-wider text-zinc-500">{label}</p>
      <p className={`mt-2 text-2xl font-bold ${highlight ? 'text-emerald-400' : 'text-white'}`}>
        {value}
        {unit && <span className="ml-1 text-sm font-normal text-zinc-400">{unit}</span>}
      </p>
    </div>
  );
}

function TxStatus({
  isPending,
  isConfirming,
  isConfirmed,
  error,
}: {
  isPending: boolean;
  isConfirming: boolean;
  isConfirmed: boolean;
  error: Error | null;
}) {
  if (error) {
    const msg = error.message.split('\n')[0].slice(0, 120);
    return <p className="mt-2 text-xs text-red-400">{msg}</p>;
  }
  if (isPending) return <p className="mt-2 text-xs text-zinc-400">Waiting for wallet…</p>;
  if (isConfirming) return <p className="mt-2 text-xs text-amber-400">Confirming transaction…</p>;
  if (isConfirmed) return <p className="mt-2 text-xs text-emerald-400">Transaction confirmed!</p>;
  return null;
}

function AddressRow({ label, address }: { label: string; address: string }) {
  const [copied, setCopied] = useState(false);

  function copy() {
    navigator.clipboard.writeText(address);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  }

  return (
    <div className="flex items-center justify-between gap-4 py-2">
      <span className="w-36 shrink-0 text-xs text-zinc-500">{label}</span>
      <span className="flex-1 truncate font-mono text-xs text-zinc-300">{address}</span>
      <button
        onClick={copy}
        className="shrink-0 rounded px-2 py-0.5 text-xs text-zinc-400 transition-colors hover:bg-zinc-800 hover:text-white"
      >
        {copied ? 'Copied!' : 'Copy'}
      </button>
    </div>
  );
}

// ── Main component ────────────────────────────────────────────────────────────

export function StakingDashboard() {
  const { address, isConnected } = useAccount();
  const [activeTab, setActiveTab] = useState<Tab>('stake');
  const [stakeInput, setStakeInput] = useState('');
  const [unstakeInput, setUnstakeInput] = useState('');

  const poolContract = { address: STAKING_POOL_ADDRESS, abi: STAKING_POOL_ABI } as const;
  const tokenContract = { address: GOVERNANCE_TOKEN_ADDRESS, abi: GOVERNANCE_TOKEN_ABI } as const;

  // ── Reads ─────────────────────────────────────────────────────────────────

  const { data: poolData, refetch: refetchPool } = useReadContracts({
    contracts: [
      { ...poolContract, functionName: 'getPoolInfo' },
      //{ ...poolContract, functionName: 'getMaxStakeLimit' },
      { ...poolContract, functionName: 'owner' },
    ],
  });

  const { data: userData, refetch: refetchUser } = useReadContracts({
    contracts: [
      { ...poolContract, functionName: 'getUserInfo', args: [address!] },
      { ...tokenContract, functionName: 'balanceOf', args: [address!] },
      { ...tokenContract, functionName: 'allowance', args: [address!, STAKING_POOL_ADDRESS] },
    ],
    query: { enabled: !!address },
  });

  const poolInfo = poolData?.[0]?.result as readonly [bigint, bigint, bigint] | undefined;
  //const maxStakeLimit = poolData?.[1]?.result as bigint | undefined;
  const contractOwner = poolData?.[1]?.result as `0x${string}` | undefined;

  const userInfo = userData?.[0]?.result as readonly [bigint, bigint, bigint, bigint] | undefined;
  const tokenBalance = userData?.[1]?.result as bigint | undefined;
  const tokenAllowance = userData?.[2]?.result as bigint | undefined;

  const [totalStaked, rewardsPool, protocolRate] = poolInfo ?? [undefined, undefined, undefined];
  const [stakedAmount, pendingReward, , userRate] = userInfo ?? [undefined, undefined, undefined, undefined];

  const isOwner = address && contractOwner && address.toLowerCase() === contractOwner.toLowerCase();

  // ── Event watchers (cross-client live updates) ────────────────────────────

  useWatchContractEvent({
    ...poolContract,
    eventName: 'STKPOOL__Staked',
    pollingInterval: 15_000,
    onLogs: () => { void refetchPool(); },
  });

  useWatchContractEvent({
    ...poolContract,
    eventName: 'STKPOOL__Unstaked',
    pollingInterval: 15_000,
    onLogs: () => { void refetchPool(); },
  });

  useWatchContractEvent({
    ...poolContract,
    eventName: 'STKPOOL__RewardPoolFunded',
    pollingInterval: 15_000,
    onLogs: () => { void refetchPool(); },
  });

  // ── Writes ────────────────────────────────────────────────────────────────

  const {
    writeContract,
    data: txHash,
    isPending,
    error: writeError,
    reset: resetWrite,
  } = useWriteContract();

  const { isLoading: isConfirming, isSuccess: isConfirmed } = useWaitForTransactionReceipt({
    hash: txHash,
  });

  useEffect(() => {
    if (isConfirmed) {
      refetchPool();
      refetchUser();
      setStakeInput('');
      setUnstakeInput('');
    }
  }, [isConfirmed, refetchPool, refetchUser]);

  // ── Derived state ─────────────────────────────────────────────────────────

  const stakeAmountWei = parseInputSafe(stakeInput);
  const unstakeAmountWei = parseInputSafe(unstakeInput);

  const needsApproval =
    stakeAmountWei !== null &&
    (tokenAllowance === undefined || tokenAllowance < stakeAmountWei);

  const stakeDisabled =
    !stakeAmountWei ||
    needsApproval ||
    isPending ||
    isConfirming ||
    (tokenBalance !== undefined && stakeAmountWei > tokenBalance);

  const unstakeDisabled =
    !unstakeAmountWei ||
    isPending ||
    isConfirming ||
    (stakedAmount !== undefined && unstakeAmountWei > stakedAmount);

  const claimDisabled =
    isPending ||
    isConfirming ||
    !pendingReward ||
    pendingReward === 0n ||
    !rewardsPool ||
    rewardsPool === 0n;

  // ── Handlers ──────────────────────────────────────────────────────────────

  function handleTabChange(tab: Tab) {
    setActiveTab(tab);
    resetWrite();
  }

  function handleApprove() {
    resetWrite();
    writeContract({
      address: GOVERNANCE_TOKEN_ADDRESS,
      abi: GOVERNANCE_TOKEN_ABI,
      functionName: 'approve',
      args: [STAKING_POOL_ADDRESS, maxUint256],
    });
  }

  function handleStake() {
    if (!stakeAmountWei) return;
    resetWrite();
    writeContract({
      address: STAKING_POOL_ADDRESS,
      abi: STAKING_POOL_ABI,
      functionName: 'stake',
      args: [stakeAmountWei],
    });
  }

  function handleUnstake() {
    if (!unstakeAmountWei) return;
    resetWrite();
    writeContract({
      address: STAKING_POOL_ADDRESS,
      abi: STAKING_POOL_ABI,
      functionName: 'unstake',
      args: [unstakeAmountWei],
    });
  }

  function handleClaim() {
    resetWrite();
    writeContract({
      address: STAKING_POOL_ADDRESS,
      abi: STAKING_POOL_ABI,
      functionName: 'claimRewards',
    });
  }

  function setMaxStake() {
    if (tokenBalance !== undefined) setStakeInput(formatEther(tokenBalance));
  }

  function setMaxUnstake() {
    if (stakedAmount !== undefined) setUnstakeInput(formatEther(stakedAmount));
  }

  function handleFaucet() {
    resetWrite();
    writeContract({
      address: GOVERNANCE_TOKEN_ADDRESS,
      abi: GOVERNANCE_TOKEN_ABI,
      functionName: 'faucet',
    });
  }

  // ── Render ────────────────────────────────────────────────────────────────

  return (
    <div className="mx-auto w-full max-w-5xl space-y-6 px-4 py-8">

      {/* Protocol stats */}
      <section>
        <h2 className="mb-3 text-xs font-semibold uppercase tracking-wider text-zinc-500">
          Protocol
        </h2>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <StatCard
            label="Total Value Locked"
            value={fmt(totalStaked, 2)}
            unit="GTK"
          />
          <StatCard
            label="Rewards Pool"
            value={fmt(rewardsPool, 2)}
            unit="GTK"
          />
          <StatCard
            label="Protocol APR"
            value={fmtAPR(protocolRate)}
            highlight
          />
        </div>
      </section>

      {/* User position */}
      {isConnected && (
        <section>
          <h2 className="mb-3 text-xs font-semibold uppercase tracking-wider text-zinc-500">
            Your Position
          </h2>
          <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
            <StatCard label="Staked" value={fmt(stakedAmount, 2)} unit="GTK" />
            <StatCard label="Pending Rewards" value={fmt(pendingReward, 6)} unit="GTK" highlight />
            <StatCard label="Your APR" value={fmtAPR(userRate)} />
            {/*<StatCard
              label="Stake Limit (V2)"
              value={fmt(maxStakeLimit, 0)}
              unit="GTK"
            />*/}
          </div>
          {isOwner && (
            <p className="mt-2 text-xs text-amber-400">
              You are the contract owner. You can set reward rate and stake limit.
            </p>
          )}
        </section>
      )}

      {/* Action panel */}
      {isConnected ? (
        <section>
          <div className="rounded-xl border border-zinc-800 bg-zinc-900">

            {/* Tabs */}
            <div className="flex border-b border-zinc-800">
              {(['stake', 'unstake', 'claim'] as Tab[]).map((tab) => (
                <button
                  key={tab}
                  onClick={() => handleTabChange(tab)}
                  className={`px-6 py-3 text-sm font-medium capitalize transition-colors ${activeTab === tab
                      ? 'border-b-2 border-emerald-500 text-emerald-400'
                      : 'text-zinc-400 hover:text-zinc-200'
                    }`}
                >
                  {tab}
                </button>
              ))}
            </div>

            <div className="p-6">
              {/* Stake tab */}
              {activeTab === 'stake' && (
                <div className="space-y-4">
                  {/* Faucet — show when balance is zero */}
                  {tokenBalance !== undefined && tokenBalance === 0n && (
                    <div className="flex items-center justify-between rounded-lg border border-indigo-500/30 bg-indigo-500/10 px-4 py-3">
                      <p className="text-sm text-indigo-300">
                        No GTK? Claim <span className="font-semibold text-white">3,000 GTK</span> from the faucet.
                      </p>
                      <button
                        onClick={handleFaucet}
                        disabled={isPending || isConfirming}
                        className="ml-4 shrink-0 rounded-lg bg-indigo-500 px-3 py-1.5 text-xs font-medium text-white transition-opacity disabled:opacity-50"
                      >
                        {isPending || isConfirming ? 'Claiming…' : 'Get GTK'}
                      </button>
                    </div>
                  )}
                  <div>
                    <div className="mb-1 flex items-center justify-between text-xs text-zinc-400">
                      <span>Amount</span>
                      <button onClick={setMaxStake} className="hover:text-white">
                        Balance: {fmt(tokenBalance, 2)} GTK
                      </button>
                    </div>
                    <div className="flex gap-2">
                      <input
                        type="number"
                        min="0"
                        placeholder="0.0"
                        value={stakeInput}
                        onChange={(e) => { setStakeInput(e.target.value); resetWrite(); }}
                        className="flex-1 rounded-lg border border-zinc-700 bg-zinc-800 px-4 py-2.5 text-white placeholder-zinc-600 focus:border-emerald-500 focus:outline-none"
                      />
                      <button
                        onClick={setMaxStake}
                        className="rounded-lg border border-zinc-700 px-3 py-2 text-xs text-zinc-400 hover:border-zinc-600 hover:text-white"
                      >
                        MAX
                      </button>
                    </div>
                    {/*maxStakeLimit !== undefined && stakeAmountWei !== null && stakeAmountWei > maxStakeLimit && (
                      <p className="mt-1 text-xs text-red-400">
                        Exceeds stake limit of {fmt(maxStakeLimit, 0)} GTK
                      </p>
                    )*/}
                  </div>

                  {needsApproval ? (
                    <button
                      onClick={handleApprove}
                      disabled={isPending || isConfirming}
                      className="w-full rounded-lg bg-amber-500 px-4 py-3 font-medium text-black transition-opacity disabled:opacity-50"
                    >
                      {isPending || isConfirming ? 'Approving…' : 'Approve GTK'}
                    </button>
                  ) : (
                    <button
                      onClick={handleStake}
                      disabled={stakeDisabled}
                      className="w-full rounded-lg bg-emerald-500 px-4 py-3 font-medium text-black transition-opacity disabled:opacity-50"
                    >
                      {isPending || isConfirming ? 'Staking…' : 'Stake GTK'}
                    </button>
                  )}

                  <TxStatus
                    isPending={isPending}
                    isConfirming={isConfirming}
                    isConfirmed={isConfirmed}
                    error={writeError}
                  />
                </div>
              )}

              {/* Unstake tab */}
              {activeTab === 'unstake' && (
                <div className="space-y-4">
                  <div>
                    <div className="mb-1 flex items-center justify-between text-xs text-zinc-400">
                      <span>Amount</span>
                      <button onClick={setMaxUnstake} className="hover:text-white">
                        Staked: {fmt(stakedAmount, 2)} GTK
                      </button>
                    </div>
                    <div className="flex gap-2">
                      <input
                        type="number"
                        min="0"
                        placeholder="0.0"
                        value={unstakeInput}
                        onChange={(e) => { setUnstakeInput(e.target.value); resetWrite(); }}
                        className="flex-1 rounded-lg border border-zinc-700 bg-zinc-800 px-4 py-2.5 text-white placeholder-zinc-600 focus:border-amber-500 focus:outline-none"
                      />
                      <button
                        onClick={setMaxUnstake}
                        className="rounded-lg border border-zinc-700 px-3 py-2 text-xs text-zinc-400 hover:border-zinc-600 hover:text-white"
                      >
                        MAX
                      </button>
                    </div>
                  </div>

                  <button
                    onClick={handleUnstake}
                    disabled={unstakeDisabled}
                    className="w-full rounded-lg bg-amber-500 px-4 py-3 font-medium text-black transition-opacity disabled:opacity-50"
                  >
                    {isPending || isConfirming ? 'Unstaking…' : 'Unstake GTK'}
                  </button>

                  <p className="text-xs text-zinc-500">
                    Unstaking also pays out any pending rewards.
                  </p>

                  <TxStatus
                    isPending={isPending}
                    isConfirming={isConfirming}
                    isConfirmed={isConfirmed}
                    error={writeError}
                  />
                </div>
              )}

              {/* Claim tab */}
              {activeTab === 'claim' && (
                <div className="space-y-4">
                  <div className="rounded-lg border border-zinc-700 bg-zinc-800 p-4 text-center">
                    <p className="text-xs text-zinc-400">Claimable Rewards</p>
                    <p className="mt-1 text-3xl font-bold text-emerald-400">
                      {fmt(pendingReward, 6)}
                    </p>
                    <p className="text-sm text-zinc-400">GTK</p>
                  </div>

                  {rewardsPool === 0n && (
                    <p className="text-xs text-amber-400">
                      Rewards pool is empty — claims are unavailable until the pool is funded.
                    </p>
                  )}

                  <button
                    onClick={handleClaim}
                    disabled={claimDisabled}
                    className="w-full rounded-lg bg-indigo-500 px-4 py-3 font-medium text-white transition-opacity disabled:opacity-50"
                  >
                    {isPending || isConfirming ? 'Claiming…' : 'Claim Rewards'}
                  </button>

                  <TxStatus
                    isPending={isPending}
                    isConfirming={isConfirming}
                    isConfirmed={isConfirmed}
                    error={writeError}
                  />
                </div>
              )}
            </div>
          </div>
        </section>
      ) : (
        <div className="rounded-xl border border-zinc-800 bg-zinc-900 py-16 text-center">
          <p className="text-zinc-400">Connect your wallet to stake, unstake, or claim rewards.</p>
        </div>
      )}

      {/* Owner panel */}
      {isConnected && isOwner && (
        <section>
          <h2 className="mb-2 text-xs font-semibold uppercase tracking-wider text-zinc-500">
            Owner
          </h2>
          <div className="rounded-xl border border-amber-500/20 bg-zinc-900 p-5 space-y-4">
            <div>
              <p className="text-xs font-medium text-amber-400 mb-3">Fund Rewards Pool</p>
              <div className="flex gap-2">
                <input
                  id="fund-input"
                  type="number"
                  min="0"
                  placeholder="Amount (GTK)"
                  className="flex-1 rounded-lg border border-zinc-700 bg-zinc-800 px-4 py-2.5 text-white placeholder-zinc-600 focus:border-amber-500 focus:outline-none text-sm"
                />
                <button
                  onClick={() => {
                    const input = (document.getElementById('fund-input') as HTMLInputElement).value;
                    const amount = parseInputSafe(input);
                    if (!amount) return;
                    resetWrite();
                    writeContract({
                      address: STAKING_POOL_ADDRESS,
                      abi: STAKING_POOL_ABI,
                      functionName: 'fundRewardsPool',
                      args: [amount],
                    });
                  }}
                  disabled={isPending || isConfirming}
                  className="rounded-lg bg-amber-500 px-4 py-2.5 text-sm font-medium text-black transition-opacity disabled:opacity-50"
                >
                  {isPending || isConfirming ? 'Funding…' : 'Fund'}
                </button>
              </div>
              <p className="mt-1.5 text-xs text-zinc-500">
                Current pool: {fmt(rewardsPool, 2)} GTK
              </p>
            </div>
            <TxStatus
              isPending={isPending}
              isConfirming={isConfirming}
              isConfirmed={isConfirmed}
              error={writeError}
            />
          </div>
        </section>
      )}

      {/* Contract addresses */}
      <section>
        <h2 className="mb-2 text-xs font-semibold uppercase tracking-wider text-zinc-500">
          Contracts
        </h2>
        <div className="rounded-xl border border-zinc-800 bg-zinc-900 px-5 divide-y divide-zinc-800">
          <AddressRow label="GovernanceToken (GTK)" address={GOVERNANCE_TOKEN_ADDRESS} />
          <AddressRow label="StakingPool (proxy)" address={STAKING_POOL_ADDRESS} />
        </div>
      </section>
    </div>
  );
}
