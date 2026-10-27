import { ProfilePanel } from '@/components/ProfilePanel';
import { PageHeader } from '@/components/data/PageHeader';

export default function PerfilPage() {
  return (
    <div className="flex flex-col gap-4">
      <PageHeader title="Perfil" description="Sua foto, seus dados e sua senha." />
      <div className="max-w-lg">
        <ProfilePanel />
      </div>
    </div>
  );
}
