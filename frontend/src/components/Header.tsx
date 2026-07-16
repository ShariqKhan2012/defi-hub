'use client';

import { ConnectButton } from '@rainbow-me/rainbowkit';

export function Header() {
  return (
    <header className="border-b border-zinc-800 bg-zinc-950 px-6 py-4">
      <div className="mx-auto flex max-w-5xl items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-emerald-500 text-sm font-bold text-black">
            D
          </div>
          <span className="text-lg font-semibold text-white">DeFi Hub</span>
          <span className="rounded-full bg-emerald-500/10 px-2 py-0.5 text-xs font-medium text-emerald-400">
            Staking
          </span>
        </div>
        <ConnectButton />
      </div>
    </header>
  );
}
