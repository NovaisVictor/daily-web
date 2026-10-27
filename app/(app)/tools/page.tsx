import { IntegrationsPanel } from '@/components/IntegrationsPanel';
import { PageHeader } from '@/components/data/PageHeader';

export default function ToolsPage() {
  return (
    <div className="flex flex-col gap-4">
      <PageHeader title="Ferramentas" />
      <IntegrationsPanel />
    </div>
  );
}
