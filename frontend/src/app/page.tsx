import { Header } from '@/components/Header';
import { StakingDashboard } from '@/components/StakingDashboard';

export default function Home() {
  return (
    <>
      <Header />
      <main className="flex-1">
        <StakingDashboard />
      </main>
    </>
  );
}
