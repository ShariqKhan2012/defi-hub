import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import { anvil, sepolia } from 'wagmi/chains';

// WalletConnect requires a real projectId for WC connections.
// Any non-empty string prevents the SSR validation error; MetaMask/injected
// wallets work regardless. Get a free ID at cloud.walletconnect.com.
const projectId =
  process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || 'local-dev-no-wc';

export const config = getDefaultConfig({
  appName: 'DeFi Hub',
  projectId,
  chains: [anvil, sepolia],
  ssr: true,
});
