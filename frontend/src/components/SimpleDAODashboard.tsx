'use client';

import {
  GOVERNANCE_TOKEN_ABI,
  GOVERNANCE_TOKEN_ADDRESS,
  SIMPLE_DAO_ABI,
  SIMPLE_DAO_ADDRESS,
} from '@/lib/contracts';
import { useEffect, useMemo, useState } from 'react';
import { BaseError, ContractFunctionRevertedError, decodeErrorResult, formatEther } from 'viem';
import {
  useAccount,
  useBlockNumber,
  useReadContract,
  useReadContracts,
  useWaitForTransactionReceipt,
  useWatchContractEvent,
  useWriteContract,
} from 'wagmi';

// ── Types ─────────────────────────────────────────────────────────────────────

type ProposalData = {
  description: string;
  forVotes: bigint;
  againstVotes: bigint;
  snapshotBlock: bigint;
  deadline: bigint;
  executed: boolean;
};

// Mirrors SimpleDAO.ProposalState enum
const STATE = { Active: 0, Passed: 1, Failed: 2, Executed: 3 } as const;
type ProposalState = 0 | 1 | 2 | 3;

// ── Error decoding ────────────────────────────────────────────────────────────

const SDAO_ERRORS: Record<string, string> = {
  SDAO__NoVotingPower: 'No voting power — delegate your GTK tokens first.',
  SDAO__AlreadyVoted: 'Already voted on this proposal.',
  SDAO__VotingPeriodEnded: 'Voting period has ended.',
  SDAO__CanNotExecuteAnActiveProposal: 'Voting still active — wait for the deadline.',
  SDAO__ProposalAlreadyExecuted: 'Proposal already executed.',
  SDAO__ProposalDidNotPass: 'Proposal did not pass.',
  SDAO__ProposalDoesNotExist: 'Proposal does not exist.',
  SDAO__VotingPeriodMustBeGreaterThanZero: 'Voting period must be > 0 blocks.',
};

function findRevertHex(err: BaseError): `0x${string}` | undefined {
  const hexRe = /^0x[\da-fA-F]{8}/;
  const node = err.walk((e) => {
    const d = (e as { data?: unknown }).data;
    // Shape A: data = "0xABCD..." (viem RawContractError / ExecutionRevertedError)
    if (typeof d === 'string' && hexRe.test(d)) return true;
    // Shape B: data = { data: "0xABCD..." } (MetaMask nested JSON-RPC error)
    if (d && typeof d === 'object' && !Array.isArray(d)) {
      const inner = (d as { data?: unknown }).data;
      if (typeof inner === 'string' && hexRe.test(inner)) return true;
    }
    return false;
  });
  if (!node) return undefined;
  const d = (node as { data?: unknown }).data;
  if (typeof d === 'string') return d as `0x${string}`;
  if (d && typeof d === 'object' && !Array.isArray(d)) {
    const inner = (d as { data?: unknown }).data;
    if (typeof inner === 'string') return inner as `0x${string}`;
  }
  return undefined;
}

