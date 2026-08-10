import { Header } from '@/components/Header';
import { SimpleDAODashboard } from '@/components/SimpleDAODashboard';

export const metadata = {
  title: 'DeFi Hub — DAO',
  description: 'On-chain governance proposals powered by GovernanceToken voting.',
};

export default function DAOPage() {
  return (
    <>
      <Header />
      <main className="flex-1">
        <SimpleDAODashboard />
      </main>
    </>
  );
}
