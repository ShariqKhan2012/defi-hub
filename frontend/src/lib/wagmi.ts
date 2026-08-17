import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import { anvil, sepolia } from 'wagmi/chains';

const projectId =
  process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || 'local-dev-no-wc';

// In production (Sepolia), exclude anvil so it isn't the default chain.
// Locally (chain 31337), keep both so MetaMask can connect to either.
const chainId = Number(process.env.NEXT_PUBLIC_CHAIN_ID ?? 31337);
const chains = chainId === 31337
  ? ([anvil, sepolia] as const)
  : ([sepolia] as const);

export const config = getDefaultConfig({
  appName: 'DeFi Hub',
  projectId,
  chains,
  ssr: true,
});