function decodeError(err: Error | null | undefined): string | null {
  if (!err) return null;
  if (!(err instanceof BaseError)) return err.message;

  // Path 1: viem already decoded the error (simulateContract / direct viem call)
  const revert = err.walk(e => e instanceof ContractFunctionRevertedError);
  if (revert instanceof ContractFunctionRevertedError) {
    const name = revert.data?.errorName;
    const reason = revert.reason;
    if (name) return SDAO_ERRORS[name] ?? name;
    if (reason) return reason;
  }

  // Path 2: wallet-layer error — raw hex in cause chain, decode manually
  const rawHex = findRevertHex(err);
  if (rawHex) {
    try {
      const { errorName } = decodeErrorResult({ abi: SIMPLE_DAO_ABI, data: rawHex });
      return SDAO_ERRORS[errorName] ?? errorName;
    } catch { /* unknown selector — fall through */ }
  }

  //console.log('[decodeError] chain:', JSON.stringify(err, Object.getOwnPropertyNames(err)));
  console.log('[decodeError] chain 1: => ', err);
  console.log('[decodeError] chain 2: => ', Object.getOwnPropertyNames(err));

  return err.shortMessage;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function fmt(wei: bigint | undefined, dp = 2): string {
  if (wei === undefined || wei === null) return '—';
  const n = Number(formatEther(wei));
  return n.toLocaleString(undefined, { minimumFractionDigits: dp, maximumFractionDigits: dp });
}

function blocksToTime(blocks: number): string {
  const secs = blocks * 12;
  if (secs < 120) return `~${secs}s`;
  if (secs < 7200) return `~${Math.round(secs / 60)}min`;
  if (secs < 172800) return `~${Math.round(secs / 3600)}h`;
  return `~${Math.round(secs / 86400)}d`;
}

// ── Sub-components ────────────────────────────────────────────────────────────

function StateBadge({ state }: { state: ProposalState | undefined }) {
  if (state === undefined) return null;
  const cfg: Record<number, { label: string; cls: string }> = {
    0: { label: 'Active', cls: 'bg-indigo-500/20 text-indigo-400 border-indigo-500/30' },
    1: { label: 'Passed', cls: 'bg-emerald-500/20 text-emerald-400 border-emerald-500/30' },
    2: { label: 'Failed', cls: 'bg-red-500/20 text-red-400 border-red-500/30' },
    3: { label: 'Executed', cls: 'bg-zinc-700/40 text-zinc-500 border-zinc-600/30' },
  };
  const { label, cls } = cfg[state];
  return (
    <span className={`rounded-full border px-2.5 py-0.5 text-xs font-medium ${cls}`}>
      {label}
    </span>
  );
}

function VoteBar({ forVotes, againstVotes }: { forVotes: bigint; againstVotes: bigint }) {
  const total = forVotes + againstVotes;
  const forPct = total === 0n ? 0 : Number((forVotes * 10000n) / total) / 100;
  const againstPct = total === 0n ? 0 : 100 - forPct;
  return (
    <div className="mt-3 space-y-1.5">
      <div className="flex h-2 overflow-hidden rounded-full bg-zinc-800">
        {total > 0n ? (
          <>
            <div className="bg-emerald-500 transition-all" style={{ width: `${forPct}%` }} />
            <div className="bg-red-500 transition-all" style={{ width: `${againstPct}%` }} />
          </>
        ) : (
          <div className="w-full bg-zinc-700 opacity-50" />
        )}
      </div>
      <div className="flex justify-between text-xs">
        <span className="text-emerald-400">
          FOR {fmt(forVotes, 0)} GTK{total > 0n && ` (${forPct.toFixed(1)}%)`}
        </span>
        <span className="text-red-400">
          AGAINST {fmt(againstVotes, 0)} GTK{total > 0n && ` (${againstPct.toFixed(1)}%)`}
        </span>
      </div>
    </div>
  );
}

function TxStatus({
  isPending,
  isConfirming,
  isConfirmed,
  error,
  receiptError,
}: {
  isPending: boolean;
  isConfirming: boolean;
  isConfirmed: boolean;
  error: Error | null;
  receiptError?: Error | null;
}) {
  const msg = decodeError(error) ?? decodeError(receiptError);
  if (msg) return <p className="text-xs text-red-400">{msg}</p>;
  if (isPending) return <p className="text-xs text-zinc-400">Waiting for wallet…</p>;
  if (isConfirming) return <p className="text-xs text-amber-400">Confirming…</p>;
  if (isConfirmed) return <p className="text-xs text-emerald-400">Confirmed!</p>;
  return null;
}

// ── Main component ────────────────────────────────────────────────────────────

export function SimpleDAODashboard() {
  const { address, isConnected } = useAccount();
  const [descInput, setDescInput] = useState('');
  const [periodInput, setPeriodInput] = useState('100');
  const [activeTx, setActiveTx] = useState<string | null>(null);

  const dao = { address: SIMPLE_DAO_ADDRESS, abi: SIMPLE_DAO_ABI } as const;
  const token = { address: GOVERNANCE_TOKEN_ADDRESS, abi: GOVERNANCE_TOKEN_ABI } as const;

  // ── Reads ─────────────────────────────────────────────────────────────────

  const { data: currentBlock } = useBlockNumber({ watch: true, query: { refetchInterval: 10_000 } });

  const { data: countRaw, refetch: refetchCount } = useReadContract({
    ...dao,
    functionName: 'getProposalCount',
  });
  const count = Number(countRaw ?? 0n);

  const { data: owner } = useReadContract({ ...dao, functionName: 'owner' });

  const { data: votingPower } = useReadContract({
    ...token,
    functionName: 'getVotes',
    args: [address!],
    query: { enabled: !!address },
  });

  // Batch: getProposal(0..N-1) — returns (Proposal, ProposalState), so no separate state call needed
  const proposalCalls = useMemo(
    () =>
      Array.from({ length: count }, (_, i) => ({
        address: SIMPLE_DAO_ADDRESS,
        abi: SIMPLE_DAO_ABI,
        functionName: 'getProposal' as const,
        args: [BigInt(i)] as const,
      })),
    [count],
  );

  // Batch: hasVoted(0..N-1, address)
  const hasVotedCalls = useMemo(
    () =>
      address
        ? Array.from({ length: count }, (_, i) => ({
          address: SIMPLE_DAO_ADDRESS,
          abi: SIMPLE_DAO_ABI,
          functionName: 'hasVoted' as const,
          args: [BigInt(i), address] as const,
        }))
        : [],
    [count, address],
  );

  const { data: proposalsRaw, refetch: refetchProposals } = useReadContracts({
    contracts: proposalCalls,
    query: { enabled: count > 0 },
  });

  const { data: hasVotedRaw, refetch: refetchVoted } = useReadContracts({
    contracts: hasVotedCalls,
    query: { enabled: !!address && count > 0 },
  });

  // ── Event watchers ────────────────────────────────────────────────────────

  useWatchContractEvent({
    ...dao,
    eventName: 'SDAO__ProposalCreated',
    pollingInterval: 15_000,
    onLogs: () => { void refetchCount(); void refetchProposals(); },
  });

  useWatchContractEvent({
    ...dao,
    eventName: 'SDAO__Voted',
    pollingInterval: 15_000,
    onLogs: () => { void refetchProposals(); void refetchVoted(); },
  });

  useWatchContractEvent({
    ...dao,
    eventName: 'SDAO__ProposalExecuted',
    pollingInterval: 15_000,
    onLogs: () => { void refetchProposals(); },
  });

  // ── Writes ────────────────────────────────────────────────────────────────

  const {
    writeContract,
    data: txHash,
    isPending,
    error: writeError,
    reset: resetWrite,
  } = useWriteContract();

  const { isLoading: isConfirming, isSuccess: isConfirmed, error: receiptError } =
    useWaitForTransactionReceipt({ hash: txHash });

  useEffect(() => {
    if (isConfirmed) {
      refetchCount();
      refetchProposals();
      refetchVoted();
      setDescInput('');
      setActiveTx(null);
    }
  }, [isConfirmed]); // eslint-disable-line react-hooks/exhaustive-deps

  // ── Derived ───────────────────────────────────────────────────────────────

  const isOwner = !!(
    address &&
    owner &&
    address.toLowerCase() === (owner as string).toLowerCase()
  );
  const hasVotingPower = votingPower !== undefined && votingPower > 0n;

  // Build display list, newest first
  const proposals = useMemo(
    () =>
      Array.from({ length: count }, (_, i) => {
        const id = count - 1 - i;
        const raw = proposalsRaw?.[id]?.result;
        // getProposal returns (Proposal, ProposalState) — state is raw[1]
        const proposalData = (Array.isArray(raw) ? raw[0] : raw) as ProposalData | undefined;
        const state        = (Array.isArray(raw) ? raw[1] : undefined) as ProposalState | undefined;
        const voted        = hasVotedRaw?.[id]?.result as boolean | undefined;
        return { id, proposalData, state, voted };
      }),
    [count, proposalsRaw, hasVotedRaw],
  );

  // ── Handlers ──────────────────────────────────────────────────────────────

  function handleCreate() {
    if (!descInput.trim() || !periodInput) return;
    setActiveTx('create');
    resetWrite();
    writeContract({
      ...dao,
      functionName: 'createProposal',
      args: [descInput.trim(), BigInt(periodInput)],
    });
  }

  function handleVote(proposalId: number, inSupport: boolean) {
    setActiveTx(`vote-${proposalId}`);
    resetWrite();
    writeContract({
      ...dao,
      functionName: 'vote',
      args: [BigInt(proposalId), inSupport],
    });
  }

  function handleExecute(proposalId: number) {
    setActiveTx(`execute-${proposalId}`);
    resetWrite();
    writeContract({
      ...dao,
      functionName: 'executeProposal',
      args: [BigInt(proposalId)],
    });
  }

  const periodBlocks = Number(periodInput) || 0;

  // ── Render ────────────────────────────────────────────────────────────────

  return (
    <div className="mx-auto w-full max-w-5xl space-y-6 px-4 py-8">

      {/* Overview */}
      <section>
        <h2 className="mb-3 text-xs font-semibold uppercase tracking-wider text-zinc-500">
          Overview
        </h2>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <div className="rounded-xl border border-zinc-800 bg-zinc-900 p-5">
            <p className="text-xs font-medium uppercase tracking-wider text-zinc-500">Proposals</p>
            <p className="mt-2 text-2xl font-bold text-white">{count}</p>
          </div>
          <div className="rounded-xl border border-zinc-800 bg-zinc-900 p-5">
            <p className="text-xs font-medium uppercase tracking-wider text-zinc-500">Your Voting Power</p>
            <p className="mt-2 text-2xl font-bold text-white">
              {isConnected ? `${fmt(votingPower, 0)} GTK` : '—'}
            </p>
          </div>
          <div className="rounded-xl border border-zinc-800 bg-zinc-900 p-5">
            <p className="text-xs font-medium uppercase tracking-wider text-zinc-500">Current Block</p>
            <p className="mt-2 text-2xl font-bold text-white">
              {currentBlock !== undefined ? currentBlock.toString() : '—'}
            </p>
          </div>
        </div>
      </section>

      {/* Create proposal */}
      {isConnected && (
        <section>
          <h2 className="mb-3 text-xs font-semibold uppercase tracking-wider text-zinc-500">
            Create Proposal
          </h2>
          <div className="rounded-xl border border-zinc-800 bg-zinc-900 p-5 space-y-4">
            {!hasVotingPower && (
              <div className="rounded-lg border border-amber-500/30 bg-amber-500/10 px-4 py-3">
                <p className="text-sm text-amber-300">
                  You need GTK voting power to create proposals. Claim GTK from the faucet on the
                  Staking page — the faucet auto-delegates, so your voting power is ready immediately.
                </p>
              </div>
            )}

            <div>
              <label className="mb-1.5 block text-xs font-medium text-zinc-400">Description</label>
              <textarea
                rows={3}
                placeholder="Describe what this proposal would change…"
                value={descInput}
                onChange={(e) => {
                  setDescInput(e.target.value);
                  if (activeTx === 'create') resetWrite();
                }}
                disabled={!hasVotingPower}
                className="w-full resize-none rounded-lg border border-zinc-700 bg-zinc-800 px-4 py-2.5 text-sm text-white placeholder-zinc-600 focus:border-indigo-500 focus:outline-none disabled:opacity-50"
              />
            </div>

            <div>
              <label className="mb-1.5 block text-xs font-medium text-zinc-400">
                Voting Period —{' '}
                <span className="text-zinc-500">
                  {periodBlocks} blocks ({blocksToTime(periodBlocks)} on Sepolia)
                </span>
              </label>
              <input
                type="number"
                min="1"
                value={periodInput}
                onChange={(e) => setPeriodInput(e.target.value)}
                disabled={!hasVotingPower}
                className="w-40 rounded-lg border border-zinc-700 bg-zinc-800 px-4 py-2.5 text-sm text-white focus:border-indigo-500 focus:outline-none disabled:opacity-50"
              />
            </div>

            <div className="flex items-center gap-3 flex-wrap">
              <button
                onClick={handleCreate}
                disabled={
                  !hasVotingPower ||
                  !descInput.trim() ||
                  !periodInput ||
                  (isPending && activeTx === 'create') ||
                  isConfirming
                }
                className="rounded-lg bg-indigo-500 px-5 py-2.5 text-sm font-medium text-white transition-opacity disabled:opacity-40"
              >
                {isPending && activeTx === 'create'
                  ? 'Creating…'
                  : isConfirming && activeTx === 'create'
                    ? 'Confirming…'
                    : 'Create Proposal'}
              </button>
              {activeTx === 'create' && (
                <TxStatus
                  isPending={isPending}
                  isConfirming={isConfirming}
                  isConfirmed={isConfirmed}
                  error={writeError}
                  receiptError={receiptError}
                />
              )}
            </div>
          </div>
        </section>
      )}

      {/* Proposal list */}
      <section>
        <h2 className="mb-3 text-xs font-semibold uppercase tracking-wider text-zinc-500">
          Proposals {count > 0 && `(${count})`}
        </h2>

        {count === 0 ? (
          <div className="rounded-xl border border-zinc-800 bg-zinc-900 py-16 text-center">
            <p className="text-zinc-500">No proposals yet.</p>
          </div>
        ) : (
          <div className="space-y-4">
            {proposals.map(({ id, proposalData, state, voted }) => {
              const isActive = state === STATE.Active;
              const isPassed = state === STATE.Passed;
              const canVote = isConnected && isActive && !voted && hasVotingPower;
              const canExecute = isConnected && isOwner && isPassed;
              const blocksLeft =
                isActive && currentBlock !== undefined && proposalData?.deadline !== undefined
                  ? Number(proposalData.deadline) - Number(currentBlock)
                  : null;
              const txKey = `vote-${id}`;
              const execKey = `execute-${id}`;

              return (
                <div
                  key={id}
                  className={`rounded-xl border bg-zinc-900 p-5 ${isActive ? 'border-indigo-500/30' : 'border-zinc-800'
                    }`}
                >
                  {/* Header row */}
                  <div className="flex items-start justify-between gap-3 flex-wrap">
                    <div className="flex items-center gap-2">
                      <span className="font-mono text-xs text-zinc-600">#{id}</span>
                      <StateBadge state={state} />
                    </div>
                    <div className="text-right text-xs text-zinc-600">
                      deadline: block {proposalData?.deadline?.toString() ?? '…'}
                      {blocksLeft !== null && blocksLeft > 0 && (
                        <span className="ml-1.5 text-indigo-400">
                          ({blocksLeft} blocks left · {blocksToTime(blocksLeft)})
                        </span>
                      )}
                    </div>
                  </div>

                  {/* Description */}
                  <p className="mt-3 text-sm leading-relaxed text-zinc-200">
                    {proposalData?.description ?? (
                      <span className="text-zinc-600 italic">Loading…</span>
                    )}
                  </p>

                  {/* Vote bar */}
                  {proposalData && (
                    <VoteBar
                      forVotes={proposalData.forVotes}
                      againstVotes={proposalData.againstVotes}
                    />
                  )}

                  {/* Actions */}
                  <div className="mt-4 flex flex-wrap items-center gap-2">
                    {canVote && (
                      <>
                        <button
                          onClick={() => handleVote(id, true)}
                          disabled={isPending || isConfirming}
                          className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-medium text-white transition-opacity disabled:opacity-40"
                        >
                          {(isPending || isConfirming) && activeTx === txKey
                            ? 'Voting…'
                            : 'Vote FOR'}
                        </button>
                        <button
                          onClick={() => handleVote(id, false)}
                          disabled={isPending || isConfirming}
                          className="rounded-lg bg-red-700 px-4 py-2 text-sm font-medium text-white transition-opacity disabled:opacity-40"
                        >
                          {(isPending || isConfirming) && activeTx === txKey
                            ? 'Voting…'
                            : 'Vote AGAINST'}
                        </button>
                      </>
                    )}

                    {canExecute && (
                      <button
                        onClick={() => handleExecute(id)}
                        disabled={isPending || isConfirming}
                        className="rounded-lg bg-amber-500 px-4 py-2 text-sm font-medium text-black transition-opacity disabled:opacity-40"
                      >
                        {(isPending || isConfirming) && activeTx === execKey
                          ? 'Executing…'
                          : 'Execute'}
                      </button>
                    )}

                    {voted && isActive && (
                      <span className="text-xs text-zinc-500 italic">You voted on this proposal</span>
                    )}
                    {isConnected && isActive && !hasVotingPower && (
                      <span className="text-xs text-zinc-500 italic">No voting power to vote</span>
                    )}
                  </div>

                  {/* Tx feedback for this proposal */}
                  {(activeTx === txKey || activeTx === execKey) && (
                    <div className="mt-2">
                      <TxStatus
                        isPending={isPending}
                        isConfirming={isConfirming}
                        isConfirmed={isConfirmed}
                        error={writeError}
                        receiptError={receiptError}
                      />
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </section>

      {!isConnected && (
        <div className="rounded-xl border border-zinc-800 bg-zinc-900 py-12 text-center">
          <p className="text-zinc-400">Connect your wallet to create proposals and vote.</p>
        </div>
      )}

      {/* Contract address */}
      <section>
        <h2 className="mb-2 text-xs font-semibold uppercase tracking-wider text-zinc-500">
          Contract
        </h2>
        <div className="rounded-xl border border-zinc-800 bg-zinc-900 px-5">
          <div className="flex items-center justify-between py-2.5 text-xs">
            <span className="text-zinc-500">SimpleDAO</span>
            <span className="font-mono text-zinc-300">{SIMPLE_DAO_ADDRESS}</span>
          </div>
        </div>
      </section>
    </div>
  );
}
